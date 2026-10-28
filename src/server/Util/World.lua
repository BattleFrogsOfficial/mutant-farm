--!strict
-- Builds the whole map in code: a round grass valley walled in by a fence and rocks, a slime
-- lake beyond it, the hub (fountain, Egg Shop stall, Sell stand) and a ring of fenced farm plots.
-- Keeping the map in code means the repo is the single source of truth (no .rbxl to merge).
-- Labels are SurfaceGuis on physical signs, never floating billboards.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Rng = require(ReplicatedStorage.Shared.Rng)

local World = {}

export type Plot = {
	index: number,
	model: Model,
	slots: { BasePart },
	spawn: SpawnLocation,
	sign: TextLabel,
	income: TextLabel,
	frame: CFrame,
}

local COLORS = {
	grass = Color3.fromHex("#7FCB5E"),
	plotGrass = Color3.fromHex("#9BE07A"),
	soil = Color3.fromHex("#5B3A24"),
	bed = Color3.fromHex("#7A5434"),
	path = Color3.fromHex("#E8DDBF"),
	cream = Color3.fromHex("#FFF4D6"),
	wood = Color3.fromHex("#A8754A"),
	darkWood = Color3.fromHex("#6E4A2E"),
	purple = Color3.fromHex("#9B5CFF"),
	toxic = Color3.fromHex("#7CFF4A"),
	slime = Color3.fromHex("#5FD43C"),
	gold = Color3.fromHex("#FFD24A"),
	slate = Color3.fromHex("#1E2230"),
	stone = Color3.fromHex("#9A93A8"),
	rock = Color3.fromHex("#6C6380"),
	hay = Color3.fromHex("#E8D27A"),
	buy = Color3.fromHex("#7CFF4A"),
}

-- Layout (studs)
local WORLD_RADIUS = 168 -- fence line; nothing walkable beyond it
local HUB_RADIUS = 34
local RING_RADIUS = 104 -- plot centers
local PLOT_HALF = 23
local SLOT_SIZE = 3.6
local SLOT_SPACING = 4.2
local SLOT_COLUMNS = 8
local GATE_WIDTH = 10

local rng = Rng.new(20261027) -- decoration placement is the same every server

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

