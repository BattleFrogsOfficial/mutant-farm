-- The scripted opening's pure rules (shared/Onboarding.lua): the grow ramp, the solo weather's
-- trigger, the first hatch's fixed outcome and the tutorial's step order.
return function(t)
	local Onboarding = t.require("src/shared/Onboarding")
	local Valuation = t.require("src/shared/Valuation")
	local O = t.require("src/shared/Config/Onboarding")

	local function state(over)
		local s = {
			harvested = 0,
			sold = 0,
			eggsBought = 0,
			eggsPlanted = 1,
			eggsInBag = 1,
			emptyPatch = true,
			growing = 1,
			waters = 0,
			padVisits = 0,
			slotsBought = 0,
			canBuySlot = true,
			hasSwamp = false,
		}
		for k, v in over or {} do
			s[k] = v
		end
		return s
	end

	return {
		["the grow ramp: Starter only, 10 / 20 / 30 s, gone from hatch 30"] = function()
			t.eq(Onboarding.rampSeconds("Starter", 0), 10)
			t.eq(Onboarding.rampSeconds("Starter", 9), 10)
			t.eq(Onboarding.rampSeconds("Starter", 10), 20)
			t.eq(Onboarding.rampSeconds("Starter", 19), 20)
			t.eq(Onboarding.rampSeconds("Starter", 20), 30)
			t.eq(Onboarding.rampSeconds("Starter", 29), 30)
			t.eq(Onboarding.rampSeconds("Starter", 30), nil)
			t.eq(Onboarding.rampSeconds("Swamp", 0), nil)
			t.eq(Onboarding.rampSeconds("StarterGem", 0), nil)
		end,
		["the first hatch is worth $320 with the real arithmetic: $13 base, Glitched x25"] = function()
			local f = Onboarding.firstHatchFields()
			local item = {
				tier = "Starter",
				rarity = f.rarity,
				mutations = f.mutations,
				size = f.size,
				valueScale = f.valueScale,
			}
			t.eq(Valuation.sellValue(item, 1), 320)
			local plain = table.clone(item)
			plain.mutations = {}
			t.eq(math.floor(Valuation.sellValue(plain, 1) * 1 + 0.5), 12) -- floored; the reveal rounds 320 / 25
			t.eq(math.floor(320 / 25 + 0.5), 13)
			-- $320 buys 5 Starter eggs ($250) with change; patch 7 ($200) is next.
			t.ok(320 >= 5 * 50 and 320 - 250 < 200)
			-- Fresh copies: changing one never changes the config.
			table.insert(f.mutations, "Shiny")
			t.eq(#O.firstHatch.mutations, 1)
		end,
		["solo weather: after 2:30, 3 growing, no global event near, once"] = function()
			t.ok(Onboarding.soloWeatherDue(false, 150, 3, false))
			t.ok(not Onboarding.soloWeatherDue(false, 149, 3, false), "too early")
			t.ok(not Onboarding.soloWeatherDue(false, 300, 2, false), "too few growing")
			t.ok(not Onboarding.soloWeatherDue(false, 300, 5, true), "a global event is near")
			t.ok(not Onboarding.soloWeatherDue(true, 300, 5, false), "once")
		end,
		["tutorial: HATCH -> SELL -> BUY 5 -> PLANT ALL -> WATER -> HATCH -> patch -> Swamp"] = function()
			t.eq(Onboarding.tutorialStep(state()), "hatch")
			t.eq(Onboarding.tutorialStep(state({ eggsPlanted = 0 })), "plantFirst")
			t.eq(Onboarding.tutorialStep(state({ harvested = 1 })), "sell")
			t.eq(Onboarding.tutorialStep(state({ harvested = 1, sold = 1 })), "buy")
			t.eq(Onboarding.tutorialStep(state({ harvested = 1, sold = 1, eggsBought = 4 })), "buy", "BUY 5")
			local bought = { harvested = 1, sold = 1, eggsBought = 5, eggsInBag = 5 }
			t.eq(Onboarding.tutorialStep(state(bought)), "plant")
			bought.eggsInBag = 0
			t.eq(Onboarding.tutorialStep(state(bought)), "water", "all planted")
			bought.waters = 1
			t.eq(Onboarding.tutorialStep(state(bought)), "hatch2")
			bought.waters, bought.padVisits = 0, 1
			t.eq(Onboarding.tutorialStep(state(bought)), "hatch2", "the pad counts as watering")
			bought.harvested = 2
			t.eq(Onboarding.tutorialStep(state(bought)), "patch")
			bought.slotsBought = 1
			t.eq(Onboarding.tutorialStep(state(bought)), "swamp")
			bought.hasSwamp = true
			t.eq(Onboarding.tutorialStep(state(bought)), nil, "done")
			-- A full farm with eggs left over still moves on to watering.
			t.eq(
				Onboarding.tutorialStep(
					state({ harvested = 1, sold = 1, eggsBought = 5, eggsInBag = 2, emptyPatch = false })
				),
				"water"
			)
		end,
	}
end
