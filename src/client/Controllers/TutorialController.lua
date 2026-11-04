--!strict
-- The tutorial card (Config/Tutorial, drawn by UI/Hud's card in the Next Up slot). Works out the
-- current step from the player's stats (so it survives rejoins; order in
-- shared/Onboarding.tutorialStep: TAP HATCH -> SELL IT -> BUY 2 EGGS -> PLANT THEM -> STAND ON THE
-- WATER PAD -> HATCH -> BUY A SOIL PATCH -> GET A SWAMP EGG -> OPEN THE ALMANAC), points the guide
-- beam at the step's target (patch, water pad, sell pad, shop pad) and gives the target a slow gold
-- outline pulse. A completed step shows a check for Tutorial.checkSeconds. The solo Solar Flare
-- shows "WEATHER!" while it hits. Once profile.tutorialDone, the same card is Next Up: Lab's earned
-- gate once a Swamp egg is owned (shared/NextUp), the rebirth goal from half its cost earned this
-- life, else the next soil patch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local NextUp = require(Shared.NextUp)
local Onboarding = require(Shared.Onboarding)
local Tutorial = require(Shared.Config.Tutorial)
local Remotes = require(Shared.Remotes)
local Mutants = require(Shared.Config.Mutants)
local Eggs = require(Shared.Config.Eggs)
local Types = require(Shared.Types)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local PlotController = require(script.Parent.PlotController)

local TutorialController = {}

local player = Players.LocalPlayer

type Step = {
	id: string?, -- the tutorial step (nil for Next Up)
	title: string,
	text: string,
	focusEgg: string?,
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
		tutorialDone = snap.tutorialDone == true,
	})
	local shopOpened = snap.onboarding == nil or not snap.onboarding.active or snap.onboarding.shopOpened
	local steps = {}
	for _, st in Tutorial.steps do
		steps[st.id] = st
	end
	local function card(id: string, extra: { [string]: any }): Step
		local st = steps[id]
		local out: { [string]: any } = { id = id, title = st.title, text = st.line }
		for k, v in extra do
			out[k] = v
		end
		return out :: any
	end
	if step == "plantFirst" then
		return {
			id = "plantFirst",
			title = Tutorial.plantFirst.title,
			text = Tutorial.plantFirst.line,
			target = emptySlot,
			soil = true,
		}
	elseif step == "hatch" then
		return card("hatch", { ui = "Hatch", target = plantedSlot })
	elseif step == "sell" then
		return card("sell", {
			hub = true,
			target = function()
				return hub("SellPad")
			end,
		})
	elseif step == "buy" and not shopOpened then
		-- The tray's BUY button (Hud), so the next eggs are one tap away from your farm.
		return card("buy", { ui = "TrayBuy", hub = true, target = onYourFarm })
	elseif step == "buy" then
		return card("buy", {
			text = steps.buy.lineShop,
			hub = true,
			target = function()
				return hub("EggShopPad")
			end,
		})
	elseif step == "plant" then
		return card("plant", { target = emptySlot, soil = true })
	elseif step == "water" then
		return card("water", { target = waterPad })
	elseif step == "hatch2" then
		return card("hatch2", { ui = "Hatch", target = plantedSlot })
	elseif step == "patch" then
		local cost = snap.nextSlotCost :: number
		local afford = snap.cash >= cost
		return card("patch", {
			text = string.format(if afford then steps.patch.line else steps.patch.lineSave, Format.cash(cost)),
			target = if afford then buySlot else nil,
		})
	elseif step == "swamp" then
		return card("swamp", {
			hub = true,
			focusEgg = "Swamp",
			target = function()
				return hub("EggShopPad")
			end,
		})
	elseif step == "almanac" then
		return card("almanac", { ui = "Almanac", hub = true })
	end
	-- After the tutorial: Next Up, the nearest goal.
	local lab = NextUp.labGoal(snap.rebirths, snap.stats.totalCashEarned or 0, snap.eggs, snap.slots)
	if lab then
		return { title = lab.title or Tutorial.nextUpTitle, text = lab.text, progress = lab.progress }
	end
	local rebirth = NextUp.rebirthGoal(snap.rebirths, snap.earnedThisLife or 0, snap.rebirthCost or 0)
	if rebirth then
		return {
			title = rebirth.title or Tutorial.nextUpTitle,
			text = rebirth.text,
			progress = rebirth.progress,
			hub = rebirth.progress == 1,
			target = if rebirth.progress == 1
				then function()
					return hub("RebirthAltar")
				end
				else nil,
		}
	end
	if snap.nextSlotCost then
		local cost = snap.nextSlotCost :: number
		return {
			title = "NEXT SOIL PATCH",
			text = string.format("%s / %s", Format.cash(math.min(snap.cash, cost)), Format.cash(cost)),
			progress = math.clamp(snap.cash / cost, 0, 1),
		}
	end
	return { title = Tutorial.nextUpTitle, text = "Your farm is full! Hatch giants for your pen" }
