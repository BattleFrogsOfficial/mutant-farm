--!strict
-- Receives server snapshots and notifications and feeds them into State.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Mutants = require(Shared.Config.Mutants)
local State = require(script.Parent.Parent.State)

local StateController = {}

function StateController.Init() end

function StateController.Start()
	Remotes.get("State").OnClientEvent:Connect(function(snapshot)
		State.snapshot:set(snapshot)
		-- Keep the selected egg valid: fall back to any egg the player owns.
		local selected = State.selectedEgg:get(false)
		if not snapshot.eggs[selected] then
			for eggId in snapshot.eggs do
				State.selectedEgg:set(eggId)
				break
			end
		end
	end)

	Remotes.get("Notify").OnClientEvent:Connect(function(message, kind)
		State.toast(message, kind)
	end)

	Remotes.get("Harvested").OnClientEvent:Connect(function(item, value)
		local mutant = Mutants[item.tier][item.rarity]
		State.toast(string.format("Hatched %s (%s) worth %s", mutant.name, item.rarity, Format.cash(value)), "success")
	end)

	while true do
		State.now:set(workspace:GetServerTimeNow())
		task.wait(0.2)
	end
end

return StateController
