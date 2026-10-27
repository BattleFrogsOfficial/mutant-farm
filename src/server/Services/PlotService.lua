--!strict
-- Assigns each player an island, spawns them on it, and mirrors their slots onto the
-- island's slot parts as attributes. Every client draws every island from those attributes,
-- so visitors see the same timers the owner does.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Growth = require(Shared.Growth)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local World = require(script.Parent.Parent.Util.World)

local PlotService = {}

local islands: { World.Island } = {}
local owners: { [Player]: World.Island } = {}

function PlotService.getIsland(player: Player): World.Island?
	return owners[player]
end

-- Writes the player's current slot state to their island. Call after any slot change.
function PlotService.refresh(player: Player, data: Types.Profile)
	local island = owners[player]
	if not island then
		return
	end
	island.model:SetAttribute("WateredUntil", data.wateredUntil)
	island.model:SetAttribute("Speed", DataService.speed(data))
	for i, part in island.slots do
		local slot = data.slots[tostring(i)]
		local active = i <= data.slotCount
		part:SetAttribute("Active", active)
		part.Color = if active then World.colors.soil else World.colors.lockedSoil
		if slot then
			part:SetAttribute("EggId", slot.eggId)
			part:SetAttribute("Growth", slot.growth)
			part:SetAttribute("UpdatedAt", slot.updatedAt)
			part:SetAttribute("Required", Growth.requiredSeconds(slot.eggId, slot.rarity))
		else
			part:SetAttribute("EggId", "")
		end
	end
end

local function clear(island: World.Island)
	island.model:SetAttribute("OwnerUserId", 0)
	island.model:SetAttribute("WateredUntil", 0)
	island.sign.Text = "Empty Farm"
	for _, part in island.slots do
		part:SetAttribute("Active", false)
		part:SetAttribute("EggId", "")
		part.Color = World.colors.lockedSoil
	end
end

local function spawnOnIsland(player: Player, character: Model)
	local island = owners[player]
	if not island then
		return
	end
	character:WaitForChild("HumanoidRootPart", 5)
	character:PivotTo(island.spawn)
end

local function assign(player: Player, data: Types.Profile)
	for _, island in islands do
		if island.model:GetAttribute("OwnerUserId") == 0 then
			owners[player] = island
			island.model:SetAttribute("OwnerUserId", player.UserId)
			island.sign.Text = player.DisplayName .. "'s Farm"
			PlotService.refresh(player, data)
			if player.Character then
				task.spawn(spawnOnIsland, player, player.Character)
			end
			return
		end
	end
	-- Only possible if Max Players in Game Settings is above islandCount.
	warn("[PlotService] no free island for", player.Name)
	player:Kick("This server is full. Please join another one!")
end

function PlotService.Init()
	islands = World.build()
end

function PlotService.Start()
	DataService.Loaded:Connect(assign)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			spawnOnIsland(player, character)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			spawnOnIsland(player, character)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		local island = owners[player]
		owners[player] = nil
		if island then
			clear(island)
		end
	end)
end

return PlotService
