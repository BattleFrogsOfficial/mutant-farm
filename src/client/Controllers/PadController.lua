--!strict
-- Makes standing on your own water pad feel like something (Config/WorldUI.padFx): a water-blue
-- vignette round the screen edges that fades in and breathes slowly, a light blue colour tint
-- and a small camera push-in while you stand there, and a splash when you step on (a ring rolling
-- out over the pad, a burst of bubbles, the water sound). Everything fades out when you step off,
-- and hides while the hatch cutscene runs. Only the owner sees it (their plot's OnPad attribute,
-- written by the server's pad check). The vignette is four edge bands with gradients, no images.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local WorldUI = require(Shared.Config.WorldUI)
local State = require(script.Parent.Parent.State)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Parent.UI.Theme)
local PlotController = require(script.Parent.PlotController)

local PadController = {}

local FX = WorldUI.padFx
local player = Players.LocalPlayer

-- 0 = off, 1 = fully on; eased toward the target every frame.
local level = 0
local onPad = false
local bands: { { frame: Frame, gradient: UIGradient } } = {}
local tint: ColorCorrectionEffect? = nil
local baseFov: number? = nil

local function buildVignette()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PadVignette"
	gui.IgnoreGuiInset = true -- edge to edge, like the backdrop
	gui.DisplayOrder = -1 -- under the HUD
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local color = Color3.fromHex(FX.vignette.color)
	-- Each band: anchored to one edge, its gradient opaque at the edge and clear inward.
	local specs = {
		{ anchor = Vector2.new(0.5, 0), pos = UDim2.fromScale(0.5, 0), rot = 90, horizontal = true },
		{ anchor = Vector2.new(0.5, 1), pos = UDim2.fromScale(0.5, 1), rot = -90, horizontal = true },
		{ anchor = Vector2.new(0, 0.5), pos = UDim2.fromScale(0, 0.5), rot = 0, horizontal = false },
		{ anchor = Vector2.new(1, 0.5), pos = UDim2.fromScale(1, 0.5), rot = 180, horizontal = false },
	}
	for _, spec in specs do
		local frame = Instance.new("Frame")
		frame.Name = "Band"
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = color
		frame.AnchorPoint = spec.anchor
		frame.Position = spec.pos
		frame.Size = if spec.horizontal
			then UDim2.new(1, 0, FX.vignette.edge, 0)
			else UDim2.new(FX.vignette.edge, 0, 1, 0)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec.rot
		gradient.Parent = frame
		frame.Parent = gui
		table.insert(bands, { frame = frame, gradient = gradient })
	end
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

local function setVignette(gui: ScreenGui, amount: number, t: number)
	gui.Enabled = amount > 0.001
	if not gui.Enabled then
		return
	end
	local v = FX.vignette
	local opacity = v.opacity + v.breathe * math.sin(t * 2 * math.pi / v.breathePeriod)
	local edge = 1 - opacity * amount -- transparency at the screen edge
	local seq = NumberSequence.new({
		NumberSequenceKeypoint.new(0, edge),
		NumberSequenceKeypoint.new(0.55, 1 - (1 - edge) * 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	for _, band in bands do
		band.gradient.Transparency = seq
	end
end

local function setTint(amount: number)
	if not tint then
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "PadTint"
		c.Parent = Lighting
		tint = c
	end
	local c = tint :: ColorCorrectionEffect
	c.Enabled = amount > 0.001
	c.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromHex(FX.tint.color), amount)
	c.Saturation = FX.tint.saturation * amount
	c.Brightness = FX.tint.brightness * amount
end

local function setFov(amount: number)
	local camera = workspace.CurrentCamera
	if not camera or camera.CameraType == Enum.CameraType.Scriptable then
		return -- the hatch cutscene owns the camera
	end
	if amount <= 0.001 then
		if baseFov then
			camera.FieldOfView = baseFov
			baseFov = nil
		end
		return
	end
	baseFov = baseFov or camera.FieldOfView
	camera.FieldOfView = (baseFov :: number) - FX.fovPush * amount
end

-- The splash on stepping on: a flat ring rolling out over the pad and a burst of bubbles.
local function splash(pad: BasePart)
	local cfg = FX.splash
	Sfx.play("water", cfg.volume, cfg.pitch)
	local top = pad.Position + Vector3.new(0, pad.Size.X / 2 + 0.05, 0)
	local ring = Instance.new("Part")
	ring.Name = "PadSplash"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Glass
	ring.Color = Theme.colors.water:Lerp(Color3.new(1, 1, 1), 0.35)
	ring.Parent = workspace
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < cfg.ringSeconds do
			local k = (os.clock() - t0) / cfg.ringSeconds
			local d = 1 + (cfg.ringRadius * 2 - 1) * (1 - (1 - k) ^ 2)
			ring.Size = Vector3.new(0.08, d, d)
			ring.CFrame = CFrame.new(top) * CFrame.Angles(0, 0, math.rad(90))
			ring.Transparency = 0.35 + 0.65 * k
			task.wait()
		end
		ring:Destroy()
	end)
	-- The burst: small glass balls hopping up and out, then fading (the pad's own bubbles keep
	-- rising while you stand there).
	local radius = ((pad:GetAttribute("Radius") or 2) :: number) * 0.7
	for _ = 1, cfg.burst do
		local a = math.random() * math.pi * 2
		local size = 0.25 + math.random() * 0.3
		local b = Instance.new("Part")
		b.Name = "PadSplashBubble"
		b.Shape = Enum.PartType.Ball
		b.Size = Vector3.one * size
		b.Material = Enum.Material.Glass
		b.Color = Theme.colors.water:Lerp(Color3.new(1, 1, 1), 0.45)
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CastShadow = false
		b.Parent = workspace
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local start = top + dir * (math.random() * radius)
		local up, out = 3 + math.random() * 2, 1.5 + math.random() * 1.5
		task.spawn(function()
			local t0 = os.clock()
			local life = 0.8
			while os.clock() - t0 < life do
				local t = os.clock() - t0
				b.CFrame = CFrame.new(start + dir * out * t + Vector3.new(0, up * t - 4.5 * t * t, 0))
				b.Transparency = 0.3 + 0.7 * (t / life)
				task.wait()
			end
			b:Destroy()
		end)
	end
end

local function padPart(plot: Model): BasePart?
	local m = plot:FindFirstChild("WaterPad")
	return if m and m:IsA("Model") then m.PrimaryPart else nil
end

function PadController.Init() end

function PadController.Start()
	local gui = buildVignette()
	RunService.RenderStepped:Connect(function(dt)
		local plot = PlotController.myPlot()
		local now = plot ~= nil and plot:GetAttribute("OnPad") == true
		if now ~= onPad then
			onPad = now
			local pad = plot and padPart(plot)
			if now and pad then
				splash(pad)
			end
		end
		local target = if onPad and not State.hatching:get(false) then 1 else 0
		local rate = if target > level then 1 / FX.fadeIn else 1 / FX.fadeOut
		level = if target > level then math.min(target, level + rate * dt) else math.max(target, level - rate * dt)
		local eased = level * level * (3 - 2 * level)
		setVignette(gui, eased, os.clock())
		setTint(eased)
		setFov(eased)
	end)
end

return PadController
