-- Builds the map headlessly and exports every visible part as JSON for render.mjs.
-- Runs the real World.lua and MutantModel.lua against Lune's Roblox instance library,
-- so screenshots show exactly what the game code builds (minus lighting/particles/GUI text).
--
--   rojo build default.project.json -o build/preview.rbxl
--   lune run tools/preview/export -- build/preview.rbxl build/scene.json

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local CFrame = roblox.CFrame

local args = {}
for _, a in process.args do
	if a ~= "--" then
		table.insert(args, a)
	end
end
local placePath, outPath = args[1], args[2]
assert(placePath and outPath, "usage: export <place.rbxl> <scene.json>")

local game = roblox.deserializePlace(fs.readFile(placePath))
local workspace = game:GetService("Workspace")

local cache = {}
local env
local function requireModule(module)
	if cache[module] ~= nil then
		return cache[module]
	end
	local chunk = luau.load(module.Source, {
		debugName = module:GetFullName(),
		-- luau.load replaces the environment's metatable, so copy the globals in.
		environment = (function()
			local e = table.clone(env)
			e.script = module
			return e
		end)(),
	})
	local result = chunk()
	cache[module] = result
	return result
end

env = {
	game = game,
	workspace = workspace,
	require = requireModule,
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	NumberSequence = roblox.NumberSequence,
	ColorSequence = roblox.ColorSequence,
	NumberRange = roblox.NumberRange,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	Font = roblox.Font,
	typeof = typeof,
	task = {
		spawn = function(f, ...)
			f(...)
		end,
		wait = function() end,
		delay = function() end,
	},
}

-- Lune doesn't implement PivotTo; move every part by the PrimaryPart delta instead.
local function pivot(model, cf)
	local delta = cf * model.PrimaryPart.CFrame:Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end

local World = requireModule(game.ServerScriptService.Server.Util.World)
local plots = World.build()

-- Showcase: a player's plot in mid-game so mutants and eggs show up in screenshots.
local MutantModel = game.ReplicatedStorage.Shared:FindFirstChild("MutantModel")
if MutantModel then
	local M = requireModule(MutantModel)
	local plot = plots[1]
	local Mutants = requireModule(game.ReplicatedStorage.Shared.Config.Mutants)
	local function sp(tier, rarity, n)
		return Mutants.buckets[tier][rarity][n]
	end
	-- Pen: a crowd from tiny to towering, like a late-game plot.
	local crowd = {
		{ "Starter", "Common", 2, {}, 0.85 },
		{ "Starter", "Rare", 3, { "Shiny" }, 1.1 },
		{ "Swamp", "Uncommon", 4, {}, 1.2 },
		{ "Lab", "Epic", 2, { "Golden" }, 1.3 },
		{ "Toxic", "Rare", 5, { "Radioactive" }, 1.6 },
		{ "Swamp", "Legendary", 3, {}, 1.4 },
		{ "Void", "Epic", 4, { "Glitched" }, 1.8 },
		{ "Lab", "Common", 7, {}, 1 },
		{ "Toxic", "Legendary", 2, { "Golden" }, 2.2 },
		{ "Cosmic", "Legendary", 4, { "Cosmic" }, 3 },
	}
	local penCenter = plot.model:GetAttribute("PenCenter")
	local rot = plot.frame.Rotation
	local x = -19
	for _, c in crowd do
		local data = { tier = c[1], rarity = c[2], species = sp(c[1], c[2], c[3]), mutations = c[4], size = c[5] }
		local model = M.build(data)
		local w = 3 * M.visualScale(data)
		x += w / 2
		pivot(model, rot + penCenter + rot * roblox.Vector3.new(x, 0, 2))
		x += w / 2 + 0.6
		model.Parent = workspace
	end
	-- One egg per tier on the first six slots, at different growth stages.
	local eggOrder = { "Starter", "Swamp", "Lab", "Toxic", "Void", "Cosmic" }
	for i = 1, 6 do
		plot.slots[i].Transparency = 0
		local egg = M.buildEgg(eggOrder[i], 0.5 + i * 0.08, if i == 2 then { "Golden" } else {})
		pivot(egg, plot.slots[i].CFrame * roblox.CFrame.new(0, 0.25, 0))
		egg.Parent = workspace
	end
	-- A lineup of 40 random species on the hub plaza for a variety check.
	local ids = {}
	for id in Mutants.species do
		table.insert(ids, id)
	end
	table.sort(ids)
	for i = 1, 40 do
		local id = ids[(i * 97) % #ids + 1]
		local e = Mutants.species[id]
		-- Pick a size that renders every species at the same height (Lune has no Model:ScaleTo).
		local unit = M.visualScale({ tier = e.tier, rarity = e.rarity, species = id, mutations = {}, size = 1 })
		local size = (1.1 / unit) ^ (1 / 1.6)
		local model = M.build({ tier = e.tier, rarity = e.rarity, species = id, mutations = {}, size = size })
		pivot(
			model,
			roblox.CFrame.new(-12 + ((i - 1) % 10) * 3.4, 0.4, 20 + ((i - 1) // 10) * 4)
				* roblox.CFrame.Angles(0, math.pi, 0)
		)
		model.Parent = workspace
	end
	-- Slot 7 as the "buy next slot" pad (PlotService styles it the same way).
	plot.slots[7].Color = roblox.Color3.fromHex("#7CFF4A")
	plot.slots[7].Transparency = 0.45
end

-- Export
local parts = {}
local function colorHex(c)
	return string.format(
		"#%02x%02x%02x",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5)
	)
end
for _, inst in workspace:GetDescendants() do
	if inst:IsA("BasePart") and inst.Transparency < 1 then
		local kind
		if inst:IsA("WedgePart") then
			kind = "Wedge"
		elseif inst:IsA("CornerWedgePart") then
			kind = "CornerWedge"
		elseif inst:IsA("Part") then
			kind = inst.Shape.Name -- Block, Ball, Cylinder
		else
			kind = "Block"
		end
		local mesh = inst:FindFirstChildOfClass("SpecialMesh")
		if mesh and mesh.MeshType == roblox.Enum.MeshType.Sphere then
			kind = "Ellipsoid"
		end
		table.insert(parts, {
			kind = kind,
			size = { inst.Size.X, inst.Size.Y, inst.Size.Z },
			cf = { inst.CFrame:GetComponents() },
			color = colorHex(inst.Color),
			material = inst.Material.Name,
			transparency = inst.Transparency,
			reflectance = inst.Reflectance,
		})
	end
end
fs.writeFile(outPath, serde.encode("json", { parts = parts }))
print(string.format("exported %d parts", #parts))
