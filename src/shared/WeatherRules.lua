--!strict
-- Weather math shared by WeatherService, GrowthService and the tests: which event comes next,
-- the chance per roll for an egg, and how many rolls an event makes.

local Weather = require(script.Parent.Config.Weather)
local Rng = require(script.Parent.Rng)

local WeatherRules = {}

-- Weighted pick of the next event id.
function WeatherRules.pick(rng: Rng.Rng): string
	local weights = {}
	for id, event in Weather.events :: any do
		weights[id] = event.weight
	end
	return rng:weighted(Weather.order, weights)
end

-- Chance per roll for one egg: the event's chance x luck, capped.
function WeatherRules.chance(eventId: string, luck: number): number
	local event = (Weather.events :: any)[eventId]
	return math.min(event.chancePerRoll * luck, Weather.maxChance)
end

-- Rolls an event makes: one when it starts, then every rollEverySeconds while it runs.
function WeatherRules.rolls(eventId: string): number
	local event = (Weather.events :: any)[eventId]
	return math.ceil(event.durationSeconds / Weather.rollEverySeconds)
end

-- Chance an egg growing through the whole event gets the mutation (at luck 1).
function WeatherRules.chanceOverEvent(eventId: string, luck: number): number
	return 1 - (1 - WeatherRules.chance(eventId, luck)) ^ WeatherRules.rolls(eventId)
end

return WeatherRules
