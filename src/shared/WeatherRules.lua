--!strict
-- Weather roll math shared by WeatherService, GrowthService and the tests: the chance of the one
-- roll an event gives each growing egg. The schedule (which event, when) is shared/Weather.lua.

local Weather = require(script.Parent.Config.Weather)

local WeatherRules = {}

-- Chance of the one roll an event gives an egg: the event's chance x luck, capped.
function WeatherRules.chance(eventId: string, luck: number): number
	local event = (Weather.events :: any)[eventId]
	return math.min(event.chancePerRoll * luck, Weather.maxChance)
end

-- Rolls an event gives each growing egg: one.
function WeatherRules.rolls(_eventId: string): number
	return 1
end

-- Chance an egg growing during the event gets the mutation.
function WeatherRules.chanceOverEvent(eventId: string, luck: number): number
	return WeatherRules.chance(eventId, luck)
end

-- The key an event marks the eggs it rolled with (slot.weatherRolled[key]): global events by
-- their start time, plot events (Instant Weather) by theirs with a "p" so the two never collide.
function WeatherRules.key(kind: "global" | "plot", startsAt: number): string
	return (if kind == "global" then "g" else "p") .. tostring(math.floor(startsAt))
end

return WeatherRules
