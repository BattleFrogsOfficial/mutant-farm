--!strict
-- Builds mutant and egg models from primitives, driven entirely by Config/Mutants.lua (species looks),
-- Config/Sizes.lua (how big they look) and Config/Eggs.lua (egg designs).
-- Used by the client (plots, pens, hatch reveal) and by tools/preview for screenshots.
-- Models are anchored, non-colliding, face -Z, and have their PrimaryPart at the feet.

local Config = script.Parent.Config
local Mutants = require(Config.Mutants)
local Mutations = require(Config.Mutations)
local Eggs = require(Config.Eggs)
local Sizes = require(Config.Sizes)

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

-- Body color after mutations; the strongest mutation wins the paint job.
local function paint(base: Color3, set: { [string]: boolean }): (Color3, Enum.Material, number)
	local color, material, reflectance = base, Enum.Material.SmoothPlastic, 0
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
	pattern: string,
	eyes: number,
	eyeStyle: string,
	mouth: string,
	accessory: string,
	scale: number,
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
	return v.tierScale[data.tier] * v.rarityScale[data.rarity] * species.scale * data.size ^ v.sizeExponent
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
	end
	local _ = color
end

-- Builds a mutant. data.size is the size multiplier rolled at harvest (0.8x-3x).
function MutantModel.build(data: MutantData): Model
	local info = MutantModel.species(data)
	local set = mutationSet(data.mutations)
	local s = MutantModel.visualScale(data)

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

	buildPattern(model, info.pattern, body, s, if set.Radioactive then Color3.fromHex("#7CFF4A") else accent, color)

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
	local eyeScale = s * (if info.eyes == 1 then 1.5 else 1)
	local positions = if info.eyes == 1
		then { Vector3.new(0, 0, 0) }
		elseif info.eyes == 2 then { Vector3.new(-0.42, 0, 0), Vector3.new(0.42, 0, 0) }
		elseif info.eyes == 3 then {
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
		buildEye(model, face * CFrame.new(p * s), eyeScale, info.eyeStyle, set.Cosmic == true, color)
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
	buildMouth(model, info.mouth, face * CFrame.new(0, -0.62 * s, 0.05 * s), s)
	buildAccessory(model, info.accessory, head, s, accent, color)

	addEffects(model, body, set, s)
	return model
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
	local s = (0.6 + 0.4 * math.clamp(progress, 0, 1)) * (Sizes.visual.tierScale[eggId] ^ 0.5)

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
	end
	addEffects(model, lower, set, s)
	return model
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
