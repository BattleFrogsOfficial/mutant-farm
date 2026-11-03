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

-- A scripted outcome (never counted in odds, mutation analytics or Top Pens).
function Onboarding.isScripted(item: { scripted: string? }): boolean
	return item.scripted ~= nil
end

return Onboarding
