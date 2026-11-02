--!strict
-- Builds mutant and egg models from primitives, driven entirely by config: Config/Mutants.lua
-- (which look each species has), Config/MutantStyle.lua (each tier's bodies, skins, features,
-- props and idle animations, as part recipes), Config/Sizes.lua (how big they look) and
-- Config/Eggs.lua (egg designs). Species with `features` are built from MutantStyle; the
-- hand-made limited species (Pumpkin) keep the older trait builder (body / eyes / mouth /
-- accessory). Used by the client (plots, pens, hatch reveal) and by tools/preview.
-- Models are anchored, non-colliding, face -Z, and have their PrimaryPart at the feet.

local Config = script.Parent.Config
local Mutants = require(Config.Mutants)
local Mutations = require(Config.Mutations)
local Eggs = require(Config.Eggs)
local Sizes = require(Config.Sizes)
local Style = require(Config.MutantStyle)

local MutantModel = {}

export type MutantData = { tier: string, rarity: string, species: string?, mutations: { string }, size: number }

local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromHex("#1E2230")
local MOUTH = Color3.fromHex("#3A1424")
local TONGUE = Color3.fromHex("#FF6F91")

-------------------------------------------------------------------------------- helpers

local function newPart(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, shape: string?): BasePart
	local p: BasePart = if shape == "wedge" then Instance.new("WedgePart") else Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	p.CFrame = cf
	p.Color = color
	if shape == "ball" then
		(p :: Part).Shape = Enum.PartType.Ball
	elseif shape == "ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif shape == "cylinder" then
		(p :: Part).Shape = Enum.PartType.Cylinder
	end
	p.Parent = model
	return p
end

local function mutationSet(mutations: { string }): { [string]: boolean }
	local set = {}
	for _, id in mutations do
		set[id] = true
	end
	return set
end

-- Body color after mutations; the strongest mutation wins the paint job. `material` and
-- `reflectance` are the skin's own (default SmoothPlastic, 0) until a mutation replaces them.
local function paint(
	base: Color3,
	set: { [string]: boolean },
	material0: Enum.Material?,
	reflectance0: number?
): (Color3, Enum.Material, number)
	local color, material, reflectance = base, material0 or Enum.Material.SmoothPlastic, reflectance0 or 0
	if set.Shiny then
		color = color:Lerp(WHITE, 0.3)
		reflectance = 0.25
	end
	if set.Golden then
		color = Color3.fromHex("#FFD24A")
		material = Enum.Material.Foil
		reflectance = 0.1
	end
	if set.Radioactive then
		color = color:Lerp(Color3.fromHex("#7CFF4A"), 0.65)
	end
	if set.Glitched then
		color = color:Lerp(Color3.fromHex("#FF3CF0"), 0.6)
	end
	if set.Cosmic then
		color = Color3.fromHex("#3B1A78")
		material = Enum.Material.Glass
		reflectance = 0.2
	end
	return color, material, reflectance
end

local function addEffects(model: Model, anchor: BasePart, set: { [string]: boolean }, scale: number)
	local function emitter(color: Color3, rate: number)
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(color)
		e.LightEmission = 0.3
		e.Rate = rate
		e.Lifetime = NumberRange.new(0.8, 1.6)
		e.Speed = NumberRange.new(0.5 * scale, 1.5 * scale)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3 * scale),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Parent = anchor
	end
	local function light(color: Color3)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = math.min(5 * scale, 16)
		l.Brightness = 0.35
		l.Parent = anchor
	end
	if set.Shiny then
		emitter(WHITE, 6)
	end
	if set.Golden then
		emitter(Color3.fromHex("#FFD24A"), 8)
		light(Color3.fromHex("#FFD24A"))
	end
	if set.Radioactive then
		emitter(Color3.fromHex("#7CFF4A"), 10)
		light(Color3.fromHex("#7CFF4A"))
	end
	if set.Glitched then
		-- No Highlight: Roblox renders at most 31 per client. The client flickers the body color instead.
		model:SetAttribute("Glitched", true)
		emitter(Color3.fromHex("#00F0FF"), 6)
	end
	if set.Cosmic then
		emitter(Color3.fromHex("#C9B8FF"), 14)
		light(Color3.fromHex("#9B5CFF"))
	end
end

-- Point on an ellipsoid (radii r) at longitude u (0 = front, -Z) and latitude v (0 = top, pi = bottom).
local function surface(center: CFrame, r: Vector3, u: number, v: number): CFrame
	local local_ = Vector3.new(r.X * math.sin(v) * math.sin(u), r.Y * math.cos(v), -r.Z * math.sin(v) * math.cos(u))
	local pos = center * local_
	local outward = center:VectorToWorldSpace(
		Vector3.new(local_.X / (r.X * r.X), local_.Y / (r.Y * r.Y), local_.Z / (r.Z * r.Z))
	).Unit
	-- Face outward: the part's -Z points away from the body.
	return CFrame.lookAt(pos, pos + outward)
end

-------------------------------------------------------------------------------- mutants

export type Species = {
	id: string,
	tier: string,
	rarity: string,
	name: string,
	body: string,
	color: string,
	accent: string,
	scale: number,
	-- MutantStyle species (every egg tier):
	skin2: string?, -- secondary tone
	features: { string }?, -- feature ids, the tier's signature first
	prop: string?, -- Epic / Legendary: a prop no other species in the tier has
	idleVariant: string?, -- Legendary: a named variant of the tier's idle animation
	-- Hand-made limited species (Pumpkin):
	pattern: string?,
	eyes: number?,
	eyeStyle: string?,
	mouth: string?,
	accessory: string?,
}

function MutantModel.species(data: MutantData): Species
	local entry = data.species and Mutants.species[data.species]
	if entry and entry.tier == data.tier and entry.rarity == data.rarity then
		return entry
	end
	-- Items from before species existed fall back to the first species of their bucket.
	return Mutants.species[Mutants.buckets[data.tier][data.rarity][1]]
end

-- Studs-per-unit scale for a mutant. Base mutant is ~3 studs tall at 1.
function MutantModel.visualScale(data: MutantData): number
	local v = Sizes.visual
	local species = MutantModel.species(data)
	return v.tierScale[Eggs.sizeTier(data.tier)]
		* v.rarityScale[data.rarity]
		* species.scale
		* data.size ^ v.sizeExponent
end

type Head = { cf: CFrame, r: Vector3 } -- where the face goes

