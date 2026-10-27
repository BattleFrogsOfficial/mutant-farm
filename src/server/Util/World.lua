--!strict
-- Builds the whole map in code: slime ground, the central hub, and a ring of player islands.
-- Keeping the map in code means the repo is the single source of truth (no .rbxl to merge).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)

local World = {}

export type Island = {
	index: number,
	model: Model,
	slots: { BasePart },
	spawn: CFrame,
	sign: TextLabel,
}

local COLORS = {
	slime = Color3.fromHex("#4FB83A"),
	cream = Color3.fromHex("#FFF4D6"),
	grass = Color3.fromHex("#8BD86B"),
	soil = Color3.fromHex("#6B4A2F"),
	lockedSoil = Color3.fromHex("#3A3F4F"),
	path = Color3.fromHex("#E8DDBF"),
	purple = Color3.fromHex("#9B5CFF"),
	gold = Color3.fromHex("#FFD24A"),
	slate = Color3.fromHex("#1E2230"),
}

local HUB_RADIUS = 36
local RING_RADIUS = 130
local ISLAND_SIZE = 60
local SLOT_SIZE = 5
local SLOT_SPACING = 6
local SLOT_COLUMNS = 8

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function label(parent: Instance, text: string, offset: Vector3, size: UDim2): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffset = offset
	gui.AlwaysOnTop = false
	gui.MaxDistance = 200
	gui.LightInfluence = 0
	local text_ = Instance.new("TextLabel")
	text_.Size = UDim2.fromScale(1, 1)
	text_.BackgroundTransparency = 1
	text_.Font = Enum.Font.FredokaOne
	text_.TextScaled = true
	text_.TextColor3 = Color3.new(1, 1, 1)
	text_.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = COLORS.slate
	stroke.Parent = text_
	text_.Parent = gui
	gui.Parent = parent
	return text_
end

local function prompt(parent: Instance, name: string, objectText: string, actionText: string)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ObjectText = objectText
	p.ActionText = actionText
	p.HoldDuration = 0
	p.MaxActivationDistance = 14
	p.RequiresLineOfSight = false
	p.Parent = parent
end

local function setLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.5
	Lighting.Ambient = Color3.fromRGB(120, 110, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 160, 180)
	Lighting.GlobalShadows = true
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.25
	atmosphere.Color = COLORS.cream
	atmosphere.Decay = Color3.fromHex("#C9B8FF")
	atmosphere.Glare = 0
	atmosphere.Haze = 1.5
	atmosphere.Parent = Lighting
end

