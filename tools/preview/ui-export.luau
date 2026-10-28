-- Runs the real client UI (Fusion 0.2 + our UI modules) headlessly under Lune's Roblox library,
-- puts it into a series of game states, and exports each GUI tree as JSON for ui-render.mjs.
-- Roblox-only pieces (events, render loop, sounds, 3D viewports) are stubbed; layout is done
-- by the browser, so this is for checking layout, overlap, sizing and color, not animation.
--
--   rojo build default.project.json -o build/preview.rbxl
--   lune run tools/preview/ui-export -- build/preview.rbxl build/ui.json

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local args = {}
for _, a in process.args do
	if a ~= "--" then
		table.insert(args, a)
	end
end
local placePath, outPath = args[1], args[2]
assert(placePath and outPath, "usage: ui-export <place.rbxl> <ui.json>")

local game = roblox.deserializePlace(fs.readFile(placePath))
local Instance = roblox.Instance

---------------------------------------------------------------------------- stubs

local deferred = {}
local function flush()
	for _ = 1, 20 do
		if #deferred == 0 then
			return
		end
		local list = deferred
		deferred = {}
		for _, job in list do
			job[1](table.unpack(job, 2))
		end
	end
end

local nullSignal = {
	Connect = function()
		return { Disconnect = function() end }
	end,
}
local task = {
	spawn = function(f, ...)
		if type(f) == "function" then
			f(...)
		end
	end,
	defer = function(f, ...)
		table.insert(deferred, { f, ... })
	end,
	delay = function() end,
	wait = function()
		return 0
	end,
}
local services = {
	RunService = {
		BindToRenderStep = function() end,
		UnbindFromRenderStep = function() end,
		IsServer = function()
			return false
		end,
		IsClient = function()
			return true
		end,
		RenderStepped = nullSignal,
		Heartbeat = nullSignal,
	},
	TweenService = {
		Create = function()
			return { Play = function() end }
		end,
	},
	SoundService = {},
	ContextActionService = {
		BindActionAtPriority = function() end,
		UnbindAction = function() end,
	},
	Players = { LocalPlayer = { UserId = 1, Name = "Preview", Character = nil } },
}
local fakeWorkspace = setmetatable({
	GetServerTimeNow = function()
		return 1_800_000_000
	end,
	CurrentCamera = { ViewportSize = roblox.Vector2.new(900, 600) },
}, {
	__index = function(_, k)
		return game:GetService("Workspace")[k]
	end,
})
local fakeGame = {
	GetService = function(_, name)
		return services[name] or game:GetService(name)
	end,
}

-- Source patches so Fusion doesn't touch events that Lune instances don't have.
local PATCHES = {
	applyInstanceProps = {
		{ "applyTo.Destroying:Connect(", "__nullSignal:Connect(" },
		{
			"if not pcall(setProperty_unsafe, instance, property, value) then",
			-- Roblox lets you set properties on destroyed instances (only Parent locks); Lune doesn't.
			"local __ok, __err = pcall(setProperty_unsafe, instance, property, value)\n\tif not __ok and tostring(__err):find('destroyed') then return end\n\tif not __ok then",
		},
	},
	OnEvent = {
		{ "local ok, event = pcall(getProperty_unsafe, applyTo, eventName)", "do return end\n\t\tlocal ok, event" },
	},
	-- Springs never tick headlessly; snap them to their goal so screenshots show final values.
	Fusion = {
		{
			"Spring = require(script.Animation.Spring),",
			"Spring = function(goal) goal.setPosition = goal.setPosition or function() end; return goal end,",
		},
	},
	-- Roblox no-ops Parent = nil on a destroyed instance; Lune errors.
	Children = { { "oldInstance.Parent = nil", "pcall(function() oldInstance.Parent = nil end)" } },
	OnChange = {
		{
			"local ok, event = pcall(applyTo.GetPropertyChangedSignal, applyTo, propertyName)",
			"do return end\n\t\tlocal ok, event",
		},
	},
}

-- Modules replaced entirely in preview mode.
local OVERRIDES = {
	Sfx = { play = function() end },
	Viewport = {
		new = function(props)
			local f = Instance.new("ViewportFrame")
			f.Name = "Viewport"
			f.BackgroundTransparency = 1
			f.Size = props.Size or roblox.UDim2.fromScale(1, 1)
			f.Position = props.Position or roblox.UDim2.new()
			f.AnchorPoint = props.AnchorPoint or roblox.Vector2.new()
			f.ZIndex = props.ZIndex or 1
			f:SetAttribute("Silhouette", props.Silhouette == true)
			f:SetAttribute("Label", props.Label or "")
			return f
		end,
	},
}

