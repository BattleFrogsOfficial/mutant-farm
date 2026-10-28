--!strict
-- The hatch cutscene. The camera leaves the farm for a magic swamp island (HatchIsland, built far
-- from the map, with heavy haze so nothing past the set shows):
--   flash in -> the egg drops onto the stump -> shakes once and cracks -> shakes again and cracks
--   all over -> the top pops off, the shell bursts apart, sparkles and a shockwave -> the mutant
--   grows out of it, the camera pulls back to fit it, the rarity title slams in, the value counts up.
-- Hatches queue (Hatch All). Skip jumps straight to the reveal; Skip all summarizes the rest.
-- Camera and Lighting are restored afterwards. Your own pen holds its update until the end.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Eggs = require(Shared.Config.Eggs)
local MutantModel = require(Shared.MutantModel)
local HatchIsland = require(Shared.HatchIsland)
local State = require(script.Parent.Parent.State)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Parent.UI.Theme)
local HatchScreen = require(script.Parent.Parent.UI.HatchScreen)
local PlotController = require(script.Parent.PlotController)

local HatchController = {}

local RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
local DESIGN = Vector2.new(900, 540)
local TITLE_COLORS = {
	Common = { "#FFFFFF", "#B4B8C2" },
	Uncommon = { "#C8FFB0", "#4FCB3F" },
	Rare = { "#BFF0FF", "#3E8BFF" },
	Epic = { "#FFC2FF", "#A24CFF" },
	Legendary = { "#FFF3A8", "#FF9A1F" },
}
-- Far from the map (which ends ~250 studs out), so the haze hides the farm completely.
local ORIGIN = CFrame.new(0, 0, 20000)
local STAGE = ORIGIN * CFrame.new(0, HatchIsland.STUMP_TOP, 0)
local FOV = 50
local MAX_CAMERA_DISTANCE = 120 -- bigger mutants are shown scaled down to fit the set

type Hatch = { item: any, value: number, slotIndex: number?, isNew: boolean }
local queue: { Hatch } = {}
local playing = false
local skip = false
local skipAll = false
local advance = false
-- Taps only count once the reveal has been up briefly (players tap eggs by reflex).
local revealedAt = math.huge
-- Bumped per hatch so tweens spawned for an old hatch stop writing to the screen.
local hatchId = 0

local gui: ScreenGui
local screen: HatchScreen.Screen
local scaleRoot: Frame
local island: Model
local stage: Folder -- egg, mutant and effects for the current hatch
local camera: Camera

---------------------------------------------------------------------------- helpers

-- Waits `seconds`; returns true early if the player skipped.
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

local function tween(duration: number, step: (number) -> (), easing: ((number) -> number)?)
	local t0 = os.clock()
	while true do
		local k = math.clamp((os.clock() - t0) / duration, 0, 1)
		step(if easing then easing(k) else k)
		if k >= 1 then
			break
		end
		task.wait()
	end
end

local function backOut(k: number): number
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (k - 1) ^ 3 + c1 * (k - 1) ^ 2
end

local function quadOut(k: number): number
	return 1 - (1 - k) * (1 - k)
end

local function smooth(k: number): number
	return k * k * (3 - 2 * k)
end

-- Effects started for one hatch stop writing once `hatchId` moves on (next hatch or scene exit).
local function flash(id: number, color: Color3, peak: number, up: number, down: number)
	screen.flash.BackgroundColor3 = color
	tween(up, function(k)
		if hatchId == id then
			screen.flash.BackgroundTransparency = 1 - peak * k
		end
	end)
	task.spawn(tween, down, function(k)
		if hatchId == id then
			screen.flash.BackgroundTransparency = 1 - peak * (1 - k)
		end
	end)
end

local function clearStage()
	stage:ClearAllChildren()
end