local function buildHub(parent: Instance)
	local hub = Instance.new("Model")
	hub.Name = "Hub"

	part({
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, HUB_RADIUS * 2, HUB_RADIUS * 2),
		CFrame = CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.cream,
		Parent = hub,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(0, 2.5, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = hub

	local shop = part({
		Name = "EggShop",
		Size = Vector3.new(12, 8, 6),
		CFrame = CFrame.new(-16, 6, -6),
		Color = COLORS.purple,
		Parent = hub,
	})
	label(shop, "EGG SHOP", Vector3.new(0, 7, 0), UDim2.fromOffset(240, 60))
	prompt(shop, "EggShopPrompt", "Egg Shop", "Browse eggs")

	local sell = part({
		Name = "SellPad",
		Size = Vector3.new(12, 1, 12),
		CFrame = CFrame.new(16, 2.5, -6),
		Color = COLORS.gold,
		Material = Enum.Material.Neon,
		Parent = hub,
	})
	label(sell, "SELL", Vector3.new(0, 5, 0), UDim2.fromOffset(200, 60))
	prompt(sell, "SellPrompt", "Sell Pad", "Sell mutants")

	local altar = part({
		Name = "RebirthAltar",
		Size = Vector3.new(8, 10, 8),
		CFrame = CFrame.new(0, 7, 18),
		Color = COLORS.slate,
		Parent = hub,
	})
	label(altar, "REBIRTH ALTAR\ncoming soon", Vector3.new(0, 8, 0), UDim2.fromOffset(240, 80))

	hub.Parent = parent
end

local function buildIsland(index: number, parent: Instance): Island
	local angle = (index - 1) / GameConfig.islandCount * math.pi * 2
	local center = Vector3.new(math.cos(angle) * RING_RADIUS, 1, math.sin(angle) * RING_RADIUS)
	-- -Z of the island frame points at the hub, so "front" rows face the center.
	local frame = CFrame.lookAt(center, Vector3.new(0, 1, 0))

	local model = Instance.new("Model")
	model.Name = "Island" .. index
	model:SetAttribute("Index", index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("WateredUntil", 0)
	model:SetAttribute("Speed", 1)

	local base = part({
		Name = "Base",
		Size = Vector3.new(ISLAND_SIZE, 2, ISLAND_SIZE),
		CFrame = frame,
		Color = COLORS.grass,
		Material = Enum.Material.Grass,
		Parent = model,
	})
	model.PrimaryPart = base

	-- Path from hub edge to the island front.
	local hubEdge = Vector3.new(math.cos(angle) * HUB_RADIUS, 1.05, math.sin(angle) * HUB_RADIUS)
	local islandFront = (frame * CFrame.new(0, 0.05, -ISLAND_SIZE / 2)).Position
	local length = (islandFront - hubEdge).Magnitude
	part({
		Name = "Path",
		Size = Vector3.new(8, 2, length),
		CFrame = CFrame.lookAt((hubEdge + islandFront) / 2, islandFront),
		Color = COLORS.path,
		Parent = model,
	})

	local slotsFolder = Instance.new("Folder")
	slotsFolder.Name = "Slots"
	slotsFolder.Parent = model
	local slots = {}
	for i = 1, Upgrades.slots.max do
		local column = (i - 1) % SLOT_COLUMNS
		local row = (i - 1) // SLOT_COLUMNS
		local x = (column - (SLOT_COLUMNS - 1) / 2) * SLOT_SPACING
		local z = -ISLAND_SIZE / 2 + 8 + row * SLOT_SPACING
		local slot = part({
			Name = "Slot" .. i,
			Size = Vector3.new(SLOT_SIZE, 0.6, SLOT_SIZE),
			CFrame = frame * CFrame.new(x, 1.3, z),
			Color = COLORS.lockedSoil,
			Parent = slotsFolder,
		})
		slot:SetAttribute("Index", i)
		slot:SetAttribute("Active", false)
		slot:SetAttribute("EggId", "")
		slot:SetAttribute("Growth", 0)
		slot:SetAttribute("UpdatedAt", 0)
		slot:SetAttribute("Required", 0)
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 60
		click.Parent = slot
		slots[i] = slot
	end

	local signPost = part({
		Name = "Sign",
		Size = Vector3.new(1, 1, 1),
		CFrame = frame * CFrame.new(0, 2, ISLAND_SIZE / 2 - 6),
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})
	local sign = label(signPost, "Empty Farm", Vector3.new(0, 12, 0), UDim2.fromOffset(320, 70))

	model.Parent = parent
	return {
		index = index,
		model = model,
		slots = slots,
		-- Stand at the front edge, facing into the plot.
		spawn = frame * CFrame.new(0, 4, -ISLAND_SIZE / 2 + 3) * CFrame.Angles(0, math.pi, 0),
		sign = sign,
	}
end

function World.build(): { Island }
	setLighting()

	local map = Instance.new("Folder")
	map.Name = "Map"

	part({
		Name = "SlimeGround",
		Size = Vector3.new(800, 2, 800),
		CFrame = CFrame.new(0, -1, 0),
		Color = COLORS.slime,
		Parent = map,
	})

	buildHub(map)

	local islandsFolder = Instance.new("Folder")
	islandsFolder.Name = "Islands"
	islandsFolder.Parent = map
	local islands = {}
	for i = 1, GameConfig.islandCount do
		islands[i] = buildIsland(i, islandsFolder)
	end

	map.Parent = workspace
	return islands
end

World.colors = COLORS

return World
