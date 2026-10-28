--!strict
-- The hatch cutscene's set: a little mossy island in a magic swamp. A stump in the middle holds
-- the egg; twisted swamp trees, glowing mushrooms, reeds and lily pads surround it, and rings of
-- trees standing in the water fill every direction the camera looks, so nothing past the set shows.
-- The camera always sits on the -Z side looking +Z; that sector is kept clear of tall trees.
--
-- Built client-side far from the map (and by tools/preview for screenshots). Everything is anchored,
-- non-colliding and non-queryable. Pure geometry: no PivotTo/ScaleTo so it also runs under Lune.

local HatchIsland = {}

HatchIsland.STUMP_TOP = 1.2 -- the egg and the mutant stand here (local y)
HatchIsland.WATER_TOP = -1.2

local C = {
	water = Color3.fromHex("#2D5E5A"),
	shallow = Color3.fromHex("#3F7A6C"),
	moss = Color3.fromHex("#5C8C3E"),
	mossDark = Color3.fromHex("#466E31"),
	mud = Color3.fromHex("#5B4632"),
	bark = Color3.fromHex("#4A3A2E"),
	barkDark = Color3.fromHex("#3A2E25"),
	stump = Color3.fromHex("#7A5636"),
	stumpTop = Color3.fromHex("#B38B5C"),
	leaf = Color3.fromHex("#2F5E3E"),
	leafLight = Color3.fromHex("#3F7548"),
	leafFar = Color3.fromHex("#2A4F45"),
	hangingMoss = Color3.fromHex("#8DAA62"),
	lily = Color3.fromHex("#5FA84A"),
	reed = Color3.fromHex("#6E8A3A"),
	cattail = Color3.fromHex("#6B4528"),
	capCyan = Color3.fromHex("#62E0D2"),
	capPink = Color3.fromHex("#E07CF2"),
	stem = Color3.fromHex("#EDE3CF"),
	rock = Color3.fromHex("#6E6A78"),
}

