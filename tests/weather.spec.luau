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
		["events last 120 s and give each egg one roll"] = function()
			for _, id in Config.order do
				t.eq(Config.events[id].durationSeconds, 120)
				t.eq(WeatherRules.rolls(id), 1)
			end
		end,
		["one roll: Acid Rain 20% Radioactive, Solar Flare 25% Golden, Glitch Storm 40% Radioactive"] = function()
			t.near(WeatherRules.chance("AcidRain", 1), 0.2, 1e-9)
			t.near(WeatherRules.chance("SolarFlare", 1), 0.25, 1e-9)
			t.near(WeatherRules.chance("GlitchStorm", 1), 0.4, 1e-9)
			t.eq(Config.events.AcidRain.mutation, "Radioactive")
			t.eq(Config.events.SolarFlare.mutation, "Golden")
			t.eq(Config.events.GlitchStorm.mutation, "Radioactive")
			t.near(WeatherRules.chanceOverEvent("SolarFlare", 1), 0.25, 1e-9)
			t.near(WeatherRules.chance("SolarFlare", 2), 0.5, 1e-9) -- luck applies
			t.near(WeatherRules.chance("SolarFlare", 6), 0.6, 1e-9) -- capped at 0.6
			t.eq(WeatherRules.key("global", 100), "g100")
			t.eq(WeatherRules.key("plot", 100), "p100")
		end,

		["schedule: hourly buckets, event 5 min in, 120 s long"] = function()
			local e = Weather.eventOf(1_200_000)
			t.eq(Config.bucketSeconds, 3600)
			t.eq(e.startsAt, 1_200_000 * 3600 + 300)
			t.eq(e.endsAt - e.startsAt, 120)
			-- During: active; just after: the next bucket's event; before: this one, upcoming.
			local during = Weather.scheduleAt(e.startsAt + 10)
			t.ok(during.active and during.startsAt == e.startsAt)
			t.ok(not Weather.scheduleAt(e.startsAt - 1).active)
			t.eq(Weather.scheduleAt(e.startsAt - 1).startsAt, e.startsAt)
			t.eq(Weather.scheduleAt(e.endsAt).startsAt, e.startsAt + 3600)
			t.eq(Weather.nextAfter(e.startsAt + 10).startsAt, e.startsAt + 3600)
			-- On the hour (unix time starts on an hour): 5 min past every hour.
			t.eq(e.startsAt % 3600, 300)
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

		["100 Acid Rain events (real WeatherService): one roll per egg, 15-25% mutate"] = function()
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
			t.ok(share >= 0.15 and share <= 0.25, string.format("Acid Rain hit %.1f%% of eggs", share * 100))
		end,
		["one roll per event: eggs planted mid-event get theirs; never twice, never a duplicate"] = function()
			local world = t.server({ now = T0, seed = 7 })
			local player, data = world:join(1, { slotCount = 40, slots = cosmicSlots(T0), grantedStarterEggs = true })
			local e = nextOfType("SolarFlare", T0)
			world:advance(e.startsAt - 3 - world.now)
			data.slots = cosmicSlots(world.now, 20)
			-- Half the eggs already have Golden: they're marked rolled but never get it twice.
			for i = 1, 10 do
				data.slots[tostring(i)].mutations = { "Golden" }
			end
			local GrowthService = world:modulesRequire("src/server/Services/GrowthService")
			local rolls = 0
			world:advance(60, 1)
			-- Plant 20 more mid-event: they get their one roll on the next tick.
			for i = 21, 40 do
				data.slots[tostring(i)] = cosmicSlots(world.now, 1)["1"]
			end
			world:advance(70, 1)
			local key = WeatherRules.key("global", e.startsAt)
			for _, slot in data.slots do
				t.ok(slot.weatherRolled and slot.weatherRolled[key], "every growing egg had its roll")
				t.ok(count(slot.mutations, function(m)
					return m == "Golden"
				end) <= 1, "no duplicate")
				rolls += 1
			end
			t.eq(rolls, 40)
			-- A second pass over the same event changes nothing.
			local before = {}
			for k, slot in data.slots do
				before[k] = #slot.mutations
			end
			GrowthService.weatherRoll(player, data, "SolarFlare", key)
			for k, slot in data.slots do
				t.eq(#slot.mutations, before[k], "one roll per egg per event")
			end
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
			-- 40 eggs at one 25% roll each: 10 expected; the other plot gets nothing.
			t.ok(golden(mine.slots) >= 3 and golden(mine.slots) <= 20, "buyer's eggs mutated: " .. golden(mine.slots))
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
