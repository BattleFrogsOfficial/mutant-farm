--!strict
-- Leaderboards. Server: `leaderstats` (Rebirths, Cash) in Roblox's player list. Global: two
-- OrderedDataStores, Top Pens (pen value, shared/Leaderboards.penValue) and Top Rebirths. Every
-- Game.leaderboardSeconds online players' values are saved (and again on leave), then the top
-- 100 of each are read and sent to every client (`Leaderboards` remote), which draws both boards
-- side by side in the hub with the viewer's own rank at the bottom (LeaderboardController).
-- Every DataStore call is pcall'd: in Studio without API access the boards just stay empty.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.Game)
local Format = require(Shared.Format)
local Leaderboards = require(Shared.Leaderboards)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local Net = require(script.Parent.Parent.Util.Net)

local LeaderboardService = {}

local STORES = { pens = "TopPens_v1", rebirths = "TopRebirths_v1" }

local stores: { [string]: OrderedDataStore } = {}
local names: { [number]: string } = {}
local pending = 0 -- leave-time saves still running (BindToClose waits for them)
-- The latest top lists, sent to players as they join.
local boards: { [string]: { Leaderboards.Entry } } = { pens = {}, rebirths = {} }

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	if ok and name then
		names[userId] = name -- only cache successes, so a throttled lookup retries next refresh
		return name
	end
	return "Player"
end

local function stats(player: Player)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		-- Rebirths first: the player list sorts by the first stat (a number sorts properly).
		local rebirths = Instance.new("IntValue")
		rebirths.Name = "Rebirths"
		rebirths.Parent = folder
		local cash = Instance.new("StringValue") -- formatted ("1.2M"), so it reads well in the list
		cash.Name = "Cash"
		cash.Parent = folder
		folder.Parent = player
	end
	return folder
end

local function updateStats(player: Player, data: Types.Profile)
	local folder = stats(player)
	local cash = folder:FindFirstChild("Cash") :: StringValue
	local rebirths = folder:FindFirstChild("Rebirths") :: IntValue
	cash.Value = Format.cash(data.cash)
	rebirths.Value = data.rebirths
end

-- What each board records for a player right now.
local function values(data: Types.Profile): { [string]: number }
	return {
		pens = Leaderboards.penValue(DataService.penItems(data)),
		rebirths = Leaderboards.storeValue(data.rebirths),
	}
end

local function save(userId: number, current: { [string]: number })
	for board, store in stores do
		pcall(function()
			store:SetAsync(tostring(userId), current[board])
		end)
	end
end

local function read(store: OrderedDataStore): { Leaderboards.Entry }?
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, Leaderboards.SIZE)
	end)
	if not ok or not pages then
		return nil
	end
	local entries = {}
	for _, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key) or 0
		table.insert(entries, { userId = userId, name = nameOf(userId), value = entry.value })
	end
	return entries
end

local function refresh()
	for board, store in stores do
		local entries = read(store)
		if entries then
			boards[board] = entries
		end
	end
	Remotes.get("Leaderboards"):FireAllClients(boards)
end

function LeaderboardService.Init()
	for board, name in STORES do
		local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)
		if ok and store then
			stores[board] = store
		end
	end
end

function LeaderboardService.Start()
	DataService.Changed:Connect(updateStats)
	DataService.Loaded:Connect(function(player)
		Net.fire(player, "Leaderboards", boards)
	end)
	-- Release hooks run synchronously before the profile is released: don't yield there.
	DataService.onRelease(function(player, data)
		local current = values(data)
		pending += 1
		task.spawn(function()
			save(player.UserId, current)
			pending -= 1
		end)
	end)
	game:BindToClose(function()
		local deadline = os.clock() + 20
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
	task.spawn(refresh)
	while true do
		task.wait(GameConfig.leaderboardSeconds)
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if data then
				save(player.UserId, values(data))
			end
		end
		refresh()
	end
end

return LeaderboardService