-- Builds the body parts and returns the head (face anchor) and the main body part.
local function buildBody(
	model: Model,
	kind: string,
	s: number,
	color: Color3,
	material: Enum.Material,
	reflectance: number
): (Head, BasePart)
	local function blobPart(name: string, size: Vector3, cf: CFrame): BasePart
		local p = newPart(model, name, size * s, cf, color, "ellipsoid")
		p.Material = material
		p.Reflectance = reflectance
		return p
	end
	local function at(y: number): CFrame
		return CFrame.new(0, y * s, 0)
	end
	if kind == "tall" then
		local size = Vector3.new(2, 3.3, 2)
		local body = blobPart("Body", size, at(1.9))
		return { cf = at(2.4), r = Vector3.new(1, 1.2, 1) * s }, body
	elseif kind == "flat" then
		local size = Vector3.new(3.2, 1.6, 2.7)
		local body = blobPart("Body", size, at(1))
		return { cf = at(1.05), r = size / 2 * s }, body
	elseif kind == "pear" then
		local body = blobPart("Body", Vector3.new(2.8, 2.2, 2.6), at(1.2))
		local headSize = Vector3.new(1.9, 1.7, 1.8)
		blobPart("Head", headSize, at(2.6))
		return { cf = at(2.65), r = headSize / 2 * s }, body
	elseif kind == "worm" then
		local body = blobPart("Body", Vector3.new(2.2, 1.6, 2.2), at(0.9))
		blobPart("Segment", Vector3.new(1.9, 1.5, 1.9), at(2.1) * CFrame.new(0.25 * s, 0, 0))
		local headSize = Vector3.new(2, 1.8, 1.9)
		local headCf = at(3.4) * CFrame.new(-0.1 * s, 0, -0.1 * s)
		blobPart("Head", headSize, headCf)
		return { cf = headCf, r = headSize / 2 * s }, body
	elseif kind == "puff" then
		local body = blobPart("Body", Vector3.new(2.4, 2.2, 2.3), at(1.3))
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			blobPart(
				"Puff",
				Vector3.new(1.3, 1.3, 1.3),
				at(1.2 + (i % 2) * 0.5) * CFrame.new(math.cos(a) * 1.1 * s, 0, math.sin(a) * 1.1 * s + 0.3 * s)
			)
		end
		return { cf = at(1.45), r = Vector3.new(1.2, 1.1, 1.15) * s }, body
	else -- blob, spiky
		local size = Vector3.new(2.6, 2.3, 2.4)
		local body = blobPart("Body", size, at(1.35))
		return { cf = at(1.45), r = size / 2 * s }, body
	end
end

local function buildEye(model: Model, cf: CFrame, s: number, style: string, glow: boolean, lidColor: Color3)
	if style == "stalk" then
		newPart(model, "Stalk", Vector3.new(0.18, 1, 0.18) * s, cf * CFrame.new(0, 0.5 * s, 0.2 * s), DARK)
		cf = cf * CFrame.new(0, 1.1 * s, 0.1 * s)
	end
	newPart(model, "Eye", Vector3.new(0.75, 0.8, 0.5) * s, cf, WHITE, "ellipsoid")
	local pupil = newPart(
		model,
		"Pupil",
		Vector3.new(0.38, 0.42, 0.3) * s,
		cf * CFrame.new(0, -0.04 * s, -0.16 * s),
		DARK,
		"ellipsoid"
	)
	if glow then
		pupil.Color = Color3.fromHex("#FF5CE1")
		pupil.Material = Enum.Material.Neon
	end
	newPart(
		model,
		"Shine",
		Vector3.new(0.13, 0.13, 0.1) * s,
		cf * CFrame.new(0.08 * s, 0.1 * s, -0.27 * s),
		WHITE,
		"ellipsoid"
	)
	if style == "sleepy" then
		newPart(
			model,
			"Lid",
			Vector3.new(0.82, 0.45, 0.56) * s,
			cf * CFrame.new(0, 0.2 * s, -0.02 * s),
			lidColor,
			"ellipsoid"
		)
	elseif style == "angry" then
		newPart(
			model,
			"Brow",
			Vector3.new(0.7, 0.14, 0.15) * s,
			cf * CFrame.new(0, 0.45 * s, -0.15 * s) * CFrame.Angles(0, 0, math.rad(-15)),
			DARK
		)
	end
end

local function buildMouth(model: Model, kind: string, cf: CFrame, s: number)
	if kind == "none" then
		return
	elseif kind == "wide" then
		newPart(model, "Mouth", Vector3.new(1.3, 0.55, 0.3) * s, cf, MOUTH, "ellipsoid")
		newPart(
			model,
			"Tongue",
			Vector3.new(0.6, 0.25, 0.3) * s,
			cf * CFrame.new(0, -0.12 * s, -0.05 * s),
			TONGUE,
			"ellipsoid"
		)
		return
	end
	newPart(model, "Mouth", Vector3.new(0.7, 0.22, 0.2) * s, cf, MOUTH, "ellipsoid")
	if kind == "fangs" then
		for _, side in { -1, 1 } do
			newPart(
				model,
				"Fang",
				Vector3.new(0.14, 0.28, 0.14) * s,
				cf * CFrame.new(side * 0.22 * s, -0.17 * s, -0.08 * s),
				WHITE
			)
		end
	elseif kind == "tooth" then
		newPart(model, "Tooth", Vector3.new(0.4, 0.6, 0.25) * s, cf * CFrame.new(0, -0.25 * s, -0.08 * s), WHITE)
	elseif kind == "tongue" then
		newPart(
			model,
			"Tongue",
			Vector3.new(0.35, 0.5, 0.15) * s,
			cf * CFrame.new(0.1 * s, -0.25 * s, -0.12 * s) * CFrame.Angles(math.rad(-20), 0, 0),
			TONGUE,
			"ellipsoid"
		)
	end
end

local function buildPattern(model: Model, kind: string, body: BasePart, s: number, accent: Color3, color: Color3)
	local center = body.CFrame
	local r = body.Size / 2
	if kind == "spots" then
		for i, uv in { { 0.9, 0.9 }, { -0.8, 1.2 }, { 2.4, 1.4 }, { -2.2, 0.8 }, { 3.1, 1.9 }, { 1.6, 2.1 } } do
			local d = (if i % 2 == 0 then 0.5 else 0.7) * s
			newPart(
				model,
				"Spot",
				Vector3.new(d, d, 0.12 * s),
				surface(center, r * 0.99, uv[1], uv[2]),
				accent,
				"ellipsoid"
			)
		end
	elseif kind == "stripes" then
		for _, h in { 0.35, 0, -0.35 } do
			local k = math.sqrt(1 - h * h)
			newPart(
				model,
				"Stripe",
				Vector3.new(r.X * 2 * k + 0.06 * s, 0.22 * s, r.Z * 2 * k + 0.06 * s),
				center * CFrame.new(0, h * r.Y, 0),
				accent,
				"ellipsoid"
			)
		end
	elseif kind == "belly" then
		newPart(
			model,
			"Belly",
			Vector3.new(r.X * 1.2, r.Y * 1.1, r.Z * 0.6),
			center * CFrame.new(0, -r.Y * 0.2, -r.Z * 0.72),
			color:Lerp(WHITE, 0.45),
			"ellipsoid"
		)
	end
end

