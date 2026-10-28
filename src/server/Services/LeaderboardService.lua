--!strict
-- Leaderboards. Server: `leaderstats` (Cash, Rebirths) in Roblox's player list. Global: all-time
-- Cash earned in an OrderedDataStore, saved and read every Game.leaderboardSeconds, shown on the
-- board in the hub (World builds it; Row1..Row10 labels). Every DataStore call is pcall'd: in
-- Studio without API access the board just keeps its placeholders.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.Game)
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local World = require(script.Parent.Parent.Util.World)

local LeaderboardService = {}

local store: OrderedDataStore? = nil
local names: { [number]: string } = {}
local pending = 0 -- leave-time saves still running (BindToClose waits for them)

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

local function save(player: Player, data: Types.Profile)
	if store then
		-- OrderedDataStore holds integers; cap at 2^53 so huge late-game totals don't error.
		local value = math.floor(math.min(data.stats.cashEarned, 2 ^ 53))
		pcall(function()
			(store :: OrderedDataStore):SetAsync(tostring(player.UserId), value)
		end)
	end
end

local function refreshBoard()
	if not store then
		return
	end
	local ok, pages = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, World.LEADERBOARD_ROWS)
	end)
	if not ok or not pages then
		return
	end
	local entries = pages:GetCurrentPage()
	local board = workspace:FindFirstChild("Map")
		and workspace.Map:FindFirstChild("Hub")
		and workspace.Map.Hub:FindFirstChild("Leaderboard")
		and workspace.Map.Hub.Leaderboard:FindFirstChild("Board")
	local gui = board and board:FindFirstChild("Rows")
	if not gui then
		return
	end
	for i = 1, World.LEADERBOARD_ROWS do
		local label = gui:FindFirstChild("Row" .. i) :: TextLabel?
		local entry = entries[i]
		if label then
			label.Text = if entry
				then string.format("%d. %s  ·  %s", i, nameOf(tonumber(entry.key) or 0), Format.cash(entry.value))
				else i .. ". ..."
		end
	end
end

function LeaderboardService.Init()
	local ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, "CashEarned_v1")
	store = if ok then result else nil
end

function LeaderboardService.Start()
	DataService.Changed:Connect(updateStats)
	-- Release hooks run synchronously before the profile is released: don't yield there.
	DataService.onRelease(function(player, data)
		local earned = data.stats.cashEarned
		pending += 1
		task.spawn(function()
			save(player, { stats = { cashEarned = earned } } :: any)
			pending -= 1
		end)
	end)
	game:BindToClose(function()
		local deadline = os.clock() + 20
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
	task.spawn(refreshBoard)
	while true do
		task.wait(GameConfig.leaderboardSeconds)
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if data then
				save(player, data)
			end
		end
		refreshBoard()
	end
end

return LeaderboardService
