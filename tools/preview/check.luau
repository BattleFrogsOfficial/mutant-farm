-- World sanity check: builds the real map headlessly and reports
--   * objects that intersect other objects (oriented-box test; spheres for balls)
--   * coplanar overlapping surfaces (z-fighting)
--   * objects floating above, or buried in, the ground under them
--   * eggs on soil and mutants in the pen that don't sit exactly on their surface
-- Exits non-zero if anything is found.
--   rojo build default.project.json -o build/preview.rbxl
--   lune run tools/preview/check -- build/preview.rbxl

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local placePath
for _, a in process.args do
	if a ~= "--" then
		placePath = a
	end
end
assert(placePath, "usage: check <place.rbxl>")

local game = roblox.deserializePlace(fs.readFile(placePath))
local workspace = game:GetService("Workspace")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local cache = {}
local env
local function requireModule(module)
	if cache[module] ~= nil then
		return cache[module]
	end
	local e = table.clone(env)
	e.script = module
	local result = luau.load(module.Source, { debugName = module:GetFullName(), environment = e })()
	cache[module] = result
	return result
end
env = {
	game = game,
	workspace = workspace,
	require = requireModule,
	Instance = roblox.Instance,
	Vector3 = Vector3,
	Vector2 = roblox.Vector2,
	CFrame = CFrame,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	NumberRange = roblox.NumberRange,
	Font = roblox.Font,
	typeof = typeof,
}

local World = requireModule(game.ServerScriptService.Server.Util.World)
-- LIMITED_AT=<unix seconds> builds the hub as at that time (limited-egg decor on or off).
local plots = World.build(tonumber(process.env.LIMITED_AT))
local MutantModel = requireModule(game.ReplicatedStorage.Shared.MutantModel)

-- Parts that are ground/walkable layers: other things may stand on them.
local GROUND = {
	Valley = true,
	Plaza = true,
	PlazaBorder = true,
	Lawn = true,
	Base = true,
	PenFloor = true,
	Path = true,
	Platform = true,
	Rim = true,
	Pad = true,
}
-- Object pairs allowed to touch/overlap by design.
local function allowedPair(a: string, b: string): boolean
	local function either(x, y)
		return (a == x and b == y) or (a == y and b == x)
	end
	return (a == "HedgeSegment" and b == "HedgeSegment") -- segments overlap to close gaps
		or (a == "Mountain" and b == "Mountain")
		or (a == "Fence" and b == "Fence") -- corner posts are shared
		or either("Mountain", "Tree") -- background scenery outside the wall
		or either("Mountain", "HedgeSegment")
end

---------------------------------------------------------------------------- geometry

type Box = { part: any, object: any, name: string, cf: any, half: any, kind: string, min: any, max: any }

local function axes(cf)
	return { cf.RightVector, cf.UpVector, cf.LookVector }
end

-- `exact` keeps an ellipsoid's full box (for "where is its lowest point"); otherwise it is
-- shrunk to roughly the ellipsoid's volume for overlap tests.
local function makeBox(p, exact: boolean?): Box?
	if p.Transparency >= 1 then
		return nil
	end
	local size = p.Size
	local kind = "box"
	if p:IsA("Part") then
		if p.Shape == roblox.Enum.PartType.Ball then
			local d = math.min(size.X, size.Y, size.Z)
			size = Vector3.new(d, d, d)
			kind = "ball"
		elseif p.Shape == roblox.Enum.PartType.Cylinder then
			local d = math.min(size.Y, size.Z)
			size = Vector3.new(size.X, d, d)
		end
	end
	local mesh = p:FindFirstChildOfClass("SpecialMesh")
	if mesh and mesh.MeshType == roblox.Enum.MeshType.Sphere then
		kind = "ellipsoid"
		if not exact then
			size = size * 0.82 -- an ellipsoid fills ~82% of its box along each axis near the faces
		end
	end
	local half = size / 2
	local cf = p.CFrame
	local ax = axes(cf)
	local ext = Vector3.new(
		math.abs(ax[1].X) * half.X + math.abs(ax[2].X) * half.Y + math.abs(ax[3].X) * half.Z,
		math.abs(ax[1].Y) * half.X + math.abs(ax[2].Y) * half.Y + math.abs(ax[3].Y) * half.Z,
		math.abs(ax[1].Z) * half.X + math.abs(ax[2].Z) * half.Y + math.abs(ax[3].Z) * half.Z
	)
	return {
		part = p,
		cf = cf,
		half = half,
		kind = kind,
		min = cf.Position - ext,
		max = cf.Position + ext,
		object = nil,
		name = "",
	}
