--!strict
-- The payoff moment. When the server confirms a harvest, the egg shakes, bursts, and the mutant
-- pops out at full size (giants included) with a name card, rarity-scaled sound, a screen banner
-- for Rare+ and a camera shake for Epic+. Also reacts to mid-grow mutations.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Eggs = require(Shared.Config.Eggs)
local MutantModel = require(Shared.MutantModel)
local State = require(script.Parent.Parent.State)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Parent.UI.Theme)
local PlotController = require(script.Parent.PlotController)

local HatchController = {}

local player = Players.LocalPlayer
local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

local function burst(at: Vector3, color: Color3, amount: number, scale: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = at
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.8
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(8 * scale, 16 * scale)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 4
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6 * scale), NumberSequenceKeypoint.new(1, 0) })
	e.Rate = 0
	e.Parent = anchor
	anchor.Parent = workspace
	e:Emit(amount)
	task.delay(2, function()
		anchor:Destroy()
	end)
end

local function shakeCamera(strength: number, duration: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local start = os.clock()
	task.spawn(function()
		while os.clock() - start < duration do
			local k = 1 - (os.clock() - start) / duration
			humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * strength * k
			task.wait()
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

local function nameCard(model: Model, item: any, value: number)
	local species = MutantModel.species(item)
	local height = (model:GetAttribute("Height") or 4) :: number
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 92)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height + 1.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = model.PrimaryPart
	local function line(text: string, y: number, h: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, h)
		l.Font = Theme.font
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = text
		Instance.new("UIStroke", l).Thickness = 2.5
		l.Parent = gui
	end
	local rarityColor = Color3.fromHex(Rarities.info[item.rarity].color)
	line(species.name, 0, 34, rarityColor)
	local tags = { item.rarity, string.format("x%.2f size", item.size) }
	for _, m in MutantModel.sortedMutations(item.mutations) do
		table.insert(tags, m:upper())
	end
	line(table.concat(tags, " · "), 34, 24, Theme.colors.white)
	line(Format.cash(value), 60, 30, Theme.colors.toxic)
	gui.Parent = model
end

local function onHarvested(item: any, value: number, slotIndex: number?)
	local slot = slotIndex and PlotController.slotPart(slotIndex)
	local rank = RARITY_RANK[item.rarity] or 1
	local rarityColor = Color3.fromHex(Rarities.info[item.rarity].color)

	Sfx.play("hatch" .. item.rarity, 0.5 + rank * 0.1, 1.15 - rank * 0.06)
	if rank >= 3 then
		local species = MutantModel.species(item)
		State.showBanner(string.format("%s HATCH!\n%s", item.rarity:upper(), species.name), rarityColor)
	end
	if rank >= 4 then
		shakeCamera(if rank == 5 then 1.2 else 0.6, if rank == 5 then 1.2 else 0.6)
	end
	if not slot then
		return
	end

	-- Egg shake, then the mutant bursts out and grows to full size.
	local base = slot.CFrame * CFrame.new(0, slot.Size.Y / 2, 0)
	local egg = MutantModel.buildEgg(item.tier, 1, item.mutations)
	egg:PivotTo(base)
	egg.Parent = workspace
	local shakeStart = os.clock()
	while os.clock() - shakeStart < 0.45 do
		egg:PivotTo(base * CFrame.Angles(0, 0, math.sin((os.clock() - shakeStart) * 60) * 0.25))
		task.wait()
	end
	egg:Destroy()

	local model = MutantModel.build(item)
	-- Face whoever is looking: turn toward the gate side of the plot.
	model:PivotTo(base)
	model:ScaleTo(0.05)
	model.Parent = workspace
	local height = (model:GetAttribute("Height") or 4) :: number
	burst(base.Position + Vector3.new(0, 1, 0), rarityColor, 20 + rank * 12, math.clamp(height / 4, 1, 6))
	burst(base.Position + Vector3.new(0, 1, 0), Color3.fromHex(Eggs.tiers[item.tier].design.shell), 14, 1)
	nameCard(model, item, value)

	local grow = Instance.new("NumberValue")
	grow.Value = 0.05
	grow.Changed:Connect(function(v)
		if model.Parent then
			model:ScaleTo(math.max(v, 0.01))
		end
	end)
	TweenService:Create(grow, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 }):Play()
	task.wait(2.6 + rank * 0.25)
	-- Shrink away; the pen picks it up from the server's pen list.
	TweenService:Create(grow, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Value = 0.01 })
		:Play()
	task.wait(0.32)
	grow:Destroy()
	model:Destroy()
end

local function onMutated(slotIndex: number, eggId: string, mutation: string)
	local info = Mutations.info[mutation]
	local tier = Eggs.tiers[eggId]
	State.toast(string.format("%s mutated: %s! (x%d)", tier.name, mutation:upper(), info.multiplier), "success")
	Sfx.play("mutate", 0.7, 1.3)
	local slot = PlotController.slotPart(slotIndex)
	if slot then
		burst(slot.Position + Vector3.new(0, 1.5, 0), Color3.fromHex(info.color), 30, 1)
	end
end

function HatchController.Init() end

function HatchController.Start()
	Remotes.get("Harvested").OnClientEvent:Connect(function(item, value, slotIndex)
		task.spawn(onHarvested, item, value, slotIndex)
	end)
	Remotes.get("Mutated").OnClientEvent:Connect(onMutated)
end

return HatchController
