--!strict
-- Draws every plot from the attributes the server replicates: eggs growing in the soil (with their
-- mutations showing), timers on your own plot, and each owner's best mutants roaming their pen.
-- Turns clicks on your own soil into Plant / Harvest / BuySlot intents. All visuals are client-only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local Growth = require(Shared.Growth)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local MutantModel = require(Shared.MutantModel)
local State = require(script.Parent.Parent.State)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Parent.UI.Theme)

local PlotController = {}

local player = Players.LocalPlayer
local folder: Folder

type SlotVisual = {
	slot: BasePart,
	plot: Model,
	egg: Model?,
	key: string,
	gui: BillboardGui?,
	fill: Frame?,
	text: TextLabel?,
}

type Roamer = { model: Model, pos: Vector3, target: Vector3, speed: number, radius: number, phase: number }
type Pen = { plot: Model, key: string, roamers: { Roamer } }

local slots: { SlotVisual } = {}
local pens: { [Model]: Pen } = {}

local function isMine(plot: Model): boolean
	return plot:GetAttribute("OwnerUserId") == player.UserId
end

function PlotController.myPlot(): Model?
	local plots = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:IsA("Model") and isMine(plot) then
			return plot
		end
	end
	return nil
end

function PlotController.slotPart(index: number): BasePart?
	local plot = PlotController.myPlot()
	local slotsFolder = plot and plot:FindFirstChild("Slots")
	return slotsFolder and slotsFolder:FindFirstChild("Slot" .. index) :: BasePart?
end

-- Current growth of a slot from its attributes (same math as the server).
local function growthOf(v: SlotVisual, now: number): (number, number)
	local required = (v.slot:GetAttribute("Required") or 1) :: number
	local growth = Growth.advance(
		(v.slot:GetAttribute("Growth") or 0) :: number,
		(v.slot:GetAttribute("UpdatedAt") or now) :: number,
		now,
		(v.plot:GetAttribute("WateredUntil") or 0) :: number,
		(v.plot:GetAttribute("Speed") or 1) :: number
	)
	return growth, required
end

local function makeTimer(v: SlotVisual)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(84, 22)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	gui.MaxDistance = 45
	gui.Adornee = v.slot
	gui.LightInfluence = 0
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Theme.colors.slate
	bar.BackgroundTransparency = 0.15
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.colors.toxic
	fill.Size = UDim2.fromScale(0, 1)
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 8)
	fill.Parent = bar
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Theme.font
	text.TextScaled = true
	text.TextColor3 = Theme.colors.white
	text.ZIndex = 2
	Instance.new("UIStroke", text).Thickness = 1.5
	text.Parent = bar
	gui.Parent = folder
	v.gui, v.fill, v.text = gui, fill, text
end

local function updateSlot(v: SlotVisual, now: number, t: number)
	local eggId = v.slot:GetAttribute("EggId") :: string?
	local owned = v.slot:GetAttribute("State") == "owned"
	if not owned or not eggId or not Eggs.tiers[eggId] then
		if v.egg then
			v.egg:Destroy()
			v.egg = nil
			v.key = ""
		end
		if v.gui then
			v.gui.Enabled = false
		end
		return
	end

	local growth, required = growthOf(v, now)
	local progress = math.clamp(growth / required, 0, 1)
	local ready = progress >= 1
	local mutations = (v.slot:GetAttribute("Mutations") or "") :: string
	-- Rebuild the egg only when it visibly changes: new egg, new mutation, or a growth step.
	local key = string.format("%s|%s|%d", eggId, mutations, math.floor(progress * 6))
	if key ~= v.key then
		if v.egg then
			v.egg:Destroy()
		end
		local list = if mutations == "" then {} else string.split(mutations, ",")
		local egg = MutantModel.buildEgg(eggId, progress, list)
		egg.Parent = folder
		v.egg = egg
		v.key = key
	end
	local egg = v.egg :: Model
	local base = v.slot.CFrame * CFrame.new(0, v.slot.Size.Y / 2, 0)
	local wobble = if ready then CFrame.Angles(0, 0, math.sin(t * 12) * 0.15) else CFrame.identity
	egg:PivotTo(base * wobble)

	if not isMine(v.plot) then
		if v.gui then
			v.gui.Enabled = false
		end
		return
	end
	if not v.gui then
		makeTimer(v)
	end
	local gui, fill, text = v.gui :: BillboardGui, v.fill :: Frame, v.text :: TextLabel
	gui.Enabled = true
	fill.Size = UDim2.fromScale(progress, 1)
	if ready then
		fill.BackgroundColor3 = Theme.colors.gold
		text.Text = "HATCH!"
	else
		local wateredUntil = (v.plot:GetAttribute("WateredUntil") or 0) :: number
		local speed = (v.plot:GetAttribute("Speed") or 1) :: number
		fill.BackgroundColor3 = if now < wateredUntil then Theme.colors.water else Theme.colors.toxic
		text.Text = Format.duration(Growth.secondsRemaining(growth, required, now, wateredUntil, speed))
	end
