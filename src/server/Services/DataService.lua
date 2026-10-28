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
local Streak = require(Shared.Streak)
local Daily = require(Shared.Config.Daily)
local Products = require(Shared.Config.Products)
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
	streak = { day = 0, lastClaimDay = 0, count = 0 }, -- day = position in the 7-day cycle, count = days in a row
	redeemedCodes = {},
	funnel = {},
	grantedStarterEggs = false,
	-- Almanac: speciesId -> { n = times hatched, first = timestamp, best = biggest size }
	almanac = {},
	stats = { eggsBought = 0, eggsPlanted = 0, harvested = 0, sold = 0, cashEarned = 0, waters = 0, slotsBought = 0 },
	nextItemId = 1,
	bundleOfferEndsAt = 0,
	bundleBought = false,
	fastHatch = false,
	potionUntil = 0,
	groupRewardClaimed = false,
	almanacRewards = 0,
	inGroup = false,
	almanacLuck = 0,
}

local store = ProfileStore.New("PlayerData_v1", TEMPLATE)
local profiles: { [Player]: any } = {}
local releasing: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}

function DataService.get(player: Player): Types.Profile?
	local profile = profiles[player]
	return profile and profile.Data
end

-- Saves now and waits (up to `timeout` s) for it to finish. Returns false if the session ended
-- or the save didn't land in time. Used before telling Roblox a Robux purchase was granted.
function DataService.saveNow(player: Player, timeout: number?): boolean
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end
	local saved = false
	local connection = profile.OnAfterSave:Connect(function()
		saved = true
	end)
	profile:Save()
	local deadline = os.clock() + (timeout or 15)
	while not saved and os.clock() < deadline and profile:IsActive() do
		task.wait(0.1)
	end
	connection:Disconnect()
	return saved and profiles[player] == profile
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
	return Valuation.cashMultiplier(
		data.rebirths,
		data.ownedPasses.VIP == true,
		if data.inGroup then GameConfig.groupCashBonus else 0
	)
end

-- Slots you can plant in: bought ones plus 10 from the +10 Plot Slots pass, up to the plot's 40.
function DataService.totalSlots(data: Types.Profile): number
	local bonus = if data.ownedPasses.PlotSlots10 then 10 else 0
	return math.min(Upgrades.slots.max, data.slotCount + bonus)
end

-- Cash price of the next patch (priced by how many you've bought), or nil when the plot is full.
function DataService.nextSlotCost(data: Types.Profile): number?
	if DataService.totalSlots(data) >= Upgrades.slots.max then
		return nil
	end
	return Costs.slot(data.slotCount + 1, data.rebirths)
end

-- The mutants standing in the pen: the owner's most valuable bag items, up to penDisplayCount.
-- Stable order (ties broken by id) so the pen doesn't reshuffle.
function DataService.penItems(data: Types.Profile): { Types.Item }
	local items = {}
	for _, item in data.inventory do
		table.insert(items, item)
	end
	table.sort(items, function(a, b)
		local va, vb = Valuation.sellValue(a, 1), Valuation.sellValue(b, 1)
		if va ~= vb then
			return va > vb
		end
		return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
	end)
	local out = {}
	for i = 1, math.min(#items, GameConfig.penDisplayCount) do
		out[i] = items[i]
	end
	return out
end

-- Cash the pen pays every minute while you're online.
function DataService.incomePerMinute(data: Types.Profile): number
	local mult = DataService.cashMultiplier(data)
	local total = 0
	for _, item in DataService.penItems(data) do
		total += Valuation.penIncome(item, mult, GameConfig.penIncomePerMinute)
	end
	return math.floor(total)
end

-- PolicyService result per online player (MonetizationService fills it on join): true when paid
-- random items / paid odds boosts aren't allowed for them. Unknown counts as restricted.
DataService.paidRandomRestricted = {} :: { [Player]: boolean }

-- Server time of each online player's next pen payout (not saved; restarts on join).
DataService.nextPayoutAt = {} :: { [Player]: number }

-- Daily streak status for the HUD: the day you'd claim next and whether it's claimable now.
function DataService.dailyStatus(data: Types.Profile): { day: number, canClaim: boolean, streak: number }
	local today = math.floor(DataService.now() / 86400)
	local day, canClaim, streak =
		Streak.status(data.streak.day, data.streak.lastClaimDay, today, #Daily.rewards, data.streak.count)
	return { day = day, canClaim = canClaim, streak = streak }
end

-- What the owning client is allowed to see. Rarity isn't sent, but `required` scales with rarity,
-- so an accurate timer implies it (a deliberate trade-off: "this one's taking longer...").
local function snapshot(player: Player, data: Types.Profile): Types.Snapshot
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
		nextSlotCost = DataService.nextSlotCost(data),
		stats = data.stats,
		incomePerMinute = DataService.incomePerMinute(data),
		nextPayoutAt = DataService.nextPayoutAt[player] or 0,
		payoutSeconds = GameConfig.payoutSeconds,
		daily = DataService.dailyStatus(data),
		totalSlots = DataService.totalSlots(data),
		fastHatch = data.fastHatch,
		potionUntil = data.potionUntil,
		groupRewardClaimed = data.groupRewardClaimed,
		paidRandomRestricted = DataService.paidRandomRestricted[player] ~= false, -- unknown = restricted
		upgrades = data.upgrades,
		upgradeCosts = {
			growthSpeed = Costs.upgrade("growthSpeed", data.upgrades.growthSpeed, data.rebirths),
			mutationOdds = Costs.upgrade("mutationOdds", data.upgrades.mutationOdds, data.rebirths),
		},
		almanacRewards = data.almanacRewards,
		inGroup = data.inGroup,
		almanacLuck = data.almanacLuck,
		ownedPasses = data.ownedPasses,
		rebirthCost = Costs.rebirth(data.rebirths),
		bundleOfferEndsAt = if data.bundleBought or DataService.now() >= data.bundleOfferEndsAt
			then 0
			else data.bundleOfferEndsAt,
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
	-- The Starter Bundle is for new players: profiles from before it existed never get the window.
	if profile.Data.bundleOfferEndsAt == 0 and profile.Data.grantedStarterEggs then
		profile.Data.bundleOfferEndsAt = -1
	elseif profile.Data.bundleOfferEndsAt == 0 then
		profile.Data.bundleOfferEndsAt = DataService.now() + Products.robux.StarterBundle.offerSeconds
	end
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
	-- Player setting: Fast Hatch (offered after FAST_HATCH_AFTER hatches).
	Net.on("SetFastHatch", function(player, data, on)
		if typeof(on) == "boolean" then
			data.fastHatch = on
			DataService.changed(player)
		end
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	-- Batch snapshot pushes so many changes in one frame send one message.
	local lastDay = math.floor(DataService.now() / 86400)
	local state = Remotes.get("State")
	while true do
		task.wait(GameConfig.stateFlushInterval)
		-- When the UTC day rolls over, resend everyone's state so the daily reward lights up.
		local day = math.floor(DataService.now() / 86400)
		if day ~= lastDay then
			lastDay = day
			for player in profiles do
				dirty[player] = true
			end
		end
		for player in dirty do
			dirty[player] = nil
			local data = DataService.get(player)
			if data then
				state:FireClient(player, snapshot(player, data))
				DataService.Changed:Fire(player, data)
			end
		end
	end
end

return DataService
