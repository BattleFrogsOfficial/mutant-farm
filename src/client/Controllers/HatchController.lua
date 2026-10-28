--!strict
-- The hatch cinematic, on its own full-screen ScreenGui (covers the top bar; the world never shows):
--   backdrop fades in, rays spin, the egg drops in -> shakes and cracks -> shakes harder and cracks
--   all over -> white flash, the shell flies apart toward the camera, confetti bursts -> the mutant
--   pops up, the rarity title slams in, the value counts up, chips and a NEW ribbon appear.
-- Hatches queue (Hatch All). Skip jumps straight to the reveal; Skip all summarizes the rest.
-- Your own pen holds its update until the cinematic ends, so nothing is spoiled on the farm.

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
local rayBase = 0
local raySpeed = 12 -- degrees per second
local glowPulse = 0.05

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

local function flash(peak: number, up: number, down: number)
	tween(up, function(k)
		screen.flash.BackgroundTransparency = 1 - peak * k
	end)
	task.spawn(tween, down, function(k)
		screen.flash.BackgroundTransparency = 1 - peak * (1 - k)
	end)
end

local function clearStage()
	for _, child in screen.viewport:GetChildren() do
		if not child:IsA("Camera") then
			child:Destroy()
		end
	end
end

-- Points the stage camera at a model of this size standing at the origin.
local function frameCamera(size: Vector3)
	local height = math.max(size.Y, 0.5)
	local extent = math.max(size.Y, size.X * 0.95, size.Z * 0.6, 0.5)
	local distance = extent * 0.68 / math.tan(math.rad(16))
	local focus = Vector3.new(0, height * 0.5, 0)
	screen.camera.CFrame = CFrame.lookAt(focus + Vector3.new(0, extent * 0.12, -distance), focus)
end

