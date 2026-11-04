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
local Eggs = require(Shared.Config.Eggs)
local Growth = require(Shared.Growth)
local GemUpgrades = require(Shared.GemUpgrades)
local Valuation = require(Shared.Valuation)
local Costs = require(Shared.Costs)
local Pen = require(Shared.Pen)
local Streak = require(Shared.Streak)
local Daily = require(Shared.Config.Daily)
local Products = require(Shared.Config.Products)
local OnboardingConfig = require(Shared.Config.Onboarding)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)
local Net = require(script.Parent.Parent.Util.Net)
local Validate = require(script.Parent.Parent.Util.Validate)

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
	patches = {}, -- Auto-Harvest replant toggle + last egg per patch (Types.Patch)
	eggs = {}, -- starting eggs are granted once in onPlayerAdded (Reconcile would refill a template value)
	inventory = {},
	pen = {},
	upgrades = { growthSpeed = 0, mutationOdds = 0 },
	gemUpgrades = { penSlots = 0, luck = 0, offline = 0 }, -- kept through rebirth
	ownedPasses = {},
	processedPurchases = {},
	-- Watering (shared/Watering.lua): the tap boost runs at `waterMult` until `wateredUntil`;
	-- `waterOffer` is the next tap's multiplier (rolled by WaterService; 0 = not rolled yet);
	-- `onPad` = standing on the plot's water pad right now (reset on join, never true offline).
	wateredUntil = 0,
	waterMult = 1,
	waterOffer = 0,
	onPad = false,
	lastSeen = 0,
	streak = { day = 0, lastClaimDay = 0, count = 0 }, -- day = position in the 7-day cycle, count = days in a row
	redeemedCodes = {},
	funnel = {},
	grantedStarterEggs = false,
	-- Almanac: speciesId -> { n = times hatched, first = timestamp, best = biggest size }
	almanac = {},
	stats = {
		eggsBought = 0,
		eggsPlanted = 0,
		harvested = 0,
		sold = 0,
		totalCashEarned = 0,
		-- Cash earned since the last rebirth (every addCash source, like totalCashEarned): the
		-- rebirth requirement. Reset to 0 by the rebirth, after its bag sale.
		cashEarnedThisLife = 0,
		waters = 0,
		padVisits = 0,
		slotsBought = 0,
	},
	nextItemId = 1,
	bundleOfferEndsAt = 0,
	bundleBought = false,
	fastHatch = false,
	potionUntil = 0,
	groupRewardClaimed = false,
	almanacRewards = 0,
	inGroup = false,
	almanacLuck = 0,
	groupOffered = false, -- the group offer was shown (once, at the first sale)
	vipGemsDay = 0, -- UTC day of the last VIP daily Gems claim
	seenLimited = {}, -- limited egg id -> true once the shop has opened on it
	-- The scripted opening (Config/Onboarding, OnboardingService). `active` only on profiles
	-- created with it on; the rest are once-per-profile flags. playSeconds: online seconds so far.
	tutorialDone = false, -- the tutorial card's 9 steps are done (OpenedAlmanac); Next Up after
	onboarding = {
		active = false,
		preplanted = false,
		firstHatch = false,
		shopOpened = false,
		weather = false,
		bundle = false,
		playSeconds = 0,
	},
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

-- The plot's watering state for the growth math (the water pad + the tap boost).
function DataService.water(data: Types.Profile): Growth.Water
	return Growth.water(data.wateredUntil, data.waterMult, data.onPad)
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

-- How many mutants the pen holds (and how many can be pinned): penDisplayCount + the Pen Slots
-- Gem upgrade (shared/GemUpgrades).
function DataService.penCapacity(data: Types.Profile): number
	return GemUpgrades.penCapacity(GemUpgrades.level(data.gemUpgrades, "penSlots"))
end

-- The mutants standing in the pen: pinned ones, then the owner's most valuable bag items, up to
-- penCapacity (shared/Pen.lua). Stable order so the pen doesn't reshuffle.
function DataService.penItems(data: Types.Profile): { Types.Item }
	return Pen.select(data.inventory, DataService.penCapacity(data)) :: any
end