end

-- Penetration depth of two oriented boxes (0 if separated), via the separating axis test.
local function obbDepth(a: Box, b: Box): number
	local A, B = axes(a.cf), axes(b.cf)
	local d = b.cf.Position - a.cf.Position
	local test = { A[1], A[2], A[3], B[1], B[2], B[3] }
	for i = 1, 3 do
		for j = 1, 3 do
			local c = A[i]:Cross(B[j])
			if c.Magnitude > 1e-4 then
				table.insert(test, c.Unit)
			end
		end
	end
	local best = math.huge
	for _, axis in test do
		local ra = a.half.X * math.abs(A[1]:Dot(axis))
			+ a.half.Y * math.abs(A[2]:Dot(axis))
			+ a.half.Z * math.abs(A[3]:Dot(axis))
		local rb = b.half.X * math.abs(B[1]:Dot(axis))
			+ b.half.Y * math.abs(B[2]:Dot(axis))
			+ b.half.Z * math.abs(B[3]:Dot(axis))
		local overlap = ra + rb - math.abs(d:Dot(axis))
		if overlap <= 0 then
			return 0
		end
		best = math.min(best, overlap)
	end
	return best
end

local function sphereBoxDepth(s: Box, b: Box): number
	local r = s.half.X
	local localP = b.cf:PointToObjectSpace(s.cf.Position)
	local clamped = Vector3.new(
		math.clamp(localP.X, -b.half.X, b.half.X),
		math.clamp(localP.Y, -b.half.Y, b.half.Y),
		math.clamp(localP.Z, -b.half.Z, b.half.Z)
	)
	return math.max(0, r - (localP - clamped).Magnitude)
end

local function depth(a: Box, b: Box): number
	if a.kind == "ball" and b.kind == "ball" then
		return math.max(0, a.half.X + b.half.X - (a.cf.Position - b.cf.Position).Magnitude)
	elseif a.kind == "ball" then
		return sphereBoxDepth(a, b)
	elseif b.kind == "ball" then
		return sphereBoxDepth(b, a)
	end
	return obbDepth(a, b)
end

---------------------------------------------------------------------------- collect

local map = workspace:FindFirstChild("Map")
local boxes: { Box } = {}
local function objectOf(p)
	-- The nearest Model ancestor is the "object"; loose parts are their own object.
	local node = p.Parent
	while node and node ~= map do
		if node:IsA("Model") and node.Name ~= "Hub" and not node.Name:match("^Plot%d") then
			return node
		end
		node = node.Parent
	end
	return p
end
for _, p in map:GetDescendants() do
	if p:IsA("BasePart") then
		local box = makeBox(p)
		if box then
			box.object = objectOf(p)
			box.name = box.object.Name
			table.insert(boxes, box)
		end
	end
end

local issues = {}
local function issue(kind: string, text: string)
	table.insert(issues, { kind = kind, text = text })
end
local function fmt(v)
	return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end
local function label(box: Box): string
	local obj = box.object
	return string.format(
		"%s/%s",
		if obj == box.part then (box.part.Parent and box.part.Parent.Name or "?") else obj.Name,
		box.part.Name
	)
end

