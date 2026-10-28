--!strict
-- Builds the hatch cutscene's overlay (plain Instances, animated by HatchController). The scene
-- itself is 3D (the swamp island); this adds top/bottom shades so text reads, 2D confetti, reveal
-- text, Skip buttons, a tap-anywhere catcher and a full-screen flash on top of everything.
-- Layout is on the same 900x540 design canvas as the HUD; the caller scales `root`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)

local HatchScreen = {}

export type Screen = {
	root: Frame,
	shades: { Frame },
	confetti: Frame,
	title: TextLabel,
	titleGradient: UIGradient,
	titleScale: UIScale,
	value: TextLabel,
	valueScale: UIScale,
	fast: TextButton,
	potion: TextButton,
	newRibbon: Frame,
	name: TextLabel,
	chips: Frame,
	hint: TextLabel,
	skip: TextButton,
	skipAll: TextButton,
	queue: TextLabel,
	tap: TextButton,
	flash: Frame,
}

local function frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	return f
end

local function stroke(parent: Instance, color: Color3, thickness: number, border: boolean?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Miter
	if border then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	s.Parent = parent
end

local function text(props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Theme.font
	t.TextScaled = true
	t.TextColor3 = Theme.colors.white
	for k, v in props do
		if k ~= "Stroke" and k ~= "Max" then
			(t :: any)[k] = v
		end
	end
	stroke(t, Theme.colors.ink, props.Stroke or 3)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = props.Max or 40
	limit.Parent = t
	return t
end

local function button(name: string, label: string, props: { [string]: any }): TextButton
	-- The button's own Text stays empty: children draw above their parent, so the bevel and lip
	-- would cover it. The label is a child on top of them instead.
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = true
	b.Text = ""
	b.BackgroundColor3 = Theme.colors.panelHi
	b.BorderSizePixel = 0
	for k, v in props do
		(b :: any)[k] = v
	end
	-- Boxy: ink outline, a light bevel on top and a dark lip along the bottom.
	stroke(b, Theme.colors.ink, 3, true)
	frame({
		Name = "Bevel",
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.75,
		ZIndex = b.ZIndex,
		Parent = b,
	})
	frame({
		Name = "Lip",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = Theme.colors.ink,
		BackgroundTransparency = 0.35,
		ZIndex = b.ZIndex,
		Parent = b,
	})
	text({
		Name = "Label",
		Text = label,
		Position = UDim2.fromOffset(8, 7),
		Size = UDim2.new(1, -16, 1, -18),
		Max = 26,
		Stroke = 2,
		ZIndex = b.ZIndex + 1,
		Parent = b,
	})
	return b
end

function HatchScreen.new(): Screen
	local root = frame({ Name = "HatchRoot", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })

	-- Soft dark fades at the top and bottom so the text reads over the 3D scene.
	local function shade(name: string, anchorY: number, rotation: number)
		local f = frame({
			Name = name,
			AnchorPoint = Vector2.new(0, anchorY),
			Position = UDim2.fromScale(0, anchorY),
			Size = UDim2.new(1, 0, 0.3, 0),
			BackgroundColor3 = Color3.fromHex("#0B0814"),
			ZIndex = 1,
			Parent = root,
		})
		local g = Instance.new("UIGradient")
		g.Rotation = rotation
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		return f
	end
	local shades = { shade("TopShade", 0, 90), shade("BottomShade", 1, -90) }

	local confetti = frame({
		Name = "Confetti",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = root,
	})

	local title = text({
		Name = "Rarity",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 18),
		Size = UDim2.fromOffset(540, 64),
		Text = "",
		Max = 60,
		Stroke = 5,
		ZIndex = 7,
		Parent = root,
	})
	local titleGradient = Instance.new("UIGradient")
	titleGradient.Rotation = 90
	titleGradient.Parent = title
	local titleScale = Instance.new("UIScale")
	titleScale.Parent = title

	local value = text({
		Name = "Value",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.fromOffset(420, 34),
		Text = "",
		TextColor3 = Theme.colors.toxic,
		Max = 32,
		ZIndex = 7,
		Parent = root,
	})

	local valueScale = Instance.new("UIScale")
	valueScale.Parent = value

	local newRibbon = frame({
		Name = "New",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, -150, 0.5, -120),
		Size = UDim2.fromOffset(150, 40),
		BackgroundColor3 = Theme.colors.toxic,
		Rotation = -14,
		Visible = false,
		ZIndex = 8,
		Parent = root,
	})
	stroke(newRibbon, Theme.colors.ink, 3, true)
	text({
		Text = "NEW!",
		Size = UDim2.new(1, -12, 1, -8),
		Position = UDim2.fromOffset(6, 4),
		Max = 28,
		ZIndex = 9,
		Parent = newRibbon,
	})

	local name = text({
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -112),
		Size = UDim2.fromOffset(640, 52),
		Text = "",
		Max = 48,
		Stroke = 4,
		ZIndex = 7,
		Parent = root,
	})

	local chips = frame({
		Name = "Chips",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -76),
		Size = UDim2.fromOffset(700, 30),
		BackgroundTransparency = 1,
		ZIndex = 7,
		Parent = root,
	})
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	chipLayout.Padding = UDim.new(0, 8)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chips

	local hint = text({
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		-- Kept well above the bottom edge: phones' home indicator and the chat bar live there.
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(360, 26),
		Text = "Tap anywhere to continue",
		TextColor3 = Theme.colors.cream,
		Max = 20,
		Stroke = 2,
		ZIndex = 7,
		Parent = root,
	})

	local tap = Instance.new("TextButton")
	tap.Name = "TapCatcher"
	tap.Text = ""
	tap.BackgroundTransparency = 1
	tap.Size = UDim2.fromScale(1, 1)
	tap.ZIndex = 9
	tap.Parent = root

	-- Skip controls sit at the right edge beside the stage, clear of the title and the name.
	local skip = button("Skip", "Skip ⏭", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, -30),
		Size = UDim2.fromOffset(130, 48),
		ZIndex = 10,
		Parent = root,
	})
	-- Veterans (20+ hatches) can turn on Fast Hatch: short cutscene for everything below Epic.
	local fast = button("Fast", "⚡ FAST: OFF", {
		-- In the Skip column (the top-left corner belongs to Roblox's buttons).
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 90),
		Size = UDim2.fromOffset(130, 48),
		ZIndex = 10,
		Visible = false,
		Parent = root,
	})
	-- Luck Potion offer during the reveal, on the left (Skip is on the right). Pink: it spends.
	local potion = button("Potion", "🍀 LUCK x3 · 25 💎", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(190, 52),
		BackgroundColor3 = Theme.colors.spend,
		ZIndex = 10,
		Visible = false,
		Parent = root,
	})
	local skipAll = button("SkipAll", "Skip all", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 30),
		Size = UDim2.fromOffset(130, 48),
		ZIndex = 10,
		Visible = false,
		Parent = root,
	})
	local queue = text({
		Name = "Queue",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, -76),
		Size = UDim2.fromOffset(130, 24),
		Text = "",
		TextColor3 = Theme.colors.cream,
		Max = 18,
		Stroke = 2,
		ZIndex = 10,
		Parent = root,
	})

	local flash = frame({
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = root,
	})

	return {
		root = root,
		shades = shades,
		confetti = confetti,
		title = title,
		titleGradient = titleGradient,
		titleScale = titleScale,
		value = value,
		valueScale = valueScale,
		fast = fast,
		potion = potion,
		newRibbon = newRibbon,
		name = name,
		chips = chips,
		hint = hint,
		skip = skip,
		skipAll = skipAll,
		queue = queue,
		tap = tap,
		flash = flash,
	}
end

-- Replaces the chips under the name.
function HatchScreen.setChips(screen: Screen, chips: { { text: string, color: Color3 } })
	for _, c in screen.chips:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for i, chip in chips do
		local f = frame({
			Name = "Chip" .. i,
			LayoutOrder = i,
			-- Width from the text length (GothamBlack at 18px is ~11px per character).
			Size = UDim2.fromOffset(30 + (utf8.len(chip.text) or #chip.text) * 11, 30),
			BackgroundColor3 = chip.color,
			ZIndex = 7,
			Parent = screen.chips,
		})
		stroke(f, Theme.colors.ink, 2.5, true)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(8, 4)
		t.Size = UDim2.new(1, -16, 1, -8)
		t.Font = Theme.font
		t.TextScaled = true
		t.TextColor3 = Theme.colors.white
		t.Text = chip.text
		t.ZIndex = 8
		stroke(t, Theme.colors.ink, 2)
		t.Parent = f
	end
end

local _ = ReplicatedStorage
return HatchScreen
