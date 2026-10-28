--!strict
-- Decides whether the player is at their plot or in the hub (State.zone), so the HUD shows only
-- what that place needs. Also draws the hub-only "bag worth" sign over the Sell pad.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Format = require(ReplicatedStorage.Shared.Format)
local Valuation = require(ReplicatedStorage.Shared.Valuation)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local PlotController = require(script.Parent.PlotController)

local Observer = Fusion.Observer

local ZoneController = {}

local MARGIN = 6 -- studs past the plot's edge that still count as "at your plot"

local function zoneNow(): string
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local plot = PlotController.myPlot()
	local base = plot and plot.PrimaryPart
	if not root or not base then
		return State.zone:get(false)
	end
	local p = base.CFrame:PointToObjectSpace(root.Position)
	local inside = math.abs(p.X) <= base.Size.X / 2 + MARGIN and math.abs(p.Z) <= base.Size.Z / 2 + MARGIN
	return if inside then "plot" else "hub"
end

-- "🎒 5 · $381K" over the Sell pad, only for you, only while the bag has something in it.
local function bagSign()
	local hub = workspace:WaitForChild("Map"):WaitForChild("Hub")
	local model = hub:WaitForChild("SellPad", 60)
	local pad = model and model:WaitForChild("Pad", 60) :: BasePart?
	if not pad then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "BagWorth"
	gui.Adornee = pad
	gui.Size = UDim2.fromOffset(220, 54)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	local box = Instance.new("Frame")
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundColor3 = Theme.colors.panel
	box.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.colors.ink
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = box
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(8, 6)
	label.Size = UDim2.new(1, -16, 1, -12)
	label.Font = Theme.font
	label.TextScaled = true
	label.TextColor3 = Theme.colors.white
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Theme.colors.ink
	textStroke.Thickness = 2
	textStroke.Parent = label
	label.Parent = box
	box.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local function update()
		local snap = State.snapshot:get(false)
		local n, value = 0, 0
		if snap then
			for _, item in snap.inventory do
				n += 1
				value += Valuation.sellValue(item, snap.cashMultiplier)
			end
		end
		label.Text = string.format("🎒 %d · SELL FOR %s", n, Format.cash(value))
		gui.Enabled = n > 0 and State.zone:get(false) == "hub" and not State.hatching:get(false)
	end
	Observer(State.snapshot):onChange(update)
	Observer(State.zone):onChange(update)
	Observer(State.hatching):onChange(update)
	update()
end

function ZoneController.Init() end

function ZoneController.Start()
	task.spawn(bagSign)
	while true do
		local zone = zoneNow()
		if zone ~= State.zone:get(false) then
			State.zone:set(zone)
		end
		task.wait(0.25)
	end
end

return ZoneController
