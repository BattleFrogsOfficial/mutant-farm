--!strict
-- The hatch cutscene. When the server confirms a hatch, the screen flashes and the camera cuts to
-- a stage far from the farm. The egg sits on a pedestal, shakes once, shakes harder, then bursts
-- into shell fragments flying in every direction, and the mutant is standing there at full size.
-- A reveal card slides up. Then the camera flashes back to the farm.
-- Hatches queue up (Hatch All); Skip and Skip all are always available. Pens hold their update
-- until the cutscene ends, so the mutant never appears on the farm before its reveal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Eggs = require(Shared.Config.Eggs)
local MutantModel = require(Shared.MutantModel)
local State = require(script.Parent.Parent.State)
local Sfx = require(script.Parent.Parent.Sfx)
local PlotController = require(script.Parent.PlotController)

local HatchController = {}

local player = Players.LocalPlayer
local RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
local STAGE = Vector3.new(0, 0, 2600) -- far outside the valley; only the cutscene camera sees it
local EGG_SCALE = 2.4

type Hatch = { item: any, value: number, slotIndex: number?, isNew: boolean }
local queue: { Hatch } = {}
local playing = false
local skip = false
local skipAll = false
local advance = false

local stage: Model? = nil
local camBase = CFrame.identity
local shake = 0
-- Bumped for every new camera move so a stale tween from a skipped hatch stops writing.
local cameraGeneration = 0

---------------------------------------------------------------------------- stage