-- Spatial hash on XZ so we only test nearby pairs.
local CELL = 10
local grid = {}
for i, b in boxes do
	for gx = math.floor(b.min.X / CELL), math.floor(b.max.X / CELL) do
		for gz = math.floor(b.min.Z / CELL), math.floor(b.max.Z / CELL) do
			local key = gx .. "," .. gz
			grid[key] = grid[key] or {}
			table.insert(grid[key], i)
		end
	end
end

local seen = {}
local reportedObjects = {}
for _, list in grid do
	for x = 1, #list do
		for y = x + 1, #list do
			local i, j = list[x], list[y]
			local key = if i < j then i .. ":" .. j else j .. ":" .. i
			if not seen[key] then
				seen[key] = true
				local a, b = boxes[i], boxes[j]
				local aGround, bGround = GROUND[a.part.Name], GROUND[b.part.Name]
				-- AABB prefilter
				if
					a.max.X > b.min.X
					and b.max.X > a.min.X
					and a.max.Y > b.min.Y
					and b.max.Y > a.min.Y
					and a.max.Z > b.min.Z
					and b.max.Z > a.min.Z
				then
					-- 1) Z-fighting: two upright surfaces at the same height overlapping.
					local aTop, bTop = a.max.Y, b.max.Y
					local upright = a.cf.UpVector.Y > 0.999 and b.cf.UpVector.Y > 0.999
					local fencePair = (a.name == "Fence" and b.name == "Fence") -- corner overlaps hide inside posts
						or (a.name == "Mountain" and b.name == "Mountain") -- background, far outside the wall
					if a.part ~= b.part and math.abs(aTop - bTop) < 0.03 and upright and not fencePair then
						-- Footprints must really overlap (rotated boxes), not just their bounding boxes.
						local lowered = table.clone(b)
						lowered.cf = b.cf + Vector3.new(0, aTop - bTop, 0)
						if a.kind ~= "ball" and b.kind ~= "ball" and obbDepth(a, lowered) > 0.2 then
							issue(
								"z-fight",
								string.format(
									"%s and %s share top y=%.2f at %s",
									label(a),
									label(b),
									aTop,
									fmt(a.cf.Position)
								)
							)
						end
					end
					-- 2) Different objects intersecting (ground is checked separately below).
					if a.object ~= b.object and not aGround and not bGround and not allowedPair(a.name, b.name) then
						local d = depth(a, b)
						local pairKey = tostring(a.object) .. "|" .. tostring(b.object)
						if d > 0.08 and not reportedObjects[pairKey] then
							reportedObjects[pairKey] = true
							issue(
								"overlap",
								string.format(
									"%s intersects %s by %.2f at %s",
									label(a),
									label(b),
									d,
									fmt(a.cf.Position)
								)
							)
						end
					end
				end
			end
		end
	end
end

-- 3) Floating / buried objects: compare each object's lowest point with the ground under it.
local function groundHeight(x: number, z: number): number
	local best = -math.huge
	for _, b in boxes do
		if GROUND[b.part.Name] and x >= b.min.X and x <= b.max.X and z >= b.min.Z and z <= b.max.Z then
			-- Exact footprint test in the part's own space (plots and paths are rotated).
			local p = b.cf:PointToObjectSpace(Vector3.new(x, b.cf.Position.Y, z))
			local inside
			if b.part:IsA("Part") and b.part.Shape == roblox.Enum.PartType.Cylinder then
				inside = math.sqrt(p.Y * p.Y + p.Z * p.Z) <= b.half.Y
			else
				inside = math.abs(p.X) <= b.half.X and math.abs(p.Z) <= b.half.Z
			end
			if inside and b.part.Name ~= "Rim" and b.part.Name ~= "Pad" then
				best = math.max(best, b.max.Y)
			end
		end
	end
	return if best == -math.huge then 0 else best