end

-- The guide beam from the player's root to the target, and the target's slow gold outline (the
-- only outline while the tutorial runs).
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
		b.Color = ColorSequence.new(Theme.colors.gold)
		b.LightEmission = 0.6
		b.Width0 = 0.6
		b.Width1 = 0.6
		b.FaceCamera = true
		b.Segments = 20
		b.CurveSize0 = 4
		b.Transparency = NumberSequence.new(0.25)
		b.Parent = workspace
		beam = b
		local h = Instance.new("Highlight")
		h.FillTransparency = 1 -- an outline only
		h.OutlineColor = Theme.colors.gold
		h.DepthMode = Enum.HighlightDepthMode.Occluded
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
	h.Adornee = (part.Parent and part.Parent:IsA("Model") and part.Parent ~= workspace) and part.Parent or part
	h.Enabled = true
	-- The slow pulse.
	local o = Tutorial.outline
	local k = 0.5 + 0.5 * math.sin(os.clock() * 2 * math.pi / o.period)
	h.OutlineTransparency = o.minTransparency + (o.maxTransparency - o.minTransparency) * k
end

local function publish(step: Step, extra: { [string]: any }?)
	local o: { [string]: any } = {
		title = step.title,
		text = step.text,
		progress = step.progress,
		step = if step.id then Onboarding.stepIndex(step.id :: any) else nil,
		ui = step.ui,
		hub = step.hub,
		soil = step.soil,
		focusEgg = step.focusEgg,
	}
	for k, v in extra or {} do
		o[k] = v
	end
	State.objective:set(o :: any)
end

local HIDDEN: Step = { title = "", text = "" }

function TutorialController.Init() end

function TutorialController.Start()
	-- The card first shows Tutorial.appearAfter seconds after spawning.
	local spawnedAt = os.clock()
	player.CharacterAdded:Connect(function()
		spawnedAt = os.clock()
	end)
	-- The Almanac's step ends when it opens (the server checks and saves tutorialDone).
	local almanacStep = false
	local lastPanel = "none"
	local shown: Step? = nil -- the step on the card now
	local checkUntil = 0 -- the check animation runs until then
	local weatherUntil = 0
	local lastWeather = ""
	while true do
		local snap = State.get()
		local now = os.clock()
		if snap and snap.stats and now - spawnedAt >= Tutorial.appearAfter then
			local step = currentStep(snap)
			local panel = State.panel:get(false)
			if panel == "almanac" and lastPanel ~= "almanac" and almanacStep then
				pcall(function()
					Remotes.get("OpenedAlmanac"):FireServer()
				end)
			end
			lastPanel = panel
			almanacStep = step.id == "almanac"
			-- The solo Solar Flare (once, during the opening): "WEATHER!" while it hits.
			local plotWeather = State.plotWeather:get(false)
			if plotWeather.id ~= lastWeather then
				lastWeather = plotWeather.id
				if plotWeather.id ~= "" and snap.onboarding and snap.onboarding.active and not snap.tutorialDone then
					weatherUntil = now + Tutorial.weatherSeconds
				end
			end
			-- A step completed: the old card shows its check for checkSeconds, then the new one.
			-- Only a step forward (or the end) plays the check; going back just switches cards.
			local forward = shown ~= nil
				and shown.id ~= nil
				and shown.id ~= step.id
				and (step.id == nil or Onboarding.stepIndex(step.id :: any) > Onboarding.stepIndex(shown.id :: any))
			if forward and now >= checkUntil then
				checkUntil = now + Tutorial.checkSeconds
				local done = shown :: Step
				shown = nil
				-- Built explicitly: nothing of the finished step keeps pulsing during the check.
				State.objective:set({
					title = done.title,
					text = done.text,
					step = Onboarding.stepIndex(done.id :: any),
					hub = done.hub,
					done = true,
				} :: any)
				setTarget(nil)
			elseif now < checkUntil then
				-- keep the check on screen
			elseif now < weatherUntil then
				publish(
					{ title = Tutorial.weather.title, text = Tutorial.weather.line, target = nil, ui = nil } :: any,
					{
						step = shown and shown.id and Onboarding.stepIndex(shown.id :: any) or nil,
					}
				)
				shown = step
			else
				shown = step
				publish(step)
				setTarget(if step.target then step.target() else nil)
			end
		else
			State.objective:set({ title = HIDDEN.title, text = HIDDEN.text } :: any)
		end
		task.wait(Tutorial.pollSeconds)
	end
end

return TutorialController
