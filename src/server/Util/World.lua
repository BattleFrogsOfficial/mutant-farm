--!strict
-- Builds the whole map in code: a round grass valley closed in by a hedge wall and mountains,
-- the hub (fountain, Egg Shop and Sell buildings with step-on pads) and a ring of fenced plots.
-- Keeping the map in code means the repo is the single source of truth (no .rbxl to merge).
--
-- Rules the layout follows (tools/preview/check.luau verifies them):
--   * Every prop is its own Model, and props never intersect each other.
--   * Ground layers never share a surface height (no z-fighting). Layer tops, in studs:
--       valley 0, path 0.25, plaza 0.45, plot base 0.5, pen floor 0.65, lawn 0.7, soil 0.95
--     Each layer is thick and sinks into the one below, so no thin floating edges.
--   * Labels are SurfaceGuis on the face that looks at the viewer (Front = -Z).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Rng = require(ReplicatedStorage.Shared.Rng)
local MutantModel = require(ReplicatedStorage.Shared.MutantModel)
local Mutants = require(ReplicatedStorage.Shared.Config.Mutants)
local Eggs = require(ReplicatedStorage.Shared.Config.Eggs)
local ShopRules = require(ReplicatedStorage.Shared.ShopRules)

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
	path = Color3.fromHex("#E8DDBF"),
	cream = Color3.fromHex("#FFF4D6"),
	wood = Color3.fromHex("#A8754A"),
	darkWood = Color3.fromHex("#6E4A2E"),
	purple = Color3.fromHex("#9B5CFF"),
	purpleDark = Color3.fromHex("#5E2FB8"),
	toxic = Color3.fromHex("#7CFF4A"),
	gold = Color3.fromHex("#FFD24A"),
	goldDark = Color3.fromHex("#C9932A"),
	slate = Color3.fromHex("#1E2230"),
	stone = Color3.fromHex("#B8B0C8"),
	rock = Color3.fromHex("#6C6380"),
	hay = Color3.fromHex("#E8D27A"),
	buy = Color3.fromHex("#7CFF4A"),
}

-- Layout (studs)
local WORLD_RADIUS = 168 -- hedge line; nothing walkable beyond it
local HUB_RADIUS = 34
-- Plot centers. Plots are 46 wide and 12 share the ring, so their inner corners need
-- atan(PLOT_HALF / (RING_RADIUS - PLOT_HALF)) < 15 degrees, or neighbours overlap.
local RING_RADIUS = 118
local PLOT_HALF = 23
local SLOT_SIZE = 3.6
local SLOT_SPACING = 4.2
local SLOT_COLUMNS = 8
local GATE_HALF = 5 -- gate opening is 10 wide

-- Surface heights (tops).
local Y = { valley = 0, path = 0.25, plaza = 0.45, plotBase = 0.5, pen = 0.65, lawn = 0.7, soil = 0.95 }

local rng = Rng.new(20261027) -- decoration placement is the same every server

local function plotAngle(index: number): number
	-- Half a step off the compass points so the Egg Shop (west) and Sell (east) sit between paths.
	return (index - 0.5) / GameConfig.islandCount * math.pi * 2
end

---------------------------------------------------------------------------- helpers

-- Moves a built model so its PrimaryPart lands on `cf` (same as PivotTo for these models, and
-- it also runs under Lune for the preview/check tools).
local function place(model: Model, cf: CFrame)
	local delta = cf * (model.PrimaryPart :: BasePart).CFrame:Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end

