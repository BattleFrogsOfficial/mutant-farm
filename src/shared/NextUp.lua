--!strict
-- "Next up" goals after the tutorial (TutorialController shows them): the rebirth goal. Pure, so the rules are tested.

local Format = require(script.Parent.Format)

local NextUp = {}

export type Goal = { title: string?, text: string, progress: number? }

-- Does the player have a Swamp egg, in the bag or growing in a slot?
function NextUp.ownsSwamp(eggs: { [string]: number }, slots: { [string]: { eggId: string } }): boolean
	if (eggs.Swamp or 0) > 0 then
		return true
	end
	for _, slot in slots do
		if slot.eggId == "Swamp" then
			return true
		end
	end
	return false
end

-- The rebirth goal, from half the next rebirth's cost earned this life (Cash earned, not held):
-- "REBIRTH 2" / "$1.2M / $3.15M earned this life".
function NextUp.rebirthGoal(rebirths: number, earnedThisLife: number, cost: number): Goal?
	if cost <= 0 or earnedThisLife < cost * 0.5 then
		return nil
	end
	if earnedThisLife >= cost then
		return {
			title = string.format("REBIRTH %d READY", rebirths + 1),
			text = "Step on the Rebirth Altar in the market",
			progress = 1,
		}
	end
	return {
		title = string.format("REBIRTH %d", rebirths + 1),
		text = string.format("%s / %s earned this life", Format.cash(earnedThisLife), Format.cash(cost)),
		progress = math.clamp(earnedThisLife / cost, 0, 1),
	}
end

return NextUp