local function buildAccessory(model: Model, kind: string, head: Head, s: number, accent: Color3, color: Color3)
	local top = head.cf * CFrame.new(0, head.r.Y * 0.92, 0)
	local gold = Color3.fromHex("#FFD24A")
	if kind == "antennae" then
		for _, side in { -1, 1 } do
			local base = top * CFrame.new(side * head.r.X * 0.4, 0, 0) * CFrame.Angles(0, 0, math.rad(-side * 18))
			newPart(model, "Stalk", Vector3.new(0.15, 1.2, 0.15) * s, base * CFrame.new(0, 0.55 * s, 0), DARK)
			newPart(model, "Bulb", Vector3.new(0.45, 0.45, 0.45) * s, base * CFrame.new(0, 1.2 * s, 0), accent, "ball")
		end
	elseif kind == "crown" then
		local band = top * CFrame.new(0, 0.1 * s, 0)
		local ring = newPart(
			model,
			"Crown",
			Vector3.new(0.35, 1.3, 1.3) * s,
			band * CFrame.Angles(0, 0, math.rad(90)),
			gold,
			"cylinder"
		)
		ring.Material = Enum.Material.Foil
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			local spike = newPart(
				model,
				"CrownSpike",
				Vector3.new(0.22, 0.45, 0.22) * s,
				band * CFrame.new(math.cos(a) * 0.55 * s, 0.35 * s, math.sin(a) * 0.55 * s),
				gold
			)
			spike.Material = Enum.Material.Foil
		end
		newPart(
			model,
			"Jewel",
			Vector3.new(0.3, 0.3, 0.3) * s,
			band * CFrame.new(0, 0, -0.66 * s),
			Color3.fromHex("#FF3C6E"),
			"ball"
		).Material =
			Enum.Material.Neon
	elseif kind == "halo" then
		local ring = top * CFrame.new(0, 0.9 * s, 0)
		for i = 0, 9 do
			local a = i / 10 * math.pi * 2
			newPart(
				model,
				"Halo",
				Vector3.new(0.3, 0.3, 0.3) * s,
				ring * CFrame.new(math.cos(a) * 0.8 * s, 0, math.sin(a) * 0.8 * s),
				gold,
				"ball"
			).Material =
				Enum.Material.Neon
		end
	elseif kind == "horns" then
		for _, side in { -1, 1 } do
			newPart(
				model,
				"Horn",
				Vector3.new(0.35, 1, 0.35) * s,
				top * CFrame.new(side * head.r.X * 0.55, 0, 0) * CFrame.Angles(0, 0, math.rad(-side * 30)),
				Color3.fromHex("#F2E6C9"),
				"ellipsoid"
			)
		end
	elseif kind == "ears" then
		for _, side in { -1, 1 } do
			newPart(
				model,
				"Ear",
				Vector3.new(0.9, 0.55, 0.3) * s,
				head.cf
					* CFrame.new(side * head.r.X * 0.95, head.r.Y * 0.2, 0)
					* CFrame.Angles(0, 0, math.rad(side * 25)),
				accent,
				"ellipsoid"
			)
		end
	elseif kind == "leaf" then
		newPart(
			model,
			"Leaf",
			Vector3.new(1.9, 0.15, 1.7) * s,
			top * CFrame.new(0, 0.05 * s, 0) * CFrame.Angles(0, 0, math.rad(8)),
			Color3.fromHex("#3FA34D"),
			"ellipsoid"
		)
	elseif kind == "goggles" then
		newPart(
			model,
			"Strap",
			Vector3.new(head.r.X * 2.04, 0.25 * s, head.r.Z * 2.04),
			head.cf * CFrame.new(0, head.r.Y * 0.25, 0),
			DARK,
			"ellipsoid"
		)
	elseif kind == "mohawk" then
		for i = -2, 2 do
			newPart(
				model,
				"Mohawk",
				Vector3.new(0.25, 0.7, 0.55) * s,
				top * CFrame.new(0, 0.2 * s, i * 0.35 * s) * CFrame.Angles(0, math.rad(90), 0),
				accent,
				"wedge"
			)
		end
	elseif kind == "wings" then
		for _, side in { -1, 1 } do
			local wing = newPart(
				model,
				"Wing",
				Vector3.new(1.8, 1.2, 0.15) * s,
				head.cf
					* CFrame.new(side * (head.r.X + 0.5 * s), 0.3 * s, head.r.Z * 0.6)
					* CFrame.Angles(0, math.rad(side * 35), math.rad(side * 20)),
				accent,
				"ellipsoid"
			)
			wing.Transparency = 0.15
		end
	elseif kind == "witchHat" then
		-- A wide brim and a tall cone, tipped a little to one side.
		local hat = top * CFrame.new(0, 0.05 * s, 0) * CFrame.Angles(0, 0, math.rad(-8))
		newPart(
			model,
			"HatBrim",
			Vector3.new(0.12, 2.3, 2.3) * s,
			hat * CFrame.Angles(0, 0, math.rad(90)),
			accent,
			"cylinder"
		)
		for i, w in { 1.25, 0.95, 0.65, 0.35 } do
			newPart(
				model,
				"HatCone",
				Vector3.new(w, 0.45, w) * s,
				hat * CFrame.new(0, (0.2 + (i - 1) * 0.38) * s, 0),
				accent,
				"ellipsoid"
			)
		end
		newPart(
			model,
			"HatBand",
			Vector3.new(0.14, 1.32, 1.32) * s,
			hat * CFrame.new(0, 0.22 * s, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromHex("#FF8A1F"),
			"cylinder"
		)
	elseif kind == "stem" then
		-- A pumpkin's stem with one curly leaf.
		newPart(
			model,
			"Stem",
			Vector3.new(0.7, 0.35, 0.35) * s, -- cylinders run along X: stood up below
			top * CFrame.new(0, 0.25 * s, 0) * CFrame.Angles(0, 0, math.rad(102)),
			Color3.fromHex("#5B3A24"),
			"cylinder"
		)
		newPart(
			model,
			"Leaf",
			Vector3.new(0.9, 0.12, 0.6) * s,
			top * CFrame.new(0.45 * s, 0.35 * s, 0) * CFrame.Angles(0, 0, math.rad(-20)),
			Color3.fromHex("#3FA34D"),
			"ellipsoid"
		)
	end
	local _ = color
end

-- The older trait builder: hand-made limited species (Pumpkin).
local function buildLegacy(data: MutantData, info: Species, set: { [string]: boolean }, s: number): Model
	local model = Instance.new("Model")
	model.Name = info.name
	model:SetAttribute("Tier", data.tier)
	model:SetAttribute("Rarity", data.rarity)
	model:SetAttribute("Height", 3.6 * s)

	-- Root sits at the feet (origin) so PivotTo(floor) never sinks giants into the ground.
	local root = newPart(model, "Root", Vector3.new(1, 0.2, 1) * s, CFrame.new(), WHITE)
	root.Transparency = 1
	model.PrimaryPart = root

	local base = Color3.fromHex(info.color)
	local accent = Color3.fromHex(info.accent)
	local color, material, reflectance = paint(base, set)
	local head, body = buildBody(model, info.body, s, color, material, reflectance)

	buildPattern(
		model,
		info.pattern or "plain",
		body,
		s,
		if set.Radioactive then Color3.fromHex("#7CFF4A") else accent,
		color
	)

	-- Feet
	for _, side in { -1, 1 } do
		newPart(
			model,
			"Foot",
			Vector3.new(0.8, 0.45, 1) * s,
			CFrame.new(side * body.Size.X * 0.25, 0.22 * s, -0.15 * s),
			color:Lerp(DARK, 0.35),
			"ellipsoid"
		)
	end

	if info.body == "spiky" then
		for i = 0, 4 do
			local a = math.rad(-60 + i * 30)
			newPart(
				model,
				"Spike",
				Vector3.new(0.4, 0.9, 0.7) * s,
				body.CFrame
					* CFrame.Angles(a, 0, 0)
					* CFrame.new(0, body.Size.Y * 0.48, 0)
					* CFrame.Angles(0, math.pi, 0),
				accent:Lerp(DARK, 0.2),
				"wedge"
			)
		end
	end

	-- Face on the front (-Z) of the head.
	local face = head.cf * CFrame.new(0, head.r.Y * 0.2, -head.r.Z * 0.86)
	local eyeCount = info.eyes or 2
	local eyeScale = s * (if eyeCount == 1 then 1.5 else 1)
	local positions = if eyeCount == 1
		then { Vector3.new(0, 0, 0) }
		elseif eyeCount == 2 then { Vector3.new(-0.42, 0, 0), Vector3.new(0.42, 0, 0) }
		elseif eyeCount == 3 then {
			Vector3.new(-0.55, -0.05, 0.05),
			Vector3.new(0, 0.3, -0.05),
			Vector3.new(0.55, -0.05, 0.05),
		}
		else {
			Vector3.new(-0.62, -0.08, 0.08),
			Vector3.new(-0.22, 0.25, -0.03),
			Vector3.new(0.22, 0.25, -0.03),
			Vector3.new(0.62, -0.08, 0.08),
		}
	for _, p in positions do
		buildEye(model, face * CFrame.new(p * s), eyeScale, info.eyeStyle or "normal", set.Cosmic == true, color)
	end
	if info.accessory == "goggles" then
		for _, p in positions do
			newPart(
				model,
				"Lens",
				Vector3.new(0.25, 1, 1) * eyeScale,
				face * CFrame.new(p * s + Vector3.new(0, 0, -0.18 * s)) * CFrame.Angles(0, math.rad(90), 0),
				DARK,
				"cylinder"
			).Transparency =
				0.35
		end
	end
	buildMouth(model, info.mouth or "smile", face * CFrame.new(0, -0.62 * s, 0.05 * s), s)
	buildAccessory(model, info.accessory or "none", head, s, accent, color)

	addEffects(model, body, set, s)
	return model
end

-------------------------------------------------------------------------------- styled mutants

local SHAPES = { ball = "ball", ellipsoid = "ellipsoid", cyl = "cylinder", wedge = "wedge", block = nil }
local SKIN_ROLES = { skin = true, skin2 = true, skinDark = true, skinLight = true }

-- A tier's feature / body / prop by id (signatures and the pool share one lookup).
local lookups: { [string]: { features: { [string]: any }, bodies: { [string]: any }, props: { [string]: any } } } = {}
local function lookup(tier: string)
	local cached = lookups[tier]
	if cached then
		return cached
	end
	local st = (Style :: any)[tier]
	local out = { features = {}, bodies = {}, props = {} }
	for _, f in st.signatures do
		out.features[f.id] = f
	end
	for _, f in st.features do
		out.features[f.id] = f
	end
	for _, b in st.bodies do
		out.bodies[b.id] = b
	end
	for _, p in st.props do
		out.props[p.id] = p
	end
	lookups[tier] = out
	return out
end
MutantModel.lookup = lookup

type Ctx = {
	model: Model,
	s: number,
	pal: { [string]: Color3 },
	material: Enum.Material,
	reflectance: number,
	transparency: number,
	anchors: { [string]: CFrame },
	overlay: any?,
}

local function roleColor(ctx: Ctx, role: string, tint: Color3?): Color3
	if role:sub(1, 1) == "#" then
		return Color3.fromHex(role)
	elseif role == "prop" then
		return tint or ctx.pal.accent
	elseif role == "dark" then
		return DARK
	elseif role == "white" then
		return WHITE
	end
	return ctx.pal[role] or ctx.pal.skin
end

-- Builds one piece (and its mirror / ring copies). Returns the parts.
local function buildPiece(ctx: Ctx, piece: any, tint: Color3?, defaultName: string): { BasePart }
	local s = ctx.s
	local anchor = ctx.anchors[piece.at] or ctx.anchors.root
	local out = {}
	local mirrors = if piece.mirror then { 1, -1 } else { 1 }
	local ring = piece.ring
	local n = if ring then ring.n else 1
	local size = Vector3.new(piece.size[1], piece.size[2], piece.size[3]) * s
	local color = roleColor(ctx, piece.color, tint)
	local skinRole = SKIN_ROLES[piece.color] == true
	for _, m in mirrors do
		-- The mirror copy reflects across the body's center line (x = 0), anchor included, so a
		-- piece on the right side's anchor gets its twin on the left side.
		local anchor = if m == 1
			then anchor
			else CFrame.new(-anchor.Position.X, anchor.Position.Y, anchor.Position.Z) * anchor.Rotation
		local pos = Vector3.new(piece.pos[1] * m, piece.pos[2], piece.pos[3]) * s
		local rot = if piece.rot
			then CFrame.Angles(math.rad(piece.rot[1]), math.rad(piece.rot[2]) * m, math.rad(piece.rot[3]) * m)
			else CFrame.identity
		for i = 0, n - 1 do
			local cf
			if ring then
				local a = (i + (ring.phase or 0)) / n * math.pi * 2
				cf = if ring.axis == "z"
					then anchor * CFrame.new(pos) * CFrame.Angles(0, 0, a) * CFrame.new(0, ring.r * s, 0) * rot
					else anchor * CFrame.new(pos) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -ring.r * s) * rot
			else
				cf = anchor * CFrame.new(pos) * rot
			end
			local p = newPart(ctx.model, piece.name or defaultName, size, cf, color, SHAPES[piece.shape])
			if piece.mat then
				p.Material = (Enum.Material :: any)[piece.mat]
			elseif piece.neon then
				p.Material = Enum.Material.Neon
			elseif skinRole then
				p.Material = ctx.material
			end
			p.Reflectance = piece.refl or (if skinRole then ctx.reflectance else 0)
			p.Transparency = piece.tr or (if skinRole then ctx.transparency else 0)
			if piece.anim then
				p:SetAttribute("Idle", piece.anim)
				if piece.anim == "orbit" then
					p:SetAttribute("OrbitCenter", Vector3.new(anchor.Position.X, 0, anchor.Position.Z))
				end
			end
			table.insert(out, p)
		end
	end
	return out
