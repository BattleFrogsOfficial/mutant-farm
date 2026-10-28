--!strict
-- Draws the server's weather event (State.weather, from Workspace attributes): colored drops falling
-- around the camera and a light tint. Paused during the hatch cutscene (it has its own lighting).
-- Also Instant Weather (a player's PlotWeatherId / PlotWeatherEndsAt attributes): colored rain and,
-- for Glitch Storm, static over that island only, under a small cloud everyone can see; the owner
-- also gets the tint while standing on their plot. State.plotWeather mirrors your own.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Weather = require(ReplicatedStorage.Shared.Config.Weather)
local State = require(script.Parent.Parent.State)

local WeatherController = {}

-- Instant Weather visuals per player: { id, model } while their plot event runs.
local plotVisuals: { [number]: { id: string, model: Model } } = {}
local plotTint: ColorCorrectionEffect

local function plotOf(userId: number): Model?
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:IsA("Model") and plot:GetAttribute("OwnerUserId") == userId then
			return plot
		end
	end
	return nil
end

-- A small grey cloud over the island with rain (and static for Glitch Storm) falling on it only.
local function buildPlotWeather(plot: Model, eventId: string): Model?
	local event = (Weather.events :: any)[eventId]
	local base = plot.PrimaryPart
	if not event or not base then
		return nil
	end
	local color = Color3.fromHex(event.color)
	local m = Instance.new("Model")
	m.Name = "PlotWeather"
	local center = base.Position + Vector3.new(0, 26, 0)
	for k, offset in
		{ Vector3.new(-3, 0, 0), Vector3.new(2.5, 0.8, 1), Vector3.new(0, 1.6, -1.5), Vector3.new(5, 0, -1) }
	do
		local puff = Instance.new("Part")
		puff.Name = "Cloud"
		puff.Shape = Enum.PartType.Ball
		puff.Size = Vector3.new(7, 7, 7) * (if k == 3 then 1.2 else 1)
		puff.Anchored = true
		puff.CanCollide = false
		puff.CanQuery = false
		puff.CanTouch = false
		puff.Material = Enum.Material.SmoothPlastic
		puff.Color = Color3.fromHex("#8C8FA3"):Lerp(color, 0.15)
		puff.CFrame = CFrame.new(center + offset)
		puff.Parent = m
	end
	-- The rain sheet: an invisible part the island's size under the cloud.
	local sheet = Instance.new("Part")
	sheet.Name = "RainSheet"
	sheet.Anchored = true
	sheet.CanCollide = false
	sheet.CanQuery = false
	sheet.CanTouch = false
	sheet.Transparency = 1
	sheet.Size = Vector3.new(base.Size.X, 1, base.Size.Z)
	sheet.CFrame = CFrame.new(base.Position + Vector3.new(0, 22, 0))
	sheet.Parent = m
	local rain = Instance.new("ParticleEmitter")
	rain.Rate = 160
	rain.Lifetime = NumberRange.new(0.9, 1.1)
	rain.Speed = NumberRange.new(24, 28)
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.SpreadAngle = Vector2.new(3, 3)
	rain.LightEmission = 0.3
	rain.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	rain.Transparency = NumberSequence.new(0.25)
	rain.Size = NumberSequence.new(0.16)
	rain.Squash = NumberSequence.new(-3)
	rain.Parent = sheet
	if eventId == "GlitchStorm" then
		local static = Instance.new("ParticleEmitter")
		static.Rate = 40
		static.Lifetime = NumberRange.new(0.2, 0.4)
		static.Speed = NumberRange.new(0, 2)
		static.EmissionDirection = Enum.NormalId.Bottom
		static.Color = ColorSequence.new(color, Color3.fromHex("#00F0FF"))
		static.Size = NumberSequence.new(0.6)
		static.LightEmission = 0.4
		static.Parent = sheet
	end
	m.Parent = workspace
	return m
end

local function updatePlotWeather()
	local now = workspace:GetServerTimeNow()
	local seen = {}
	for _, player in Players:GetPlayers() do
		local id = player:GetAttribute("PlotWeatherId") :: string?
		local endsAt = (player:GetAttribute("PlotWeatherEndsAt") or 0) :: number
		local active = id ~= nil and now < endsAt and not State.hatching:get(false)
		if player == Players.LocalPlayer then
			local mine = State.plotWeather:get(false)
			local want = if id and now < endsAt then { id = id, endsAt = endsAt } else { id = "", endsAt = 0 }
			if mine.id ~= want.id or mine.endsAt ~= want.endsAt then
				State.plotWeather:set(want)
			end
			local event = active and (Weather.events :: any)[id]
			plotTint.Enabled = event ~= nil and State.zone:get(false) == "plot"
			if event then
				plotTint.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromHex(event.color), 0.18)
			end
		end
		local v = plotVisuals[player.UserId]
		if active then
			seen[player.UserId] = true
			if not v or v.id ~= id then
				if v then
					v.model:Destroy()
				end
				local plot = plotOf(player.UserId)
				local model = plot and buildPlotWeather(plot, id :: string)
				plotVisuals[player.UserId] = if model then { id = id :: string, model = model } else nil
			end
		end
	end
	for userId, v in plotVisuals do
		if not seen[userId] then
			v.model:Destroy()
			plotVisuals[userId] = nil
		end
	end
end

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
	plotTint = Instance.new("ColorCorrectionEffect")
	plotTint.Name = "PlotWeatherTint"
	plotTint.Enabled = false
end

function WeatherController.Start()
	cloud.Parent = workspace
	tint.Parent = Lighting
	plotTint.Parent = Lighting
	task.spawn(function()
		while true do
			updatePlotWeather()
			task.wait(0.25)
		end
	end)
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
