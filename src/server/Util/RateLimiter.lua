--!strict
-- Token bucket per player, shared across all remotes. Over-limit calls are dropped silently.

local Players = game:GetService("Players")

local RateLimiter = {}

type Bucket = { tokens: number, updatedAt: number }

local buckets: { [Player]: Bucket } = {}

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

function RateLimiter.allow(player: Player, perSecond: number): boolean
	local now = os.clock()
	local bucket = buckets[player]
	if not bucket then
		bucket = { tokens = perSecond, updatedAt = now }
		buckets[player] = bucket
	end
	bucket.tokens = math.min(perSecond, bucket.tokens + (now - bucket.updatedAt) * perSecond)
	bucket.updatedAt = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

return RateLimiter