end

-- Slow, faint particles (skin and feature `particles`).
local function particles(anchor: BasePart, def: any, s: number)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Color3.fromHex(def.color))
	e.LightEmission = 0
	e.Rate = def.rate
	e.Lifetime = NumberRange.new(def.lifetime * 0.7, def.lifetime)
	e.Speed = NumberRange.new(def.speed * 0.5 * s, def.speed * s)
	e.SpreadAngle = Vector2.new(30, 30)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, def.transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, def.size * s),
		NumberSequenceKeypoint.new(1, def.size * s * 1.6),
	})
	e.Parent = anchor
end

-- Eyes that aren't white: sclera color, pupil size (x, y) and color.
local TINTED_EYES: { [string]: any } = {
	frog = { sclera = Color3.fromHex("#E8C84A"), pupil = { 0.5, 0.16 }, pupilColor = DARK },
	-- Dark eyes with an acid-green glowing slit (reads on the light slime skin).
	toxic = {
		sclera = Color3.fromHex("#1E2A0A"),
		pupil = { 0.12, 0.44 },
		pupilColor = Color3.fromHex("#C8FF3A"),
		neon = true,
	},
	-- Pale lavender eyes, a deep-blue pupil and a star glint (reads on the dark cosmic skins).
	starlit = {
		sclera = Color3.fromHex("#DCD4FF"),
		reflectance = 0.2,
		pupil = { 0.36, 0.4 },
		pupilColor = Color3.fromHex("#2A1A6A"),
		glint = true,
	},
}

