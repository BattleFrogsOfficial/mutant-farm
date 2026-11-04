return function(t)
	local GateSign = t.require("src/shared/GateSign")
	local NextUp = t.require("src/shared/NextUp")
	local Eggs = t.require("src/shared/Config/Eggs")
	return {
		["gate sign: the income while eggs grow, cents under $10, a hatch / plant hint when none grow"] = function()
			t.eq(GateSign.incomeText(0, 0, 0), "$0/min · PLANT EGGS")
			t.eq(GateSign.incomeText(160, 1, 0), "$160/min") -- eggs growing
			t.eq(GateSign.incomeText(3_400, 4, 2), "$3.4K/min") -- some growing, some ready: no hint
			t.eq(GateSign.incomeText(0, 0, 1), "$0/min · HATCH EGGS") -- the only egg is ready
			t.eq(GateSign.incomeText(0.04, 0, 0), "$0.04/min · PLANT EGGS") -- one Starter Common in the pen
			t.eq(GateSign.incomeText(9.999, 2, 0), "$9.99/min") -- cents under $10, never rounded up
			t.eq(GateSign.incomeText(12.7, 2, 0), "$12/min")
			t.eq(GateSign.incomeText(1_250_000, 40, 0), "$1.2M/min")
		end,
		["next up: the rebirth goal from half its cost earned this life"] = function()
			t.eq(NextUp.rebirthGoal(0, 349_999, 700_000), nil)
			local g = NextUp.rebirthGoal(0, 420_000, 700_000)
			t.eq(g.title, "REBIRTH 1")
			t.eq(g.text, "$420K / $700K earned this life")
			t.near(g.progress, 0.6, 1e-9)
			local ready = NextUp.rebirthGoal(1, 5_000_000, 3_150_000)
			t.eq(ready.title, "REBIRTH 2 READY")
			t.eq(ready.progress, 1)
		end,
		["next up: Lab's earned gate once Swamp is owned, from the Eggs config"] = function()
			local need = Eggs.tiers.Lab.unlockEarned
			local goal = NextUp.labGoal(0, 12_400, { Swamp = 1 }, {})
			t.ok(goal, "goal with a Swamp egg in the bag")
			t.eq(goal.title, "LAB EGG")
			t.eq(goal.text, "$12.4K / $25K earned")
			t.near(goal.progress, 12_400 / need, 1e-9)
			-- A Swamp egg growing in a slot counts too.
			local growing = NextUp.labGoal(0, 600, { Starter = 2 }, { ["1"] = { eggId = "Swamp" } })
			t.ok(growing, "goal with a Swamp egg growing")
			t.eq(growing.text, "$600 / $25K earned")
			-- No Swamp yet: no Lab goal (Next soil patch instead).
			t.eq(NextUp.labGoal(0, 12_400, { Starter = 3, Swamp = 0 }, { ["1"] = { eggId = "Starter" } }), nil)
			-- Lab unlocked (earned enough) or past Rebirth 0: no Lab goal.
			t.eq(NextUp.labGoal(0, need, { Swamp = 1 }, {}), nil)
			t.eq(NextUp.labGoal(1, 0, { Swamp = 1 }, {}), nil)
		end,
	}
end