local function stripEffects(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
end

local function noPhysics(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

---------------------------------------------------------------------------- camera & lighting

-- Camera framing for something `size` big standing on the stump: from the -Z side, a little above.
local function shotFor(size: Vector3): CFrame
	local height = math.max(size.Y, 0.5)
	local extent = math.max(size.Y * 1.25, size.X * 0.8, size.Z * 0.5, 2.5)
	local distance = extent * 0.62 / math.tan(math.rad(FOV / 2))
	local focus = STAGE.Position + Vector3.new(0, height * 0.48, 0)
	local eye = focus + Vector3.new(0, math.min(extent * 0.18, 12) + 1, -distance)
	return CFrame.lookAt(eye, focus)
end

-- Keeps the camera ours even if something (e.g. a respawn) switched it back to Custom.
local function holdCamera(cf: CFrame)
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	camera.CFrame = cf
end

local function moveCamera(id: number, to: CFrame, duration: number)
	local from = camera.CFrame
	tween(duration, function(k)
		if hatchId == id then
			holdCamera(from:Lerp(to, k))
		end
	end, smooth)
end

local saved: { [string]: any }? = nil
local LIGHTING_PROPS =
	{ "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation", "GlobalShadows" }
local ATMOSPHERE_PROPS = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" }

local function setAtmosphereForDistance(distance: number)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		-- Thick swamp haze, thinned a little when the camera pulls far back for a giant.
		atmosphere.Density = math.clamp(0.62 - distance / 500, 0.4, 0.62)
	end
end

local function enterScene()
	camera = workspace.CurrentCamera
	local state: { [string]: any } = {
		cameraType = camera.CameraType,
		cameraCFrame = camera.CFrame,
		fov = camera.FieldOfView,
		lighting = {},
		atmosphere = {},
	}
	for _, prop in LIGHTING_PROPS do
		state.lighting[prop] = (Lighting :: any)[prop]
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "HatchAtmosphere"
		atmosphere.Parent = Lighting
		state.createdAtmosphere = atmosphere
	else
		for _, prop in ATMOSPHERE_PROPS do
			state.atmosphere[prop] = (atmosphere :: any)[prop]
		end
	end
	saved = state

	-- Magic-hour swamp: violet ambient, teal haze that swallows the horizon.
	Lighting.ClockTime = 17.4
	Lighting.Brightness = 1.6
	Lighting.Ambient = Color3.fromHex("#5A4C80")
	Lighting.OutdoorAmbient = Color3.fromHex("#7E70A8")
	Lighting.ExposureCompensation = 0.1
	Lighting.GlobalShadows = true
	local a = atmosphere :: Atmosphere
	a.Offset = 0.3
	a.Color = Color3.fromHex("#7FA59E")
	a.Decay = Color3.fromHex("#4A3A78")
	a.Glare = 0
	a.Haze = 2.4
	setAtmosphereForDistance(0)

	island.Parent = workspace
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FOV
	camera.CFrame = shotFor(Vector3.new(2, 3, 2)) * CFrame.new(0, 1.5, 6)
end

local function exitScene()
	hatchId += 1 -- stops any camera/flash tweens still running for the last hatch
	island.Parent = nil
	clearStage()
	local state = saved
	saved = nil
	if not state then
		return
	end
	for prop, value in state.lighting do
		(Lighting :: any)[prop] = value
	end
	if state.createdAtmosphere then
		state.createdAtmosphere:Destroy()
	else
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			for prop, value in state.atmosphere do
				(atmosphere :: any)[prop] = value
			end
		end
	end
	camera.FieldOfView = state.fov
	camera.CameraType = state.cameraType
	camera.CFrame = state.cameraCFrame
end

---------------------------------------------------------------------------- effects

-- 2D confetti bursting from the center of the screen.
local function confetti(colors: { Color3 }, amount: number)
	local pieces = {}
	for i = 1, amount do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(8 + math.random(6), 14 + math.random(10))
		f.BackgroundColor3 = colors[(i % #colors) + 1]
		f.Position = UDim2.new(0.5, 0, 0.5, 10)
		f.ZIndex = 6
		f.Parent = screen.confetti
		local angle = math.random() * math.pi * 2
		local speed = 380 + math.random() * 520
		table.insert(pieces, {
			frame = f,
			x = 0,
			y = 10,
			vx = math.cos(angle) * speed,
			vy = math.sin(angle) * speed - 260,
			spin = (math.random() - 0.5) * 900,
		})
	end
	task.spawn(function()
		local t0, last = os.clock(), os.clock()
		while os.clock() - t0 < 2.2 do
			local now = os.clock()
			local dt = now - last
			last = now
			local fade = math.clamp((now - t0 - 1.4) / 0.8, 0, 1)
			for _, p in pieces do
				p.vy += 900 * dt
				p.vx *= 1 - 1.2 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
				p.frame.Position = UDim2.new(0.5, p.x, 0.5, p.y)
				p.frame.Rotation += p.spin * dt
				p.frame.BackgroundTransparency = fade
			end
			task.wait()
		end
		for _, p in pieces do
			p.frame:Destroy()
		end
	end)
end

-- Moves parts with simple ballistics for `duration`, fading them out at the end, then destroys them.
local function fling(pieces: { { part: BasePart, vel: Vector3, spin: Vector3 } }, gravity: number, duration: number)
	task.spawn(function()
		local t0, last = os.clock(), os.clock()
		while os.clock() - t0 < duration do
			local now = os.clock()
			local dt = now - last
			last = now
			local fade = math.clamp((now - t0 - duration * 0.6) / (duration * 0.4), 0, 1)
			for _, piece in pieces do
				if piece.part.Parent then
					piece.vel += Vector3.new(0, -gravity, 0) * dt
					local rotation = piece.part.CFrame - piece.part.Position
					piece.part.CFrame = CFrame.new(piece.part.Position + piece.vel * dt)
						* rotation
						* CFrame.Angles(piece.spin.X * dt, piece.spin.Y * dt, piece.spin.Z * dt)
					piece.part.Transparency = math.max(piece.part.Transparency, fade)
				end
			end
			task.wait()
		end
		for _, piece in pieces do
			piece.part:Destroy()
		end
	end)
end

-- The egg opens: its top half pops off and tumbles away, the lower half bursts outward,
-- and extra shards fly everywhere.
local function openEgg(egg: Model, eggSize: Vector3, shell: Color3, accent: Color3)
	local base = STAGE
	local split = eggSize.Y * 0.52
	local lid, cup = {}, {}
	for _, d in egg:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			d.Parent = stage
			local y = base:PointToObjectSpace(d.Position).Y
			table.insert(if y > split then lid else cup, d)
		end
	end
	egg:Destroy()
	local scale = eggSize.Y
	local pieces = {}
	-- The lid flies up and back as one piece, spinning.
	local lidVel = Vector3.new((math.random() - 0.5) * 2, 9, 3) * scale * 0.55
	local lidSpin = Vector3.new(3 + math.random() * 2, math.random() * 2, (math.random() - 0.5) * 3)
	for _, p in lid do
		table.insert(pieces, { part = p, vel = lidVel, spin = lidSpin })
	end
	-- The cup bursts outward in all directions.
	for _, p in cup do
		local out = (p.Position - base.Position) * Vector3.new(1, 0, 1)
		out = if out.Magnitude < 0.05 then Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit else out.Unit
		table.insert(pieces, {
			part = p,
			vel = (out * (4 + math.random() * 3) + Vector3.new(0, 3 + math.random() * 3, 0)) * scale * 0.5,
			spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 10,
		})
	end
	-- Extra shards.
	for i = 1, 26 do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = if i % 4 == 0 then accent else shell
		local s = (0.12 + math.random() * 0.2) * scale
		p.Size = Vector3.new(s, s * 0.3, s * (0.6 + math.random() * 0.6))
		local dir = Vector3.new(math.random() * 2 - 1, math.random() * 1.4, math.random() * 2 - 1)
		dir = if dir.Magnitude < 0.1 then Vector3.yAxis else dir.Unit
		p.CFrame = CFrame.new(base.Position + Vector3.new(0, scale * 0.5, 0) + dir * scale * 0.3)
			* CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		p.Parent = stage
		table.insert(pieces, {
			part = p,
			vel = dir * (6 + math.random() * 7) * scale * 0.5,
			spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 16,
		})
	end
	fling(pieces, 16 * scale * 0.5, 1.4)
end

-- Sparkle burst and an expanding glow ring on the stump, in the rarity color.
local function burst(color: Color3, scale: number, amount: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = STAGE * CFrame.new(0, scale * 0.5, 0)
	anchor.Parent = stage
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.LightEmission = 0.7
	e.Lifetime = NumberRange.new(0.6, 1.3)
	e.Speed = NumberRange.new(10 * scale * 0.4, 22 * scale * 0.4)
	e.Drag = 3
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * scale * 0.4), NumberSequenceKeypoint.new(1, 0) })
	e.Rate = 0
	e.Parent = anchor
	e:Emit(amount)

	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Parent = stage
	task.spawn(tween, 0.6, function(k)
		local d = (1 + 18 * quadOut(k)) * scale * 0.4
		ring.Size = Vector3.new(0.15, d, d)
		ring.CFrame = STAGE * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90))
		ring.Transparency = 0.2 + 0.8 * k
	end)
