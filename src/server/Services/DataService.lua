--!strict
-- Owns player profiles (ProfileStore, session-locked) and pushes state snapshots to clients.
-- Other services read/write `DataService.get(player)` and call `DataService.changed(player)`
-- after any change the client should see. Cash and Gems are written only by EconomyService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileStore = require(ReplicatedStorage.Packages.ProfileStore)
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.Game)
local Upgrades = require(Shared.Config.Upgrades)
local Growth = require(Shared.Growth)
local Valuation = require(Shared.Valuation)
local Costs = require(Shared.Costs)
local Expected = require(Shared.Expected)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)
local Net = require(script.Parent.Parent.Util.Net)

local DataService = {}

-- Fired after a profile is loaded and ready: (player, data)
DataService.Loaded = Signal.new()

-- Fired (batched, at most every stateFlushInterval) after changes: (player, data)
DataService.Changed = Signal.new()

-- Called synchronously, in registration order, right before a profile is released: (player, data)
local releaseHooks: { (Player, Types.Profile) -> () } = {}

local TEMPLATE: Types.Profile = {
	version = 1,
	cash = GameConfig.startingCash,
	gems = 0,
	rebirths = 0,
	slotCount = Upgrades.slots.base,
	slots = {},
	eggs = {}, -- starting eggs are granted once in onPlayerAdded (Reconcile would refill a template value)
	inventory = {},
	pen = {},
	upgrades = { growthSpeed = 0, mutationOdds = 0 },
	ownedPasses = {},
	processedPurchases = {},
	wateredUntil = 0,
	lastSeen = 0,
	streak = { day = 0, lastClaimDay = 0 },
	redeemedCodes = {},
	funnel = {},
	grantedStarterEggs = false,
	-- Almanac: speciesId -> { n = times hatched, first = timestamp, best = biggest size }
	almanac = {},
	stats = { eggsBought = 0, eggsPlanted = 0, harvested = 0, sold = 0, cashEarned = 0, waters = 0, slotsBought = 0 },
	nextItemId = 1,
}

local store = ProfileStore.New("PlayerData_v1", TEMPLATE)
local profiles: { [Player]: any } = {}
local releasing: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}

function DataService.get(player: Player): Types.Profile?
	local profile = profiles[player]
	return profile and profile.Data
end

function DataService.onRelease(fn: (Player, Types.Profile) -> ())
	table.insert(releaseHooks, fn)
end

function DataService.changed(player: Player)
	dirty[player] = true
end

function DataService.now(): number
	return workspace:GetServerTimeNow()
end

function DataService.speed(data: Types.Profile): number
	return Growth.speed(data.upgrades.growthSpeed, data.ownedPasses.GrowthSpeed2x == true)
end

function DataService.cashMultiplier(data: Types.Profile): number
	return Valuation.cashMultiplier(data.rebirths, data.ownedPasses.VIP == true)
end

-- Expected Cash per minute from everything growing right now (unwatered speed).
function DataService.incomePerMinute(data: Types.Profile): number
	local speed = DataService.speed(data)
	local mult = DataService.cashMultiplier(data)
	local luck = if data.ownedPasses.Luck2x then 2 else 1
	local oddsBonus = Upgrades.mutationOdds.bonusPerLevel * data.upgrades.mutationOdds
	local total = 0
	for _, slot in data.slots do
		local value = Expected.egg(slot.eggId, luck, oddsBonus, slot.rarity)
		total += value * mult / (Growth.requiredSeconds(slot.eggId, slot.rarity) / speed) * 60
	end
	return total
end

-- What the owning client is allowed to see. Rarity isn't sent, but `required` scales with rarity,
-- so an accurate timer implies it (a deliberate trade-off: "this one's taking longer...").
local function snapshot(data: Types.Profile): Types.Snapshot
	local slots = {}
	for key, slot in data.slots do
		slots[key] = {
			index = tonumber(key) :: number,
			eggId = slot.eggId,
			growth = slot.growth,
			updatedAt = slot.updatedAt,
			required = Growth.requiredSeconds(slot.eggId, slot.rarity),
		}
	end
	return {
		serverTime = DataService.now(),
		cash = data.cash,
		gems = data.gems,
		rebirths = data.rebirths,
		slotCount = data.slotCount,
		cashMultiplier = DataService.cashMultiplier(data),
		speed = DataService.speed(data),
		wateredUntil = data.wateredUntil,
		eggs = data.eggs,
		slots = slots,
		inventory = data.inventory,
		inventoryCap = GameConfig.inventoryCap,
		nextSlotCost = Costs.slot(data.slotCount + 1, data.rebirths),
		stats = data.stats,
		incomePerMinute = DataService.incomePerMinute(data),
	}
end

-- Runs the release hooks and stamps lastSeen exactly once per session. Called on leave and
-- from OnLastSave, which also covers server shutdown (ProfileStore's own BindToClose).
local function finalize(player: Player, profile: any)
	if profile.finalized then
		return
	end
	profile.finalized = true
	for _, hook in releaseHooks do
		local ok, err = pcall(hook, player, profile.Data)
		if not ok then
			warn("[DataService] release hook failed:", err)
		end
	end
	profile.Data.lastSeen = DataService.now()
end

local function release(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	releasing[player] = true
	profiles[player] = nil
	dirty[player] = nil
	finalize(player, profile)
	profile:EndSession()
	releasing[player] = nil
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if not profile then
		player:Kick("Couldn't load your farm. Please rejoin.")
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	if not profile.Data.grantedStarterEggs then
		profile.Data.grantedStarterEggs = true
		for eggId, count in GameConfig.startingEggs do
			profile.Data.eggs[eggId] = (profile.Data.eggs[eggId] or 0) + count
		end
	end
	profile.OnLastSave:Connect(function()
		finalize(player, profile)
	end)
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		-- Only a session taken by another server needs a kick; not our own release or shutdown.
		if not releasing[player] and not ProfileStore.IsClosing and player.Parent == Players then
			player:Kick("Your farm was opened on another server. Please rejoin.")
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	profiles[player] = profile
	DataService.Loaded:Fire(player, profile.Data)
	DataService.changed(player)
end

function DataService.Init()
	ProfileStore.SetConstant("AUTO_SAVE_PERIOD", GameConfig.autoSaveSeconds)
	Net.setDataGetter(DataService.get)
end

function DataService.Start()
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	-- Batch snapshot pushes so many changes in one frame send one message.
	local state = Remotes.get("State")
	while true do
		task.wait(GameConfig.stateFlushInterval)
		for player in dirty do
			dirty[player] = nil
			local data = DataService.get(player)
			if data then
				state:FireClient(player, snapshot(data))
				DataService.Changed:Fire(player, data)
			end
		end
	end
end

return DataService
