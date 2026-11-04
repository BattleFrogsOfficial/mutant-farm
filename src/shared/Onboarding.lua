--!strict
-- The scripted opening's rules (numbers in Config/Onboarding.lua), shared by the server, the HUD
-- and the simulator.

local Config = script.Parent.Config
local O = require(Config.Onboarding)

local Onboarding = {}

-- The ramped grow time (seconds, as a Common) for `eggId` planted after `hatches` hatches, or nil
-- for the normal one: only the ramp egg (Starter), only before the last ramp step.
function Onboarding.rampSeconds(eggId: string, hatches: number): number?
	if eggId ~= O.rampEgg then
		return nil
	end
	for _, step in O.growRamp do
		if hatches < step.hatches then
			return step.seconds
		end
	end
	return nil
end

-- The item fields the scripted first hatch overrides.
function Onboarding.firstHatchFields(): { rarity: string, mutations: { string }, size: number, valueScale: number }
	return {
		rarity = O.firstHatch.rarity,
		mutations = table.clone(O.firstHatch.mutations),
		size = O.firstHatch.size,
		valueScale = O.firstHatchValueScale,
	}
end

-- Is it time for the solo weather? `played` = seconds of play, `growing` = eggs growing,
-- `globalNear` = a global event runs or starts within soloWeather.clearSeconds.
function Onboarding.soloWeatherDue(done: boolean, played: number, growing: number, globalNear: boolean): boolean
	local w = O.soloWeather
	return not done and played >= w.afterSeconds and growing >= w.minGrowing and not globalNear
end

-- The tutorial card's step for where the player is, each completed by the real event: TAP HATCH
-- -> SELL IT -> BUY 2 EGGS -> PLANT THEM -> STAND ON THE WATER PAD -> HATCH -> BUY A SOIL PATCH ->
-- GET A SWAMP EGG -> OPEN THE ALMANAC (Config/Tutorial); nil once profile.tutorialDone (Next Up
-- shows the nearest goal). "plantFirst" only for a profile without the pre-planted egg.
export type TutorialState = {
	harvested: number,
	sold: number,
	eggsBought: number,
	eggsPlanted: number,
	eggsInBag: number,
	emptyPatch: boolean, -- an owned patch is empty
	growing: number, -- eggs growing now
	waters: number, -- growth circle taps
	padVisits: number,
	slotsBought: number,
	canBuySlot: boolean, -- there is a next patch to buy
	hasSwamp: boolean, -- ever bought / planted / hatched a Swamp egg
	tutorialDone: boolean?, -- profile.tutorialDone (set when the Almanac is opened on its step)
}
export type Step =
	"plantFirst"
	| "hatch"
	| "sell"
	| "buy"
	| "plant"
	| "water"
	| "hatch2"
	| "patch"
	| "swamp"
	| "almanac"

function Onboarding.tutorialStep(s: TutorialState): Step?
	if s.tutorialDone then
		return nil
	elseif s.harvested == 0 then
		return if s.eggsPlanted == 0 then "plantFirst" else "hatch"
	elseif s.sold == 0 then
		return "sell"
	elseif s.eggsBought < O.trayBuy.quantity then
		return "buy"
	elseif s.harvested < 2 then
		if s.eggsInBag > 0 and s.emptyPatch then
			return "plant"
		elseif s.waters == 0 and s.padVisits == 0 and s.growing > 0 then
			return "water"
		end
		return "hatch2"
	elseif s.slotsBought == 0 and s.canBuySlot then
		return "patch"
	elseif not s.hasSwamp then
		return "swamp"
	end
	return "almanac"
end

-- The step's place in the tutorial (1..stepCount) for the card's "3 / 9".
local ORDER = {
	plantFirst = 1,
	hatch = 1,
	sell = 2,
	buy = 3,
	plant = 4,
	water = 5,
	hatch2 = 6,
	patch = 7,
	swamp = 8,
	almanac = 9,
}
Onboarding.stepCount = 9
function Onboarding.stepIndex(step: Step): number
	return ORDER[step] or 1
end

-- A scripted outcome (never counted in odds, mutation analytics or Top Pens).
function Onboarding.isScripted(item: { scripted: string? }): boolean
	return item.scripted ~= nil
end

return Onboarding
