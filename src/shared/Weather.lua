--!strict
-- The global weather schedule: a pure function of wall-clock time, so every server (and every
-- client, for the countdown) agrees on which event runs when, with no messages between them.
-- Numbers in Config/Weather.lua.
--
--   bucket b covers [b * bucketSeconds, (b + 1) * bucketSeconds) of unix time
--   its event starts at b * bucketSeconds + offsetSeconds and lasts the event's durationSeconds
--   its type is a seeded hash of b, weighted by the events' `weight`

local Config = require(script.Parent.Config.Weather)
local Rng = require(script.Parent.Rng)

local Weather = {}

export type Event = { id: string, bucket: number, startsAt: number, endsAt: number }

local TOTAL_WEIGHT = 0
for _, id in Config.order do
	TOTAL_WEIGHT += Config.events[id].weight
end

-- The event type of bucket b: a hash of (b, seed) mapped onto the weights. Deterministic.
function Weather.typeOf(bucket: number): string
	local mixed = (bucket * 2654435761 + Config.seed) % 4294967296
	local roll = Rng.new(mixed):next() * TOTAL_WEIGHT
	for _, id in Config.order do
		roll -= Config.events[id].weight
		if roll < 0 then
			return id
		end
	end
	return Config.order[#Config.order]
end

-- Bucket b's event.
function Weather.eventOf(bucket: number): Event
	local id = Weather.typeOf(bucket)
	local startsAt = bucket * Config.bucketSeconds + Config.offsetSeconds
	return { id = id, bucket = bucket, startsAt = startsAt, endsAt = startsAt + Config.events[id].durationSeconds }
end

-- The event running at time t, or else the next one to start. `active` = it runs at t
-- (startsAt <= t < endsAt).
function Weather.scheduleAt(t: number): Event & { active: boolean }
	local bucket = t // Config.bucketSeconds
	local event = Weather.eventOf(bucket)
	if t >= event.endsAt then
		event = Weather.eventOf(bucket + 1)
	end
	return {
		id = event.id,
		bucket = event.bucket,
		startsAt = event.startsAt,
		endsAt = event.endsAt,
		active = t >= event.startsAt and t < event.endsAt,
	}
end

-- The next event that starts after time t (not the one running at t).
function Weather.nextAfter(t: number): Event
	local event = Weather.scheduleAt(t)
	return if event.active then Weather.eventOf(event.bucket + 1) else event
end

return Weather
