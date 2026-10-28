--!strict
-- Weather roll math shared by WeatherService, GrowthService and the tests: the chance per roll for
-- an egg and how many rolls an event makes. The schedule (which event, when) is shared/Weather.lua.

local Weather = require(script.Parent.Config.Weather)

local WeatherRules = {}

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
