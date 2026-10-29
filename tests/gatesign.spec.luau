return function(t)
	local GateSign = t.require("src/shared/GateSign")
	local NextUp = t.require("src/shared/NextUp")
	local Eggs = t.require("src/shared/Config/Eggs")
	return {
		["gate sign: plant hint before the first harvest, then the live income"] = function()
			t.eq(GateSign.incomeText(0, 0), "$0/min · plant eggs to earn")
			t.eq(GateSign.incomeText(3_400, 1), "$3.4K/min")
			t.eq(GateSign.incomeText(0, 5), "$0/min") -- empty pen after selling: still shown
			t.eq(GateSign.incomeText(12, 2), "$12/min")
			t.eq(GateSign.incomeText(1_250_000, 40), "$1.2M/min")
		end,
		["next up: Lab's earned gate once Swamp is owned, from the Eggs config"] = function()
			local need = Eggs.tiers.Lab.unlockEarned
			local goal = NextUp.labGoal(0, 12_400, { Swamp = 1 }, {})
			t.ok(goal, "goal with a Swamp egg in the bag")
			t.eq(goal.text, "Lab Egg: $12.4K / $25K earned")
			t.near(goal.progress, 12_400 / need, 1e-9)
			-- A Swamp egg growing in a slot counts too.
			local growing = NextUp.labGoal(0, 600, { Starter = 2 }, { ["1"] = { eggId = "Swamp" } })
			t.ok(growing, "goal with a Swamp egg growing")
			t.eq(growing.text, "Lab Egg: $600 / $25K earned")
			-- No Swamp yet: no Lab goal (Next soil patch instead).
			t.eq(NextUp.labGoal(0, 12_400, { Starter = 3, Swamp = 0 }, { ["1"] = { eggId = "Starter" } }), nil)
			-- Lab unlocked (earned enough) or past Rebirth 0: no Lab goal.
			t.eq(NextUp.labGoal(0, need, { Swamp = 1 }, {}), nil)
			t.eq(NextUp.labGoal(1, 0, { Swamp = 1 }, {}), nil)
		end,
	}
end
