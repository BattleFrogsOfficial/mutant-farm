--!strict
-- Pen income: the mutants standing in your pen pay you every payoutSeconds while you're online.
-- The payout schedule is per session (not saved); offline earnings are handled at join by
-- GrowthService's catch-up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local Net = require(script.Parent.Parent.Util.Net)

local IncomeService = {}

local function pay(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local amount = DataService.incomePerMinute(data)
	if amount > 0 and EconomyService.addCash(player, data, amount, "Gameplay", "PenIncome") then
		Net.fire(player, "Payout", amount)
	end
	DataService.changed(player)
end

function IncomeService.Init()
	Players.PlayerRemoving:Connect(function(player)
		DataService.nextPayoutAt[player] = nil
	end)
end

function IncomeService.Start()
	DataService.Loaded:Connect(function(player)
		DataService.nextPayoutAt[player] = DataService.now() + GameConfig.payoutSeconds
		DataService.changed(player)
	end)
	while true do
		task.wait(0.25)
		local now = DataService.now()
		for player, at in DataService.nextPayoutAt do
			if now >= at then
				-- Schedule first, so a slow payout can never double-pay.
				DataService.nextPayoutAt[player] = math.max(at + GameConfig.payoutSeconds, now + 1)
				pay(player)
			end
		end
	end
end

return IncomeService
