-- World UI on your own plot, drawn flat so the checks (tools/preview/checks/world.js) can see it:
--   * the soil marker (UI/SoilMarker) on a patch: "+" still, "+" mid-pulse, and the price, each at
--     the size a patch has on a phone (Config/WorldUI.soil.phonePatchPx) and as read from the gate;
--   * the egg timer (UI/SlotTimer) at its real pixel size (a BillboardGui is fixed px on every
--     screen): ready, growing, growing + watered (the "2x" chip);
--   * the gate's income line (shared/GateSign) on a board like World's IncomeBoard, at its
--     SurfaceGui canvas size (40 px per stud), before the first harvest and after.
-- Rendered only at the phone size (844x390): the scene name ends in @844x390.

local PHONE_W, PHONE_H, TOPBAR = 844, 390, 58

return function(api)
	local Instance, roblox = api.Instance, api.roblox
	local UDim2, Color3 = roblox.UDim2, roblox.Color3
	local Shared = api.Shared
	local WorldUI = api.requireModule(Shared.Config.WorldUI)
	local HudScale = api.requireModule(Shared.HudScale)
	local GateSign = api.requireModule(Shared.GateSign)
	local SoilMarker = api.requireModule(api.UI.SoilMarker)
	local SlotTimer = api.requireModule(api.UI.SlotTimer)

	-- ui-render draws everything at the HUD scale; these things don't scale with the HUD, so each
	-- gets a UIScale that undoes it (1 design px = `screenPx` screen px).
	local hudScale = HudScale.of(PHONE_W, PHONE_H - TOPBAR, false)
	local function box(name, parent, x, y, w, h, screenPerPx)
		local f = Instance.new("Frame")
		f.Name = name
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(w, h)
		f.BackgroundTransparency = 1
		local s = Instance.new("UIScale")
		s.Scale = screenPerPx / hudScale
		s.Parent = f
		f.Parent = parent
		return f
	end

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	local function label(text, x, y)
		local l = Instance.new("TextLabel")
		l.Name = "Caption"
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(x, y)
		l.Size = UDim2.fromOffset(480, 24)
		l.Font = roblox.Enum.Font.GothamBold
		l.TextSize = 18
		l.TextXAlignment = roblox.Enum.TextXAlignment.Left
		l.TextColor3 = Color3.new(0.1, 0.1, 0.1)
		l.Text = text
		l.Parent = root
	end

	-- Soil markers: the patch canvas (pixelsPerStud x 3.6 studs) drawn phonePatchPx wide.
	local canvas = SoilMarker.canvasPx(3.6)
	local patchScale = WorldUI.soil.phonePatchPx / canvas
	local patchStep = math.ceil(WorldUI.soil.phonePatchPx / hudScale) + 60
	local soilCases = {
		{ "Plus", "plus", nil, 1, Color3.fromHex("#5B3A24"), 0 },
		{ "PlusPulse", "plus", nil, 1 + WorldUI.soil.pulseAmount, Color3.fromHex("#5B3A24"), 0 },
		{ "Price", "price", "$675", 1, Color3.fromHex("#7CFF4A"), 0.3 },
		{ "PriceLong", "price", "$99.9K", 1, Color3.fromHex("#7CFF4A"), 0.3 },
	}
	label("SOIL (phone size, from the gate)", 40, 20)
	for i, case in soilCases do
		local name, kind, price, pulse, color, transparency = table.unpack(case)
		local patch = box("Patch" .. name, root, 40 + (i - 1) * patchStep, 60, canvas, canvas, patchScale)
		patch.BackgroundTransparency = transparency
		patch.BackgroundColor3 = color
		local marker = SoilMarker.new()
		SoilMarker.set(marker, kind, price, pulse)
		-- Drawn as the player reads it from the gate side (in the world the Top face's canvas is
		-- upside down from there, so the tile is turned by WorldUI.soil.rotation).
		marker.holder.Rotation = 0
		marker.root.Parent = patch
	end

	-- Timers at their real pixel size.
	local timerY = 60 + math.ceil(WorldUI.soil.phonePatchPx / hudScale) + 70
	local timerStep = math.ceil(SlotTimer.SIZE.X / hudScale) + 60
	label("TIMERS (real px)", 40, timerY - 40)
	local timerCases = {
		{ "Ready", 1, true, false, "" },
		{ "Growing", 0.4, false, false, "2m 05s" },
		{ "Watered", 0.6, false, true, "1m 02s" },
		{ "WateredLong", 0.1, false, true, "7h 59m" },
	}
	for i, case in timerCases do
		local name, progress, ready, watered, text = table.unpack(case)
		local holder =
			box("Timer" .. name, root, 40 + (i - 1) * timerStep, timerY, SlotTimer.SIZE.X, SlotTimer.SIZE.Y, 1)
		local timer = SlotTimer.new()
		SlotTimer.set(timer, progress, ready, watered, text)
		timer.root.Parent = holder
	end

	-- The gate's income line on a board like World's IncomeBoard (7.5 x 1.5 studs at 40 px/stud,
	-- FredokaOne, padded 5% / 10%), at canvas size, scaled down to fit the phone canvas.
	local gateY = timerY + math.ceil(SlotTimer.SIZE.Y / hudScale) + 70
	label("GATE SIGN (canvas px)", 40, gateY - 40)
	for i, case in { { "GateNew", 0, 0 }, { "GateIncome", 3_400, 3 } } do
		local name, income, harvested = table.unpack(case)
		local board = box(name, root, 40 + (i - 1) * 560, gateY, 300, 60, 1)
		board.BackgroundTransparency = 0
		board.BackgroundColor3 = Color3.fromHex("#1E2230")
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Font = roblox.Enum.Font.FredokaOne
		text.TextScaled = true
		text.TextColor3 = Color3.fromHex("#7CFF4A")
		text.Text = GateSign.incomeText(income, harvested)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = Color3.fromHex("#1E2230")
		stroke.Parent = text
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = roblox.UDim.new(0.05, 0)
		pad.PaddingRight = roblox.UDim.new(0.05, 0)
		pad.PaddingTop = roblox.UDim.new(0.1, 0)
		pad.PaddingBottom = roblox.UDim.new(0.1, 0)
		pad.Parent = text
		text.Parent = board
	end

	api.setRoot(root)
	api.capture(string.format("world@%dx%d", PHONE_W, PHONE_H))
	api.restoreRoot()
	api.reset()
end
