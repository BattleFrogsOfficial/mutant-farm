--!strict
-- Guided first session. Works out the current step from the player's stats (so it survives
-- rejoins with nothing extra saved; the order is shared/Onboarding.tutorialStep: TAP HATCH ->
-- SELL -> BUY 5 EGGS (the tray's button) -> PLANT ALL 5 -> WATER -> HATCH -> first soil patch ->
-- first Swamp egg), shows it in the "Next up" panel, and draws a glowing beam from the player to
-- whatever they should tap or walk to. Every step ends on the real event, never on a panel. After the tutorial, "Next up" keeps
-- pointing at the nearest goal: Lab's earned gate once a Swamp egg is owned (shared/NextUp), else
-- the next soil patch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local NextUp = require(Shared.NextUp)
local Onboarding = require(Shared.Onboarding)
local OnboardingConfig = require(Shared.Config.Onboarding)
local Mutants = require(Shared.Config.Mutants)
local Eggs = require(Shared.Config.Eggs)
local Types = require(Shared.Types)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local PlotController = require(script.Parent.PlotController)

local TutorialController = {}

local player = Players.LocalPlayer

type Step = {
	text: string,
	target: (() -> BasePart?)?,
	ui: string?, -- name of a HUD element to pulse ("Boost", "Harvest")
	hub: boolean?, -- the step happens in the hub, so Next Up shows there too
	soil: boolean?, -- a plant step: the "+" markers on your empty soil pulse (PlotController)
	progress: number?,
}

local function hub(name: string): BasePart?
	local map = workspace:FindFirstChild("Map")
	local hubModel = map and map:FindFirstChild("Hub")
	local found = hubModel and hubModel:FindFirstChild(name)
	if found and found:IsA("Model") then
		return found.PrimaryPart
	end
	return found :: BasePart?
end

local function firstSlot(predicate: (BasePart) -> boolean): BasePart?
	local plot = PlotController.myPlot()
	local slotsFolder = plot and plot:FindFirstChild("Slots")
	if not slotsFolder then
		return nil
	end
	for i = 1, 40 do
		local slot = slotsFolder:FindFirstChild("Slot" .. i) :: BasePart?
		if slot and predicate(slot) then
			return slot
		end
	end
	return nil
end

local function emptySlot(): BasePart?
	return firstSlot(function(s)
		return s:GetAttribute("State") == "owned" and s:GetAttribute("EggId") == ""
	end)
end

local function plantedSlot(): BasePart?
	return firstSlot(function(s)
		return s:GetAttribute("State") == "owned" and s:GetAttribute("EggId") ~= ""
	end)
end

local function buySlot(): BasePart?
	return firstSlot(function(s)
		return s:GetAttribute("State") == "buy"
	end)
end

-- Your plot's water pad (its top disc).
local function waterPad(): BasePart?
	local plot = PlotController.myPlot()
	local pad = plot and plot:FindFirstChild("WaterPad")
	return if pad and pad:IsA("Model") then pad.PrimaryPart else nil
end

local function eggCount(snap: Types.Snapshot): number
	local n = 0
	for _, c in snap.eggs do
		n += c
	end
	return n
end

-- Has the player ever had a Swamp egg (bought, planted or hatched)?
local function hasSwamp(snap: Types.Snapshot): boolean
	for id, n in snap.eggs do
		if n > 0 and Eggs.baseOf(id) == "Swamp" then
			return true
		end
	end
	for _, slot in snap.slots do
		if Eggs.baseOf(slot.eggId) == "Swamp" then
			return true
		end
	end
	for id in State.almanac:get(false) do
		local e = Mutants.species[id]
		if e and e.tier == "Swamp" then
			return true
		end
	end
	return false
end

local function anyEmptyPatch(snap: Types.Snapshot): boolean
	for i = 1, snap.totalSlots or snap.slotCount do
		if not snap.slots[tostring(i)] then
			return true
		end
	end
	return false
end

local function onYourFarm(): BasePart?
	return firstSlot(function(s)
		return s:GetAttribute("State") == "owned"
	end)
end