end

local function setRevealVisible(visible: boolean)
	screen.title.Visible = visible
	screen.value.Visible = visible
	screen.name.Visible = visible
	screen.chips.Visible = visible
	screen.hint.Visible = visible
	if not visible then
		screen.newRibbon.Visible = false
	end
end

---------------------------------------------------------------------------- the cutscene

local function play(h: Hatch)
	local item = h.item
	local rank = RANK[item.rarity] or 1
	local rarityColor = Color3.fromHex(Rarities.info[item.rarity].color)
	local species = MutantModel.species(item)
	local design = Eggs.tiers[item.tier].design
	local quick = #queue > 0 and rank <= 2 -- Commons in a long Hatch All get a short version
	skip = false
	advance = false
	revealedAt = math.huge
	hatchId += 1
	local myId = hatchId

	clearStage()
	setRevealVisible(false)

	-- The egg drops onto the stump while the camera settles in front of it.
	local egg = MutantModel.buildEgg(item.tier, 1, item.mutations)
	stripEffects(egg)
	noPhysics(egg)
	egg:PivotTo(STAGE)
	egg.Parent = stage
	local eggSize = egg:GetExtentsSize()
	local eggShot = shotFor(eggSize * 1.6)
	setAtmosphereForDistance(0)
	task.spawn(moveCamera, myId, eggShot, if quick then 0.25 else 0.7)
	if not skip then
		tween(if quick then 0.25 else 0.45, function(k)
			egg:PivotTo(STAGE * CFrame.new(0, (1 - backOut(k)) * eggSize.Y * 2.5, 0))
		end)
	end
	egg:PivotTo(STAGE)

	local function shake(duration: number, degrees: number, jitter: number, cameraKick: number)
		local t0 = os.clock()
		while os.clock() - t0 < duration and not (skip or skipAll) do
			local k = (os.clock() - t0) / duration
			local swing = math.sin(k * math.pi * 10) * math.rad(degrees) * (0.6 + 0.4 * math.sin(k * math.pi))
			local offset = Vector3.new((math.random() - 0.5) * jitter, 0, 0) * eggSize.X
			egg:PivotTo(STAGE * CFrame.new(offset) * CFrame.Angles(0, 0, swing))
			holdCamera(eggShot * CFrame.new((math.random() - 0.5) * cameraKick, (math.random() - 0.5) * cameraKick, 0))
			task.wait()
		end
		egg:PivotTo(STAGE)
		holdCamera(eggShot)
	end

	-- Shake one: a wobble and a first crack.
	if not wait(if quick then 0.1 else 0.45) then
		Sfx.play("crack", 0.6, 0.95)
		shake(if quick then 0.3 else 0.5, 10, 0.02, 0.04)
		MutantModel.addCracks(egg, 1)
	end
	-- Shake two: harder, cracks all over.
	if not wait(if quick then 0.15 else 0.5) then
		Sfx.play("crack", 0.85, 1.2)
		shake(if quick then 0.35 else 0.7, 20, 0.07, 0.12)
		MutantModel.addCracks(egg, 2)
		wait(0.12)
	end

	-- It opens.
	Sfx.play("explode", 0.8)
	Sfx.play("hatch" .. item.rarity, 0.5 + rank * 0.1, 1.15 - rank * 0.06)
	task.spawn(flash, myId, rarityColor:Lerp(Color3.new(1, 1, 1), 0.6), 0.75, 0.05, 0.4)
	openEgg(egg, eggSize, Color3.fromHex(design.shell), Color3.fromHex(design.accent))
	burst(rarityColor, eggSize.Y, if quick then 25 else 40 + rank * 12)
	confetti(
		{ rarityColor, Theme.colors.gold, Theme.colors.white, Color3.fromHex(design.accent) },
		if quick then 16 else 24 + rank * 8
	)

	-- The mutant grows out of the shell; the camera pulls back to fit it.
	local mutant = MutantModel.build(item)
	stripEffects(mutant)
	noPhysics(mutant)
	mutant:PivotTo(STAGE)
	local fullSize = mutant:GetExtentsSize()
	local shot = shotFor(fullSize)
	local distance = (shot.Position - STAGE.Position).Magnitude
	local fit = 1
	if distance > MAX_CAMERA_DISTANCE then
		-- A true giant: show it scaled to fit the set (its real height is in the chips).
		fit = MAX_CAMERA_DISTANCE / distance
		shot = shotFor(fullSize * fit)
		distance = MAX_CAMERA_DISTANCE
	end
	setAtmosphereForDistance(distance)
	mutant:ScaleTo(0.15 * fit)
	mutant.Parent = stage
	local height = (mutant:GetAttribute("Height") or 4) :: number
	task.spawn(tween, 0.5, function(k)
		if mutant.Parent then
			mutant:ScaleTo(math.max((0.15 + 0.85 * backOut(k)) * fit, 0.02))
		end
	end)
	task.spawn(moveCamera, myId, shot, if quick then 0.3 else 0.6)

	-- Reveal text.
	local colors = TITLE_COLORS[item.rarity] or TITLE_COLORS.Common
	screen.titleGradient.Color = ColorSequence.new(Color3.fromHex(colors[1]), Color3.fromHex(colors[2]))
	screen.title.Text = item.rarity:upper() .. "!"
	screen.name.Text = species.name
	screen.name.TextColor3 = rarityColor:Lerp(Color3.new(1, 1, 1), 0.3)
	local chips = {
		{ text = string.format("x%.2f size", item.size), color = Theme.colors.slateLight },
		{ text = string.format("%.0f studs tall", height), color = Theme.colors.slateLight },
	}
	for _, m in MutantModel.sortedMutations(item.mutations) do
		table.insert(chips, {
			text = string.format("%s x%d", m:upper(), Mutations.info[m].multiplier),
			color = Color3.fromHex(Mutations.info[m].color):Lerp(Theme.colors.slate, 0.35),
		})
	end
	HatchScreen.setChips(screen, chips)
	setRevealVisible(true)
	screen.newRibbon.Visible = h.isNew
	screen.titleScale.Scale = 1.8
	task.spawn(tween, 0.3, function(k)
		if hatchId == myId then
			screen.titleScale.Scale = 1.8 - 0.8 * backOut(k)
		end
	end)
	task.spawn(tween, 0.7, function(k)
		if hatchId == myId then
			screen.value.Text = "Worth " .. Format.cash(math.floor(h.value * quadOut(k)))
		end
	end)
	if rank >= 4 then
		-- Screen shake for Epic and Legendary.
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 0.5 do
				local k = 1 - (os.clock() - t0) / 0.5
				screen.root.Position = UDim2.fromOffset((math.random() - 0.5) * 14 * k, (math.random() - 0.5) * 14 * k)
				task.wait()
			end
			screen.root.Position = UDim2.new()
		end)
	end

	-- Hold until tapped / skipped (or a short auto-advance in quick mode). The mutant turns
	-- side to side and the camera drifts slowly around it.
	skip = false
	advance = false
	revealedAt = os.clock()
	local t0 = os.clock()
	local auto = if quick then 1.3 else 9
	local focus = STAGE.Position + Vector3.new(0, fullSize.Y * fit * 0.48, 0)
	while not advance and not skip and not skipAll and os.clock() - t0 < auto do
		local t = os.clock() - t0
		if t > 0.65 then
			if mutant.Parent then
				mutant:PivotTo(STAGE * CFrame.Angles(0, math.sin(t * 0.9) * 0.55, 0))
			end
			local orbit = CFrame.Angles(0, math.sin((t - 0.65) * 0.35) * 0.22, 0)
			local eye = focus + orbit:VectorToWorldSpace(shot.Position - focus)
			holdCamera(CFrame.lookAt(eye, focus))
		end
		screen.hint.TextTransparency = 0.25 + 0.35 * math.abs(math.sin(t * 2.5))
		task.wait()
	end
	mutant:Destroy()
	revealedAt = math.huge
