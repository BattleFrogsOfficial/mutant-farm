--!strict
-- Wraps client -> server remotes: rate limit, require a loaded profile, then call the handler.
-- Handlers receive (player, data, ...args) and must validate every arg themselves.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local RateLimiter = require(script.Parent.RateLimiter)

local Net = {}

local getData: (Player) -> any = function()
	return nil
end

function Net.setDataGetter(fn: (Player) -> any)
	getData = fn
end

function Net.on(name: string, handler: (Player, any, ...any) -> ())
	Remotes.get(name).OnServerEvent:Connect(function(player, ...)
		if not RateLimiter.allow(player, GameConfig.remoteCallsPerSecond) then
			return
		end
		local data = getData(player)
		if not data then
			return
		end
		handler(player, data, ...)
	end)
end

function Net.notify(player: Player, message: string, kind: ("info" | "error" | "success")?)
	Remotes.get("Notify"):FireClient(player, message, kind or "info")
end

function Net.fire(player: Player, name: string, ...: any)
	Remotes.get(name):FireClient(player, ...)
end

return Net