local function stagePart(model: Model, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = model
	return p
end

local function buildStage(): Model
	local model = Instance.new("Model")
	model.Name = "HatchStage"
	local cream = Color3.fromHex("#FFF4D6")
	local purple = Color3.fromHex("#9B5CFF")
	local slate = Color3.fromHex("#2A2440")
	stagePart(model, {
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 120, 120),
		CFrame = CFrame.new(STAGE + Vector3.new(0, -1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = slate,
	})
	stagePart(model, {
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 30, 30),
		CFrame = CFrame.new(STAGE + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = purple,
	})
	stagePart(model, {
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 9, 9),
		CFrame = CFrame.new(STAGE + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = cream,
	})
	-- Curtain arc behind the pedestal (+Z side; the camera looks from -Z).
	for i = -7, 7 do
		local a = math.rad(i * 9)
		local pos = STAGE + Vector3.new(math.sin(a) * 46, 30, math.cos(a) * 46)
		stagePart(model, {
			Name = "Curtain",
			Size = Vector3.new(7.6, 64, 1.5),
			CFrame = CFrame.lookAt(pos, STAGE + Vector3.new(0, 30, 0)),
			Color = if i % 2 == 0 then purple else Color3.fromHex("#7A45D6"),
			Material = Enum.Material.Fabric,
		})
	end
	-- A ring of bulbs around the edge of the stage floor.
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		stagePart(model, {
			Name = "Bulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.2, 1.2, 1.2),
			CFrame = CFrame.new(STAGE + Vector3.new(math.cos(a) * 15, 0.6, math.sin(a) * 15)),
			Color = if i % 2 == 0 then Color3.fromHex("#FFD24A") else cream,
		})
	end
	model.Parent = workspace
	return model
end

---------------------------------------------------------------------------- helpers

-- Waits `seconds`, returning early (true) if the player skipped.
local function wait(seconds: number): boolean
	local t = os.clock()
	while os.clock() - t < seconds do
		if skip or skipAll then
			return true
		end
		task.wait()
	end
	return skip or skipAll
end

local function tweenNumber(
	from: number,
	to: number,
	duration: number,
	set: (number) -> (),
	easing: ((number) -> number)?
)
	local t0 = os.clock()
	while true do
		local k = math.clamp((os.clock() - t0) / duration, 0, 1)
		set(from + (to - from) * (if easing then easing(k) else k))
		if k >= 1 then
			break
		end
		task.wait()
	end
end

local function easeOutBack(k: number): number
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (k - 1) ^ 3 + c1 * (k - 1) ^ 2
end

local function flash(to: number, duration: number)
	tweenNumber(State.hatchFlash:get(false), to, duration, function(v)
		State.hatchFlash:set(v)
	end)
end

local function burst(at: Vector3, color: Color3, amount: number, scale: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = at
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.3
	e.Lifetime = NumberRange.new(0.7, 1.4)
	e.Speed = NumberRange.new(14 * scale, 28 * scale)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	e.Acceleration = Vector3.new(0, -20, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8 * scale), NumberSequenceKeypoint.new(1, 0) })
	e.Rate = 0
	e.Parent = anchor
	anchor.Parent = workspace
	e:Emit(amount)
	task.delay(2.5, function()
		anchor:Destroy()
	end)
end

-- Shell fragments flying out in every direction with gravity, fading as they land.
local function explodeShell(center: Vector3, shell: Color3, accent: Color3, scale: number)
	local pieces = {}
	for i = 1, 28 do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = if i % 4 == 0 then accent else shell
		local s = (0.35 + math.random() * 0.55) * scale
		p.Size = Vector3.new(s, s * 0.35, s * (0.7 + math.random() * 0.6))
		local dir = Vector3.new(math.random() * 2 - 1, math.random() * 1.4 - 0.2, math.random() * 2 - 1)
		if dir.Magnitude < 0.1 then
			dir = Vector3.yAxis
		end
		dir = dir.Unit
		p.CFrame = CFrame.new(center + dir * scale * 0.8) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		p.Parent = workspace
		table.insert(pieces, {
			part = p,
			vel = dir * (16 + math.random() * 18) * math.sqrt(scale) + Vector3.new(0, 10, 0),
			spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 14,
		})
	end
	task.spawn(function()
		local t0 = os.clock()
		local last = t0
		while os.clock() - t0 < 1.6 do
			local now = os.clock()
			local dt = now - last
			last = now
			local fade = math.clamp((now - t0 - 1.1) / 0.5, 0, 1)
			for _, piece in pieces do
				piece.vel += Vector3.new(0, -70, 0) * dt
				local pos = piece.part.Position + piece.vel * dt
				if pos.Y < STAGE.Y + 0.2 then
					pos = Vector3.new(pos.X, STAGE.Y + 0.2, pos.Z)
					piece.vel = Vector3.new(piece.vel.X * 0.6, -piece.vel.Y * 0.35, piece.vel.Z * 0.6)
				end
				local rotation = piece.part.CFrame - piece.part.Position
				piece.part.CFrame = CFrame.new(pos)
					* rotation
					* CFrame.Angles(piece.spin.X * dt, piece.spin.Y * dt, piece.spin.Z * dt)
				piece.part.Transparency = fade
			end
			task.wait()
		end
		for _, piece in pieces do
			piece.part:Destroy()
		end
	end)
end

-- Camera framing for something `height` studs tall standing on the pedestal.
local function framing(height: number): CFrame
	local h = math.max(height, 3)
	local focus = STAGE + Vector3.new(0, 1.6 + h * 0.5, 0)
	local distance = h * 1.25 + 9
	return CFrame.lookAt(focus + Vector3.new(0, h * 0.15 + 2, -distance), focus)
end

local function moveCamera(to: CFrame, duration: number)
	cameraGeneration += 1
	local generation = cameraGeneration
	local from = camBase
	tweenNumber(0, 1, duration, function(k)
		if generation == cameraGeneration then
			camBase = from:Lerp(to, k)
		end
	end, function(k)
		return 1 - (1 - k) ^ 3
	end)
end

---------------------------------------------------------------------------- the cutscene

local function play(h: Hatch)
	local item = h.item
	local rank = RANK[item.rarity] or 1
	local rarityColor = Color3.fromHex(Rarities.info[item.rarity].color)
	local species = MutantModel.species(item)
	local design = Eggs.tiers[item.tier].design
	-- Commons in a long Hatch All get a short version.
	local quick = #queue > 0 and rank <= 2
	skip = false
	advance = false

	-- Cut to the stage.
	flash(1, 0.18)
	stage = stage or buildStage()
	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	local egg = MutantModel.buildEgg(item.tier, 1, item.mutations)
	egg:ScaleTo(EGG_SCALE)
	local top = CFrame.new(STAGE + Vector3.new(0, 1.6, 0))
	egg:PivotTo(top)
	egg.Parent = workspace
	local eggHeight = egg:GetExtentsSize().Y
	cameraGeneration += 1
	camBase = framing(eggHeight) * CFrame.new(0, 0, 6)
	flash(0, 0.25)

	-- Dolly in, then two shakes: a small one, then a big one.
	if not quick then
		task.spawn(moveCamera, framing(eggHeight), 1.2)
	end
	local function wobble(duration: number, amount: number)
		local t0 = os.clock()
		while os.clock() - t0 < duration and egg.Parent do
			local k = (os.clock() - t0) / duration
			egg:PivotTo(top * CFrame.Angles(0, 0, math.sin(k * math.pi * 10) * amount * (1 - k * 0.3)))
			task.wait()
		end
		if egg.Parent then
			egg:PivotTo(top)
		end
	end
	if not wait(if quick then 0.15 else 0.6) then
		Sfx.play("crack", 0.6, 0.9)
		wobble(if quick then 0.25 else 0.4, 0.12)
	end
	if not quick and not wait(0.55) then
		Sfx.play("crack", 0.8, 1.15)
		shake = 0.15
		wobble(0.6, 0.28)
		shake = 0
		wait(0.2)
	end

	-- Boom: the shell flies apart in every direction.
	local center = egg:GetPivot().Position + Vector3.new(0, eggHeight * 0.5, 0)
	egg:Destroy()
	Sfx.play("explode", 0.8)
	Sfx.play("hatch" .. item.rarity, 0.5 + rank * 0.1, 1.15 - rank * 0.06)
	explodeShell(center, Color3.fromHex(design.shell), Color3.fromHex(design.accent), EGG_SCALE * 0.9)
	burst(center, rarityColor, 30 + rank * 15, 1 + rank * 0.25)
	if rank >= 3 then
		burst(center, Color3.fromHex("#FFD24A"), 40, 1.6)
	end
	task.spawn(function()
		State.hatchFlash:set(0.7)
		flash(0, 0.3)
	end)
	shake = if rank >= 4 then 0.9 else 0.4
	task.delay(0.45, function()
		shake = 0
	end)

	-- ...and the mutant is standing there.
	local model = MutantModel.build(item)
	local height = (model:GetAttribute("Height") or 4) :: number
	model:PivotTo(top)
	model:ScaleTo(0.15)
	model.Parent = workspace
	task.spawn(moveCamera, framing(height), 0.7)
	tweenNumber(0.15, 1, 0.45, function(v)
		if model.Parent then
			model:ScaleTo(math.max(v, 0.05))
		end
	end, easeOutBack)

	local tags = { string.format("x%.2f size", item.size), string.format("%.0f studs tall", height) }
	for _, m in MutantModel.sortedMutations(item.mutations) do
		table.insert(tags, string.format("%s x%d", m:upper(), Mutations.info[m].multiplier))
	end
	State.hatchCard:set({
		name = species.name,
		rarity = item.rarity,
		color = rarityColor,
		tags = tags,
		value = Format.cash(h.value),
		isNew = h.isNew,
	})

	-- Hold until Continue / Skip, or a short auto-advance in quick mode.
	local t0 = os.clock()
	local auto = if quick then 1.4 else 8
	while not advance and not skip and not skipAll and os.clock() - t0 < auto do
		-- Slow turntable so the player sees the whole mutant.
		if model.Parent then
			model:PivotTo(top * CFrame.Angles(0, math.sin((os.clock() - t0) * 0.8) * 0.5, 0))
		end
		task.wait()
	end

	State.hatchCard:set(nil)
	flash(1, 0.15)
	model:Destroy()
end

local function finish()
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	if stage then
		stage:Destroy()
		stage = nil
	end
	State.hatching:set(false)
	flash(0, 0.3)
end

local function run()
	if playing then
		return
	end
	playing = true
	State.hatching:set(true)
	State.panel:set("none")
	skipAll = false
	camBase = workspace.CurrentCamera.CFrame -- hold the current view until the stage is ready
	RunService:BindToRenderStep("HatchCamera", Enum.RenderPriority.Camera.Value + 1, function()
		local offset = if shake > 0
			then CFrame.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, 0)
			else CFrame.identity
		workspace.CurrentCamera.CFrame = camBase * offset
	end)
	while #queue > 0 do
		local h = table.remove(queue, 1) :: Hatch
		State.hatchQueue:set(#queue)
		if skipAll then
			-- Skipped hatches still get a line in the toasts.
			State.toast(
				string.format(
					"Hatched %s (%s) worth %s",
					MutantModel.species(h.item).name,
					h.item.rarity,
					Format.cash(h.value)
				),
				"success"
			)
		else
			local ok, err = pcall(play, h)
			if not ok then
				warn("[Hatch] cutscene failed:", err)
				State.hatchCard:set(nil)
			end
		end
	end
	RunService:UnbindFromRenderStep("HatchCamera")
	playing = false
	finish()
	State.hatchQueue:set(#queue)
	-- A hatch that arrived during the final fade starts its own run.
	if #queue > 0 then
		task.spawn(run)
	end
end

local function onHarvested(item: any, value: number, slotIndex: number?, isNew: boolean?)
	if slotIndex then
		PlotController.hideSlotEgg(slotIndex)
	end
	table.insert(queue, { item = item, value = value, slotIndex = slotIndex, isNew = isNew == true })
	State.hatchQueue:set(if playing then #queue else math.max(0, #queue - 1))
	task.spawn(run)
end

local function onMutated(slotIndex: number, eggId: string, mutation: string)
	local info = Mutations.info[mutation]
	local tier = Eggs.tiers[eggId]
	State.toast(string.format("%s mutated: %s! (x%d)", tier.name, mutation:upper(), info.multiplier), "success")
	Sfx.play("mutate", 0.7, 1.3)
	local slot = PlotController.slotPart(slotIndex)
	if slot then
		burst(slot.Position + Vector3.new(0, 1.5, 0), Color3.fromHex(info.color), 30, 0.6)
	end
end

function HatchController.Init() end

function HatchController.Start()
	Remotes.get("Harvested").OnClientEvent:Connect(onHarvested)
	Remotes.get("Mutated").OnClientEvent:Connect(onMutated)
	-- Overlay buttons bump State.hatchInput; translate them into flags the cutscene checks.
	local lastInput = 0
	RunService.Heartbeat:Connect(function()
		local input = State.hatchInput:get(false)
		if input.id ~= lastInput then
			lastInput = input.id
			if input.action == "next" then
				advance = true
			elseif input.action == "skip" then
				skip = true
			elseif input.action == "skipAll" then
				skipAll = true
			end
		end
	end)
end

return HatchController
