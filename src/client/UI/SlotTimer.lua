--!strict
-- The timer over a growing egg on your own plot (PlotController puts it in a BillboardGui): a
-- progress bar with the time left, gold "HATCH!" when ready, and a water-blue "2x" chip above the
-- bar's right end while the plot is watered. Plain Instances (updated 20x a second, no Fusion),
-- built here so the UI preview can draw it. Numbers in Config/WorldUI.timer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldUI = require(ReplicatedStorage.Shared.Config.WorldUI)
local Theme = require(script.Parent.Theme)

local SlotTimer = {}

local CFG = WorldUI.timer

export type Timer = {
	root: Frame,
	bar: Frame,
	fill: Frame,
	text: TextLabel,
	chip: Frame,
}

-- Pixel size of the whole timer (bar plus the room for the chip above it).
SlotTimer.SIZE = Vector2.new(CFG.width, CFG.chipHeight + CFG.chipGap + CFG.barHeight)

local function stroke(parent: Instance, thickness: number, border: boolean)
	local s = Instance.new("UIStroke")
	s.Color = Theme.colors.ink
	s.Thickness = thickness
	if border then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.LineJoinMode = Enum.LineJoinMode.Miter
	end
	s.Parent = parent
end

local function label(name: string, parent: Instance): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Theme.font
	text.TextScaled = true
	text.TextColor3 = Theme.colors.white
	text.Text = ""
	text.ZIndex = 3
	stroke(text, 1.5, false)
	text.Parent = parent
	return text
end

function SlotTimer.new(): Timer
	local root = Instance.new("Frame")
	root.Name = "SlotTimer"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.fromScale(0, 1)
	bar.Size = UDim2.new(1, 0, 0, CFG.barHeight)
	bar.BackgroundColor3 = Theme.colors.slate
	bar.BackgroundTransparency = 0.15
	bar.BorderSizePixel = 0
	stroke(bar, CFG.outline, true)
	bar.Parent = root

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Theme.colors.toxic
	fill.Size = UDim2.fromScale(0, 1)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local text = label("Time", bar)

	-- "2x" chip: boxy water-blue tile with an ink outline and a hard shadow, above the bar's end.
	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.AnchorPoint = Vector2.new(1, 0)
	chip.Position = UDim2.new(1, -2, 0, 0)
	chip.Size = UDim2.fromOffset(CFG.chipWidth - 2, CFG.chipHeight - 2)
	chip.BackgroundTransparency = 1
	chip.Visible = false
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BorderSizePixel = 0
	shadow.BackgroundColor3 = Theme.colors.ink
	shadow.Position = UDim2.fromOffset(2, 2)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.ZIndex = 1
	shadow.Parent = chip
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BorderSizePixel = 0
	face.BackgroundColor3 = Theme.colors.water
	face.Size = UDim2.fromScale(1, 1)
	face.ZIndex = 2
	stroke(face, CFG.outline, true)
	face.Parent = chip
	local chipText = label("Text", face)
	chipText.Text = CFG.chipText
	chipText.Size = UDim2.new(1, -4, 1, -2)
	chipText.Position = UDim2.fromOffset(2, 1)
	chip.Parent = root

	return { root = root, bar = bar, fill = fill, text = text, chip = chip }
end

-- progress 0..1; ready = gold "HATCH!"; watered = the 2x chip and a water-blue fill.
function SlotTimer.set(timer: Timer, progress: number, ready: boolean, watered: boolean, timeText: string)
	timer.fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	if ready then
		timer.fill.BackgroundColor3 = Theme.colors.gold
		timer.text.Text = "HATCH!"
	else
		timer.fill.BackgroundColor3 = if watered then Theme.colors.water else Theme.colors.toxic
		timer.text.Text = timeText
	end
	timer.chip.Visible = watered and not ready
end

return SlotTimer
