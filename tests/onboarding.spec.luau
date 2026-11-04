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
		["the first hatch is worth $115 with the real arithmetic: $13 base, Glitched +8 (x9)"] = function()
			local f = Onboarding.firstHatchFields()
			local item = {
				tier = "Starter",
				rarity = f.rarity,
				mutations = f.mutations,
				size = f.size,
				valueScale = f.valueScale,
			}
			local value = Valuation.sellValue(item, 1)
			t.eq(value, 115)
			t.ok(value >= 100 and value <= 130)
			local plain = table.clone(item)
			plain.mutations = {}
			t.eq(Valuation.sellValue(plain, 1), 12) -- floored; the reveal rounds 115 / 9
			t.eq(math.floor(115 / 9 + 0.5), 13)
			-- $115 + the $100 start buys the tray's 2 Starter eggs ($100); patch 7 ($200) is next.
			t.ok(115 + 100 >= O.trayBuy.quantity * 50 and O.trayBuy.quantity == 2)
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
		["tutorial: HATCH -> SELL -> BUY 2 -> PLANT -> WATER PAD -> CIRCLE -> HATCH -> patch -> Swamp -> Almanac"] = function()
			t.eq(Onboarding.tutorialStep(state()), "hatch")
			t.eq(Onboarding.tutorialStep(state({ eggsPlanted = 0 })), "plantFirst")
			t.eq(Onboarding.tutorialStep(state({ harvested = 1 })), "sell")
			t.eq(Onboarding.tutorialStep(state({ harvested = 1, sold = 1 })), "buy")
			t.eq(Onboarding.tutorialStep(state({ harvested = 1, sold = 1, eggsBought = 1 })), "buy", "BUY 2")
			local bought = { harvested = 1, sold = 1, eggsBought = 5, eggsInBag = 5 }
			t.eq(Onboarding.tutorialStep(state(bought)), "plant")
			bought.eggsInBag = 0
			t.eq(Onboarding.tutorialStep(state(bought)), "water", "all planted: the pad at once")
			bought.padVisits = 1
			t.eq(Onboarding.tutorialStep(state(bought)), "circle", "then the circle")
			-- Only a TapBoost (stats.waters) ends the circle step: more pad visits, plants or time don't.
			bought.padVisits = 5
			bought.eggsPlanted = 9
			t.eq(Onboarding.tutorialStep(state(bought)), "circle")
			bought.waters = 1
			t.eq(Onboarding.tutorialStep(state(bought)), "hatch2")
			-- With nothing growing (eggs already ripe) the pad and circle steps step aside.
			t.eq(
				Onboarding.tutorialStep(state({ harvested = 1, sold = 1, eggsBought = 2, eggsInBag = 0, growing = 0 })),
				"hatch2"
			)
			bought.harvested = 2
			t.eq(Onboarding.tutorialStep(state(bought)), "patch")
			bought.slotsBought = 1
			t.eq(Onboarding.tutorialStep(state(bought)), "swamp")
			bought.hasSwamp = true
			t.eq(Onboarding.tutorialStep(state(bought)), "almanac")
			bought.tutorialDone = true
			t.eq(Onboarding.tutorialStep(state(bought)), nil, "done")
			-- The card's "n / 9".
			t.eq(Onboarding.stepIndex("hatch"), 1)
			t.eq(Onboarding.stepIndex("water"), 5)
			t.eq(Onboarding.stepIndex("circle"), 6)
			t.eq(Onboarding.stepIndex("almanac"), 10)
			t.eq(Onboarding.stepCount, 10)
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