-- The face: tier defaults, then each feature's overrides in order (the signature first).
local function buildStyledFace(ctx: Ctx, face: { [string]: any }, set: { [string]: boolean })
	local s = ctx.s
	local head = ctx.anchors.head
	local hr = ctx.anchors.headR.Position -- head radii (a CFrame only to keep the table typed)
	local front = ctx.anchors.face
	local eyes = face.eyes or 2
	local style = face.eyeStyle or "normal"
	local eyeScale = s * (if style == "glow" then 1.05 elseif eyes == 1 then 1.5 elseif style == "baby" then 1.3 else 1)
	local positions = if eyes == 1
		then { Vector3.new(0, 0, 0) }
		elseif eyes == 2 then { Vector3.new(-0.42, 0, 0), Vector3.new(0.42, 0, 0) }
		elseif eyes == 3 then {
			Vector3.new(-0.55, -0.05, 0.05),
			Vector3.new(0, 0.3, -0.05),
			Vector3.new(0.55, -0.05, 0.05),
		}
		else {
			Vector3.new(-0.62, -0.08, 0.08),
			Vector3.new(-0.22, 0.25, -0.03),
			Vector3.new(0.22, 0.25, -0.03),
			Vector3.new(0.62, -0.08, 0.08),
		}
	for _, p in positions do
		local cf = front * CFrame.new(p * s)
		if style == "bulge" then
			-- Frog eyes on bumps on top of the head.
			cf = head * CFrame.new(p.X * s * 1.2, hr.Y * 0.85, -hr.Z * 0.35)
			newPart(ctx.model, "EyeBump", Vector3.new(0.85, 0.75, 0.85) * s, cf, ctx.pal.skin, "ellipsoid").Material =
				ctx.material
			cf = cf * CFrame.new(0, 0.12 * s, -0.3 * s)
		end
		-- Tier eyes with their own colors: a sclera, then a pupil shape.
		local tinted = TINTED_EYES[style]
		if tinted then
			local eye =
				newPart(ctx.model, "Eye", Vector3.new(0.75, 0.8, 0.5) * eyeScale, cf, tinted.sclera, "ellipsoid")
			eye.Reflectance = tinted.reflectance or 0
			local pupil = newPart(
				ctx.model,
				"Pupil",
				Vector3.new(tinted.pupil[1], tinted.pupil[2], 0.2) * eyeScale,
				cf * CFrame.new(0, -0.03 * eyeScale, -0.2 * eyeScale),
				tinted.pupilColor,
				"ellipsoid"
			)
			if tinted.neon then
				pupil.Material = Enum.Material.Neon
			end
			if tinted.glint then
				newPart(
					ctx.model,
					"Glint",
					Vector3.new(0.12, 0.12, 0.08) * eyeScale,
					cf * CFrame.new(0.1 * eyeScale, 0.1 * eyeScale, -0.29 * eyeScale),
					WHITE,
					"ball"
				).Material =
					Enum.Material.Neon
			end
			if style == "toxic" then
				newPart(
					ctx.model,
					"Brow",
					Vector3.new(0.7, 0.14, 0.15) * eyeScale,
					cf
						* CFrame.new(0, 0.45 * eyeScale, -0.15 * eyeScale)
						* CFrame.Angles(0, 0, math.rad(p.X > 0 and 15 or -15)),
					DARK
				)
			end
		elseif style == "hollow" then
			newPart(
				ctx.model,
				"Socket",
				Vector3.new(0.6, 0.7, 0.3) * eyeScale,
				cf,
				Color3.fromHex("#06040A"),
				"ellipsoid"
			)
			newPart(
				ctx.model,
				"Pupil",
				Vector3.new(0.14, 0.14, 0.1) * eyeScale,
				cf * CFrame.new(0, 0, -0.14 * eyeScale),
				Color3.fromHex("#8A6AD8"),
				"ball"
			).Material =
				Enum.Material.Neon
		elseif style == "glow" then
			newPart(ctx.model, "Eye", Vector3.new(0.75, 0.8, 0.5) * eyeScale, cf, WHITE, "ellipsoid")
			local glow = newPart(
				ctx.model,
				"Pupil",
				Vector3.new(0.3, 0.3, 0.2) * eyeScale,
				cf * CFrame.new(0, 0, -0.2 * eyeScale),
				Color3.fromHex("#F0ECFF"),
				"ball"
			)
			glow.Material = Enum.Material.Neon
			glow:SetAttribute("Idle", "flicker")
		else
			local kind = if style == "sleepy" or style == "angry" then style else "normal"
			buildEye(ctx.model, cf, eyeScale, kind, set.Cosmic == true, ctx.pal.skin)
			if style == "baby" then
				newPart(
					ctx.model,
					"Shine",
					Vector3.new(0.18, 0.18, 0.1) * eyeScale,
					cf * CFrame.new(-0.12 * eyeScale, -0.12 * eyeScale, -0.27 * eyeScale),
					WHITE,
					"ellipsoid"
				)
			elseif style == "star" then
				local star = newPart(
					ctx.model,
					"StarPupil",
					Vector3.new(0.16, 0.16, 0.12) * eyeScale,
					cf * CFrame.new(0, 0, -0.3 * eyeScale),
					Color3.fromHex("#FFD24A"),
					"ball"
				)
				star.Material = Enum.Material.Neon
			elseif style == "goggle" then
				newPart(
					ctx.model,
					"Lens",
					Vector3.new(0.25, 1, 1) * eyeScale,
					cf * CFrame.new(0, 0, -0.18 * s) * CFrame.Angles(0, math.rad(90), 0),
					DARK,
					"cylinder"
				).Transparency =
					0.35
			end
		end
	end
	local mouth = face.mouth or "smile"
	local mcf = front * CFrame.new(0, -0.62 * s, 0.05 * s)
	if mouth == "frog" then
		newPart(
			ctx.model,
			"Mouth",
			Vector3.new(hr.X * 1.6, 0.14 * s, 0.3 * s),
			mcf * CFrame.new(0, 0.1 * s, 0),
			MOUTH,
			"ellipsoid"
		)
	elseif mouth == "line" then
		newPart(ctx.model, "Mouth", Vector3.new(0.5, 0.08, 0.15) * s, mcf, MOUTH)
	elseif mouth == "whisper" then
		newPart(ctx.model, "Mouth", Vector3.new(0.45, 0.05, 0.12) * s, mcf, Color3.fromHex("#C8B8F0"))
	else
		buildMouth(ctx.model, mouth, mcf, s)
	end
end