-- Ellipsoid of any proportions: a block with a sphere mesh.
local function blob(props: { [string]: any }): Part
	local p = part(props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function wedge(props: { [string]: any }): WedgePart
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- A flat text sign on one face of a part.
local function signText(board: BasePart, face: Enum.NormalId, text: string, color: Color3?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = COLORS.slate
	stroke.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = label
	label.Parent = gui
	gui.Parent = board
	return label
end

local function prompt(parent: Instance, name: string, objectText: string, actionText: string)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ObjectText = objectText
	p.ActionText = actionText
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.Parent = parent
end

-- Wooden fence from a to b (y is ground level), posts every ~4 studs and two rails.
local function fence(parent: Instance, a: Vector3, b: Vector3, height: number?)
	local h = height or 3
	local length = (b - a).Magnitude
	if length < 0.5 then
		return
	end
	local posts = math.max(1, math.floor(length / 4))
	for i = 0, posts do
		local pos = a:Lerp(b, i / posts)
		part({
			Name = "Post",
			Size = Vector3.new(0.6, h + 0.4, 0.6),
			CFrame = CFrame.new(pos + Vector3.new(0, (h + 0.4) / 2, 0)),
			Color = COLORS.darkWood,
			Material = Enum.Material.Wood,
			Parent = parent,
		})
	end
	for _, y in { h * 0.45, h * 0.85 } do
		local mid = (a + b) / 2 + Vector3.new(0, y, 0)
		part({
			Name = "Rail",
			Size = Vector3.new(0.3, 0.35, length),
			CFrame = CFrame.lookAt(mid, b + Vector3.new(0, y, 0)),
			Color = COLORS.wood,
			Material = Enum.Material.Wood,
			Parent = parent,
		})
	end
end

local function tree(parent: Instance, pos: Vector3, scale: number, mutant: boolean)
	local trunkHeight = 7 * scale
	part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(trunkHeight, 1.6 * scale, 1.6 * scale),
		CFrame = CFrame.new(pos + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.darkWood,
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	local leaf = if mutant then COLORS.purple else Color3.fromHex("#4FAE3F")
	local leaf2 = if mutant then Color3.fromHex("#C29BFF") else Color3.fromHex("#6CCB4F")
	for i, offset in { Vector3.new(0, 0, 0), Vector3.new(1.6, -0.8, 0.6), Vector3.new(-1.3, -0.6, -0.9) } do
		local s = (if i == 1 then 6 else 4.2) * scale
		part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(s, s, s),
			CFrame = CFrame.new(pos + Vector3.new(0, trunkHeight + 1.2 * scale, 0) + offset * scale),
			Color = if i == 1 then leaf else leaf2,
			Material = Enum.Material.Grass,
			Parent = parent,
		})
	end
end

local function mushroom(parent: Instance, pos: Vector3, scale: number)
	local stem = 2.2 * scale
	part({
		Name = "Stem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(stem, 0.9 * scale, 0.9 * scale),
		CFrame = CFrame.new(pos + Vector3.new(0, stem / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.cream,
		Parent = parent,
	})
	local caps = { Color3.fromHex("#FF5A7A"), COLORS.purple, Color3.fromHex("#FF9A3C") }
	blob({
		Name = "Cap",
		Size = Vector3.new(3 * scale, 1.4 * scale, 3 * scale),
		CFrame = CFrame.new(pos + Vector3.new(0, stem + 0.2 * scale, 0)),
		Color = caps[rng:integer(1, #caps)],
		Parent = parent,
	})
end

local function barrel(parent: Instance, pos: Vector3)
	part({
		Name = "Barrel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 2.2, 2.2),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromHex("#3E8F2F"),
		Material = Enum.Material.Metal,
		Parent = parent,
	})
	part({
		Name = "Ooze",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 1.9, 1.9),
		CFrame = CFrame.new(pos + Vector3.new(0, 3.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.toxic,
		Parent = parent,
	})
end

local function rock(parent: Instance, pos: Vector3, size: Vector3)
	blob({
		Name = "Rock",
		Size = size,
		CFrame = CFrame.new(pos) * CFrame.Angles(0, rng:next() * math.pi * 2, 0),
		Color = COLORS.rock:Lerp(COLORS.stone, rng:next() * 0.6),
		Material = Enum.Material.Slate,
		Parent = parent,
	})
end

local function setLighting()
	-- Soft daylight. No Neon on big surfaces and only a whisper of bloom: bright, not glaring.
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(105, 98, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 145, 165)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.05
	atmosphere.Color = COLORS.cream
	atmosphere.Decay = Color3.fromHex("#B9A3FF")
	atmosphere.Glare = 0
	atmosphere.Haze = 1
	atmosphere.Parent = Lighting
	local color = Instance.new("ColorCorrectionEffect")
	color.Saturation = 0.08
	color.Contrast = 0.03
	color.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.12
	bloom.Size = 16
	bloom.Threshold = 2.6
	bloom.Parent = Lighting
end

local function buildTerrain(parent: Instance)
	-- Valley floor (top at y = 0), wide enough that the mountains outside stand on it.
	part({
		Name = "Valley",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 640, 640),
		CFrame = CFrame.new(0, -2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.grass,
		Material = Enum.Material.Grass,
		Parent = parent,
	})

	-- A solid hedge wall all the way round, rocks in front of it, mountains behind it.
	local edge = Instance.new("Folder")
	edge.Name = "Edge"
	edge.Parent = parent
	local hedge = Color3.fromHex("#3F8F3A")
	local hedgeTop = Color3.fromHex("#4FA845")
	local segments = 72
	for i = 0, segments - 1 do
		local a0 = i / segments * math.pi * 2
		local a1 = (i + 1) / segments * math.pi * 2
		local p0 = Vector3.new(math.cos(a0), 0, math.sin(a0)) * WORLD_RADIUS
		local p1 = Vector3.new(math.cos(a1), 0, math.sin(a1)) * WORLD_RADIUS
		local mid = (p0 + p1) / 2
		local length = (p1 - p0).Magnitude + 2
		part({
			Name = "Hedge",
			Size = Vector3.new(length, 14, 7),
			CFrame = CFrame.lookAt(mid + Vector3.new(0, 7, 0), Vector3.new(0, 7, 0)),
			Color = hedge,
			Material = Enum.Material.Grass,
			Parent = edge,
		})
		-- Bushy rounded top.
		for k, t in { 0.2, 0.55, 0.85 } do
			part({
				Name = "HedgeTop",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(8, 8, 8),
				CFrame = CFrame.new(p0:Lerp(p1, t) + Vector3.new(0, 13.5 + rng:next() * 1.5, 0)),
				Color = if (i + k) % 2 == 0 then hedge else hedgeTop,
				Material = Enum.Material.Grass,
				Parent = edge,
			})
		end
		-- Invisible wall well above the hedge so nobody climbs out.
		part({
			Name = "Barrier",
			Size = Vector3.new(length, 120, 2),
			CFrame = CFrame.lookAt(mid + Vector3.new(0, 60, 0), Vector3.new(0, 60, 0)),
			Transparency = 1,
			CanQuery = false,
			Parent = edge,
		})
		if i % 3 == 0 then
			local inward = -mid.Unit
			local s = 4 + rng:next() * 4
			rock(edge, mid + inward * (5 + s * 0.3) + Vector3.new(0, s * 0.3, 0), Vector3.new(s * 1.4, s, s * 1.1))
		end
	end
	-- Mountains close the horizon so the valley feels like a place, not a floating disc.
	for i = 1, 36 do
		local angle = i / 36 * math.pi * 2 + rng:next() * 0.08
		local radius = WORLD_RADIUS + 40 + rng:next() * 40
		local pos = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local s = 60 + rng:next() * 50
		blob({
			Name = "Mountain",
			Size = Vector3.new(s * 1.3, s * (0.8 + rng:next() * 0.5), s),
			CFrame = CFrame.lookAt(pos, Vector3.zero),
			Color = Color3.fromHex("#7A8F6A"):Lerp(COLORS.rock, rng:next() * 0.5),
			Material = Enum.Material.Grass,
			Parent = edge,
		})
	end
	-- Trees peeking over the hedge.
	for i = 0, 47 do
		local angle = (i + 0.5) / 48 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		tree(edge, dir * (WORLD_RADIUS + 12 + rng:next() * 10), 1.8 + rng:next() * 0.8, rng:next() < 0.2)
	end
end

local function lamp(parent: Instance, pos: Vector3)
	part({
		Name = "LampPole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(8, 0.5, 0.5),
		CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.slate,
		Material = Enum.Material.Metal,
		Parent = parent,
	})
	part({
		Name = "Lamp",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.4, 1.4, 1.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 8.4, 0)),
		Color = COLORS.cream,
		Parent = parent,
	})
end

local function flowerBed(parent: Instance, pos: Vector3)
	part({
		Name = "Bush",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)),
		Color = Color3.fromHex("#4FAE3F"),
		Material = Enum.Material.Grass,
		Parent = parent,
	})
	local flowers = { "#FF7AA8", "#FFD24A", "#C29BFF", "#FFFFFF" }
	for k = 1, 5 do
		local a = k / 5 * math.pi * 2
		part({
			Name = "Flower",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.6, 0.6, 0.6),
			CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 1.2, 2.1 + (k % 2) * 0.3, math.sin(a) * 1.2)),
			Color = Color3.fromHex(flowers[(k % #flowers) + 1]),
			Parent = parent,
		})
	end
end

local function buildHub(parent: Instance)
	local hub = Instance.new("Model")
	hub.Name = "Hub"

	part({
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, HUB_RADIUS * 2, HUB_RADIUS * 2),
		CFrame = CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.path,
		Material = Enum.Material.Cobblestone,
		Parent = hub,
	})
	part({
		Name = "PlazaBorder",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.38, HUB_RADIUS * 2 + 2, HUB_RADIUS * 2 + 2),
		CFrame = CFrame.new(0, 0.19, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.stone,
		Material = Enum.Material.Slate,
		Parent = hub,
	})
	part({
		Name = "Lawn",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 30, 30),
		CFrame = CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.plotGrass,
		Material = Enum.Material.Grass,
		Parent = hub,
	})

	-- Two-tier fountain with a golden egg statue on top.
	local stone = Color3.fromHex("#C9C2D6")
	local water = Color3.fromHex("#6FD3C7")
	local function disc(
		name: string,
		radius: number,
		height: number,
		y: number,
		color: Color3,
		material: Enum.Material,
		transparency: number?
	)
		part({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, radius * 2, radius * 2),
			CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = material,
			Transparency = transparency or 0,
			CanCollide = name ~= "Water",
			Parent = hub,
		})
	end
	disc("Basin", 8, 1.8, 1.4, stone, Enum.Material.Slate)
	disc("Water", 7.2, 0.2, 2.25, water, Enum.Material.Glass, 0.25)
	disc("Column", 1.4, 4, 4, stone, Enum.Material.Slate)
	disc("UpperBasin", 3.8, 0.9, 6.2, stone, Enum.Material.Slate)
	disc("Water", 3.2, 0.2, 6.6, water, Enum.Material.Glass, 0.25)
	disc("Pedestal", 1.2, 1.4, 7.4, stone, Enum.Material.Slate)
	local gold = Color3.fromHex("#E8B830")
	blob({
		Name = "EggStatue",
		Size = Vector3.new(3.4, 2.9, 3.4),
		CFrame = CFrame.new(0, 9.3, 0),
		Color = gold,
		Material = Enum.Material.Metal,
		Parent = hub,
	})
	blob({
		Name = "EggStatueTop",
		Size = Vector3.new(2.9, 3.6, 2.9),
		CFrame = CFrame.new(0, 10.3, 0),
		Color = gold,
		Material = Enum.Material.Metal,
		Parent = hub,
	})

	-- Flower beds around the lawn, lamps around the plaza.
	for i = 0, 7 do
		local a = (i + 0.5) / 8 * math.pi * 2
		flowerBed(hub, Vector3.new(math.cos(a) * 12.5, 0.4, math.sin(a) * 12.5))
	end
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2 + math.pi / 12
		lamp(hub, Vector3.new(math.cos(a) * (HUB_RADIUS - 2), 0.4, math.sin(a) * (HUB_RADIUS - 2)))
	end

	-- Egg Shop: a little market stall on the west side, counter facing the fountain.
	local shopFrame = CFrame.lookAt(Vector3.new(-23, 0, 0), Vector3.new(0, 0, 0))
	local function shop(cf: CFrame, props: { [string]: any })
		props.CFrame = shopFrame * cf
		return part(props)
	end
	shop(CFrame.new(0, 4, 4), {
		Name = "ShopBack",
		Size = Vector3.new(16, 8, 1),
		Color = COLORS.cream,
		Material = Enum.Material.WoodPlanks,
		Parent = hub,
	})
	local counter = shop(CFrame.new(0, 1.75, -1), {
		Name = "EggShopCounter",
		Size = Vector3.new(16, 3.5, 3),
		Color = COLORS.purple,
		Parent = hub,
	})
	prompt(counter, "EggShopPrompt", "Egg Shop", "Buy eggs")
	shop(CFrame.new(0, 3.6, -1), {
		Name = "CounterTop",
		Size = Vector3.new(16.6, 0.3, 3.6),
		Color = COLORS.cream,
		Material = Enum.Material.WoodPlanks,
		Parent = hub,
	})
	for _, x in { -7.7, 7.7 } do
		for _, z in { -2.2, 4 } do
			shop(CFrame.new(x, 4.6, z), {
				Name = "Post",
				Size = Vector3.new(0.8, 9.2, 0.8),
				Color = COLORS.darkWood,
				Material = Enum.Material.Wood,
				Parent = hub,
			})
		end
	end
	for i = 0, 7 do
		shop(CFrame.new(-8 + i * 2 + 1, 9.6, 0.9) * CFrame.Angles(math.rad(-16), 0, 0), {
			Name = "Awning",
			Size = Vector3.new(2, 0.4, 8.4),
			Color = if i % 2 == 0 then COLORS.purple else COLORS.cream,
			Material = Enum.Material.Fabric,
			Parent = hub,
		})
	end
	local shopSign = shop(CFrame.new(0, 12, -2.2), {
		Name = "EggShopSign",
		Size = Vector3.new(12, 2.8, 0.5),
		Color = COLORS.darkWood,
		Material = Enum.Material.WoodPlanks,
		Parent = hub,
	})
	signText(shopSign, Enum.NormalId.Front, "EGG SHOP", COLORS.toxic)
	signText(shopSign, Enum.NormalId.Back, "EGG SHOP", COLORS.toxic)
	-- Eggs on display, one per tier.
	local eggColors = { "#F6F0D8", "#7FA85A", "#EEF3F8", "#3B4A2A", "#2B2140", "#5A2DFF" }
	for i, hex in eggColors do
		local base = shopFrame * CFrame.new(-6 + (i - 1) * 2.4, 3.75, -1)
		blob({
			Name = "DisplayEgg",
			Size = Vector3.new(1.5, 1.3, 1.5),
			CFrame = base * CFrame.new(0, 0.65, 0),
			Color = Color3.fromHex(hex),
			Parent = hub,
		})
		blob({
			Name = "DisplayEggTop",
			Size = Vector3.new(1.3, 1.6, 1.3),
			CFrame = base * CFrame.new(0, 1.1, 0),
			Color = Color3.fromHex(hex),
			Parent = hub,
		})
	end

	-- Sell stand on the east side: a coin booth with the pad in front.
	local sellFrame = CFrame.lookAt(Vector3.new(23, 0, 0), Vector3.new(0, 0, 0))
	local pad = part({
		Name = "SellPad",
		Size = Vector3.new(10, 0.4, 10),
		CFrame = sellFrame * CFrame.new(0, 0.6, -3),
		Color = Color3.fromHex("#E9C44A"),
		Material = Enum.Material.SmoothPlastic,
		Parent = hub,
	})
	prompt(pad, "SellPrompt", "Sell Pad", "Sell mutants")
	part({
		Name = "PadTrim",
		Size = Vector3.new(11, 0.3, 11),
		CFrame = sellFrame * CFrame.new(0, 0.5, -3),
		Color = COLORS.darkWood,
		Material = Enum.Material.WoodPlanks,
		Parent = hub,
	})
	part({
		Name = "Booth",
		Size = Vector3.new(12, 7, 3),
		CFrame = sellFrame * CFrame.new(0, 3.5, 4),
		Color = COLORS.darkWood,
		Material = Enum.Material.WoodPlanks,
		Parent = hub,
	})
	for i = 0, 5 do
		wedge({
			Name = "BoothRoof",
			Size = Vector3.new(2, 2, 4.5),
			CFrame = sellFrame * CFrame.new(-5 + i * 2, 8, 3.4) * CFrame.Angles(0, math.pi, 0),
			Color = if i % 2 == 0 then Color3.fromHex("#E9C44A") else COLORS.cream,
			Parent = hub,
		})
	end
	local sellSign = part({
		Name = "SellSign",
		Size = Vector3.new(9, 2.6, 0.4),
		CFrame = sellFrame * CFrame.new(0, 10.4, 3.5),
		Color = COLORS.darkWood,
		Material = Enum.Material.WoodPlanks,
		Parent = hub,
	})
	signText(sellSign, Enum.NormalId.Front, "SELL", COLORS.gold)
	signText(sellSign, Enum.NormalId.Back, "SELL", COLORS.gold)
	for i = 1, 5 do
		part({
			Name = "Coins",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4 + i * 0.25, 1.6, 1.6),
			CFrame = sellFrame
				* CFrame.new(-4.5 + i * 1.8, 0.4 + (0.4 + i * 0.25) / 2, 2)
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromHex("#E9C44A"),
			Material = Enum.Material.Metal,
			Parent = hub,
		})
	end

	-- Benches facing the fountain.
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local pos = Vector3.new(math.cos(a) * 18, 0, math.sin(a) * 18)
		local cf = CFrame.lookAt(pos, Vector3.zero)
		part({
			Name = "BenchSeat",
			Size = Vector3.new(5, 0.4, 1.6),
			CFrame = cf * CFrame.new(0, 1.4, 0),
			Color = COLORS.wood,
			Material = Enum.Material.WoodPlanks,
			Parent = hub,
		})
		part({
			Name = "BenchBack",
			Size = Vector3.new(5, 1.4, 0.3),
			CFrame = cf * CFrame.new(0, 2.3, 0.7),
			Color = COLORS.wood,
			Material = Enum.Material.WoodPlanks,
			Parent = hub,
		})
		for _, x in { -2, 2 } do
			part({
				Name = "BenchLeg",
				Size = Vector3.new(0.4, 1.2, 1.2),
				CFrame = cf * CFrame.new(x, 0.6, 0),
				Color = COLORS.darkWood,
				Parent = hub,
			})
		end
	end

	hub.Parent = parent