local function stripEffects(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
end

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

-- Shell pieces flying out of the egg (in 3D, inside the stage window).
local function explodeShell(center: Vector3, scale: number, shell: Color3, accent: Color3)
	local pieces = {}
	for i = 1, 30 do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = if i % 4 == 0 then accent else shell
		local s = (0.25 + math.random() * 0.4) * scale
		p.Size = Vector3.new(s, s * 0.3, s * (0.6 + math.random() * 0.6))
		local dir = Vector3.new(math.random() * 2 - 1, math.random() * 1.6 - 0.3, math.random() * 2 - 1.4)
		dir = if dir.Magnitude < 0.1 then Vector3.yAxis else dir.Unit
		p.CFrame = CFrame.new(center + dir * scale * 0.4) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		p.Parent = screen.viewport
		table.insert(pieces, {
			part = p,
			vel = dir * (5 + math.random() * 6) * scale,
			spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 16,
		})
	end
	task.spawn(function()
		local t0, last = os.clock(), os.clock()
		while os.clock() - t0 < 1.3 do
			local now = os.clock()
			local dt = now - last
			last = now
			for _, piece in pieces do
				if piece.part.Parent then
					piece.vel += Vector3.new(0, -14 * scale, 0) * dt
					local rotation = piece.part.CFrame - piece.part.Position
					piece.part.CFrame = CFrame.new(piece.part.Position + piece.vel * dt)
						* rotation
						* CFrame.Angles(piece.spin.X * dt, piece.spin.Y * dt, piece.spin.Z * dt)
				end
			end
			task.wait()
		end
		for _, piece in pieces do
			piece.part:Destroy()
		end
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

---------------------------------------------------------------------------- the cinematic

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
	HatchScreen.setColor(screen, Color3.fromHex(design.accent))
	raySpeed = 12
	glowPulse = 0.05

	-- The egg drops in.
	local egg = MutantModel.buildEgg(item.tier, 1, item.mutations)
	stripEffects(egg)
	egg:PivotTo(CFrame.identity)
	egg.Parent = screen.viewport
	local eggSize = egg:GetExtentsSize()
	frameCamera(eggSize * 1.35)
	local base = CFrame.identity
	if not skip then
		tween(if quick then 0.2 else 0.4, function(k)
			egg:PivotTo(base * CFrame.new(0, (1 - backOut(k)) * eggSize.Y * 1.2, 0))
		end)
	end

	local function shake(duration: number, degrees: number, jitter: number)
		local t0 = os.clock()
		while os.clock() - t0 < duration and not (skip or skipAll) do
			local k = (os.clock() - t0) / duration
			local swing = math.sin(k * math.pi * 12) * math.rad(degrees) * (0.6 + 0.4 * math.sin(k * math.pi))
			local offset = Vector3.new((math.random() - 0.5) * jitter, 0, 0) * eggSize.X
			egg:PivotTo(CFrame.new(offset) * CFrame.Angles(0, 0, swing))
			task.wait()
		end
		egg:PivotTo(base)
	end

	-- Shake once, crack; shake harder, crack all over.
	if not wait(if quick then 0.1 else 0.35) then
		Sfx.play("crack", 0.6, 0.95)
		shake(if quick then 0.3 else 0.45, 9, 0.02)
		MutantModel.addCracks(egg, 1)
		glowPulse = 0.1
	end
	if not quick and not wait(0.4) then
		Sfx.play("crack", 0.85, 1.2)
		raySpeed = 40
		shake(0.65, 18, 0.06)
		MutantModel.addCracks(egg, 2)
		glowPulse = 0.18
		wait(0.12)
	end

	-- Boom.
	egg:Destroy()
	Sfx.play("explode", 0.8)
	Sfx.play("hatch" .. item.rarity, 0.5 + rank * 0.1, 1.15 - rank * 0.06)
	flash(0.85, 0.06, 0.35)
	HatchScreen.setColor(screen, rarityColor)
	raySpeed = 18 + rank * 4
	glowPulse = 0.06 + rank * 0.015
	explodeShell(
		Vector3.new(0, eggSize.Y * 0.5, 0),
		eggSize.Y,
		Color3.fromHex(design.shell),
		Color3.fromHex(design.accent)
	)
	confetti(
		{ rarityColor, Theme.colors.gold, Theme.colors.white, Color3.fromHex(design.accent) },
		if quick then 20 else 30 + rank * 10
	)

	-- The mutant pops up.
	local mutant = MutantModel.build(item)
	stripEffects(mutant)
	mutant:PivotTo(CFrame.identity)
	local fullSize = mutant:GetExtentsSize()
	frameCamera(fullSize)
	mutant:ScaleTo(0.2)
	mutant.Parent = screen.viewport
	local height = (mutant:GetAttribute("Height") or 4) :: number
	task.spawn(tween, 0.45, function(k)
		if mutant.Parent then
			mutant:ScaleTo(math.max(0.2 + 0.8 * backOut(k), 0.05))
		end
	end)

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

	-- Hold until tapped / skipped, or a short auto-advance in quick mode.
	skip = false
	advance = false
	revealedAt = os.clock()
	local t0 = os.clock()
	local auto = if quick then 1.3 else 9
	while not advance and not skip and not skipAll and os.clock() - t0 < auto do
		if mutant.Parent and os.clock() - t0 > 0.45 then
			mutant:PivotTo(CFrame.Angles(0, math.sin((os.clock() - t0) * 0.9) * 0.55, 0))
		end
		screen.hint.TextTransparency = 0.25 + 0.35 * math.abs(math.sin((os.clock() - t0) * 2.5))
		task.wait()
	end
	mutant:Destroy()
	revealedAt = math.huge
end

local function setVisible(visible: boolean)
	gui.Enabled = visible
	screen.backdrop.BackgroundTransparency = if visible then 0.04 else 1
end

local function run()
	if playing then
		return
	end
	playing = true
	State.hatching:set(true)
	State.panel:set("none")
	skipAll = false
	setVisible(true)
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
			local ok, err = pcall(play, h)
			if not ok then
				warn("[Hatch] cinematic failed:", err)
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
	clearStage()
	setVisible(false)
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
	gui.IgnoreGuiInset = true -- cover the top bar too, so the flash and backdrop are full-screen
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

	-- Spin rays and breathe the glow while the cinematic is up.
	RunService.RenderStepped:Connect(function(dt)
		if not gui.Enabled then
			return
		end
		rayBase += raySpeed * dt
		for i, ray in screen.rays do
			ray.Rotation = rayBase + (i - 1) * (360 / #screen.rays)
		end
		local pulse = 1 + glowPulse * math.sin(os.clock() * 5)
		for i, g in screen.glow do
			local size = (180 + i * 70) * pulse
			g.Size = UDim2.fromOffset(size, size)
		end
	end)
end

function HatchController.Start()
	-- Parent here, not in Init (Init must not yield).
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	HatchController.rescale()
	Remotes.get("Harvested").OnClientEvent:Connect(onHarvested)
	Remotes.get("Mutated").OnClientEvent:Connect(onMutated)
end

return HatchController
