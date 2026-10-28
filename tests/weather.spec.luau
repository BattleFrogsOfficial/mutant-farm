-- Weather: roll odds, the global schedule (shared/Weather.lua), and the real WeatherService through
-- the server harness: global events, announcements, the Discord relay claim and Instant Weather.
return function(t)
	local Config = t.require("src/shared/Config/Weather")
	local WeatherRules = t.require("src/shared/WeatherRules")
	local Weather = t.require("src/shared/Weather")
	local Mutants = t.require("src/shared/Config/Mutants")

	local T0 = 1_800_000_000

	-- 40 freshly planted Cosmic eggs (8 h: nothing matures or crosses a natural roll in minutes).
	local function cosmicSlots(now: number, n: number?)
		local slots = {}
		for i = 1, n or 40 do
			slots[tostring(i)] = {
				eggId = "Cosmic",
				rarity = "Common",
				species = Mutants.buckets.Cosmic.Common[1],
				mutations = {},
				size = 1,
				plantedAt = now,
				growth = 60,
				updatedAt = now,
				rollsDone = 0,
				lastRollAt = now,
			}
		end
		return slots
	end

	local function count(list, pred): number
		local n = 0
		for _, v in list do
			if pred(v) then
				n += 1
			end
		end
		return n
	end

	-- The first bucket at or after `from` whose event is `id`.
	local function nextOfType(id: string, from: number): any
		local b = from // Config.bucketSeconds + 1
		while Weather.typeOf(b) ~= id do
			b += 1
		end
		return Weather.eventOf(b)
	end

	return {
		["events last 120 s with a roll every 30 s: 4 rolls"] = function()
			for _, id in Config.order do
				t.eq(Config.events[id].durationSeconds, 120)
				t.eq(WeatherRules.rolls(id), 4)
			end
		end,
		["chance per tick 25% / 30% / 10%; over a full event ~68% / 76% / 34%"] = function()
			t.near(WeatherRules.chance("AcidRain", 1), 0.25, 1e-9)
			t.near(WeatherRules.chance("SolarFlare", 1), 0.3, 1e-9)
			t.near(WeatherRules.chance("GlitchStorm", 1), 0.1, 1e-9)
			t.near(WeatherRules.chanceOverEvent("AcidRain", 1), 0.684, 0.001)
			t.near(WeatherRules.chanceOverEvent("SolarFlare", 1), 0.760, 0.001)
			t.near(WeatherRules.chanceOverEvent("GlitchStorm", 1), 0.344, 0.001)
			t.near(WeatherRules.chance("SolarFlare", 6), Config.maxChance, 1e-9) -- luck is capped
		end,

		["schedule: 25-min buckets, event 5 min in, 120 s long"] = function()
			local e = Weather.eventOf(1_200_000)
			t.eq(e.startsAt, 1_200_000 * 1500 + 300)
			t.eq(e.endsAt - e.startsAt, 120)
			-- During: active; just after: the next bucket's event; before: this one, upcoming.
			local during = Weather.scheduleAt(e.startsAt + 10)
			t.ok(during.active and during.startsAt == e.startsAt)
			t.ok(not Weather.scheduleAt(e.startsAt - 1).active)
			t.eq(Weather.scheduleAt(e.startsAt - 1).startsAt, e.startsAt)
			t.eq(Weather.scheduleAt(e.endsAt).startsAt, e.startsAt + 1500)
			t.eq(Weather.nextAfter(e.startsAt + 10).startsAt, e.startsAt + 1500)
			-- The grid meets the hour every 5 hours (unix time starts on an hour).
			t.eq((5 * 3600) % Config.bucketSeconds, 0)
		end,
		["scheduleAt(t) is identical on two servers"] = function()
			-- Two harness servers load their own copy of the module.
			local a = t.server():modulesRequire("src/shared/Weather")
			local b = t.server():modulesRequire("src/shared/Weather")
			t.ok(a ~= b, "separate module instances")
			for k = 0, 2000 do
				local at = T0 + k * 377
				local x, y = a.scheduleAt(at), b.scheduleAt(at)
				t.ok(x.id == y.id and x.startsAt == y.startsAt and x.active == y.active, "differs at " .. at)
			end
		end,
		["type mix over 10,000 buckets is within 2 points of 45 / 40 / 15"] = function()
			local n = { AcidRain = 0, SolarFlare = 0, GlitchStorm = 0 }
			local first = T0 // Config.bucketSeconds
			for b = first, first + 9_999 do
				local id = Weather.typeOf(b)
				n[id] += 1
			end
			t.near(n.AcidRain / 100, 45, 2, "Acid Rain %")
			t.near(n.SolarFlare / 100, 40, 2, "Solar Flare %")
			t.near(n.GlitchStorm / 100, 15, 2, "Glitch Storm %")
		end,

		["100 Acid Rain events (real WeatherService): 60-75% of fully grown-through eggs mutate"] = function()
			local world = t.server({ now = T0, seed = 2026 })
			local _, data = world:join(1, { slotCount = 40, slots = cosmicSlots(T0), grantedStarterEggs = true })
			local eggs, hit = 0, 0
			local from = T0
			for _ = 1, 100 do
				local e = nextOfType("AcidRain", from)
				-- Jump to just before it with fresh eggs, then play it through second by second.
				world:advance(e.startsAt - 3 - world.now)
				data.slots = cosmicSlots(world.now)
				world:advance(125, 1)
				t.eq(world.workspace:GetAttribute("WeatherId"), "", "event ended")
				for _, slot in data.slots do
					eggs += 1
					if table.find(slot.mutations, "Radioactive") then
						hit += 1
					end
				end
				from = e.endsAt
			end
			local share = hit / eggs
			t.ok(share >= 0.6 and share <= 0.75, string.format("Acid Rain hit %.1f%% of eggs", share * 100))
		end,
		["announcements: toast at T-5:00 (+ chat line), T-1:00 and the start"] = function()
			local e = Weather.eventOf(T0 // Config.bucketSeconds + 3)
			local world = t.server({ now = e.startsAt - 400 })
			world:join(1)
			world:advance(410, 1)
			local said = {}
			for _, m in world.broadcast do
				if m.name == "WeatherAnnounce" then
					table.insert(said, { text = m.args[1], chat = m.args[2] })
				end
			end
			local event = Config.events[e.id]
			t.eq(#said, 3)
			t.eq(said[1].text, string.format(event.soon, event.icon, "5:00"))
			t.eq(said[1].chat, true)
			t.eq(said[2].text, string.format(event.soon, event.icon, "1:00"))
			t.eq(said[2].chat, false)
			t.eq(said[3].text, string.format(event.start, event.icon))
			t.eq(world.workspace:GetAttribute("WeatherId"), e.id)
		end,
		["Discord relay: one claim per startsAt across servers, one POST, only Glitch Storm"] = function()
			local memory = {}
			local storm = nextOfType("GlitchStorm", T0)
			local servers = {}
			for k = 1, 3 do
				local world =
					t.server({ now = storm.startsAt - 320, memory = memory, relayUrl = "https://relay.test/weather" })
				world.secrets.WEATHER_RELAY_KEY = "s3cret"
				world:join(k)
				servers[k] = world
			end
			-- All three servers cross T-5:00 within the same seconds.
			for _ = 1, 30 do
				for _, world in servers do
					world:advance(1)
				end
			end
			local posts = {}
			for _, world in servers do
				for _, r in world.http do
					table.insert(posts, r)
				end
			end
			t.eq(#posts, 1, "exactly one server posts")
			t.eq(posts[1].Url, "https://relay.test/weather")
			t.eq(posts[1].Headers["X-Relay-Key"], "s3cret")
			local body = require("@lune/serde").decode("json", posts[1].Body)
			t.eq(body.event, "GlitchStorm")
			t.eq(body.startsAt, storm.startsAt)
			t.eq(
				count(memory.WeatherAnnounce, function()
					return true
				end),
				1,
				"one claim stored"
			)
			-- A second claim for the same start time is refused, even by the winner.
			for _, world in servers do
				t.eq(world.service.WeatherService.claimAnnounce(storm.startsAt), false)
			end
			-- Non-Glitch events are never posted.
			local acid = nextOfType("AcidRain", storm.endsAt)
			local world = servers[1]
			local before = #world.http
			world:advance(acid.startsAt - 320 - world.now)
			world:advance(30, 1)
			t.eq(#world.http, before, "Acid Rain isn't posted")
		end,
		["Discord relay: off without relayUrl or secret, silently, logged once"] = function()
			local storm = nextOfType("GlitchStorm", T0)
			local world = t.server({ now = storm.startsAt - 320 }) -- relayUrl "" (default)
			world:join(1)
			world:advance(60, 1)
			t.eq(#world.http, 0)
			local logged = count(world.warnings, function(w)
				return w:find("relay skipped", 1, true) ~= nil
			end)
			t.eq(logged, 1)
			local second = nextOfType("GlitchStorm", storm.endsAt)
			local noSecret = t.server({ now = second.startsAt - 320, relayUrl = "https://relay.test/weather" })
			noSecret:join(1)
			noSecret:advance(60, 1)
			t.eq(#noSecret.http, 0)
		end,

		["Instant Weather: rolls only on the buyer's plot, 400 Gems, never stacked"] = function()
			-- Pick a quiet time: no global event for the next 10 minutes.
			local now = T0
			while Weather.scheduleAt(now).startsAt - now < 600 do
				now += 60
			end
			local world = t.server({ now = now, seed = 77 })
			local buyer, mine =
				world:join(1, { gems = 1_000, slotCount = 40, slots = cosmicSlots(now), grantedStarterEggs = true })
			local _, theirs =
				world:join(2, { gems = 1_000, slotCount = 40, slots = cosmicSlots(now), grantedStarterEggs = true })
			world:send(buyer, "BuyInstantWeather", "SolarFlare")
			t.eq(mine.gems, 600)
			t.eq(buyer:GetAttribute("PlotWeatherId"), "SolarFlare")
			world:send(buyer, "BuyInstantWeather", "AcidRain") -- one at a time
			t.eq(mine.gems, 600, "no second event while one runs")
			world:advance(125, 1)
			t.eq(buyer:GetAttribute("PlotWeatherId"), nil, "ended")
			local golden = function(slots)
				local n = 0
				for _, slot in slots do
					if table.find(slot.mutations, "Golden") then
						n += 1
					end
				end
				return n
			end
			-- 40 eggs at 1 - 0.7^4 = 76%: comfortably above 20; the other plot gets nothing.
			t.ok(golden(mine.slots) >= 20, "buyer's eggs mutated: " .. golden(mine.slots))
			t.eq(golden(theirs.slots), 0, "other plot untouched")
			t.ok(count(world.economy, function(e)
				return e.sku == "InstantWeather_SolarFlare" and e.flow == "Sink" and e.amount == 400
			end) == 1, "Gems sink InstantWeather_SolarFlare")
			-- After it ends, another can be bought.
			world:send(buyer, "BuyInstantWeather", "AcidRain")
			t.eq(mine.gems, 200)
		end,
		["Instant Weather: refused for restricted players"] = function()
			local world = t.server({ now = T0 })
			world.restricted[1] = true
			local player, data = world:join(1, { gems = 1_000 })
			world:send(player, "BuyInstantWeather", "AcidRain")
			t.eq(data.gems, 1_000)
			t.eq(player:GetAttribute("PlotWeatherId"), nil)
		end,
	}
end