local function stripEffects(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
end

local function group(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

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

-- A flat horizontal disc (Roblox cylinders run along X, so stand it up). `top` is the top height.
local function disc(props: { [string]: any }, center: Vector3, radius: number, thickness: number, top: number): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(thickness, radius * 2, radius * 2)
	props.CFrame = CFrame.new(center.X, top - thickness / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	return part(props)
end

-- Text on one face of a sign board. Front (-Z) is the face you see when the board looks at you.
local function signText(board: BasePart, face: Enum.NormalId, text: string, color: Color3?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.15
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
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = label
	label.Parent = gui
	gui.Parent = board
	return label
end

-- Wooden fence from a to b (y = the surface it stands on), posts every ~4 studs and two rails.
local function fence(parent: Instance, a: Vector3, b: Vector3, height: number?)
	local m = group("Fence", parent)
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
			Parent = m,
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
			Parent = m,
		})
	end
end

local function tree(parent: Instance, pos: Vector3, scale: number, mutant: boolean)
	local m = group("Tree", parent)
	local trunkHeight = 7 * scale
	part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(trunkHeight, 1.6 * scale, 1.6 * scale),
		CFrame = CFrame.new(pos + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.darkWood,
		Material = Enum.Material.Wood,
		Parent = m,
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
			Parent = m,
		})
	end
end

local function mushroom(parent: Instance, pos: Vector3, scale: number)
	local m = group("Mushroom", parent)
	local stem = 2.2 * scale
	part({
		Name = "Stem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(stem, 0.9 * scale, 0.9 * scale),
		CFrame = CFrame.new(pos + Vector3.new(0, stem / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.cream,
		Parent = m,
	})
	local caps = { Color3.fromHex("#FF5A7A"), COLORS.purple, Color3.fromHex("#FF9A3C") }
	blob({
		Name = "Cap",
		Size = Vector3.new(3 * scale, 1.4 * scale, 3 * scale),
		CFrame = CFrame.new(pos + Vector3.new(0, stem + 0.2 * scale, 0)),
		Color = caps[rng:integer(1, #caps)],
		Parent = m,
	})
end

local function barrel(parent: Instance, pos: Vector3)
	local m = group("Barrel", parent)
	part({
		Name = "Barrel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 2.2, 2.2),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromHex("#3E8F2F"),
		Material = Enum.Material.Metal,
		Parent = m,
	})
	part({
		Name = "Ooze",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 1.9, 1.9),
		CFrame = CFrame.new(pos + Vector3.new(0, 3.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.toxic,
		Parent = m,
	})
end

local function rock(parent: Instance, pos: Vector3, size: Vector3)
	local m = group("Rock", parent)
	blob({
		Name = "Rock",
		Size = size,
		-- Sunk a quarter into the ground so it looks embedded, not balanced on a point.
		CFrame = CFrame.new(pos + Vector3.new(0, size.Y * 0.25, 0)) * CFrame.Angles(0, rng:next() * math.pi * 2, 0),
		Color = COLORS.rock:Lerp(COLORS.stone, rng:next() * 0.6),
		Material = Enum.Material.Slate,
		Parent = m,
	})
end

local function lamp(parent: Instance, pos: Vector3)
	local m = group("Lamp", parent)
	part({
		Name = "LampPole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(8, 0.5, 0.5),
		CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.slate,
		Material = Enum.Material.Metal,
		Parent = m,
	})
	part({
		Name = "Lamp",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.4, 1.4, 1.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 8.6, 0)),
		Color = COLORS.cream,
		Parent = m,
	})
end

local function flowerBed(parent: Instance, pos: Vector3)
	local m = group("FlowerBed", parent)
	part({
		Name = "Bush",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.6, 2.6, 2.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)),
		Color = Color3.fromHex("#4FAE3F"),
		Material = Enum.Material.Grass,
		Parent = m,
	})
	local flowers = { "#FF7AA8", "#FFD24A", "#C29BFF", "#FFFFFF" }
	for k = 1, 5 do
		local a = k / 5 * math.pi * 2
		part({
			Name = "Flower",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.6, 0.6, 0.6),
			CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 1.05, 2 + (k % 2) * 0.25, math.sin(a) * 1.05)),
			Color = Color3.fromHex(flowers[(k % #flowers) + 1]),
			Parent = m,
		})
	end
end

local function bench(parent: Instance, cf: CFrame)
	local m = group("Bench", parent)
	part({
		Name = "Seat",
		Size = Vector3.new(5, 0.4, 1.6),
		CFrame = cf * CFrame.new(0, 1.4, 0),
		Color = COLORS.wood,
		Material = Enum.Material.WoodPlanks,
		Parent = m,
	})
	part({
		Name = "Back",
		Size = Vector3.new(5, 1.4, 0.3),
		CFrame = cf * CFrame.new(0, 2.3, 0.65),
		Color = COLORS.wood,
		Material = Enum.Material.WoodPlanks,
		Parent = m,
	})
	for _, x in { -2, 2 } do
		part({
			Name = "Leg",
			Size = Vector3.new(0.4, 1.2, 1.2),
			CFrame = cf * CFrame.new(x, 0.6, 0),
			Color = COLORS.darkWood,
			Parent = m,
		})
	end
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

---------------------------------------------------------------------------- terrain

local function buildTerrain(parent: Instance)
	disc(
		{ Name = "Valley", Color = COLORS.grass, Material = Enum.Material.Grass, Parent = parent },
		Vector3.zero,
		320,
		4,
		Y.valley
	)

	-- A solid hedge wall all the way round, rocks in front of it, mountains behind it.
	local edge = group("Edge", parent)
	local hedge = Color3.fromHex("#3F8F3A")
	local hedgeTop = Color3.fromHex("#4FA845")
	local segments = 72
	local thickness = 7
	for i = 0, segments - 1 do
		local a0 = i / segments * math.pi * 2
		local a1 = (i + 1) / segments * math.pi * 2
		local p0 = Vector3.new(math.cos(a0), 0, math.sin(a0)) * WORLD_RADIUS
		local p1 = Vector3.new(math.cos(a1), 0, math.sin(a1)) * WORLD_RADIUS
		local mid = (p0 + p1) / 2
		local length = (p1 - p0).Magnitude + 2
		local seg = group("HedgeSegment", edge)
		part({
			Name = "Hedge",
			-- Alternate heights so overlapping segment ends never share a top face (z-fighting).
			Size = Vector3.new(length, 14 + (i % 2) * 0.2, thickness),
			CFrame = CFrame.lookAt(mid + Vector3.new(0, 7 + (i % 2) * 0.1, 0), Vector3.new(0, 7 + (i % 2) * 0.1, 0)),
			Color = hedge,
			Material = Enum.Material.Grass,
			Parent = seg,
		})
		for k, t in { 0.2, 0.55, 0.85 } do
			part({
				Name = "HedgeTop",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(8, 8, 8),
				CFrame = CFrame.new(p0:Lerp(p1, t) + Vector3.new(0, 13.5 + rng:next() * 1.5, 0)),
				Color = if (i + k) % 2 == 0 then hedge else hedgeTop,
				Material = Enum.Material.Grass,
				Parent = seg,
			})
		end
		-- Invisible wall well above the hedge so nobody climbs out.
		part({
			Name = "Barrier",
			Size = Vector3.new(length, 120, 2),
			CFrame = CFrame.lookAt(mid + Vector3.new(0, 60, 0), Vector3.new(0, 60, 0)),
			Transparency = 1,
			CanQuery = false,
			Parent = seg,
		})
		if i % 3 == 0 then
			-- Rock just in front of the hedge, not poking into it.
			local s = 4 + rng:next() * 3
			local inner = WORLD_RADIUS - thickness / 2 - s * 0.75 - 0.4
			rock(edge, mid.Unit * inner, Vector3.new(s * 1.4, s, s * 1.1))
		end
	end
	-- Mountains close the horizon so the valley feels like a place, not a floating disc.
	for i = 1, 36 do
		local angle = i / 36 * math.pi * 2 + rng:next() * 0.08
		local radius = WORLD_RADIUS + 48 + rng:next() * 36
		local pos = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local s = 60 + rng:next() * 50
		blob({
			Name = "Mountain",
			Size = Vector3.new(s * 1.3, s * (0.8 + rng:next() * 0.5), s),
			CFrame = CFrame.lookAt(pos, Vector3.zero),
			Color = Color3.fromHex("#7A8F6A"):Lerp(COLORS.rock, rng:next() * 0.5),
			Material = Enum.Material.Grass,
			Parent = group("Mountain", edge),
		})
	end
	-- Trees peeking over the hedge from outside.
	for i = 0, 47 do
		local angle = (i + 0.5) / 48 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		tree(edge, dir * (WORLD_RADIUS + 16 + rng:next() * 8), 1.8 + rng:next() * 0.8, rng:next() < 0.2)
	end
end

---------------------------------------------------------------------------- hub buildings

-- A step-on pad: walk onto it and the client opens `opens` ("shop" | "sell").
local function pad(
	parent: Instance,
	name: string,
	center: Vector3,
	radius: number,
	color: Color3,
	label: string,
	opens: string,
	faceToward: Vector3
)
	local m = group(name, parent)
	disc({ Name = "Rim", Color = Color3.new(1, 1, 1), Parent = m }, center, radius + 0.6, 0.6, Y.plaza + 0.15)
	local top = disc({ Name = "Pad", Color = color, Parent = m }, center, radius, 0.6, Y.plaza + 0.25)
	top:SetAttribute("Opens", opens)
	top:SetAttribute("Radius", radius)
	m.PrimaryPart = top
	-- Floor text, readable when walking up from the fountain. A thin flat slab carries it.
	local slab = part({
		Name = "Label",
		Size = Vector3.new(radius * 1.5, 0.05, radius * 0.6),
		CFrame = CFrame.lookAt(
			Vector3.new(center.X, Y.plaza + 0.28, center.Z),
			Vector3.new(faceToward.X, Y.plaza + 0.28, faceToward.Z)
		),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = m,
	})
	local text = signText(slab, Enum.NormalId.Top, label)
	text.Rotation = 180
	return top
end

-- A friendly mutant behind the counter, sized to about `height` studs whatever its species.
local function shopkeeper(parent: Instance, speciesTier: string, rarity: string, cf: CFrame, height: number)
	local id = Mutants.buckets[speciesTier][rarity][1]
	local unit =
		MutantModel.visualScale({ tier = speciesTier, rarity = rarity, species = id, mutations = {}, size = 1 })
	local size = ((height / 3.6) / unit) ^ (1 / 1.6)
	local model = MutantModel.build({ tier = speciesTier, rarity = rarity, species = id, mutations = {}, size = size })
	stripEffects(model)
	model.Name = "Shopkeeper"
	place(model, cf)
	model.Parent = parent
end

-- Market stall in the classic simulator style: stone platform, three walls, a flat roof with a
-- giant sign standing on it, a striped awning over the open front, and a counter with the goods
-- on it and a shopkeeper behind. -Z of `frame` is the open front.
local function building(
	parent: Instance,
	name: string,
	frame: CFrame,
	colors: { main: Color3, trim: Color3, roof: Color3 },
	title: string,
	titleColor: Color3
)
	local m = group(name, parent)
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local W, D, H = 16, 10, 8 -- width, depth, wall height
	local floorTop = Y.plaza + 0.6
	local function up(x: number, y: number, z: number): CFrame
		return at(x, floorTop + y, z)
	end
	part({
		Name = "Platform",
		Size = Vector3.new(W + 2, 1.2, D + 2),
		CFrame = at(0, floorTop - 0.6, 0),
		Color = COLORS.stone,
		Material = Enum.Material.Slate,
		Parent = m,
	})
	part({
		Name = "BackWall",
		Size = Vector3.new(W, H, 1),
		CFrame = up(0, H / 2, D / 2 - 0.5),
		Color = colors.main,
		Material = Enum.Material.WoodPlanks,
		Parent = m,
	})
	for _, side in { -1, 1 } do
		part({
			Name = "SideWall",
			Size = Vector3.new(1, H, D - 1.9),
			CFrame = up(side * (W / 2 - 0.5), H / 2, -0.05),
			Color = colors.main,
			Material = Enum.Material.WoodPlanks,
			Parent = m,
		})
		part({
			Name = "Pillar",
			Size = Vector3.new(1.4, H, 1.4),
			CFrame = up(side * (W / 2 - 0.3), H / 2, -D / 2 + 0.3),
			Color = colors.trim,
			Material = Enum.Material.Wood,
			Parent = m,
		})
	end
	part({
		Name = "Roof",
		Size = Vector3.new(W + 1.6, 1, D + 1),
		CFrame = up(0, H + 0.5, 0),
		Color = colors.trim,
		Material = Enum.Material.Wood,
		Parent = m,
	})
	part({
		Name = "RoofTop",
		Size = Vector3.new(W + 0.6, 0.4, D),
		CFrame = up(0, H + 1.2, 0),
		Color = colors.roof,
		Parent = m,
	})

	-- Striped awning sloping down and out from the front edge of the roof.
	local stripes, tilt, length = 8, math.rad(24), 4.4
	local stripeW = (W + 1.6) / stripes
	for i = 0, stripes - 1 do
		local x = -(W + 1.6) / 2 + stripeW * (i + 0.5)
		local color = if i % 2 == 0 then colors.main else COLORS.cream
		local hinge = up(x, H - 0.1, -D / 2 - 0.5) * CFrame.Angles(-tilt, 0, 0)
		part({
			Name = "Awning",
			Size = Vector3.new(stripeW, 0.3, length),
			CFrame = hinge * CFrame.new(0, 0, -length / 2),
			Color = color,
			Material = Enum.Material.Fabric,
			Parent = m,
		})
		part({
			Name = "Valance",
			Size = Vector3.new(stripeW, 1, 0.2),
			CFrame = hinge * CFrame.new(0, 0, -length) * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, -0.5, 0),
			Color = color,
			Material = Enum.Material.Fabric,
			Parent = m,
		})
	end

	-- Counter across the opening; the goods go on top so they show from the plaza.
	part({
		Name = "Counter",
		Size = Vector3.new(W - 3, 3, 1.6),
		CFrame = up(0, 1.5, -D / 2 + 1.6),
		Color = colors.trim,
		Material = Enum.Material.WoodPlanks,
		Parent = m,
	})
	part({
		Name = "CounterTop",
		Size = Vector3.new(W - 2.4, 0.3, 2.2),
		CFrame = up(0, 3.15, -D / 2 + 1.6),
		Color = colors.main,
		Material = Enum.Material.WoodPlanks,
		Parent = m,
	})

	-- Giant sign standing on the roof, readable from anywhere on the plaza.
	local signY = H + 1.4 + 2.8
	for _, side in { -1, 1 } do
		part({
			Name = "SignPost",
			Size = Vector3.new(0.8, 3, 0.8),
			CFrame = up(side * 5, H + 1.4 + 1.5, -D / 2 + 2.6),
			Color = COLORS.darkWood,
			Material = Enum.Material.Wood,
			Parent = m,
		})
	end
	part({
		Name = "SignFrame",
		Size = Vector3.new(W + 2, 5.6, 0.6),
		CFrame = up(0, signY, -D / 2 + 1.9),
		Color = colors.trim,
		Material = Enum.Material.Wood,
		Parent = m,
	})
	local board = part({
		Name = "Sign",
		Size = Vector3.new(W + 1, 4.6, 0.3),
		CFrame = up(0, signY, -D / 2 + 1.45),
		Color = COLORS.slate,
		Parent = m,
	})
	signText(board, Enum.NormalId.Front, title, titleColor)
	return m, up
end

-- Two global boards side by side on the north edge of the plaza, facing the fountain: Top Pens
-- and Top Rebirths. The title is a header strip on top; the rows are drawn per player by
-- LeaderboardController (a SurfaceGui on the Board part, so it can scroll and show your rank).
World.LEADERBOARDS = {
	{ name = "TopPens", title = "🏆 TOP PENS", x = -7.4 },
	{ name = "TopRebirths", title = "🔁 TOP REBIRTHS", x = 7.4 },
}
local function leaderboard(hub: Instance, name: string, title: string, x: number)
	local m = group(name, hub)
	local frame = CFrame.lookAt(Vector3.new(x, 0, -27), Vector3.new(x, 0, 0))
	local W, H, bottom, header = 12, 11, Y.plaza + 2, 1.6
	local top = bottom + H + header
	local postHeight = top - Y.plaza -- from the plaza surface to the top of the header
	for _, side in { -1, 1 } do
		part({
			Name = "Post",
			Size = Vector3.new(0.8, postHeight, 0.8),
			CFrame = frame * CFrame.new(side * (W / 2 + 0.8), Y.plaza + postHeight / 2, 0.3),
			Color = COLORS.darkWood,
			Material = Enum.Material.Wood,
			Parent = m,
		})
	end
	part({
		Name = "Board",
		Size = Vector3.new(W, H, 0.4),
		CFrame = frame * CFrame.new(0, bottom + H / 2, 0),
		Color = COLORS.slate,
		Parent = m,
	})
	local head = part({
		Name = "Header",
		Size = Vector3.new(W, header, 0.4),
		CFrame = frame * CFrame.new(0, bottom + H + header / 2, 0),
		Color = COLORS.purpleDark,
		Parent = m,
	})
	signText(head, Enum.NormalId.Front, title, COLORS.gold)
	part({
		Name = "Frame",
		Size = Vector3.new(W + 0.8, H + header + 0.8, 0.3),
		CFrame = frame * CFrame.new(0, bottom + (H + header) / 2, 0.3),
		Color = COLORS.darkWood,
		Material = Enum.Material.Wood,
		Parent = m,
	})
end

local function leaderboards(hub: Instance)
	for _, board in World.LEADERBOARDS do
		leaderboard(hub, board.name, board.title, board.x)
	end
end

-- Rebirth Altar on the south edge of the plaza, across the fountain from the leaderboards: a
-- violet step-on pad (opens the Rebirth panel) ringed by small glowing stones, and a sign behind
-- it facing the fountain. ZoneController writes each player's own line on the sign ("REBIRTH 1 ·
-- $700K · unlocks Toxic Egg") and fills its progress bar (Cash / cost).
World.ALTAR_CENTER = Vector3.new(0, 0, 21)
local function rebirthAltar(hub: Instance)
	local center = World.ALTAR_CENTER
	local top = pad(hub, "RebirthAltar", center, 3.6, COLORS.purple, "REBIRTH", "rebirth", Vector3.zero)
	-- Soft glow: one weak light (art rules: range <= 16, brightness <= 0.35) and Neon only on
	-- the small stones.
	local light = Instance.new("PointLight")
	light.Color = COLORS.purple
	light.Range = 14
	light.Brightness = 0.35
	light.Parent = top
	local glow = group("RebirthAltarGlow", hub)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		part({
			Name = "GlowStone",
			Size = Vector3.new(0.5, 0.9, 0.5),
			CFrame = CFrame.new(center.X + math.cos(a) * 5.2, Y.plaza + 0.45, center.Z + math.sin(a) * 5.2)
				* CFrame.Angles(0, a, 0),
			Color = Color3.fromHex("#C9A2FF"),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = glow,
		})
	end

	-- The sign: posts, a board facing the fountain, the text and a progress bar on its Front face.
	local m = group("RebirthSign", hub)
	local frame = CFrame.lookAt(Vector3.new(center.X, 0, center.Z + 7.5), Vector3.new(center.X, 0, 0))
	local W, H, bottom = 14, 5.6, Y.plaza + 3.2
	local postHeight = bottom + H - Y.plaza
	for _, side in { -1, 1 } do
		part({
			Name = "Post",
			Size = Vector3.new(0.8, postHeight, 0.8),
			CFrame = frame * CFrame.new(side * (W / 2 + 0.8), Y.plaza + postHeight / 2, 0.3),
			Color = COLORS.darkWood,
			Material = Enum.Material.Wood,
			Parent = m,
		})
	end
	local board = part({
		Name = "Board",
		Size = Vector3.new(W, H, 0.4),
		CFrame = frame * CFrame.new(0, bottom + H / 2, 0),
		Color = COLORS.purpleDark,
		Parent = m,
	})
	part({
		Name = "Frame",
		Size = Vector3.new(W + 0.8, H + 0.8, 0.3),
		CFrame = frame * CFrame.new(0, bottom + H / 2, 0.3),
		Color = COLORS.darkWood,
		Material = Enum.Material.Wood,
		Parent = m,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Name = "AltarGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.15
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.66)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = COLORS.gold
	title.Text = "🔁 REBIRTH ALTAR"
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = COLORS.slate
	stroke.Parent = title
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.04, 0)
	padding.Parent = title
	title.Parent = gui
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.fromScale(0.5, 0.7)
	bar.Size = UDim2.fromScale(0.9, 0.2)
	bar.BackgroundColor3 = COLORS.slate
	bar.BorderSizePixel = 0
	local barStroke = Instance.new("UIStroke")
	barStroke.Thickness = 4
	barStroke.Color = COLORS.cream
	barStroke.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = COLORS.toxic
	fill.BorderSizePixel = 0
	fill.Parent = bar
	bar.Parent = gui
	gui.Parent = board
end

-- A carved pumpkin on the plaza, its face toward the fountain (dark carving, no Neon).
local function carvedPumpkin(parent: Instance, pos: Vector3, scale: number)
	local m = group("Pumpkin", parent)
	local face = CFrame.lookAt(Vector3.new(pos.X, 0, pos.Z), Vector3.new(0, 0, 0))
	local h = 1.9 * scale
	local mid = Y.plaza + h / 2 - 0.05
	blob({
		Name = "PumpkinBody",
		Size = Vector3.new(2.5, 1.9, 2.5) * scale,
		CFrame = CFrame.new(pos.X, mid, pos.Z),
		Color = Color3.fromHex("#FF8A1F"),
		Parent = m,
	})
	local carve = Color3.fromHex("#3A1A06")
	local front = face * CFrame.new(0, mid, -1.2 * scale)
	for _, side in { -1, 1 } do
		part({
			Name = "PumpkinEye",
			Size = Vector3.new(0.42, 0.42, 0.12) * scale,
			CFrame = front * CFrame.new(side * 0.45 * scale, 0.3 * scale, 0) * CFrame.Angles(0, 0, math.rad(45)),
			Color = carve,
			CanCollide = false,
			Parent = m,
		})
	end
	part({
		Name = "PumpkinGrin",
		Size = Vector3.new(1.1, 0.22, 0.12) * scale,
		CFrame = front * CFrame.new(0, -0.3 * scale, 0.05 * scale),
		Color = carve,
		CanCollide = false,
		Parent = m,
	})
	part({
		Name = "PumpkinStem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 0.35, 0.35) * scale,
		CFrame = CFrame.new(pos.X, Y.plaza + h + 0.2 * scale, pos.Z) * CFrame.Angles(0, 0, math.rad(95)),
		Color = COLORS.darkWood,
		CanCollide = false,
		Parent = m,
	})
end

-- Limited eggs on sale when the server starts dress the hub: a banner on the Egg Shop's roof sign
-- (config `banner`) and their decor around the fountain (config `decor`: "pumpkins").
local function limitedDecor(hub: Instance, shop: Model, shopAt: (number, number, number) -> CFrame, now: number)
	for _, id in ShopRules.activeLimited(now) do
		local tier = Eggs.tiers[id]
		if tier.banner then
			-- Sits on top of the roof sign's frame (the stall's sign: H 8 + 1.4 + 2.8 center, 5.6 tall).
			local banner = part({
				Name = "LimitedBanner",
				Size = Vector3.new(16, 1.8, 0.4),
				CFrame = shopAt(0, 8 + 1.4 + 2.8 + 2.8 + 0.9, -10 / 2 + 1.9),
				Color = Color3.fromHex(tier.color),
				Parent = shop,
			})
			banner:SetAttribute("Limited", id)
			signText(banner, Enum.NormalId.Front, tier.banner)
		end
		if tier.decor == "pumpkins" then
			-- On the plaza ring between the lawn (r 11) and the benches (r 19), clear of the pads.
			for k, a in { 90, 210, 330 } do
				local r = math.rad(a)
				carvedPumpkin(hub, Vector3.new(math.cos(r) * 14, 0, math.sin(r) * 14), if k == 1 then 1.2 else 1)
			end
		end
	end
