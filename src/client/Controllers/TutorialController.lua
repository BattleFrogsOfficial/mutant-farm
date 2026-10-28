--!strict
-- Guided first session. Works out the current step from the player's stats (so it survives
-- rejoins with nothing extra saved), shows it in the "Next up" panel, and draws a glowing beam
-- from the player to whatever they should tap or walk to. After the tutorial, "Next up" keeps
-- pointing at the nearest goal (the next soil patch).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local PlotController = require(script.Parent.PlotController)

local TutorialController = {}

local player = Players.LocalPlayer

type Step = {
	text: string,
	target: (() -> BasePart?)?,
	ui: string?, -- name of a HUD element to pulse ("Water", "Harvest")
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

local function eggCount(snap: Types.Snapshot): number
	local n = 0
	for _, c in snap.eggs do
		n += c
	end
	return n
end

local function currentStep(snap: Types.Snapshot): Step
	local st = snap.stats
	local planted = next(snap.slots) ~= nil
	if st.eggsPlanted == 0 then
		return { text = "Tap a soil patch to plant your egg", target = emptySlot }
	elseif st.waters == 0 and planted then
		return { text = "Tap WATER to grow 2x faster", ui = "Water" }
	elseif st.harvested == 0 then
		return { text = "Tap your egg when it says HATCH!", target = plantedSlot }
	elseif st.eggsPlanted < 2 and eggCount(snap) > 0 then
		return { text = "Plant your 2nd egg. It's guaranteed RARE!", target = emptySlot }
	elseif st.harvested < 2 and planted then
		return { text = "Hatch your Rare mutant!", target = plantedSlot }
	elseif st.sold == 0 then
		return {
			text = "Walk to the gold SELL pad and sell your mutants",
			target = function()
				return hub("SellPad")
			end,
		}
	elseif st.eggsBought == 0 then
		return {
			text = "Buy more eggs at the EGG SHOP",
			target = function()
				return hub("EggShopPad")
			end,
		}
	elseif st.slotsBought == 0 and snap.nextSlotCost then
		local cost = snap.nextSlotCost :: number
		return {
			text = if snap.cash >= cost
				then "Tap the glowing + patch to grow your farm!"
				else "Save up for a new soil patch",
			target = if snap.cash >= cost then buySlot else nil,
			progress = math.clamp(snap.cash / cost, 0, 1),
		}
	end
	-- After the tutorial: always show the nearest goal.
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
			State.objective:set({ text = step.text, progress = step.progress, ui = step.ui })
			setTarget(if step.target then step.target() else nil)
		end
		task.wait(0.25)
	end
end

return TutorialController