end

local function onSlotClicked(plot: Model, slot: BasePart)
	if not isMine(plot) then
		return
	end
	local index = slot:GetAttribute("Index") :: number
	local state = slot:GetAttribute("State")
	if state == "buy" then
		local snap = State.get()
		local price = (slot:GetAttribute("Price") or 0) :: number
		if snap and snap.cash < price then
			State.toast("Need " .. Format.cash(price) .. " for this patch", "error")
			Sfx.play("error")
			return
		end
		Remotes.get("BuySlot"):FireServer()
		Sfx.play("buy")
		return
	elseif state ~= "owned" then
		return
	end
	local eggId = slot:GetAttribute("EggId") :: string
	if eggId == "" then
		local snap = State.get()
		local selected = State.selectedEgg:get(false)
		if not snap or (snap.eggs[selected] or 0) < 1 then
			State.toast("No eggs! Buy some at the Egg Shop in the middle.", "error")
			Sfx.play("error")
			return
		end
		Remotes.get("Plant"):FireServer(index, selected)
		Sfx.play("plant")
		return
	end
	for _, v in slots do
		if v.slot == slot then
			local growth, required = growthOf(v, workspace:GetServerTimeNow())
			if growth >= required then
				Remotes.get("Harvest"):FireServer(index)
			else
				State.toast("Still growing. Tap Water to speed it up!", "info")
			end
			return
		end
	end
end

---------------------------------------------------------------------------- pens

local function penFrame(plot: Model): (CFrame, Vector2)
	local center = (plot:GetAttribute("PenCenter") or Vector3.zero) :: Vector3
	local size = (plot:GetAttribute("PenSize") or Vector2.new(30, 8)) :: Vector2
	local base = plot.PrimaryPart
	local rot = if base then base.CFrame.Rotation else CFrame.identity
	return rot + center, size
end

local function randomPoint(half: Vector2, radius: number): Vector3
	local hx = math.max(0, half.X - radius)
	local hz = math.max(0, half.Y - radius)
	return Vector3.new((math.random() * 2 - 1) * hx, 0, (math.random() * 2 - 1) * hz)
end

local function rebuildPen(pen: Pen)
	for _, r in pen.roamers do
		r.model:Destroy()
	end
	pen.roamers = {}
	local ok, list = pcall(HttpService.JSONDecode, HttpService, pen.key)
	if not ok or type(list) ~= "table" then
		return
	end
	local frame, size = penFrame(pen.plot)
	local half = size / 2
	for i, item in list do
		local data = {
			tier = item.tier,
			rarity = item.rarity,
			species = item.species,
			mutations = item.mutations or {},
			size = item.size or 1,
		}
		local model = MutantModel.build(data)
		local radius = 1.4 * MutantModel.visualScale(data)
		-- Start spread along the pen so the crowd reads at a glance.
		local x = -half.X + (i - 0.5) / #list * size.X
		local start = Vector3.new(math.clamp(x, -half.X, half.X), 0, 0)
		model:PivotTo(frame * CFrame.new(start))
		model.Parent = folder
		table.insert(pen.roamers, {
			model = model,
			pos = start,
			target = randomPoint(half, radius),
			speed = 2.5 / math.sqrt(math.max(1, radius)),
			radius = radius,
			phase = math.random() * 10,
		})
	end