end

local function buildHub(parent: Instance, now: number)
	local hub = group("Hub", parent)

	disc(
		{ Name = "PlazaBorder", Color = COLORS.stone, Material = Enum.Material.Slate, Parent = hub },
		Vector3.zero,
		HUB_RADIUS + 1,
		2,
		Y.plaza - 0.1
	)
	disc(
		{ Name = "Plaza", Color = COLORS.path, Material = Enum.Material.Cobblestone, Parent = hub },
		Vector3.zero,
		HUB_RADIUS,
		2,
		Y.plaza
	)
	disc(
		{ Name = "Lawn", Color = COLORS.plotGrass, Material = Enum.Material.Grass, Parent = hub },
		Vector3.zero,
		11,
		2,
		Y.lawn
	)

	-- Two-tier fountain with a golden egg statue on top.
	local fountain = group("Fountain", hub)
	local water = Color3.fromHex("#6FD3C7")
	disc(
		{ Name = "Basin", Color = COLORS.stone, Material = Enum.Material.Slate, Parent = fountain },
		Vector3.zero,
		7,
		2.2,
		Y.lawn + 1.6
	)
	disc({
		Name = "Water",
		Color = water,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		CanCollide = false,
		Parent = fountain,
	}, Vector3.zero, 6.3, 0.3, Y.lawn + 1.75)
	disc(
		{ Name = "Column", Color = COLORS.stone, Material = Enum.Material.Slate, Parent = fountain },
		Vector3.zero,
		1.2,
		4,
		Y.lawn + 5
	)
	disc(
		{ Name = "UpperBasin", Color = COLORS.stone, Material = Enum.Material.Slate, Parent = fountain },
		Vector3.zero,
		3.4,
		1,
		Y.lawn + 5.6
	)
	disc({
		Name = "UpperWater",
		Color = water,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		CanCollide = false,
		Parent = fountain,
	}, Vector3.zero, 2.9, 0.3, Y.lawn + 5.75)
	disc(
		{ Name = "Pedestal", Color = COLORS.stone, Material = Enum.Material.Slate, Parent = fountain },
		Vector3.zero,
		1.1,
		1.4,
		Y.lawn + 7
	)
	local gold = Color3.fromHex("#E8B830")
	local eggBase = Y.lawn + 7
	blob({
		Name = "EggStatue",
		Size = Vector3.new(3.2, 2.7, 3.2),
		CFrame = CFrame.new(0, eggBase + 1.35, 0),
		Color = gold,
		Material = Enum.Material.Metal,
		Parent = fountain,
	})
	blob({
		Name = "EggStatueTop",
		Size = Vector3.new(2.75, 3.4, 2.75),
		CFrame = CFrame.new(0, eggBase + 2.3, 0),
		Color = gold,
		Material = Enum.Material.Metal,
		Parent = fountain,
	})

	for i = 0, 7 do
		local a = (i + 0.5) / 8 * math.pi * 2
		flowerBed(hub, Vector3.new(math.cos(a) * 9.2, Y.lawn, math.sin(a) * 9.2))
	end
	-- Lamps around the plaza edge, skipping the two buildings (east/west) and the paths.
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local nearBuilding = math.abs(math.cos(a)) > 0.85
		local atLeaderboard = math.abs(math.sin(a) + 1) < 0.05 -- north: the leaderboards stand there
		local atAltar = math.abs(math.sin(a) - 1) < 0.05 -- south: the Rebirth Altar's sign
		if not nearBuilding and not atLeaderboard and not atAltar then
			lamp(hub, Vector3.new(math.cos(a) * (HUB_RADIUS - 2.5), Y.plaza, math.sin(a) * (HUB_RADIUS - 2.5)))
		end
	end
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local pos = Vector3.new(math.cos(a) * 19, Y.plaza, math.sin(a) * 19)
		bench(hub, CFrame.lookAt(pos, Vector3.new(0, Y.plaza, 0)))
	end

	-- Egg Shop on the west side, facing the fountain.
	local shopFrame = CFrame.lookAt(Vector3.new(-26, 0, 0), Vector3.new(0, 0, 0))
	local shop, shopAt = building(hub, "EggShop", shopFrame, {
		main = Color3.fromHex("#7A45D6"),
		trim = COLORS.cream,
		roof = Color3.fromHex("#9B6BF0"),
	}, "🥚 EGG SHOP", COLORS.toxic)
	-- One egg per tier on the counter.
	local eggOrder = { "Starter", "Swamp", "Lab", "Toxic", "Void", "Cosmic" }
	for i, eggId in eggOrder do
		local egg = MutantModel.buildEgg(eggId, 0, {}) -- progress 0 = the smallest egg size
		stripEffects(egg)
		place(egg, shopAt(-5.5 + (i - 1) * 2.2, 3.3, -3.4))
		egg.Parent = shop
	end
	shopkeeper(shop, "Lab", "Legendary", shopAt(0, 0, 0.6), 5)
	-- Giant egg icon floating over the roof.
	local icon = group("Icon", shop)
	local iconAt = shopAt(0, 19, 1)
	blob({ Name = "IconEgg", Size = Vector3.new(4.4, 3.8, 4.4), CFrame = iconAt, Color = COLORS.toxic, Parent = icon })
	blob({
		Name = "IconEggTop",
		Size = Vector3.new(3.8, 4.8, 3.8),
		CFrame = iconAt * CFrame.new(0, 1.4, 0),
		Color = COLORS.toxic,
		Parent = icon,
	})
	for k, off in { Vector3.new(0.9, 0.6, -1.9), Vector3.new(-1.2, 1.6, -1.6), Vector3.new(0.4, 2.6, -1.5) } do
		blob({
			Name = "Spot" .. k,
			Size = Vector3.new(1, 1, 0.3),
			CFrame = iconAt * CFrame.new(off),
			Color = Color3.fromHex("#3FA82A"),
			Parent = icon,
		})
	end
	-- Pads sit between the fountain lawn (r 11) and the building platform (r 20).
	pad(
		hub,
		"EggShopPad",
		(shopFrame * CFrame.new(0, 0, -10.4)).Position,
		3.6,
		COLORS.purple,
		"EGG SHOP",
		"shop",
		Vector3.zero
	)

	-- Sell building on the east side.
	local sellFrame = CFrame.lookAt(Vector3.new(26, 0, 0), Vector3.new(0, 0, 0))
	local sell, sellAt = building(hub, "SellShop", sellFrame, {
		main = Color3.fromHex("#B07A2E"),
		trim = COLORS.cream,
		roof = Color3.fromHex("#E9B43A"),
	}, "💰 SELL", COLORS.gold)
	-- Coin stacks of different heights on the counter.
	for i = 1, 4 do
		local h = 0.6 + (i % 3) * 0.5
		part({
			Name = "Coins",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(h, 1.6, 1.6),
			CFrame = sellAt(-5.6 + (i - 1) * 1.9, 3.3 + h / 2, -3.4) * CFrame.Angles(0, 0, math.rad(90)),
			Color = COLORS.gold,
			Material = Enum.Material.Metal,
			Parent = sell,
		})
	end
	part({
		Name = "Register",
		Size = Vector3.new(2, 1.4, 1.4),
		CFrame = sellAt(3.5, 4.0, -3.4),
		Color = COLORS.slate,
		Material = Enum.Material.Metal,
		Parent = sell,
	})
	shopkeeper(sell, "Starter", "Legendary", sellAt(0, 0, 0.6), 5)
	local coin = group("Icon", sell)
	local coinPart = part({
		Name = "IconCoin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 6, 6),
		CFrame = sellAt(0, 19, 1) * CFrame.Angles(0, math.rad(90), 0),
		Color = COLORS.gold,
		Material = Enum.Material.Metal,
		Parent = coin,
	})
	-- "$" on both faces of the coin (a cylinder's flat ends are its Left/Right faces).
	signText(coinPart, Enum.NormalId.Left, "$", COLORS.goldDark)
	signText(coinPart, Enum.NormalId.Right, "$", COLORS.goldDark)
	pad(hub, "SellPad", (sellFrame * CFrame.new(0, 0, -10.4)).Position, 3.6, COLORS.gold, "SELL", "sell", Vector3.zero)

	leaderboards(hub)
	rebirthAltar(hub)
	limitedDecor(hub, shop, shopAt, now)
end

---------------------------------------------------------------------------- plots

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
	local angle = plotAngle(index)
	local center = Vector3.new(math.cos(angle) * RING_RADIUS, 0, math.sin(angle) * RING_RADIUS)
	-- -Z of the plot frame points at the hub; the gate is on that side.
	local frame = CFrame.lookAt(center, Vector3.new(0, 0, 0))
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local function world(x: number, z: number, y: number?): Vector3
		return (frame * CFrame.new(x, y or 0, z)).Position
	end
	local h = PLOT_HALF

	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("Index", index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("WateredUntil", 0)
	model:SetAttribute("Speed", 1)
	model:SetAttribute("Pen", "[]")

	local base = part({
		Name = "Base",
		Size = Vector3.new(h * 2, 1.5, h * 2),
		CFrame = at(0, Y.plotBase - 0.75, 0),
		Color = COLORS.plotGrass,
		Material = Enum.Material.Grass,
		Parent = model,
	})
	model.PrimaryPart = base

	local penZ0, penZ1 = 9, h - 1
	part({
		Name = "PenFloor",
		Size = Vector3.new(h * 2 - 2, 0.6, penZ1 - penZ0),
		CFrame = at(0, Y.pen - 0.3, (penZ0 + penZ1) / 2),
		Color = COLORS.hay,
		Material = Enum.Material.Sand,
		Parent = model,
	})
	model:SetAttribute("PenCenter", world(0, (penZ0 + penZ1) / 2, Y.pen))
	model:SetAttribute("PenSize", Vector2.new(h * 2 - 6, penZ1 - penZ0 - 3))

	-- Fence: three closed sides, the gate on the hub side, a low fence around the pen.
	local fences = Instance.new("Folder")
	fences.Name = "Fence"
	fences.Parent = model
	local gateEdge = GATE_HALF + 1.2 -- leave room for the arch posts
	fence(fences, world(-h, -h, Y.plotBase), world(-gateEdge, -h, Y.plotBase))
	fence(fences, world(gateEdge, -h, Y.plotBase), world(h, -h, Y.plotBase))
	fence(fences, world(h, -h, Y.plotBase), world(h, h, Y.plotBase))
	fence(fences, world(h, h, Y.plotBase), world(-h, h, Y.plotBase))
	fence(fences, world(-h, h, Y.plotBase), world(-h, -h, Y.plotBase))
	fence(fences, world(-h + 1, penZ0, Y.pen), world(-4, penZ0, Y.pen), 2)
	fence(fences, world(4, penZ0, Y.pen), world(h - 1, penZ0, Y.pen), 2)

	-- Gate arch with the owner's name on top and the farm's $/min underneath, facing the path.
	local arch = group("GateArch", model)
	for _, side in { -1, 1 } do
		part({
			Name = "ArchPost",
			Size = Vector3.new(0.8, 9, 0.8),
			CFrame = at(side * GATE_HALF, Y.plotBase + 4.5, -h),
			Color = COLORS.darkWood,
			Material = Enum.Material.Wood,
			Parent = arch,
		})
	end
	part({
		Name = "ArchBeam",
		Size = Vector3.new(GATE_HALF * 2 + 1.6, 0.8, 0.9),
		CFrame = at(0, Y.plotBase + 9.2, -h),
		Color = COLORS.darkWood,
		Material = Enum.Material.Wood,
		Parent = arch,
	})
	-- Boards hang just in front of the arch (toward the hub) so they never clip into the posts.
	local nameBoard = part({
		Name = "NameBoard",
		Size = Vector3.new(GATE_HALF * 2 + 1, 2.4, 0.3),
		CFrame = at(0, Y.plotBase + 10.9, -h - 0.25),
		Color = COLORS.wood,
		Material = Enum.Material.WoodPlanks,
		Parent = arch,
	})
	local incomeBoard = part({
		Name = "IncomeBoard",
		Size = Vector3.new(GATE_HALF * 2 - 2.5, 1.5, 0.3),
		CFrame = at(0, Y.plotBase + 8, -h - 0.25),
		Color = COLORS.slate,
		Parent = arch,
	})
	local sign = signText(nameBoard, Enum.NormalId.Front, "Empty Plot")
	local income = signText(incomeBoard, Enum.NormalId.Front, "", COLORS.toxic)

	local slotsFolder = Instance.new("Folder")
	slotsFolder.Name = "Slots"
	slotsFolder.Parent = model
	local slots = {}
	for i, offset in slotOffsets() do
		local slot = part({
			Name = "Slot" .. i,
			Size = Vector3.new(SLOT_SIZE, 0.6, SLOT_SIZE),
			CFrame = at(offset.X, Y.soil - 0.3, offset.Z),
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
	spawn.CFrame = at(0, Y.plotBase + 0.1, -h + 3) * CFrame.Angles(0, math.pi, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Parent = model

	-- Path from the plaza edge to the gate (thick, so its edges sink into the valley).
	local from = Vector3.new(math.cos(angle) * (HUB_RADIUS - 1), 0, math.sin(angle) * (HUB_RADIUS - 1))
	local to = world(0, -h + 1)
	local mid = (from + to) / 2
	part({
		Name = "Path",
		Size = Vector3.new(7, 1, (to - from).Magnitude),
		CFrame = CFrame.lookAt(Vector3.new(mid.X, Y.path - 0.5, mid.Z), Vector3.new(to.X, Y.path - 0.5, to.Z)),
		Color = COLORS.path,
		Material = Enum.Material.Cobblestone,
		CanQuery = false,
		Parent = model,
	})

	model.Parent = parent
	return { index = index, model = model, slots = slots, spawn = spawn, sign = sign, income = income, frame = frame }
end

local function buildDecor(parent: Instance)
	local decor = group("Decor", parent)
	local n = GameConfig.islandCount
	for i = 0, n - 1 do
		-- Between each pair of plots (plots sit at half steps, so gaps are at whole steps).
		local angle = i / n * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local side = Vector3.new(-dir.Z, 0, dir.X)
		tree(decor, dir * 72, 0.9 + rng:next() * 0.3, i % 3 == 0)
		mushroom(decor, dir * 124 + side * (rng:next() * 2 - 1), 0.8 + rng:next() * 0.4)
		if i % 2 == 0 then
			barrel(decor, dir * 86)
		else
			rock(decor, dir * 136, Vector3.new(4, 2.6, 3.4))
		end
	end
	-- An outer ring of trees between the plots and the hedge, skipping the plot corners.
	for i = 0, 35 do
		local angle = i / 36 * math.pi * 2 + rng:next() * 0.04
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		tree(decor, dir * (152 + rng:next() * 3), 1 + rng:next() * 0.5, rng:next() < 0.25)
	end
end

-- Builds the map. `now` (unix seconds, default os.time()) decides which limited eggs dress the
-- hub; the preview tools pass LIMITED_AT to force it.
function World.build(now: number?): { Plot }
	setLighting()

	local map = Instance.new("Folder")
	map.Name = "Map"

	buildTerrain(map)
	buildHub(map, now or os.time())
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
World.surface = Y

return World
