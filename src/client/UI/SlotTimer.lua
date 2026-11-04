--!strict
-- The timer over a growing egg on your own plot (PlotController puts it in a BillboardGui): a
-- progress bar with the time left, gold "HATCH!" when ready, and a water-blue chip with the
-- watering multiplier ("2x" on the water pad, "7x" during a growth boost) above the bar's right end. Plain Instances (updated 20x a second, no Fusion),
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

-- Room for the outlines, which are drawn outside each face (a BillboardGui clips its descendants).
local PAD = CFG.outline
local CHIP_SHADOW = math.max(CFG.chipShadow, CFG.outline)

-- Pixel size of the whole timer: the bar, the chip above it, and every outline.
SlotTimer.SIZE = Vector2.new(CFG.width + 2 * PAD, PAD + CFG.chipHeight + CFG.chipGap + PAD + CFG.barHeight + PAD)

-- BillboardGui.SizeOffset that keeps the bar's center (not the whole box's) at the adornee's
-- StudsOffset: the box is shifted up by the room the chip takes above the bar.
SlotTimer.SIZE_OFFSET = Vector2.new(0, (SlotTimer.SIZE.Y / 2 - PAD - CFG.barHeight / 2) / SlotTimer.SIZE.Y)

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
	stroke(text, CFG.textStroke, false)
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
	bar.Position = UDim2.new(0, PAD, 1, -PAD)
	bar.Size = UDim2.new(1, -2 * PAD, 0, CFG.barHeight)
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

	-- Multiplier chip ("2x", "10x"): boxy water-blue tile with an ink outline and a hard shadow, above the bar's end.
	-- The frame is the face; its outline (top/left) and shadow (right/bottom) end at the gui's edge.
	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.AnchorPoint = Vector2.new(1, 0)
	chip.Position = UDim2.new(1, -CHIP_SHADOW, 0, PAD)
	chip.Size = UDim2.fromOffset(CFG.chipWidth - CHIP_SHADOW, CFG.chipHeight - CHIP_SHADOW)
	chip.BackgroundTransparency = 1
	chip.Visible = false
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BorderSizePixel = 0
	shadow.BackgroundColor3 = Theme.colors.ink
	shadow.Position = UDim2.fromOffset(CFG.chipShadow, CFG.chipShadow)
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
	chipText.Text = "2x"
	local inset = CFG.chipTextInset
	chipText.Size = UDim2.new(1, -2 * inset[1], 1, -2 * inset[2])
	chipText.Position = UDim2.fromOffset(inset[1], inset[2])
	chip.Parent = root

	return { root = root, bar = bar, fill = fill, text = text, chip = chip }
end

-- "2x", "1.5x", "3.3x", "23x" (one decimal under 10, a trailing .0 dropped).
function SlotTimer.multiplierText(m: number): string
	if m >= 10 then
		return string.format("%dx", math.floor(m + 0.5))
	end
	local r = math.floor(m * 10 + 0.5) / 10
	return (if r == math.floor(r) then tostring(math.floor(r)) else string.format("%.1f", r)) .. "x"
end

-- progress 0..1; ready = gold "HATCH!"; a total speed `multiplier` above 1 (the pass, upgrades,
-- the pad, a boost) = its chip ("2x", "3x") and a water-blue bar and time; none at 1x.
function SlotTimer.set(timer: Timer, progress: number, ready: boolean, multiplier: number, timeText: string)
	local fast = multiplier > 1 + 1e-6
	timer.fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	if ready then
		timer.fill.BackgroundColor3 = Theme.colors.gold
		timer.text.Text = "HATCH!"
		timer.text.TextColor3 = Theme.colors.white
	else
		timer.fill.BackgroundColor3 = if fast then Theme.colors.water else Theme.colors.toxic
		timer.text.Text = timeText
		timer.text.TextColor3 = if fast then Theme.colors.water else Theme.colors.white
	end
	timer.chip.Visible = fast and not ready
	if fast then
		local text = (timer.chip :: any).Face.Text :: TextLabel
		text.Text = SlotTimer.multiplierText(multiplier)
	end
end

return SlotTimer
