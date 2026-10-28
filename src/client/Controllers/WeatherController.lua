--!strict
-- Draws the server's weather event (State.weather, from Workspace attributes): colored drops falling
-- around the camera and a light tint. Paused during the hatch cutscene (it has its own lighting).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Weather = require(ReplicatedStorage.Shared.Config.Weather)
local State = require(script.Parent.Parent.State)

local WeatherController = {}

local cloud: Part
local drops: ParticleEmitter
local tint: ColorCorrectionEffect
local current = ""

local function apply(eventId: string)
	current = eventId
	local event = (Weather.events :: any)[eventId]
	if not event then
		drops.Enabled = false
		tint.Enabled = false
		return
	end
	local color = Color3.fromHex(event.color)
	drops.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	drops.Enabled = true
	tint.TintColor = Color3.new(1, 1, 1):Lerp(color, 0.18)
	tint.Enabled = true
end

function WeatherController.Init()
	cloud = Instance.new("Part")
	cloud.Name = "WeatherCloud"
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	cloud.Transparency = 1
	cloud.Size = Vector3.new(120, 1, 120)
	drops = Instance.new("ParticleEmitter")
	drops.Enabled = false
	drops.Rate = 260
	drops.Lifetime = NumberRange.new(1.4, 1.8)
	drops.Speed = NumberRange.new(45, 55)
	drops.EmissionDirection = Enum.NormalId.Bottom
	drops.SpreadAngle = Vector2.new(4, 4)
	drops.LightEmission = 0.3
	drops.Transparency = NumberSequence.new(0.25)
	drops.Size = NumberSequence.new(0.14)
	drops.Squash = NumberSequence.new(-3) -- stretched into streaks
	drops.Parent = cloud
	tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "WeatherTint"
	tint.Enabled = false
end

function WeatherController.Start()
	cloud.Parent = workspace
	tint.Parent = Lighting
	RunService.Heartbeat:Connect(function()
		local w = State.weather:get(false)
		local active = w.id ~= "" and workspace:GetServerTimeNow() < w.endsAt and not State.hatching:get(false)
		local want = if active then w.id else ""
		if want ~= current then
			apply(want)
		end
		if active then
			local cam = workspace.CurrentCamera.CFrame.Position
			cloud.CFrame = CFrame.new(cam.X, cam.Y + 40, cam.Z)
		end
	end)
end

return WeatherController