-- Cash the pen pays per minute (not rounded): online, or at the offline rate.
function DataService.penIncome(data: Types.Profile, offline: boolean?): number
	local mult = Valuation.rebirthMultiplier(data.rebirths)
	local rate = if offline then GameConfig.penIncomePerMinuteOffline else GameConfig.penIncomePerMinute
	local total = 0
	for _, item in DataService.penItems(data) do
		total += Valuation.penIncome(item, mult, rate)
	end
	return total
end

-- 2x Luck pass x Luck Potion (while active) x permanent luck (the Almanac's + the Permanent Luck
-- Gem upgrade). Rolls.clampLuck caps the total at Game.maxLuck.
function DataService.luck(data: Types.Profile): number
	local pass = if data.ownedPasses.Luck2x then 2 else 1
	local potion = if DataService.now() < data.potionUntil then Products.gems.LuckPotion.luck else 1
	local permanent = data.almanacLuck + GemUpgrades.luckBonus(GemUpgrades.level(data.gemUpgrades, "luck"))
	return pass * potion * (1 + permanent)
end

-- Extra mutation chance from the Mutation Odds upgrade.
function DataService.oddsBonus(data: Types.Profile): number
	return Upgrades.mutationOdds.bonusPerLevel * data.upgrades.mutationOdds
end

-- Planted eggs now: still growing, and mature (ready to hatch).
function DataService.eggCounts(data: Types.Profile): (number, number)
	local now, speed = DataService.now(), DataService.speed(data)
	local growing, ready = 0, 0
	for _, slot in data.slots do
		local required = Growth.slotRequired(slot)
		if Growth.secondsRemaining(slot.growth, required, now, DataService.water(data), speed) > 0 then
			growing += 1
		else
			ready += 1
		end
	end
	return growing, ready
end

-- Farm income for the HUD and the gate sign: what the pen's mutants earn per minute (eggs earn
-- nothing until they're hatched and sold). Cents are kept: a lone pen mutant earns a few cents.
function DataService.incomePerMinute(data: Types.Profile): number
	return math.floor(DataService.penIncome(data) * 100) / 100
end

-- PolicyService result per online player (MonetizationService fills it on join): true when paid
-- random items / paid odds boosts aren't allowed for them. Unknown counts as restricted.
DataService.paidRandomRestricted = {} :: { [Player]: boolean }

-- Server time each online player's session started (funnel steps carry seconds since it).
DataService.joinedAt = {} :: { [Player]: number }

function DataService.secondsSinceJoin(player: Player): number
	return DataService.now() - (DataService.joinedAt[player] or DataService.now())
end

-- Server time of each online player's next pen payout (not saved; restarts on join).
DataService.nextPayoutAt = {} :: { [Player]: number }