local function buildStyled(data: MutantData, info: Species, set: { [string]: boolean }, s: number): Model
	local st = (Style :: any)[data.tier]
	local look = lookup(data.tier)
	local bodyDef = look.bodies[info.body]
	assert(bodyDef, "unknown body " .. tostring(info.body) .. " for " .. data.tier)

	local model = Instance.new("Model")
	model.Name = info.name
	model:SetAttribute("Tier", data.tier)
	model:SetAttribute("Rarity", data.rarity)
	model:SetAttribute("Idle", st.idle)
	if info.idleVariant then
		model:SetAttribute("IdleVariant", info.idleVariant)
	end
	local root = newPart(model, "Root", Vector3.new(1, 0.2, 1) * s, CFrame.new(), WHITE)
	root.Transparency = 1
	model.PrimaryPart = root

	local skin = st.skin
	local material0 = (Enum.Material :: any)[skin.material] or Enum.Material.SmoothPlastic
	local color, material, reflectance = paint(Color3.fromHex(info.color), set, material0, skin.reflectance)
	local skin2 = paint(Color3.fromHex(info.skin2 or info.color), set)
	local accent = Color3.fromHex(info.accent)
	local mutated = material ~= material0
	local ctx: Ctx = {
		model = model,
		s = s,
		pal = {
			skin = color,
			skin2 = skin2,
			skinDark = color:Lerp(DARK, 0.35),
			skinLight = color:Lerp(WHITE, 0.4),
			accent = if set.Radioactive then Color3.fromHex("#7CFF4A") else accent,
		},
		material = material,
		reflectance = reflectance,
		transparency = if mutated then 0 else skin.transparency or 0,
		anchors = { root = CFrame.new() },
	}

	-- Body (anchored at the feet), then every anchor features attach to.
	local bodyParts = {}
	for _, piece in bodyDef.parts do
		for _, p in buildPiece(ctx, piece, nil, "Body") do
			table.insert(bodyParts, p)
		end
	end
	local main = bodyParts[1]
	local mainDef = bodyDef.parts[1]
	local ext = Vector3.new(mainDef.size[1], mainDef.size[2], mainDef.size[3]) / 2 * s
	if mainDef.shape == "cyl" and mainDef.rot and math.abs(mainDef.rot[3]) == 90 then
		ext = Vector3.new(ext.Y, ext.X, ext.Z) -- a stood-up cylinder
	end
	local bodyCf = CFrame.new(main.CFrame.Position)
	local hp, hrDef = bodyDef.head.pos, bodyDef.head.r
	local headCf = CFrame.new(hp[1] * s, hp[2] * s, hp[3] * s)
	local hr = Vector3.new(hrDef[1], hrDef[2], hrDef[3]) * s
	local a = ctx.anchors
	a.body = bodyCf
	a.head = headCf
	a.headR = CFrame.new(hr)
	a.top = headCf * CFrame.new(0, hr.Y * 0.92, 0)
	a.face = headCf * CFrame.new(0, hr.Y * 0.2, -hr.Z * 0.86)
	a.neck = headCf * CFrame.new(0, -hr.Y * 0.75, 0)
	a.front = bodyCf * CFrame.new(0, 0, -ext.Z * 0.92)
	a.back = bodyCf * CFrame.new(0, 0, ext.Z * 0.92)
	a.side = bodyCf * CFrame.new(ext.X * 0.95, 0, 0)
	a.above = headCf * CFrame.new(0, hr.Y + 0.9 * s, 0)
	a.beside = CFrame.new(ext.X + 0.9 * s, 0, -0.2 * s)
	a.hand = a.beside

	-- Wet sheen (Swamp): a slightly bigger Glass shell over each body part.
	local overlay = skin.overlay
	if overlay and not mutated then
		for _, p in bodyParts do
			local o = p:Clone()
			o.Name = "Sheen"
			o.Size = p.Size * overlay.grow
			o.Material = (Enum.Material :: any)[overlay.material]
			o.Transparency = overlay.transparency
			o.Reflectance = overlay.reflectance
			o.Color = color:Lerp(WHITE, 0.25)
			for _, c in o:GetChildren() do
				if not c:IsA("SpecialMesh") then
					c:Destroy()
				end
			end
			o.Parent = model
		end
	end
	-- Starfield (Cosmic): tiny Neon specks on the body.
	if skin.specks then
		for i = 1, skin.specks.n do
			local speck = newPart(
				model,
				"Speck",
				Vector3.one * skin.specks.size * s,
				surface(bodyCf, ext * 0.98, i * 2.39, 0.5 + (i * 0.618) % 1 * 2.0),
				Color3.fromHex(skin.specks.color),
				"ball"
			)
			speck.Material = Enum.Material.Neon
		end
	end

	-- Arms (Lab): a capsule each side; `hand` is the right one's end.
	if st.arms and bodyDef.arms then
		local ax, ay = bodyDef.arms.x * s, bodyDef.arms.y * s
		for _, side in { -1, 1 } do
			local arm = newPart(
				model,
				"Arm",
				Vector3.new(0.42, 1.3, 0.42) * s,
				CFrame.new(side * (ax + 0.2 * s), ay - 0.3 * s, 0) * CFrame.Angles(0, 0, math.rad(side * 25)),
				color,
				"ellipsoid"
			)
			arm.Material = material
			newPart(
				model,
				"Hand",
				Vector3.new(0.38, 0.38, 0.38) * s,
				CFrame.new(side * (ax + 0.45 * s), ay - 0.85 * s, -0.05 * s),
				ctx.pal.skinLight,
				"ball"
			)
		end
		a.hand = CFrame.new(ax + 0.45 * s, ay - 0.95 * s, -0.25 * s)
	end

	-- Features: the face and feet take every override in order; then each feature's parts.
	local face = table.clone(st.face)
	local feet = st.feet
	for _, id in info.features or {} do
		local f = look.features[id]
		assert(f, "unknown feature " .. id .. " for " .. data.tier)
		for k, v in f.face or {} do
			if k == "feet" then
				feet = v
			else
				face[k] = v
			end
		end
	end
	if feet == "nub" or feet == "webbed" then
		for _, side in { -1, 1 } do
			local x = side * math.max(ext.X * 0.45, 0.45 * s)
			if feet == "nub" then
				newPart(
					model,
					"Foot",
					Vector3.new(0.8, 0.45, 1) * s,
					CFrame.new(x, 0.22 * s, -0.15 * s),
					ctx.pal.skinDark,
					"ellipsoid"
				)
			else
				newPart(
					model,
					"Foot",
					Vector3.new(1.2, 0.2, 1.3) * s,
					CFrame.new(x, 0.1 * s, -0.35 * s),
					ctx.pal.skinDark,
					"ellipsoid"
				)
				for t = -1, 1 do
					newPart(
						model,
						"Toe",
						Vector3.new(0.28, 0.18, 0.4) * s,
						CFrame.new(x + t * 0.35 * s, 0.09 * s, -0.95 * s),
						ctx.pal.skinDark,
						"ellipsoid"
					)
				end
			end
		end
	end
	buildStyledFace(ctx, face, set)
	for _, id in info.features or {} do
		local f = look.features[id]
		for _, piece in f.parts do
			buildPiece(ctx, piece, nil, (f.label:gsub("%s", "")))
		end
		if f.particles then
			particles(main, f.particles, s)
		end
	end
	if info.prop then
		local prop = look.props[info.prop]
		assert(prop, "unknown prop " .. info.prop .. " for " .. data.tier)
		for _, piece in prop.parts do
			buildPiece(ctx, piece, Color3.fromHex(prop.tint), "Prop")
		end
	end
	if skin.particles and not mutated then
		particles(main, skin.particles, s)
	end

	-- Height: the top of the tallest part (the hatch camera frames it).
	local top = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			top = math.max(top, d.CFrame.Position.Y + d.Size.Y / 2)
		end
	end
	model:SetAttribute("Height", top)
	addEffects(model, main, set, s)
	return model
end

-- Builds a mutant. data.size is the size multiplier rolled at harvest (0.8x-3x).
function MutantModel.build(data: MutantData): Model
	local info = MutantModel.species(data)
	local set = mutationSet(data.mutations)
	local s = MutantModel.visualScale(data)
	if info.features and (Style :: any)[data.tier] then
		return buildStyled(data, info, set, s)
	end
	return buildLegacy(data, info, set, s)
end

-- Height in studs of a mutant standing still: its body recipe's top (head included) for a
-- styled species, 3.6 units for a hand-made one; times the visual scale.
function MutantModel.height(data: MutantData): number
	local info = MutantModel.species(data)
	local units = 3.6
	if info.features and (Style :: any)[data.tier] then
		local def = lookup(data.tier).bodies[info.body]
		units = def.head.pos[2] + def.head.r[2]
		for _, piece in def.parts do
			units = math.max(units, piece.pos[2] + piece.size[2] / 2)
		end
	end
	return units * MutantModel.visualScale(data)
end