-- Small deterministic RNG (Lune has no Random), so the set looks the same every time.
local function rng(seed: number)
	local state = seed
	return function(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

type Ctx = { origin: CFrame, parent: Model }

local function part(ctx: Ctx, name: string, size: Vector3, cf: CFrame, color: Color3, shape: string?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	if shape == "cylinder" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "ball" then
		p.Shape = Enum.PartType.Ball
	end
	p.Size = size
	p.CFrame = ctx.origin * cf
	if shape == "ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = ctx.parent
	return p
end

-- Upright cylinder (a Roblox cylinder's axis is X) with its top at `top`.
local function disc(
	ctx: Ctx,
	name: string,
	center: Vector3,
	radius: number,
	thickness: number,
	top: number,
	color: Color3
): BasePart
	return part(
		ctx,
		name,
		Vector3.new(thickness, radius * 2, radius * 2),
		CFrame.new(center.X, top - thickness / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		"cylinder"
	)
end

-- A cylinder from a to b.
local function limb(ctx: Ctx, name: string, a: Vector3, b: Vector3, thickness: number, color: Color3): BasePart
	local length = (b - a).Magnitude
	return part(
		ctx,
		name,
		Vector3.new(length, thickness, thickness),
		CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0),
		color,
		"cylinder"
	)
end

-- Twisted swamp tree: a leaning, bending trunk on splayed roots, a lumpy dark canopy and
-- strands of hanging moss. `base` is where the trunk meets the ground or water.
local function swampTree(ctx: Ctx, base: Vector3, height: number, rand: () -> number, far: boolean?)
	local thick = height * 0.09
	local lean = Vector3.new(rand() - 0.5, 0, rand() - 0.5) * height * 0.25
	local points = { base }
	for i = 1, 3 do
		local k = i / 3
		local wobble = Vector3.new(rand() - 0.5, 0, rand() - 0.5) * height * 0.08
		table.insert(points, base + Vector3.new(0, height * 0.72 * k, 0) + lean * k * k + wobble * (1 - k))
	end
	for i = 1, 3 do
		local t = thick * (1.25 - i * 0.18)
		limb(ctx, "Trunk", points[i], points[i + 1], t, if far then C.barkDark else C.bark)
		if i < 3 then -- round knuckle so the bends don't show flat cylinder ends
			part(
				ctx,
				"Knot",
				Vector3.one * t * 0.95,
				CFrame.new(points[i + 1]),
				if far then C.barkDark else C.bark,
				"ball"
			)
		end
	end
	-- Roots splay out and down into the ground or water.
	for r = 0, 3 do
		local a = r / 4 * math.pi * 2 + rand()
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		limb(
			ctx,
			"Root",
			base + Vector3.new(0, height * 0.12, 0),
			base + out * thick * 2.6 - Vector3.new(0, 1.2, 0),
			thick * 0.45,
			C.barkDark
		)
	end
	-- Canopy: a few flattened blobs around the top.
	local top = points[4]
	local leaf = if far then C.leafFar else C.leaf
	local spread = height * 0.34
	for b = 0, 4 do
		local a = b / 5 * math.pi * 2 + rand()
		local off = if b == 0 then Vector3.zero else Vector3.new(math.cos(a), 0, math.sin(a)) * spread * 0.6
		local s = spread * (if b == 0 then 1.3 else 0.9 + rand() * 0.3)
		part(
			ctx,
			"Canopy",
			Vector3.new(s * 1.6, s * 0.7, s * 1.6),
			CFrame.new(top + off + Vector3.new(0, (rand() - 0.3) * s * 0.3, 0)),
			if b % 2 == 0 then leaf else (if far then C.leafFar else C.leafLight),
			"ellipsoid"
		)
	end
	-- Hanging moss strands under the canopy edge.
	if not far then
		for m = 0, 6 do
			local a = m / 7 * math.pi * 2 + rand()
			local r = spread * (0.7 + rand() * 0.5)
			local len = height * (0.12 + rand() * 0.14)
			local at = top + Vector3.new(math.cos(a) * r, -spread * 0.15 - len / 2, math.sin(a) * r)
			part(ctx, "Moss", Vector3.new(0.25, len, 0.25), CFrame.new(at), C.hangingMoss)
		end
	end
end

local function mushroom(ctx: Ctx, base: Vector3, height: number, cap: Color3, rand: () -> number)
	local tilt = CFrame.Angles((rand() - 0.5) * 0.4, rand() * 6, (rand() - 0.5) * 0.4)
	local foot = CFrame.new(base) * tilt
	part(
		ctx,
		"MushroomStem",
		Vector3.new(height, height * 0.28, height * 0.28),
		foot * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		C.stem,
		"cylinder"
	)
	local capPart = part(
		ctx,
		"MushroomCap",
		Vector3.new(height * 1.1, height * 0.5, height * 1.1),
		foot * CFrame.new(0, height, 0),
		cap,
		"ellipsoid"
	)
	capPart.Material = Enum.Material.Neon
	capPart.Transparency = 0.1
	-- Spots on top.
	for s = 0, 2 do
		local a = s / 3 * math.pi * 2 + rand()
		part(
			ctx,
			"CapSpot",
			Vector3.new(height * 0.16, height * 0.06, height * 0.16),
			foot * CFrame.new(math.cos(a) * height * 0.28, height * 1.2, math.sin(a) * height * 0.28),
			C.stem,
			"ellipsoid"
		)
	end
end

local function reeds(ctx: Ctx, base: Vector3, rand: () -> number)
	for i = 1, 5 do
		local h = 2 + rand() * 2.2
		local off = Vector3.new(rand() - 0.5, 0, rand() - 0.5) * 1.4
		local tip = base + off + Vector3.new((rand() - 0.5) * 0.6, h, (rand() - 0.5) * 0.6)
		limb(ctx, "Reed", base + off - Vector3.new(0, 0.5, 0), tip, 0.14, C.reed)
		if i % 2 == 1 then
			part(
				ctx,
				"Cattail",
				Vector3.new(0.32, 0.9, 0.32),
				CFrame.lookAt(tip, tip + (tip - base - off).Unit) * CFrame.Angles(math.rad(90), 0, 0),
				C.cattail,
				"ellipsoid"
			)
		end
	end
end

-- Is this direction (from the island center) inside the camera's lane?
local function inCameraLane(angle: number, width: number): boolean
	-- The camera sits toward -Z, i.e. angle -pi/2.
	local d = math.abs(((angle + math.pi / 2 + math.pi) % (math.pi * 2)) - math.pi)
	return d < width
end

-- The camera backs straight out along -Z for big mutants; keep a widening wedge there clear.
local function blocksCamera(pos: Vector3, height: number): boolean
	return pos.Z < -8 and math.abs(pos.X) < 10 + height * 0.3 + math.abs(pos.Z) * 0.22
end

-- Builds the set at `origin` (the stump's base, island top at local y = 0) and returns it.
function HatchIsland.build(origin: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "HatchIsland"
	local ctx: Ctx = { origin = origin, parent = model }
	local rand = rng(424242)

	local center = part(ctx, "Center", Vector3.new(1, 1, 1), CFrame.new(), C.moss)
	center.Transparency = 1
	model.PrimaryPart = center

	-- Water to the horizon, with a lighter shallow ring around the island.
	part(ctx, "Water", Vector3.new(2048, 2, 2048), CFrame.new(0, HatchIsland.WATER_TOP - 1, 0), C.water).Reflectance =
		0.12
	disc(ctx, "Shallows", Vector3.zero, 19, 1, HatchIsland.WATER_TOP + 0.08, C.shallow)

	-- The island: mud rim, mossy top, a few lumps.
	disc(ctx, "Mud", Vector3.zero, 12.5, 3, -0.45, C.mud)
	local top = disc(ctx, "Island", Vector3.zero, 11, 3, 0, C.moss)
	top.Material = Enum.Material.Grass
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2 + 0.3
		local r = 6.5 + rand() * 2.5
		part(
			ctx,
			"Lump",
			Vector3.new(4 + rand() * 2, 1.2, 3 + rand() * 2),
			CFrame.new(math.cos(a) * r, -0.15, math.sin(a) * r) * CFrame.Angles(0, rand() * 6, 0),
			if i % 2 == 0 then C.moss else C.mossDark,
			"ellipsoid"
		)
	end

	-- The stump in the middle.
	disc(ctx, "Stump", Vector3.zero, 2.3, 1.6, HatchIsland.STUMP_TOP - 0.06, C.stump)
	disc(ctx, "StumpTop", Vector3.zero, 2.0, 0.12, HatchIsland.STUMP_TOP, C.stumpTop)
	for r = 0, 4 do
		local a = r / 5 * math.pi * 2 + 0.5
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		limb(ctx, "StumpRoot", out * 1.6 + Vector3.new(0, 0.6, 0), out * 3.4 - Vector3.new(0, 0.2, 0), 0.7, C.stump)
	end

	-- Island trees behind and beside the stump (never in front of the camera).
	for _, t in
		{
			{ 1.25, 8.2, 15 },
			{ 1.95, 8.6, 17 },
			{ 0.5, 8.4, 13 },
			{ 2.75, 7.6, 12 },
			{ 0.05, 7.4, 11 },
			{ 3.3, 7.6, 11 },
		}
	do
		swampTree(ctx, Vector3.new(math.cos(t[1]) * t[2], 0, math.sin(t[1]) * t[2]), t[3], rand)
	end

	-- Glowing mushrooms around the stump.
	for i = 0, 8 do
		local a = i / 9 * math.pi * 2 + 0.2
		if not inCameraLane(a, 0.35) then
			local r = 4.2 + rand() * 3.5
			mushroom(
				ctx,
				Vector3.new(math.cos(a) * r, 0, math.sin(a) * r),
				0.9 + rand() * 1.3,
				if i % 2 == 0 then C.capCyan else C.capPink,
				rand
			)
		end
	end
	-- Two big ones framing the shot.
	mushroom(ctx, Vector3.new(-7.5, 0, -1.5), 3.2, C.capPink, rand)
	mushroom(ctx, Vector3.new(7.8, 0, -0.5), 2.6, C.capCyan, rand)

	-- Reeds at the shoreline and rocks in the shallows.
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2 + rand() * 0.3
		reeds(ctx, Vector3.new(math.cos(a) * 12.3, HatchIsland.WATER_TOP, math.sin(a) * 12.3), rand)
	end
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2 + 0.6
		local s = 1.2 + rand() * 1.6
		part(
			ctx,
			"Rock",
			Vector3.new(s * 1.4, s, s * 1.2),
			CFrame.new(math.cos(a) * 14.5, HatchIsland.WATER_TOP + s * 0.2, math.sin(a) * 14.5)
				* CFrame.Angles(0, rand() * 6, 0),
			C.rock,
			"ellipsoid"
		)
	end

	-- Lily pads (some with flowers) on the water, including in front of the camera.
	for i = 0, 34 do
		local a = rand() * math.pi * 2
		local r = 14 + rand() * 30
		local d = 1.4 + rand() * 1.6
		local pos = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		disc(ctx, "LilyPad", pos, d / 2, 0.12, HatchIsland.WATER_TOP + 0.14, C.lily)
		if i % 5 == 0 then
			part(
				ctx,
				"Lotus",
				Vector3.new(0.6, 0.45, 0.6),
				CFrame.new(pos + Vector3.new(0, HatchIsland.WATER_TOP + 0.35, 0)),
				C.capPink,
				"ellipsoid"
			)
		end
	end

	-- Rings of trees standing in the water, ever bigger and darker, closing in every view.
	for ring, spec in { { 30, 14, 20, 26 }, { 46, 18, 28, 38 }, { 68, 22, 38, 52 }, { 100, 28, 52, 70 } } do
		local radius, count, minH, maxH = spec[1], spec[2], spec[3], spec[4]
		for i = 0, count - 1 do
			local a = (i + rand() * 0.6) / count * math.pi * 2
			local r = radius + (rand() - 0.5) * 8
			local pos = Vector3.new(math.cos(a) * r, HatchIsland.WATER_TOP, math.sin(a) * r)
			local h = minH + rand() * (maxH - minH)
			if not blocksCamera(pos, h) then
				swampTree(ctx, pos, h, rand, ring >= 3)
			end
		end
	end

	-- Fireflies drifting over the island (client only: Lune and the preview ignore these).
	local fireflies = part(ctx, "Fireflies", Vector3.new(36, 8, 36), CFrame.new(0, 5, 0), C.moss)
	fireflies.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Fireflies"
	emitter.Color = ColorSequence.new(Color3.fromHex("#E8FF8A"))
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(4, 7)
	emitter.Rate = 14
	emitter.Speed = NumberRange.new(0.3, 1)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.22),
		NumberSequenceKeypoint.new(0.8, 0.22),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = fireflies

	return model
end

return HatchIsland