end

local function updatePen(pen: Pen, dt: number, t: number, camPos: Vector3)
	local key = (pen.plot:GetAttribute("Pen") or "[]") :: string
	if key ~= pen.key then
		pen.key = key
		rebuildPen(pen)
	end
	local frame, size = penFrame(pen.plot)
	-- Far-away pens stand still to save work.
	if (frame.Position - camPos).Magnitude > 160 then
		return
	end
	local half = size / 2
	for _, r in pen.roamers do
		local delta = r.target - r.pos
		if delta.Magnitude < 0.3 then
			r.target = randomPoint(half, r.radius)
		else
			r.pos += delta.Unit * math.min(delta.Magnitude, r.speed * dt)
		end
		local dir = if delta.Magnitude > 0.01 then delta.Unit else Vector3.new(0, 0, -1)
		local hop = math.abs(math.sin(t * 6 + r.phase)) * 0.35 * math.min(r.radius, 4)
		local world = frame * CFrame.new(r.pos + Vector3.new(0, hop, 0))
		r.model:PivotTo(CFrame.lookAt(world.Position, world.Position + frame:VectorToWorldSpace(dir)))
	end
end

---------------------------------------------------------------------------- setup

local function watchSlot(plot: Model, slot: Instance)
	if not slot:IsA("BasePart") then
		return
	end
	table.insert(slots, { slot = slot, plot = plot, egg = nil, key = "" })
	local click = slot:WaitForChild("ClickDetector", 10) :: ClickDetector?
	if click then
		click.MouseClick:Connect(function()
			onSlotClicked(plot, slot)
		end)
	end
end

local function watchPlot(plot: Instance)
	if not plot:IsA("Model") then
		return
	end
	pens[plot] = { plot = plot, key = "", roamers = {} }
	local slotsFolder = plot:WaitForChild("Slots")
	slotsFolder.ChildAdded:Connect(function(slot)
		watchSlot(plot, slot)
	end)
	for _, slot in slotsFolder:GetChildren() do
		task.spawn(watchSlot, plot, slot)
	end
end

function PlotController.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientVisuals"
	folder.Parent = workspace
end

function PlotController.Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "EggShopPrompt" then
			State.panel:set("shop")
		elseif prompt.Name == "SellPrompt" then
			State.panel:set("sell")
		end
	end)

	-- The map replicates in full at join (StreamingEnabled is off in default.project.json);
	-- ChildAdded covers anything that arrives after this first read.
	local plots = workspace:WaitForChild("Map"):WaitForChild("Plots")
	plots.ChildAdded:Connect(function(plot)
		task.spawn(watchPlot, plot)
	end)
	for _, plot in plots:GetChildren() do
		task.spawn(watchPlot, plot)
	end

	local last = os.clock()
	while true do
		task.wait(1 / 20)
		local t = os.clock()
		local dt = t - last
		last = t
		local now = workspace:GetServerTimeNow()
		for _, v in slots do
			updateSlot(v, now, t)
		end
		local camPos = workspace.CurrentCamera.CFrame.Position
		for _, pen in pens do
			updatePen(pen, dt, t, camPos)
		end
		-- Glitched mutants flicker.
		for _, d in folder:GetChildren() do
			if d:GetAttribute("Glitched") then
				local h = d:FindFirstChildOfClass("Highlight")
				if h then
					h.Enabled = math.random() > 0.25
				end
			end
		end
	end
end

return PlotController