-- The Almanac's trait lines for a species, from the same vocabulary the model is built from:
-- { { label, value } }. Styled species: body, signature, other features, prop, dance (Legendary).
local LEGACY_TRAITS = {
	body = {
		blob = "Round",
		tall = "Tall",
		flat = "Flat",
		spiky = "Spiky",
		pear = "Pear",
		worm = "Wiggly",
		puff = "Puffy",
	},
	mouth = {
		smile = "Grin",
		fangs = "Fangs",
		tooth = "Big tooth",
		wide = "Huge mouth",
		tongue = "Tongue out",
		none = "None",
	},
}
function MutantModel.traits(info: Species): { { string } }
	if not (info.features and (Style :: any)[info.tier]) then
		local accessory = info.accessory or "none"
		return {
			{ "Body", LEGACY_TRAITS.body[info.body] or info.body },
			{ "Eyes", tostring(info.eyes or 2) },
			{ "Mouth", LEGACY_TRAITS.mouth[info.mouth or "smile"] or info.mouth or "" },
			{ "Wears", if accessory == "none" then "Nothing" else (accessory:gsub("^%l", string.upper)) },
		}
	end
	local look = lookup(info.tier)
	local features = info.features :: { string }
	local out = {
		{ "Body", look.bodies[info.body].label },
		{ "Signature", look.features[features[1]].label },
	}
	if #features > 1 then
		local rest = {}
		for i = 2, #features do
			table.insert(rest, look.features[features[i]].label)
		end
		table.insert(out, { "Features", table.concat(rest, ", ") })
	end
	if info.prop then
		table.insert(out, { "Prop", look.props[info.prop].label })
	end
	if info.idleVariant then
		table.insert(out, { "Dance", info.idleVariant })
	end
	return out
end

-------------------------------------------------------------------------------- idle animations

-- The whole model's offset from its feet at time t (seconds): the tier's idle (MutantStyle
-- `idle`), bigger and faster for a Legendary's named variant (the variant's place in the tier's
-- idleVariants adds a sway (2nd) or a slow spin (3rd)). `scale` is MutantModel.visualScale.
function MutantModel.idlePose(tier: string, variant: string?, t: number, scale: number): CFrame
	local st = (Style :: any)[tier]
	if not st then
		return CFrame.identity
	end
	local def = Style.idles[st.idle]
	local amp, speed = def.amp, def.speed
	local extra = CFrame.identity
	if variant then
		amp *= Style.variantBoost.amp
		speed *= Style.variantBoost.speed
		local index = table.find(st.idleVariants, variant) or 1
		if index == 2 then
			extra = CFrame.Angles(0, 0, math.rad(6) * math.sin(t * speed * 0.5))
		elseif index == 3 then
			extra = CFrame.Angles(0, t * 0.6, 0)
		end
	end
	local kind = st.idle
	local wave = math.sin(t * speed)
	local pose
	if kind == "bob" then
		pose = CFrame.new(0, math.abs(wave) * amp * scale, 0)
	elseif kind == "sag" then
		pose = CFrame.new(0, -(wave + 1) / 2 * amp * scale, 0)
			* CFrame.Angles(0, 0, math.rad(def.tilt) * math.sin(t * speed * 0.5))
	elseif kind == "twitch" then
		-- Still most of the time; a quick jerk every couple of seconds.
		local phase = (t * 0.6) % 1
		local jerk = if phase < 0.08 then math.sin(phase / 0.08 * math.pi * 3) else 0
		pose = CFrame.Angles(0, math.rad(amp) * jerk, math.rad(amp * 0.5) * jerk)
	elseif kind == "drip" then
		pose = CFrame.new(0, wave * amp * scale, 0)
	elseif kind == "hover" then
		pose = CFrame.new(0, (def.lift + wave * def.amp) * scale * (amp / def.amp), 0)
	else -- orbit
		pose = CFrame.new(0, wave * amp * scale, 0) * CFrame.Angles(0, t * (def.spin or 0), 0)
	end
	return pose * extra
end

-- A tagged part's offset (from the feet) at time t: "orbit" circles the vertical axis through
-- `center`, "drip" slides down and starts over, "float" bobs gently. Others stay put.
function MutantModel.partPose(anim: string, t: number, offset: CFrame, center: Vector3?, scale: number): CFrame
	if anim == "orbit" then
		local c = center or Vector3.zero
		return CFrame.new(c) * CFrame.Angles(0, t * 0.8, 0) * CFrame.new(-c) * offset
	elseif anim == "drip" then
		return CFrame.new(0, -((t * 0.5) % 1) * 0.5 * scale, 0) * offset
	elseif anim == "float" then
		return CFrame.new(0, math.sin(t * 1.7) * 0.15 * scale, 0) * offset
	end
	return offset
end

-- "flicker" parts (a Void eye, a status light): shown except for brief blinks.
function MutantModel.flickerVisible(t: number): boolean
	return (t * 0.9) % 1 > 0.07
end

-------------------------------------------------------------------------------- eggs

-- Real egg silhouette: a round lower half and a narrower, taller upper half.
local EGG_W, EGG_LOW_H, EGG_LOW_Y, EGG_UP_W, EGG_UP_H, EGG_UP_Y = 1.75, 1.5, 0.75, 0.86, 1.9, 1.35

local function eggRadius(y: number): number
	local function r(halfW: number, halfH: number, cy: number): number
		local t = (y - cy) / halfH
		return if math.abs(t) >= 1 then 0 else halfW * math.sqrt(1 - t * t)
	end
	return math.max(r(EGG_W / 2, EGG_LOW_H / 2, EGG_LOW_Y), r(EGG_W * EGG_UP_W / 2, EGG_UP_H / 2, EGG_UP_Y))
end