end

local function run()
	if playing then
		return
	end
	playing = true
	State.hatching:set(true)
	State.panel:set("none")
	skipAll = false
	-- Whoosh in: flash to white, swap to the island behind it, fade back out.
	gui.Enabled = true
	setRevealVisible(false)
	screen.flash.BackgroundColor3 = Color3.new(1, 1, 1)
	tween(0.18, function(k)
		screen.flash.BackgroundTransparency = 1 - k
	end)
	local ok, err = pcall(enterScene)
	if not ok then
		warn("[Hatch] scene failed:", err)
	end
	task.spawn(tween, 0.35, function(k)
		screen.flash.BackgroundTransparency = k
	end)

	-- Hatches skipped with "Skip all" (including the one on screen) become one summary toast.
	local skippedCount, skippedValue, best = 0, 0, nil
	local function addSkipped(h: Hatch)
		skippedCount += 1
		skippedValue += h.value
		if not best or (RANK[h.item.rarity] or 0) > (RANK[best.item.rarity] or 0) then
			best = h
		end
	end
	while #queue > 0 do
		local h = table.remove(queue, 1) :: Hatch
		screen.skipAll.Visible = #queue > 0
		screen.queue.Text = if #queue > 0 then string.format("+%d more", #queue) else ""
		if skipAll then
			addSkipped(h)
		else
			local played, playErr = pcall(play, h)
			if not played then
				warn("[Hatch] cutscene failed:", playErr)
			end
			if skipAll then
				addSkipped(h)
			end
		end
	end
	if skippedCount > 0 and best then
		State.toast(
			string.format(
				"Hatched %d mutants worth %s (best: %s %s)",
				skippedCount,
				Format.cash(skippedValue),
				best.item.rarity,
				MutantModel.species(best.item).name
			),
			"success"
		)
	end

	-- Whoosh out.
	setRevealVisible(false)
	tween(0.15, function(k)
		screen.flash.BackgroundTransparency = 1 - k
	end)
	exitScene()
	tween(0.3, function(k)
		screen.flash.BackgroundTransparency = k
	end)
	gui.Enabled = false
	playing = false
	State.hatching:set(false)
	-- A hatch that arrived during the last moments starts a fresh run.
	if #queue > 0 then
		task.spawn(run)
	end