local cache = {}
local env
local function requireModule(module)
	if type(module) == "table" then
		return module -- already a stub
	end
	if cache[module] ~= nil then
		return cache[module]
	end
	local override = OVERRIDES[module.Name]
	if override and module.Parent and module.Parent.Name ~= "Fusion" then
		cache[module] = override
		return override
	end
	local source = module.Source
	for _, patch in PATCHES[module.Name] or {} do
		local a, b = patch[1], patch[2]
		local i = source:find(a, 1, true)
		assert(i, "patch target not found in " .. module.Name)
		source = source:sub(1, i - 1) .. b .. source:sub(i + #a)
	end
	local e = table.clone(env)
	e.script = module
	local chunk = luau.load(source, { debugName = module:GetFullName(), environment = e })
	local result = chunk()
	cache[module] = result
	return result
end

env = {
	game = fakeGame,
	workspace = fakeWorkspace,
	require = requireModule,
	task = task,
	__nullSignal = nullSignal,
	Instance = Instance,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	TweenInfo = {
		new = function()
			return {}
		end,
	},
	Font = roblox.Font,
	typeof = typeof,
	os = os,
}

---------------------------------------------------------------------------- mount

local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
local State = requireModule(client.State)
local UI = client.UI

local function stateValue(v)
	return v
end

local mountModule = UI:FindFirstChild("Root")
local root
if mountModule then
	root = requireModule(mountModule)()
else
	-- Fallback: mount the individual screens like UIController does.
	local Fusion = requireModule(game:GetService("ReplicatedStorage").Packages.Fusion)
	root = Fusion.New("Frame")({
		Name = "Root",
		BackgroundTransparency = 1,
		Size = roblox.UDim2.fromScale(1, 1),
		[Fusion.Children] = {
			requireModule(UI.Hud)(),
			requireModule(UI.Toasts)(),
			requireModule(UI.EggShop)(),
			requireModule(UI.SellPanel)(),
			requireModule(UI.Almanac)(),
			requireModule(UI.HatchOverlay)(),
		},
	})
end
local _ = stateValue

---------------------------------------------------------------------------- mock game states

local function item(id, tier, rarity, n, size, mutations)
	local Mutants = requireModule(game:GetService("ReplicatedStorage").Shared.Config.Mutants)
	return {
		id = tostring(id),
		tier = tier,
		rarity = rarity,
		species = Mutants.buckets[tier][rarity][n],
		mutations = mutations or {},
		size = size,
		harvestedAt = 0,
	}
end

local inventory = {}
for i, it in
	{
		item(1, "Starter", "Common", 1, 1.1),
		item(2, "Starter", "Rare", 2, 1.4, { "Shiny" }),
		item(3, "Swamp", "Epic", 3, 2.1, { "Golden" }),
		item(4, "Swamp", "Common", 4, 0.9),
		item(5, "Starter", "Uncommon", 5, 1.2),
		item(6, "Pumpkin", "Rare", 1, 1.3),
	}
do
	inventory[tostring(i)] = it
end
inventory["4"].pinned = true -- a low-value mutant kept in the pen

local snapshot = {
	serverTime = 1_800_000_000,
	cash = 48_250,
	gems = 60,
	rebirths = 0,
	slotCount = 8,
	cashMultiplier = 1,
	speed = 1,
	wateredUntil = 1_800_000_012,
	eggs = { Starter = 3, Swamp = 2, Pumpkin = 1 },
	slots = {},
	inventory = inventory,
	inventoryCap = 200,
	nextSlotCost = 675,
	stats = {
		eggsPlanted = 12,
		harvested = 9,
		sold = 4,
		eggsBought = 5,
		waters = 6,
		slotsBought = 2,
		totalCashEarned = 12_400,
	},
	incomePerMinute = 3_400,
	nextPayoutAt = 1_800_000_000 + 21,
	payoutSeconds = 60,
	totalSlots = 8,
	ownedPasses = {},
	rebirthCost = 700_000,
	bundleOfferEndsAt = 1_800_000_000 + 581,
	daily = { day = 2, canClaim = true, streak = 1 },
	potionUntil = 0,
	groupRewardClaimed = false,
	paidRandomRestricted = false,
	upgrades = { growthSpeed = 2, mutationOdds = 0 },
	upgradeCosts = { growthSpeed = 18_000, mutationOdds = 2_000 },
	almanacRewards = 1,
	inGroup = true,
	almanacLuck = 0,
	fastHatch = false,
}

local almanac = {}
do
	local Mutants = requireModule(game:GetService("ReplicatedStorage").Shared.Config.Mutants)
	local n = 0
	for id in Mutants.species do
		n += 1
		if n % 9 == 0 then
			almanac[id] = { n = 3, first = 1_799_000_000, best = 1.7 }
		end
	end
end

local scenes = {}
local function capture(name: string)
	flush()
	local function ser(inst)
		local node = { class = inst.ClassName, name = inst.Name, props = {}, children = {} }
		local p = node.props
		local function put(key)
			local ok, v = pcall(function()
				return inst[key]
			end)
			if not ok or v == nil then
				return
			end
			local t = typeof(v)
			if t == "UDim2" then
				p[key] = { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset }
			elseif t == "UDim" then
				p[key] = { v.Scale, v.Offset }
			elseif t == "Vector2" then
				p[key] = { v.X, v.Y }
			elseif t == "Color3" then
				p[key] = { v.R, v.G, v.B }
			elseif t == "EnumItem" then
				p[key] = v.Name
			elseif t == "ColorSequence" then
				local ks = {}
				for _, k in v.Keypoints do
					table.insert(ks, { k.Time, k.Value.R, k.Value.G, k.Value.B })
				end
				p[key] = ks
			elseif t == "NumberSequence" then
				local ks = {}
				for _, k in v.Keypoints do
					table.insert(ks, { k.Time, k.Value })
				end
				p[key] = ks
			elseif t == "number" or t == "string" or t == "boolean" then
				p[key] = v
			end
		end
		for _, key in
			{
				"Size",
				"Position",
				"AnchorPoint",
				"Visible",
				"BackgroundColor3",
				"BackgroundTransparency",
				"ZIndex",
				"LayoutOrder",
				"Rotation",
				"ClipsDescendants",
				"AutomaticSize",
				"Text",
				"TextColor3",
				"TextTransparency",
				"TextScaled",
				"TextSize",
				"TextWrapped",
				"RichText",
				"Font",
				"TextXAlignment",
				"TextYAlignment",
				"Image",
				"ImageColor3",
				"ImageTransparency",
				"CornerRadius",
				"Color",
				"Thickness",
				"Transparency",
				"ApplyStrokeMode",
				"Enabled",
				"PaddingTop",
				"PaddingBottom",
				"PaddingLeft",
				"PaddingRight",
				"FillDirection",
				"HorizontalAlignment",
				"VerticalAlignment",
				"SortOrder",
				"Padding",
				"CellSize",
				"CellPadding",
				"Scale",
				"AspectRatio",
				"MaxTextSize",
				"MinTextSize",
				"MaxSize",
				"MinSize",
				"Offset",
			}
		do
			put(key)
		end
		local attrs = inst:GetAttributes()
		if next(attrs) then
			node.attrs = attrs
		end
		for _, child in inst:GetChildren() do
			table.insert(node.children, ser(child))
		end
		return node
	end
	table.insert(scenes, { name = name, root = ser(root) })
end

local function set(value, v)
	value:set(v, true)
end

set(State.snapshot, snapshot)
set(State.now, 1_800_000_000)
set(State.weather, { nextId = "AcidRain", nextAt = 1_800_000_000 + 252, id = "", endsAt = 0 })
set(State.almanac, almanac)
set(State.objective, { text = "Next soil patch: $675", progress = 0.62 })
set(State.toasts, {
	{ id = 1, text = "GOLDEN x5 on your Swamp Egg · worth $4.5K now", kind = "success" },
})
set(State.panel, "none")
-- HUD states, each captured once per screen size (some layout depends on the real screen size,
-- e.g. the egg tray shifting clear of the chat). Named "hud...@WxH"; ui-render checks each at
-- its own size. Keep this list in sync with ui-render's sizes + checkSizes.
local SCREENS = { { 1280, 720 }, { 844, 390 }, { 667, 375 }, { 800, 360 }, { 1024, 768 }, { 1920, 1080 } }
local function captureHud(name)
	for _, wh in SCREENS do
		local w, h = wh[1], wh[2]
		set(
			State.screen,
			{ width = w, height = h - 58, scale = math.clamp(math.min(w / 900, (h - 58) / 540), 0.5, 1.4) }
		)
		capture(string.format("%s@%dx%d", name, w, h))
	end
	set(State.screen, { width = 1280, height = 720, scale = 720 / 540 })
end
set(State.zone, "hub")
captureHud("hud")
set(State.zone, "plot")
captureHud("hud-plot")
set(State.touch, true)
captureHud("hud-plot-touch")
set(State.zone, "hub")
captureHud("hud-touch")
set(State.touch, false)

set(State.toasts, {})
-- Egg Shop carousel, per screen size: Cash mode, Gem mode (same focus and offset), and a player
-- restricted by PolicyService (no switch, no potion). Opening focuses the best affordable egg.
set(State.panel, "shop")
captureHud("shop")
set(State.shopMode, "Gems")
captureHud("shop-gems")
set(State.shopMode, "Cash")
set(State.panel, "none")
local restricted = table.clone(snapshot)
restricted.paidRandomRestricted = true
set(State.snapshot, restricted)
set(State.panel, "shop")
captureHud("shop-restricted")
set(State.panel, "none")
set(State.snapshot, snapshot)
-- Mid-session unlock: crossing $25K earned while the shop is open turns Lab buyable with NEW.
set(State.panel, "shop")
do
	local pitch = requireModule(game:GetService("ReplicatedStorage").Shared.Config.EggShopUI).pitch
	local after = table.clone(snapshot)
	after.stats = table.clone(snapshot.stats)
	after.stats.totalCashEarned = 26_000
	set(State.snapshot, after)
	set(State.clock, (State.clock:get() or 0) + 1) -- past the unlock flash
	set(State.shopFocus, 3)
	set(State.shopOffset, 2 * pitch)
	captureHud("shop-unlock")
	-- Focus on the next locked tier (Lab, progress card) with a further-locked neighbor (Toxic).
	set(State.snapshot, snapshot)
	captureHud("shop-next")
	set(State.snapshot, snapshot)
	set(State.shopFocus, 2)
	set(State.shopOffset, pitch)
end
-- A limited egg on sale (inside the Pumpkin Egg's window), never seen: the shop opens on it, at
-- the left end, in Cash and Gem mode; a restricted player never sees it.
do
	local LIMITED_NOW = 1_793_500_000 -- 2026-11-01, inside the Pumpkin window
	local lim = table.clone(snapshot)
	lim.serverTime = LIMITED_NOW
	lim.seenLimited = {}
	lim.gems = 650
	set(State.panel, "none")
	set(State.now, LIMITED_NOW)
	set(State.snapshot, lim)
	set(State.panel, "shop")
	set(State.clock, (State.clock:get() or 0) + 1) -- past the first-open flash
	captureHud("shop-limited")
	set(State.shopMode, "Gems")
	captureHud("shop-limited-gems")
	set(State.shopMode, "Cash")
	set(State.panel, "none")
	local restrictedLim = table.clone(lim)
	restrictedLim.paidRandomRestricted = true
	set(State.snapshot, restrictedLim)
	set(State.panel, "shop")
	captureHud("shop-limited-restricted")
	set(State.panel, "none")
	set(State.snapshot, snapshot)
	set(State.now, 1_800_000_000)
end
set(State.panel, "sell")
capture("sell")
set(State.panel, "almanac")
capture("almanac")
set(State.panel, "daily")
capture("daily")
do -- a VIP owner with today's Gems to claim
	local vip = table.clone(snapshot)
	vip.ownedPasses = { VIP = true }
	vip.vipGemsReady = true
	vip.inGroup = false
	set(State.snapshot, vip)
	capture("daily-vip")
	set(State.snapshot, snapshot)
end
set(State.panel, "groupOffer")
capture("groupOffer")
set(State.welcome, { away = 3 * 3600 + 720, ready = 6, mutations = 4, capped = true, earned = 128_400 })
set(State.panel, "welcome")
capture("welcome")
set(State.panel, "store")
capture("store")
set(State.panel, "slotOffer")
capture("slotOffer")
set(State.panel, "rebirth")
capture("rebirth")
set(State.panel, "upgrades")
capture("upgrades")

set(State.panel, "none")

-- The hatch cinematic is plain Instances (HatchScreen), shown here at the reveal.
do
	local HatchScreen = requireModule(UI.HatchScreen)
	local Rarities = requireModule(game:GetService("ReplicatedStorage").Shared.Config.Rarities)
	local Mutations = requireModule(game:GetService("ReplicatedStorage").Shared.Config.Mutations)
	local Theme = requireModule(UI.Theme)
	local screen = HatchScreen.new()
	local gold = roblox.Color3.fromHex(Rarities.info.Legendary.color)

	screen.titleGradient.Color =
		roblox.ColorSequence.new(roblox.Color3.fromHex("#FFF3A8"), roblox.Color3.fromHex("#FF9A1F"))
	screen.title.Text = "LEGENDARY!"
	screen.value.Text = "Worth $1.62M"
	screen.name.Text = "Duchess Froibby"
	screen.newRibbon.Visible = true
	screen.queue.Text = "+2 more"
	screen.skipAll.Visible = true
	screen.potion.Visible = true
	screen.pin.Visible = true
	HatchScreen.setChips(screen, {
		{ text = "x2.31 size", color = Theme.colors.slateLight },
		{ text = "47 studs tall", color = Theme.colors.slateLight },
		{
			text = "GOLDEN x5",
			color = roblox.Color3.fromHex(Mutations.info.Golden.color):Lerp(Theme.colors.slate, 0.35),
		},
	})
	root = screen.root
	capture("hatch")
end

fs.writeFile(outPath, serde.encode("json", { scenes = scenes }))
print(string.format("exported %d UI scenes", #scenes))
