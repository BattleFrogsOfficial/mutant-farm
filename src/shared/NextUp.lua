--!strict
-- "Next up" goals after the tutorial (TutorialController shows them). Pure, so the rules are tested.

local Eggs = require(script.Parent.Config.Eggs)
local Format = require(script.Parent.Format)
local ShopRules = require(script.Parent.ShopRules)

local NextUp = {}

export type Goal = { text: string, progress: number? }

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

-- While Lab is the next locked tier (its lifetime-Cash gate at Rebirth 0) and the player owns a
-- Swamp egg: "Lab Egg: $12.4K / $25K earned" with the progress toward the gate. Otherwise nil.
function NextUp.labGoal(
	rebirths: number,
	totalCashEarned: number,
	eggs: { [string]: number },
	slots: { [string]: { eggId: string } }
): Goal?
	if ShopRules.nextLocked(rebirths, totalCashEarned) ~= "Lab" then
		return nil
	end
	local lab = Eggs.tiers.Lab
	local need = lab.unlockEarned
	if not need or need <= 0 or rebirths ~= lab.unlockRebirth or not NextUp.ownsSwamp(eggs, slots) then
		return nil
	end
	return {
		text = string.format("%s: %s / %s earned", lab.name, Format.cash(totalCashEarned), Format.cash(need)),
		progress = math.clamp(totalCashEarned / need, 0, 1),
	}
end

return NextUp