end

local function onHarvested(item: any, value: number, slotIndex: number?, isNew: boolean?)
	if slotIndex then
		PlotController.hideSlotEgg(slotIndex)
	end
	table.insert(queue, { item = item, value = value, slotIndex = slotIndex, isNew = isNew == true })
	if playing then
		screen.skipAll.Visible = true
		screen.queue.Text = string.format("+%d more", #queue)
	end
	task.spawn(run)
end

local function onMutated(slotIndex: number, eggId: string, mutation: string)
	local info = Mutations.info[mutation]
	local tier = Eggs.tiers[eggId]
	State.toast(string.format("%s mutated: %s! (x%d)", tier.name, mutation:upper(), info.multiplier), "success")
	Sfx.play("mutate", 0.7, 1.3)
	local slot = PlotController.slotPart(slotIndex)
	if slot then
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		anchor.Position = slot.Position + Vector3.new(0, 1.5, 0)
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(Color3.fromHex(info.color))
		e.LightEmission = 0.3
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(6, 12)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		e.Rate = 0
		e.Parent = anchor
		anchor.Parent = workspace
		e:Emit(30)
		task.delay(2, function()
			anchor:Destroy()
		end)
	end
end

function HatchController.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "MutantFarmHatch"
	gui.IgnoreGuiInset = true -- cover the top bar too, so the flash covers the whole screen
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	scaleRoot = Instance.new("Frame")
	scaleRoot.Name = "Root"
	scaleRoot.BackgroundTransparency = 1
	scaleRoot.Size = UDim2.fromScale(1, 1)
	scaleRoot.Parent = gui
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = scaleRoot

	screen = HatchScreen.new()
	screen.root.Parent = scaleRoot

	-- Same scaling rule as the HUD: fit the 900x540 design canvas, oversize the root by 1/scale.
	local function rescale()
		local size = gui.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return
		end
		local s = math.clamp(math.min(size.X / DESIGN.X, size.Y / DESIGN.Y), 0.5, 1.4)
		uiScale.Scale = s
		scaleRoot.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	HatchController.rescale = rescale

	screen.tap.Activated:Connect(function()
		if os.clock() - revealedAt > 0.3 then
			advance = true
		end
	end)
	screen.skip.Activated:Connect(function()
		skip = true
	end)
	screen.skipAll.Activated:Connect(function()
		skipAll = true
	end)

	-- The island is built once and parented to workspace only during a hatch.
	island = HatchIsland.build(ORIGIN)
	stage = Instance.new("Folder")
	stage.Name = "Stage"
	stage.Parent = island
end

function HatchController.Start()
	-- Parent here, not in Init (Init must not yield).
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	HatchController.rescale()
	Remotes.get("Harvested").OnClientEvent:Connect(onHarvested)
	Remotes.get("Mutated").OnClientEvent:Connect(onMutated)
end

return HatchController
