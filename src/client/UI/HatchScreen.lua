--!strict
-- Builds the full-screen hatch cinematic (plain Instances, animated by HatchController):
-- dark backdrop, rarity glow, spinning light rays, the egg/mutant in a 3D window, 2D confetti,
-- reveal text, Skip buttons, a tap-anywhere catcher and a white flash on top of everything.
-- Layout is on the same 900x540 design canvas as the HUD; the caller scales `root`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)

local HatchScreen = {}

export type Screen = {
	root: Frame,
	backdrop: Frame,
	glow: { Frame },
	rays: { Frame },
	viewport: ViewportFrame,
	camera: Camera,
	confetti: Frame,
	title: TextLabel,
	titleGradient: UIGradient,
	titleScale: UIScale,
	value: TextLabel,
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

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = if radius then UDim.new(0, radius) else UDim.new(1, 0)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, border: boolean?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
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
	stroke(t, Theme.colors.slate, props.Stroke or 3)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = props.Max or 40
	limit.Parent = t
	return t
end

local function button(name: string, label: string, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = true
	b.Font = Theme.font
	b.TextScaled = true
	b.Text = label
	b.TextColor3 = Theme.colors.white
	b.BackgroundColor3 = Theme.colors.slateLight
	b.BackgroundTransparency = 0.1
	for k, v in props do
		(b :: any)[k] = v
	end
	corner(b, 14)
	stroke(b, Theme.colors.slate, 3, true)
	local inner = Instance.new("UIStroke")
	inner.Color = Theme.colors.slate
	inner.Thickness = 2
	inner.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = b
	return b
end

function HatchScreen.new(): Screen
	local root = frame({ Name = "HatchRoot", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })

	local backdrop = frame({
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 1,
		Parent = root,
	})
	local backGradient = Instance.new("UIGradient")
	backGradient.Rotation = 90
	backGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("#2A1E4A")),
		ColorSequenceKeypoint.new(0.55, Color3.fromHex("#140F24")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("#0B0814")),
	})
	backGradient.Parent = backdrop

	-- Soft rarity glow: stacked circles, faintest outermost.
	local glow = {}
	for i = 1, 6 do
		local size = 180 + i * 70
		local g = frame({
			Name = "Glow" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 10),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Theme.colors.white,
			BackgroundTransparency = 0.78 + i * 0.03,
			ZIndex = 2,
			Parent = root,
		})
		corner(g)
		glow[i] = g
	end

	-- Light rays: each is a long bar centered on the screen center (GUI rotation is around an
	-- object's own center), with only its outer half lit and fading toward the tip.
	local rays = {}
	for i = 1, 14 do
		local holder = frame({
			Name = "Ray" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 10),
			Size = UDim2.fromOffset(if i % 2 == 0 then 54 else 34, 1300),
			BackgroundTransparency = 1,
			Rotation = (i - 1) * (360 / 14),
			ZIndex = 2,
			Parent = root,
		})
		local beam = frame({
			Name = "Beam",
			Size = UDim2.fromScale(1, 0.5),
			BackgroundColor3 = Theme.colors.white,
			BackgroundTransparency = 0,
			ZIndex = 2,
			Parent = holder,
		})
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.55, 0.82),
			NumberSequenceKeypoint.new(1, 0.55),
		})
		fade.Parent = beam
		rays[i] = holder
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Stage"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.new(0.5, 0, 0.5, 10)
	viewport.Size = UDim2.fromOffset(310, 310)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(205, 200, 215)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-0.4, -1, 0.7)
	viewport.ZIndex = 4
	viewport.Parent = root
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	camera.Parent = viewport
	viewport.CurrentCamera = camera

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
	corner(newRibbon, 12)
	stroke(newRibbon, Theme.colors.slate, 3, true)
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
		Position = UDim2.new(0.5, 0, 1, -76),
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
		Position = UDim2.new(0.5, 0, 1, -42),
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
		Position = UDim2.new(0.5, 0, 1, -10),
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
		backdrop = backdrop,
		glow = glow,
		rays = rays,
		viewport = viewport,
		camera = camera,
		confetti = confetti,
		title = title,
		titleGradient = titleGradient,
		titleScale = titleScale,
		value = value,
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
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = chip.color,
			ZIndex = 7,
			Parent = screen.chips,
		})
		corner(f)
		stroke(f, Theme.colors.slate, 2.5, true)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 14)
		pad.PaddingRight = UDim.new(0, 14)
		pad.Parent = f
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AutomaticSize = Enum.AutomaticSize.X
		t.Size = UDim2.fromScale(0, 1)
		t.Font = Theme.font
		t.TextSize = 19
		t.TextColor3 = Theme.colors.white
		t.Text = chip.text
		t.ZIndex = 8
		stroke(t, Theme.colors.slate, 2)
		t.Parent = f
	end
end

-- Tints rays and glow for a rarity.
function HatchScreen.setColor(screen: Screen, color: Color3)
	for _, g in screen.glow do
		g.BackgroundColor3 = color
	end
	for _, ray in screen.rays do
		(ray:FindFirstChild("Beam") :: Frame).BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
	end
end

local _ = ReplicatedStorage
return HatchScreen
