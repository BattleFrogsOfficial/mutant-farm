--!strict
-- Live 3D previews in the UI (egg shop cards, hotbar, almanac, sell list). Builds a model,
-- frames it with a camera, and optionally spins it. Silhouette mode renders it pitch black
-- for undiscovered almanac entries and locked eggs.

local RunService = game:GetService("RunService")

local Viewport = {}

type Spinner = { model: Model, frame: ViewportFrame, speed: number }
local spinners: { Spinner } = {}
local started = false

local function start()
	if started then
		return
	end
	started = true
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for i = #spinners, 1, -1 do
			local s = spinners[i]
			if not s.frame.Parent then
				table.remove(spinners, i)
			elseif s.frame.Visible then
				s.model:PivotTo(CFrame.Angles(0, math.sin(t * s.speed) * 0.6, 0))
			end
		end
	end)
end

-- props: Build (() -> Model), Spin (bool), Silhouette (bool), Size, Position, AnchorPoint, ZIndex, Name
function Viewport.new(props: { [string]: any }): ViewportFrame
	local frame = Instance.new("ViewportFrame")
	frame.Name = props.Name or "Viewport"
	frame.BackgroundTransparency = 1
	frame.Size = props.Size or UDim2.fromScale(1, 1)
	frame.Position = props.Position or UDim2.new()
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.ZIndex = props.ZIndex or 1
	frame.Ambient = Color3.fromRGB(190, 185, 200)
	frame.LightColor = Color3.fromRGB(255, 250, 240)
	frame.LightDirection = Vector3.new(-0.4, -1, 0.6)
	if props.Silhouette then
		frame.ImageColor3 = Color3.new(0, 0, 0)
		frame.ImageTransparency = 0.15
	end

	local model = props.Build() :: Model
	model:PivotTo(CFrame.identity)
	-- Particles and lights don't render in viewports; strip them so they cost nothing.
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
	model.Parent = frame

	local size = model:GetExtentsSize()
	local height = math.max(size.Y, 0.1)
	local extent = math.max(size.Y, size.X * 0.9, 0.1)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local distance = extent * 0.62 / math.tan(math.rad(15))
	local focus = Vector3.new(0, height * 0.5, 0)
	-- Models face -Z, so look at them from the -Z side, slightly above.
	camera.CFrame = CFrame.lookAt(focus + Vector3.new(0, extent * 0.12, -distance), focus)
	camera.Parent = frame
	frame.CurrentCamera = camera

	if props.Spin then
		start()
		table.insert(spinners, { model = model, frame = frame, speed = props.SpinSpeed or 0.9 })
	end
	return frame
end

return Viewport