end
local objects = {}
for _, b in boxes do
	if not GROUND[b.part.Name] then
		local o = objects[b.object]
		if not o then
			-- Objects nested in another model (eggs on the shop shelf) rest on furniture, not ground.
			local onFurniture = b.object ~= b.part
				and b.object.Parent ~= nil
				and b.object.Parent:IsA("Model")
				and b.object.Parent.Name ~= "Hub"
			o = { min = b.min, max = b.max, name = b.name, label = label(b), onFurniture = onFurniture }
			objects[b.object] = o
		else
			o.min = Vector3.new(math.min(o.min.X, b.min.X), math.min(o.min.Y, b.min.Y), math.min(o.min.Z, b.min.Z))
			o.max = Vector3.new(math.max(o.max.X, b.max.X), math.max(o.max.Y, b.max.Y), math.max(o.max.Z, b.max.Z))
		end
	end
end
local MAY_FLOAT = { Icon = true } -- floating shop icons are meant to hover
local MAY_SINK = { Rock = true, Mountain = true }
for _, o in objects do
	local cx, cz = (o.min.X + o.max.X) / 2, (o.min.Z + o.max.Z) / 2
	local g = groundHeight(cx, cz)
	if o.min.Y > g + 0.35 and not MAY_FLOAT[o.name] and not o.onFurniture then
		issue(
			"floating",
			string.format("%s floats %.2f above ground at %s", o.label, o.min.Y - g, fmt(Vector3.new(cx, o.min.Y, cz)))
		)
	elseif o.min.Y < g - 0.6 and not MAY_SINK[o.name] then
		issue(
			"buried",
			string.format(
				"%s sinks %.2f into the ground at %s",
				o.label,
				g - o.min.Y,
				fmt(Vector3.new(cx, o.min.Y, cz))
			)
		)
	elseif o.max.Y < g - 0.01 then
		issue("buried", string.format("%s is completely underground at %s", o.label, fmt(Vector3.new(cx, o.max.Y, cz))))
	end
end

-- 4) Eggs on soil and mutants in the pen, placed exactly the way PlotController places them.
local function modelMinY(model): number
	local m = math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local b = makeBox(d, true)
			if b then
				m = math.min(m, b.min.Y)
			end
		end
	end
	return m
end
local function placeModel(model, cf)
	local delta = cf * model.PrimaryPart.CFrame:Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end
local plot = plots[1]
for _, eggId in { "Starter", "Swamp", "Lab", "Toxic", "Void", "Cosmic" } do
	for _, progress in { 0, 1 } do
		local slot = plot.slots[1]
		local egg = MutantModel.buildEgg(eggId, progress, {})
		local top = slot.CFrame * CFrame.new(0, slot.Size.Y / 2, 0)
		placeModel(egg, top)
		local gap = modelMinY(egg) - top.Position.Y
		if math.abs(gap) > 0.12 then
			issue("egg", string.format("%s egg (progress %d) sits %.2f off the soil", eggId, progress, gap))
		end
	end
end
local penCenter = plot.model:GetAttribute("PenCenter")
for _, spec in { { "Starter", "Common", 0.8 }, { "Cosmic", "Legendary", 3 } } do
	local Mutants = requireModule(game.ReplicatedStorage.Shared.Config.Mutants)
	local data = {
		tier = spec[1],
		rarity = spec[2],
		species = Mutants.buckets[spec[1]][spec[2]][1],
		mutations = {},
		size = spec[3],
	}
	local model = MutantModel.build(data)
	placeModel(model, CFrame.new(penCenter))
	local gap = modelMinY(model) - penCenter.Y
	if math.abs(gap) > 0.25 * MutantModel.visualScale(data) then
		issue(
			"mutant",
			string.format("%s %s (size %.1f) feet are %.2f off the pen floor", spec[1], spec[2], spec[3], gap)
		)
	end
end

-- Report
table.sort(issues, function(a, b)
	return a.kind < b.kind
end)
local counts = {}
for _, i in issues do
	counts[i.kind] = (counts[i.kind] or 0) + 1
	print(string.format("[%s] %s", i.kind, i.text))
end
print(string.format("\n%d parts checked, %d issues", #boxes, #issues))
for kind, n in counts do
	print(string.format("  %s: %d", kind, n))
end
process.exit(if #issues > 0 then 1 else 0)