local function currentStep(snap: Types.Snapshot): Step
	local st = snap.stats
	local qty = OnboardingConfig.trayBuy.quantity
	local step = Onboarding.tutorialStep({
		harvested = st.harvested or 0,
		sold = st.sold or 0,
		eggsBought = st.eggsBought or 0,
		eggsPlanted = st.eggsPlanted or 0,
		eggsInBag = eggCount(snap),
		emptyPatch = anyEmptyPatch(snap),
		growing = snap.growingCount or 0,
		waters = st.waters or 0,
		padVisits = st.padVisits or 0,
		slotsBought = st.slotsBought or 0,
		canBuySlot = snap.nextSlotCost ~= nil,
		hasSwamp = hasSwamp(snap),
	})
	local shopOpened = snap.onboarding == nil or not snap.onboarding.active or snap.onboarding.shopOpened
	if step == "plantFirst" then
		return { text = "Tap a soil patch to plant your egg", target = emptySlot, soil = true }
	elseif step == "hatch" then
		return { text = "TAP HATCH: your first egg is ready!", ui = "Hatch", target = plantedSlot }
	elseif step == "sell" then
		return {
			text = "WALK TO THE SELL PAD and sell your mutant",
			hub = true,
			target = function()
				return hub("SellPad")
			end,
		}
	elseif step == "buy" and not shopOpened then
		-- The tray's BUY button (Hud), so the next eggs are one tap away from your farm.
		return {
			text = string.format("BUY %d EGGS: tap BUY on your egg tray", qty),
			ui = "TrayBuy",
			hub = true,
			target = onYourFarm,
		}
	elseif step == "buy" then
		return {
			text = string.format("BUY %d EGGS at the EGG SHOP", qty),
			hub = true,
			target = function()
				return hub("EggShopPad")
			end,
		}
	elseif step == "plant" then
		return { text = string.format("PLANT ALL %d: tap your soil patches", qty), target = emptySlot, soil = true }
	elseif step == "water" then
		return { text = "WATER: tap the growth circle, or stand on the blue pad", ui = "Boost", target = waterPad }
	elseif step == "hatch2" then
		return { text = "HATCH your eggs when they say HATCH!", target = plantedSlot }
	elseif step == "patch" then
		local cost = snap.nextSlotCost :: number
		return {
			text = if snap.cash >= cost
				then string.format("Tap the %s patch to grow your farm!", Format.cash(cost))
				else "Save up for a new soil patch",
			target = if snap.cash >= cost then buySlot else nil,
			progress = math.clamp(snap.cash / cost, 0, 1),
		}
	elseif step == "swamp" then
		return {
			text = "Buy your first SWAMP EGG at the EGG SHOP",
			hub = true,
			target = function()
				return hub("EggShopPad")
			end,
		}
	end
	-- After the tutorial: always show the nearest goal. Lab's earned gate once a Swamp egg is owned,
	-- else the next soil patch.
	local lab = NextUp.labGoal(snap.rebirths, snap.stats.totalCashEarned or 0, snap.eggs, snap.slots)
	if lab then
		return { text = lab.text, progress = lab.progress }
	end
	if snap.nextSlotCost then
		local cost = snap.nextSlotCost :: number
		return {
			text = string.format("Next soil patch: %s", Format.cash(cost)),
			progress = math.clamp(snap.cash / cost, 0, 1),
		}
	end
	return { text = "Your farm is full! Hatch giants to fill your pen." }
end

-- Beam from the player's root to the target part.
local beam: Beam? = nil
local targetAttachment: Attachment? = nil
local highlight: Highlight? = nil

local function setTarget(part: BasePart?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not part or not root then
		if beam then
			beam.Enabled = false
		end
		if highlight then
			highlight.Enabled = false
		end
		return
	end
	if not beam then
		local b = Instance.new("Beam")
		b.Color = ColorSequence.new(Theme.colors.toxic)
		b.LightEmission = 1
		b.Width0 = 0.6
		b.Width1 = 0.6
		b.FaceCamera = true
		b.Segments = 20
		b.CurveSize0 = 4
		b.Transparency = NumberSequence.new(0.2)
		b.Parent = workspace
		beam = b
		local h = Instance.new("Highlight")
		h.FillColor = Theme.colors.toxic
		h.FillTransparency = 0.6
		h.OutlineColor = Theme.colors.toxic
		h.Parent = workspace
		highlight = h
	end
	local fromAttachment = root:FindFirstChild("TutorialFrom") :: Attachment?
	if not fromAttachment then
		local a = Instance.new("Attachment")
		a.Name = "TutorialFrom"
		a.Parent = root
		fromAttachment = a
	end
	if not targetAttachment or targetAttachment.Parent ~= part then
		if targetAttachment then
			targetAttachment:Destroy()
		end
		local a = Instance.new("Attachment")
		a.Name = "TutorialTo"
		a.Position = Vector3.new(0, part.Size.Y / 2 + 0.5, 0)
		a.Parent = part
		targetAttachment = a
	end
	local b = beam :: Beam
	b.Attachment0 = fromAttachment
	b.Attachment1 = targetAttachment
	b.Enabled = true
	local h = highlight :: Highlight
	h.Adornee = part
	h.Enabled = true
end

function TutorialController.Init() end

function TutorialController.Start()
	while true do
		local snap = State.get()
		if snap and snap.stats then
			local step = currentStep(snap)
			State.objective:set({
				text = step.text,
				progress = step.progress,
				ui = step.ui,
				hub = step.hub,
				soil = step.soil,
			})
			setTarget(if step.target then step.target() else nil)
		end
		task.wait(0.25)
	end
end

return TutorialController
