--!strict
-- Every remote in the game. Clients send intents only, never values.
-- The server creates these; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

-- client -> server
Remotes.ClientToServer = {
	"Plant", -- (slotIndex: number, eggId: string)
	"Harvest", -- (slotIndex: number)
	"HarvestAll", -- ()
	"Water", -- ()
	"BuyEgg", -- (eggId: string, quantity: number)
	"Sell", -- (itemId: string)
	"SellAll", -- ()
	"BuySlot", -- ()
	"ClaimDaily", -- ()
	"Rebirth", -- ()
}

-- server -> client
Remotes.ServerToClient = {
	"State", -- (snapshot: Types.Snapshot)
	"Notify", -- (message: string, kind: "info" | "error" | "success")
	"Harvested", -- (item, valueNow, slotIndex, isNewSpecies, auto: boolean) auto = Auto-Harvest pass
	"Mutated", -- (slotIndex: number, eggId: string, mutationId: string, worthNow: number)
	"Payout", -- (amount: number) pen income just paid
	"WelcomeBack", -- ({ away: number, ready: number, mutations: number })
	"Rebirthed", -- (rebirths: number) celebration after a rebirth
	"Almanac", -- (entries: { [speciesId]: Types.AlmanacEntry }) full on join, then one entry per change
}

local folder: Folder

function Remotes.init()
	if RunService:IsServer() then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		for _, name in Remotes.ClientToServer do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		for _, name in Remotes.ServerToClient do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		folder.Parent = ReplicatedStorage
	else
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
end

function Remotes.get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
