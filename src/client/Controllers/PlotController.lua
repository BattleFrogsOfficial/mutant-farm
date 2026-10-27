--!strict
-- Draws eggs and timer bars on every island from the slot attributes the server replicates,
-- and turns clicks on your own slots into Plant / Harvest intents.
-- Visuals are client-only, so they cost the server nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local Growth = require(Shared.Growth)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)

local PlotController = {}

local player = Players.LocalPlayer

type Visual = {
	slot: BasePart,
	island: Model,
	egg: Part,
	gui: BillboardGui,
	fill: Frame,
	text: TextLabel,
}

local visuals: { Visual } = {}
local folder: Folder

local function makeVisual(island: Model, slot: BasePart): Visual
	local egg = Instance.new("Part")
	egg.Name = "Egg"
	egg.Shape = Enum.PartType.Ball
	egg.Anchored = true
	egg.CanCollide = false
	egg.CanQuery = false
	egg.CanTouch = false
	egg.Material = Enum.Material.SmoothPlastic
	egg.Transparency = 1
	egg.Parent = folder

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(110, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	gui.MaxDistance = 70
	gui.Adornee = slot
	gui.Enabled = false
	gui.LightInfluence = 0

	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Theme.colors.slate
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke", bar)
	stroke.Color = Theme.colors.slate
	stroke.Thickness = 2
	bar.Parent = gui

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.colors.toxic
	fill.Size = UDim2.fromScale(0, 1)
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 10)
	fill.Parent = bar

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Theme.font
	text.TextScaled = true
	text.TextColor3 = Theme.colors.white
	text.ZIndex = 2
	Instance.new("UIStroke", text).Thickness = 2
	text.Parent = bar

	gui.Parent = folder
	return { slot = slot, island = island, egg = egg, gui = gui, fill = fill, text = text }
end

local function update(v: Visual, now: number)
	local eggId = v.slot:GetAttribute("EggId") :: string?
	local active = v.slot:GetAttribute("Active") == true
	local tier = eggId and Eggs.tiers[eggId]
	if not active or not tier then
		v.egg.Transparency = 1
		v.gui.Enabled = false
		return
	end

	local required = v.slot:GetAttribute("Required") :: number
	local wateredUntil = v.island:GetAttribute("WateredUntil") :: number
	local speed = v.island:GetAttribute("Speed") :: number
	local growth = Growth.advance(
		v.slot:GetAttribute("Growth") :: number,
		v.slot:GetAttribute("UpdatedAt") :: number,
		now,
		wateredUntil,
		speed
	)
	local progress = math.clamp(growth / required, 0, 1)
	local ready = progress >= 1

	-- Egg swells as it grows, wobbles when ready.
	local size = 1.4 + 1.8 * progress
	v.egg.Size = Vector3.new(size, size, size)
	v.egg.Color = Color3.fromHex(tier.color)
	v.egg.Transparency = 0
	local wobble = if ready then math.sin(now * 10) * 0.18 else 0
	v.egg.CFrame = v.slot.CFrame * CFrame.new(0, 0.3 + size / 2, 0) * CFrame.Angles(0, 0, wobble)

	v.gui.Enabled = true
	v.fill.Size = UDim2.fromScale(progress, 1)
	if ready then
		v.fill.BackgroundColor3 = Theme.colors.gold
		v.text.Text = "READY!"
	else
		v.fill.BackgroundColor3 = if now < wateredUntil then Theme.colors.water else Theme.colors.toxic
		v.text.Text = Format.duration(Growth.secondsRemaining(growth, required, now, wateredUntil, speed))
	end
end

local function isMine(island: Model): boolean
	return island:GetAttribute("OwnerUserId") == player.UserId
end

local function onSlotClicked(island: Model, slot: BasePart)
	if not isMine(island) then
		return
	end
	local index = slot:GetAttribute("Index") :: number
	if slot:GetAttribute("Active") ~= true then
		State.toast("Locked plot. More slots unlock soon!", "info")
		return
	end
	local eggId = slot:GetAttribute("EggId") :: string
	if eggId == "" then
		local snap = State.get()
		local selected = State.selectedEgg:get(false)
		if not snap or (snap.eggs[selected] or 0) < 1 then
			State.toast("No eggs! Buy some at the Egg Shop in the middle.", "error")
			return
		end
		Remotes.get("Plant"):FireServer(index, selected)
		return
	end
	local snap = State.get()
	local view = snap and snap.slots[tostring(index)]
	if view and State.slotGrowth(snap :: any, view, workspace:GetServerTimeNow()) >= view.required then
		Remotes.get("Harvest"):FireServer(index)
	end
end

local function watchSlot(island: Model, slot: Instance)
	if not slot:IsA("BasePart") then
		return
	end
	table.insert(visuals, makeVisual(island, slot))
	local click = slot:WaitForChild("ClickDetector", 10) :: ClickDetector?
	if click then
		click.MouseClick:Connect(function()
			onSlotClicked(island, slot)
		end)
	end
end

local function watchIsland(island: Instance)
	if not island:IsA("Model") then
		return
	end
	local slots = island:WaitForChild("Slots")
	slots.ChildAdded:Connect(function(slot)
		watchSlot(island, slot)
	end)
	for _, slot in slots:GetChildren() do
		task.spawn(watchSlot, island, slot)
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
	local islands = workspace:WaitForChild("Map"):WaitForChild("Islands")
	islands.ChildAdded:Connect(function(island)
		task.spawn(watchIsland, island)
	end)
	for _, island in islands:GetChildren() do
		task.spawn(watchIsland, island)
	end

	while true do
		local now = workspace:GetServerTimeNow()
		for _, v in visuals do
			update(v, now)
		end
		task.wait(1 / 15)
	end
end

return PlotController