-- An egg at `progress` (0-1) of its growth. Mutations gained while growing show on the shell.
function MutantModel.buildEgg(eggId: string, progress: number, mutations: { string }): Model
	local tier = Eggs.tiers[eggId]
	local design = tier.design
	local set = mutationSet(mutations)
	local s = (0.6 + 0.4 * math.clamp(progress, 0, 1)) * (Sizes.visual.tierScale[Eggs.sizeTier(eggId)] ^ 0.5)

	local model = Instance.new("Model")
	model.Name = "Egg"
	-- Root sits at the feet (origin) so PivotTo(floor) never sinks giants into the ground.
	local root = newPart(model, "Root", Vector3.new(1, 0.2, 1) * s, CFrame.new(), WHITE)
	root.Transparency = 1
	model.PrimaryPart = root

	local shellColor, material, reflectance = paint(Color3.fromHex(design.shell), set)
	local accent = Color3.fromHex(design.accent)
	local function shellPart(name: string, size: Vector3, y: number): BasePart
		local p = newPart(model, name, size * s, CFrame.new(0, y * s, 0), shellColor, "ellipsoid")
		p.Material = material
		p.Reflectance = reflectance
		return p
	end
	local lower = shellPart("Shell", Vector3.new(EGG_W, EGG_LOW_H, EGG_W), EGG_LOW_Y)
	shellPart("ShellTop", Vector3.new(EGG_W * EGG_UP_W, EGG_UP_H, EGG_W * EGG_UP_W), EGG_UP_Y)

	-- A point on the shell at angle `a` (0 = front) and height `y` (0..2.3), facing outward.
	local function onShell(a: number, y: number): CFrame
		local r = eggRadius(y) * s
		local pos = Vector3.new(math.sin(a) * r, y * s, -math.cos(a) * r)
		local out = Vector3.new(math.sin(a), 0.25, -math.cos(a)).Unit
		return CFrame.lookAt(pos, pos + out)
	end
	local function ring(name: string, y: number, thickness: number, color: Color3): BasePart
		local d = eggRadius(y) * 2 * s + 0.06 * s
		return newPart(model, name, Vector3.new(d, thickness * s, d), CFrame.new(0, y * s, 0), color, "ellipsoid")
	end

	local pattern = design.pattern
	if pattern == "spots" or pattern == "blotches" then
		local big = pattern == "blotches"
		for i, ay in
			{ { 0.3, 1.5 }, { -0.9, 0.9 }, { 1.4, 0.7 }, { 2.4, 1.3 }, { -2.2, 1.6 }, { 3.3, 0.6 }, { 0.9, 1.9 } }
		do
			local d = (if big then 0.75 else 0.45) * (if i % 2 == 0 then 0.8 else 1)
			newPart(
				model,
				"Spot",
				Vector3.new(d, d * (if big then 0.7 else 1), 0.12) * s,
				onShell(ay[1], ay[2]),
				accent,
				"ellipsoid"
			)
		end
	elseif pattern == "hazard" then
		ring("Band", 1.05, 0.38, accent)
		for i = 0, 7 do
			local cf = onShell(i / 8 * math.pi * 2, 1.05)
			newPart(
				model,
				"Hazard",
				Vector3.new(0.18, 0.36, 0.1) * s,
				cf * CFrame.new(0, 0, -0.04 * s) * CFrame.Angles(0, 0, math.rad(30)),
				DARK
			)
		end
		ring("Cap", 2.05, 0.12, accent)
	elseif pattern == "cracks" or pattern == "stars" then
		local glowColor = accent
		if pattern == "cracks" then
			for c = 0, 3 do
				local a = c / 4 * math.pi * 2 + 0.4
				local y = 0.6
				for seg = 0, 3 do
					local dy = 0.35
					local da = (if seg % 2 == 0 then 0.18 else -0.18)
					local p0 = onShell(a, y).Position
					local p1 = onShell(a + da, y + dy).Position
					local crack = newPart(
						model,
						"Crack",
						Vector3.new(0.09 * s, 0.09 * s, (p1 - p0).Magnitude),
						CFrame.lookAt((p0 + p1) / 2, p1),
						glowColor
					)
					crack.Material = Enum.Material.Neon
					a += da
					y += dy
				end
			end
		else
			for i = 0, 13 do
				local star = newPart(
					model,
					"Star",
					Vector3.new(0.14, 0.14, 0.14) * s,
					onShell(i * 2.4, 0.35 + (i * 0.37) % 1.7),
					glowColor,
					"ball"
				)
				star.Material = Enum.Material.Neon
			end
		end
	elseif pattern == "ring" then
		local band = newPart(
			model,
			"Ring",
			Vector3.new(0.08, 2.9, 2.9) * s,
			CFrame.new(0, 1.05 * s, 0) * CFrame.Angles(math.rad(15), 0, math.rad(90)),
			accent,
			"cylinder"
		)
		band.Material = Enum.Material.Neon
		band.Transparency = 0.25
		for i = 0, 7 do
			newPart(
				model,
				"Star",
				Vector3.new(0.13, 0.13, 0.13) * s,
				onShell(i * 0.9, 0.5 + (i * 0.29) % 1.5),
				WHITE,
				"ball"
			).Material =
				Enum.Material.Neon
		end
	elseif pattern == "jack" then
		-- Jack-o'-lantern: darker ridges down the shell, a carved face on the front (dark, not
		-- Neon: no glow on a big surface) and a stem on top.
		local ridge = shellColor:Lerp(DARK, 0.22)
		for i = 0, 5 do
			newPart(
				model,
				"Ridge",
				Vector3.new(0.14, 1.9, 0.1) * s,
				onShell(i / 6 * math.pi * 2 + math.pi / 6, 1.05),
				ridge,
				"ellipsoid"
			)
		end
		for _, side in { -1, 1 } do
			newPart(
				model,
				"JackEye",
				Vector3.new(0.34, 0.34, 0.1) * s,
				onShell(side * 0.42, 1.5) * CFrame.Angles(0, 0, math.rad(45)),
				accent
			)
		end
		newPart(
			model,
			"JackNose",
			Vector3.new(0.2, 0.2, 0.1) * s,
			onShell(0, 1.18) * CFrame.Angles(0, 0, math.rad(45)),
			accent
		)
		for k = -3, 3 do
			newPart(
				model,
				"JackGrin",
				Vector3.new(0.17, 0.2, 0.1) * s,
				onShell(k * 0.16, 0.82 + (if k % 2 == 0 then 0.05 else -0.05) + math.abs(k) * 0.04),
				accent
			)
		end
		newPart(
			model,
			"JackStem",
			Vector3.new(0.55, 0.32, 0.32) * s, -- cylinders run along X: stood up
			CFrame.new(0.05 * s, 2.42 * s, 0) * CFrame.Angles(0, 0, math.rad(100)),
			Color3.fromHex("#5B3A24"),
			"cylinder"
		)
	end
	if design.gem then
		-- Gem variant: a band of faceted cyan crystals around the middle and one crowning the top.
		local gemColor = Color3.fromHex("#4FD8FF")
		for i = 0, 5 do
			local crystal = newPart(
				model,
				"Gem",
				Vector3.new(0.34, 0.34, 0.34) * s,
				onShell(i / 6 * math.pi * 2, 1.25) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
				gemColor
			)
			crystal.Material = Enum.Material.Glass
			crystal.Reflectance = 0.25
		end
		local crown = newPart(
			model,
			"GemCrown",
			Vector3.new(0.42, 0.42, 0.42) * s,
			CFrame.new(0, 2.32 * s, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
			gemColor
		)
		crown.Material = Enum.Material.Glass
		crown.Reflectance = 0.25
	end
	addEffects(model, lower, set, s)
	return model
end

-- Adds dark crack lines across the front of an egg built by buildEgg (for the hatch cinematic).
-- `level` 1 = a couple of hairline cracks, 2 = cracks all over.
function MutantModel.addCracks(egg: Model, level: number)
	local root = egg.PrimaryPart :: BasePart
	local s = root.Size.X -- buildEgg sizes the root 1 stud wide per unit of egg scale (ScaleTo keeps that)
	local count = if level >= 2 then 6 else 2
	for c = 1, count do
		local a = (c - (count + 1) / 2) * 0.55
		local y = 0.8 + (c % 3) * 0.2 -- ends below ~2.0, short of the tip where the radius shrinks to 0
		for seg = 0, 2 do
			local da = if seg % 2 == 0 then 0.16 else -0.16
			local function at(angle: number, height: number): Vector3
				local r = eggRadius(height) * s + 0.06 * s -- clear of the shell even across the waist
				return root.CFrame * Vector3.new(math.sin(angle) * r, height * s, -math.cos(angle) * r)
			end
			local p0, p1 = at(a, y), at(a + da, y + 0.28)
			newPart(
				egg,
				"Crack",
				Vector3.new(0.07 * s, 0.07 * s, (p1 - p0).Magnitude),
				CFrame.lookAt((p0 + p1) / 2, p1),
				DARK
			)
			a += da
			y += 0.28
		end
	end
end

-- Names of mutations in display order, e.g. { "Golden", "Glitched" }.
function MutantModel.sortedMutations(mutations: { string }): { string }
	local set = mutationSet(mutations)
	local out = {}
	for _, id in Mutations.order do
		if set[id] then
			table.insert(out, id)
		end
	end
	return out
end

return MutantModel