end

-- Slot positions, filled from the gate row outward and from the middle of each row,
-- so the first 6 slots are a tidy centered row.
local function slotOffsets(): { Vector3 }
	local list = {}
	for row = 0, (Upgrades.slots.max // SLOT_COLUMNS) - 1 do
		for col = 0, SLOT_COLUMNS - 1 do
			table.insert(list, { row = row, col = col })
		end
	end
	table.sort(list, function(a, b)
		if a.row ~= b.row then
			return a.row < b.row
		end
		local da, db = math.abs(a.col - 3.5), math.abs(b.col - 3.5)
		if da ~= db then
			return da < db
		end
		return a.col < b.col
	end)
	local out = {}
	for i, s in list do
		out[i] = Vector3.new((s.col - 3.5) * SLOT_SPACING, 0, -14 + s.row * SLOT_SPACING)
	end
	return out
end

local function buildPlot(index: number, parent: Instance): Plot
	local angle = (index - 1) / GameConfig.islandCount * math.pi * 2
	local center = Vector3.new(math.cos(angle) * RING_RADIUS, 0, math.sin(angle) * RING_RADIUS)
	-- -Z of the plot frame points at the hub; the gate is on that side.
	local frame = CFrame.lookAt(center, Vector3.new(0, 0, 0))
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local function world(x: number, z: number): Vector3
		return (frame * CFrame.new(x, 0, z)).Position
	end

	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("Index", index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("WateredUntil", 0)
	model:SetAttribute("Speed", 1)
	model:SetAttribute("Pen", "[]")

	local base = part({
		Name = "Base",
		Size = Vector3.new(PLOT_HALF * 2, 0.4, PLOT_HALF * 2),
		CFrame = at(0, 0.2, 0),
		Color = COLORS.plotGrass,
		Material = Enum.Material.Grass,
		Parent = model,
	})
	model.PrimaryPart = base

	-- Hay-floored pen at the back; slots are individual soil patches (no empty bed).
	local penZ0, penZ1 = 9, PLOT_HALF - 1
	part({
		Name = "PenFloor",
		Size = Vector3.new(PLOT_HALF * 2 - 2, 0.3, penZ1 - penZ0),
		CFrame = at(0, 0.45, (penZ0 + penZ1) / 2),
		Color = COLORS.hay,
		Material = Enum.Material.Sand,
		Parent = model,
	})
	model:SetAttribute("PenCenter", world(0, (penZ0 + penZ1) / 2) + Vector3.new(0, 0.6, 0))
	model:SetAttribute("PenSize", Vector2.new(PLOT_HALF * 2 - 6, penZ1 - penZ0 - 3))

	-- Fence: three closed sides, a gate gap facing the hub, and a low fence around the pen.
	local fences = Instance.new("Folder")
	fences.Name = "Fence"
	fences.Parent = model
	local h = PLOT_HALF
	fence(fences, world(-h, -h), world(-GATE_WIDTH / 2, -h))
	fence(fences, world(GATE_WIDTH / 2, -h), world(h, -h))
	fence(fences, world(h, -h), world(h, h))
	fence(fences, world(h, h), world(-h, h))
	fence(fences, world(-h, h), world(-h, -h))
	fence(fences, world(-h + 1, penZ0), world(-4, penZ0), 2)
	fence(fences, world(4, penZ0), world(h - 1, penZ0), 2)

	-- Owner sign beside the gate, readable from the path.
	part({
		Name = "SignPost",
		Size = Vector3.new(0.6, 5, 0.6),
		CFrame = at(GATE_WIDTH / 2 + 3, 2.5, -h - 1.5),
		Color = COLORS.darkWood,
		Material = Enum.Material.Wood,
		Parent = model,
	})
	local board = part({
		Name = "SignBoard",
		Size = Vector3.new(8, 2.2, 0.3),
		CFrame = at(GATE_WIDTH / 2 + 3, 5, -h - 1.8),
		Color = COLORS.wood,
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	-- The board's Back face points toward the hub (frame -Z), where visitors come from.
	local sign = signText(board, Enum.NormalId.Back, "Empty Plot")
	signText(board, Enum.NormalId.Front, "")

	-- Income sign on the other side of the gate: what this farm earns per minute.
	part({
		Name = "IncomePost",
		Size = Vector3.new(0.6, 5, 0.6),
		CFrame = at(-GATE_WIDTH / 2 - 3, 2.5, -h - 1.5),
		Color = COLORS.darkWood,
		Material = Enum.Material.Wood,
		Parent = model,
	})
	local incomeBoard = part({
		Name = "IncomeBoard",
		Size = Vector3.new(8, 2.6, 0.3),
		CFrame = at(-GATE_WIDTH / 2 - 3, 5.2, -h - 1.8),
		Color = COLORS.slate,
		Parent = model,
	})
	local income = signText(incomeBoard, Enum.NormalId.Back, "", COLORS.toxic)
	signText(incomeBoard, Enum.NormalId.Front, "", COLORS.toxic)

	local slotsFolder = Instance.new("Folder")
	slotsFolder.Name = "Slots"
	slotsFolder.Parent = model
	local slots = {}
	for i, offset in slotOffsets() do
		local slot = part({
			Name = "Slot" .. i,
			Size = Vector3.new(SLOT_SIZE, 0.5, SLOT_SIZE),
			CFrame = at(offset.X, 0.75, offset.Z),
			Color = COLORS.soil,
			Material = Enum.Material.Ground,
			Transparency = 1,
			CanCollide = false,
			Parent = slotsFolder,
		})
		slot:SetAttribute("Index", i)
		slot:SetAttribute("State", "locked") -- "owned" | "buy" | "locked"
		slot:SetAttribute("EggId", "")
		slot:SetAttribute("Mutations", "")
		slot:SetAttribute("Growth", 0)
		slot:SetAttribute("UpdatedAt", 0)
		slot:SetAttribute("Required", 0)
		slot:SetAttribute("Price", 0)
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 0
		click.Parent = slot
		slots[i] = slot
	end

	-- Spawn just inside the gate, facing into the plot.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(4, 0.2, 4)
	spawn.CFrame = at(0, 0.5, -h + 3) * CFrame.Angles(0, math.pi, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Parent = model

	-- Path from the plaza edge to the gate.
	local from = Vector3.new(math.cos(angle) * HUB_RADIUS, 0.1, math.sin(angle) * HUB_RADIUS)
	local to = world(0, -h) + Vector3.new(0, 0.1, 0)
	part({
		Name = "Path",
		Size = Vector3.new(7, 0.2, (to - from).Magnitude + 2),
		CFrame = CFrame.lookAt((from + to) / 2, to),
		Color = COLORS.path,
		Material = Enum.Material.Cobblestone,
		CanQuery = false,
		Parent = model,
	})

	model.Parent = parent
	return { index = index, model = model, slots = slots, spawn = spawn, sign = sign, income = income, frame = frame }
end

local function buildDecor(parent: Instance)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = parent
	local n = GameConfig.islandCount
	for i = 0, n - 1 do
		-- Between each pair of plots: a tree near the hub side and one further out, plus clutter.
		local angle = (i + 0.5) / n * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		tree(decor, dir * 70, 0.9 + rng:next() * 0.3, i % 3 == 0)
		tree(decor, dir * 140, 1.1 + rng:next() * 0.4, i % 4 == 1)
		mushroom(decor, dir * 112 + Vector3.new(rng:next() * 4 - 2, 0, rng:next() * 4 - 2), 0.8 + rng:next() * 0.5)
		if i % 2 == 0 then
			barrel(decor, dir * 96)
		else
			rock(decor, dir * 124 + Vector3.new(0, 0.6, 0), Vector3.new(4, 2.6, 3.4))
		end
	end
	-- An outer ring of trees between the plots and the fence.
	for i = 0, 35 do
		local angle = i / 36 * math.pi * 2 + rng:next() * 0.05
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		tree(decor, dir * (152 + rng:next() * 8), 1 + rng:next() * 0.6, rng:next() < 0.25)
	end
end

function World.build(): { Plot }
	setLighting()

	local map = Instance.new("Folder")
	map.Name = "Map"

	buildTerrain(map)
	buildHub(map)
	buildDecor(map)

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = map
	local plots = {}
	for i = 1, GameConfig.islandCount do
		plots[i] = buildPlot(i, plotsFolder)
	end

	map.Parent = workspace
	return plots
end

World.colors = COLORS

return World