-- Daily streak status for the HUD: the day you'd claim next and whether it's claimable now.
function DataService.dailyStatus(data: Types.Profile): { day: number, canClaim: boolean, streak: number }
	local today = math.floor(DataService.now() / 86400)
	local day, canClaim, streak =
		Streak.status(data.streak.day, data.streak.lastClaimDay, today, #Daily.rewards, data.streak.count)
	return { day = day, canClaim = canClaim, streak = streak }
end

-- VIP pass owners can claim Passes.VIP.dailyGems once per UTC day.
function DataService.vipGemsReady(data: Types.Profile): boolean
	return data.ownedPasses.VIP == true and data.vipGemsDay < math.floor(DataService.now() / 86400)
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
			required = Growth.slotRequired(slot),
		}
	end
	local growingCount, readyCount = DataService.eggCounts(data)
	local replant = {}
	for key, patch in data.patches do
		if patch.replant then
			replant[key] = true
		end
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
		waterMult = data.waterMult,
		waterOffer = data.waterOffer,
		onPad = data.onPad,
		eggs = data.eggs,
		slots = slots,
		replant = replant,
		inventory = data.inventory,
		inventoryCap = GameConfig.inventoryCap,
		nextSlotCost = DataService.nextSlotCost(data),
		stats = data.stats,
		incomePerMinute = DataService.incomePerMinute(data),
		growingCount = growingCount,
		readyCount = readyCount,
		penPerMinute = math.floor(DataService.penIncome(data)),
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
		gemUpgrades = data.gemUpgrades,
		penCapacity = DataService.penCapacity(data),
		almanacRewards = data.almanacRewards,
		inGroup = data.inGroup,
		almanacLuck = data.almanacLuck,
		ownedPasses = data.ownedPasses,
		rebirthCost = Costs.rebirth(data.rebirths),
		earnedThisLife = data.stats.cashEarnedThisLife,
		vipGemsReady = DataService.vipGemsReady(data),
		seenLimited = data.seenLimited,
		bundleOfferEndsAt = if data.bundleBought or DataService.now() >= data.bundleOfferEndsAt
			then 0
			else data.bundleOfferEndsAt,
		tutorialDone = data.tutorialDone,
		onboarding = {
			active = data.onboarding.active,
			shopOpened = data.onboarding.shopOpened,
			weather = data.onboarding.weather,
		},
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
	DataService.joinedAt[player] = nil
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
	-- Profiles from before cashEarnedThisLife (2026-11-04) keep their progress: what they held
	-- was the old requirement. Seeded once, below, after Reconcile adds the field.
	-- Profiles from before the tutorial card (2026-11-04) that are past its hatch steps skip it.
	local seedTutorial = profile.Data.grantedStarterEggs == true and profile.Data.tutorialDone == nil
	local seedLife = profile.Data.grantedStarterEggs == true
		and (profile.Data.stats == nil or profile.Data.stats.cashEarnedThisLife == nil)
	profile:Reconcile()
	if seedTutorial and (profile.Data.stats.harvested or 0) >= 2 then
		profile.Data.tutorialDone = true
	end
	-- The grow ramp is gone (2026-11-05): its fields leave saved data.
	profile.Data.stats.hatchesThisLife = nil
	for _, slot in profile.Data.slots do
		slot.baseGrow = nil
	end
	if seedLife then
		profile.Data.stats.cashEarnedThisLife = math.max(0, profile.Data.cash or 0)
	end
	-- Nobody is standing on a pad when they join (and the growth since leaving was dry).
	profile.Data.onPad = false
	-- Renamed stat: carry the old lifetime total over once.
	local stats = profile.Data.stats :: any
	if stats.cashEarned and stats.totalCashEarned == 0 then
		stats.totalCashEarned = stats.cashEarned
	end
	stats.cashEarned = nil
	-- A brand-new profile gets the scripted opening (Config/Onboarding): OnboardingService plants
	-- its first egg; the bag gets Onboarding.bag instead of Game.startingEggs.
	local isNew = not profile.Data.grantedStarterEggs
	if isNew and OnboardingConfig.enabled then
		profile.Data.onboarding.active = true
	end
	-- The Starter Bundle is for new players: profiles from before it existed never get the window.
	-- Onboarding profiles get it on the reveal of their first Rare (OnboardingService), not on join.
	local waitsForRare = profile.Data.onboarding.active and not profile.Data.onboarding.bundle
	if profile.Data.bundleOfferEndsAt == 0 and waitsForRare then
		-- stays 0 until the first Rare's reveal
	elseif profile.Data.bundleOfferEndsAt == 0 and profile.Data.grantedStarterEggs then
		profile.Data.bundleOfferEndsAt = -1
	elseif profile.Data.bundleOfferEndsAt == 0 then
		profile.Data.bundleOfferEndsAt = DataService.now() + Products.robux.StarterBundle.offerSeconds
	end
	if isNew then
		profile.Data.grantedStarterEggs = true
		local bag = if profile.Data.onboarding.active then OnboardingConfig.bag else GameConfig.startingEggs
		for eggId, count in bag do
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
	DataService.joinedAt[player] = DataService.now()
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
	-- Pin / unpin a bag mutant: pinned ones always stand in the pen (at most penCapacity),
	-- are skipped by Sell All and stay through rebirth.
	Net.on("Pin", function(player, data, itemId, on)
		if not Validate.string(itemId, 16) or typeof(on) ~= "boolean" then
			return
		end
		local item = data.inventory[itemId]
		if not item or (item.pinned == true) == on then
			return
		end
		if on and not Pen.canPin(data.inventory, DataService.penCapacity(data)) then
			Net.notify(
				player,
				string.format("Your pen holds %d. Unpin one first!", DataService.penCapacity(data)),
				"info"
			)
			return
		end
		item.pinned = if on then true else nil
		DataService.changed(player)
	end)
	-- The shop opened on a limited egg for the first time: remember it (once per egg).
	Net.on("SeenLimited", function(player, data, eggId)
		if Validate.string(eggId, 32) and Eggs.tiers[eggId] and Eggs.tiers[eggId].limited then
			data.seenLimited[eggId] = true
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
