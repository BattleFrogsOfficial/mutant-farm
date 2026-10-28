return function(t)
	local Weather = t.require("src/shared/Config/Weather")
	local WeatherRules = t.require("src/shared/WeatherRules")
	local Rng = t.require("src/shared/Rng")

	return {
		["events last 120 s with a roll every 30 s: 4 rolls"] = function()
			for _, id in Weather.order do
				t.eq(Weather.events[id].durationSeconds, 120)
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
			t.near(WeatherRules.chance("SolarFlare", 6), Weather.maxChance, 1e-9) -- luck is capped
		end,
		["Glitch Storm is 1 event in 6"] = function()
			local rng = Rng.new(99)
			local n, glitch = 60_000, 0
			for _ = 1, n do
				if WeatherRules.pick(rng) == "GlitchStorm" then
					glitch += 1
				end
			end
			t.near(glitch / n, 1 / 6, 0.01)
		end,
		["100 Acid Rain events (real WeatherService): 60-75% of fully grown-through eggs mutate"] = function()
			local world = t.server({ seed = 2026 })
			local Mutants = t.require("src/shared/Config/Mutants")
			local slots = {}
			for i = 1, 40 do
				-- Cosmic eggs (8 h): nothing matures or crosses a natural roll within an event.
				slots[tostring(i)] = {
					eggId = "Cosmic",
					rarity = "Common",
					species = Mutants.buckets.Cosmic.Common[1],
					mutations = {},
					size = 1,
					plantedAt = world.now,
					growth = 60,
					updatedAt = world.now,
					rollsDone = 0,
					lastRollAt = world.now,
				}
			end
			local _, data = world:join(1, { slotCount = 40, slots = slots, grantedStarterEggs = true })
			local eggs, hit = 0, 0
			for _ = 1, 100 do
				for _, slot in data.slots do
					table.clear(slot.mutations)
				end
				-- Start Acid Rain now; the service's own loop picks it up within a second.
				world.workspace:SetAttribute("WeatherNextId", "AcidRain")
				world.workspace:SetAttribute("WeatherNextAt", world.now)
				world:advance(125, 1)
				t.eq(world.workspace:GetAttribute("WeatherId"), "", "event ended")
				for _, slot in data.slots do
					eggs += 1
					if table.find(slot.mutations, "Radioactive") then
						hit += 1
					end
				end
			end
			local share = hit / eggs
			t.ok(share >= 0.6 and share <= 0.75, string.format("Acid Rain hit %.1f%% of eggs", share * 100))
		end,
	}
end
