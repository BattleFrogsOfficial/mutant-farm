--!strict
-- Decides whether the player is at their plot or in the hub (State.zone), so the HUD shows only
-- what that place needs. Also writes your bag's worth onto the Sell stall's sign, and your next
-- rebirth onto the Rebirth Altar's sign.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Format = require(ReplicatedStorage.Shared.Format)
local Valuation = require(ReplicatedStorage.Shared.Valuation)
local ShopRules = require(ReplicatedStorage.Shared.ShopRules)
local Eggs = require(ReplicatedStorage.Shared.Config.Eggs)
local State = require(script.Parent.Parent.State)
local PlotController = require(script.Parent.PlotController)

local Observer = Fusion.Observer

local ZoneController = {}

local MARGIN = 6 -- studs past the plot's edge that still count as "at your plot"

local function zoneNow(): string
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local plot = PlotController.myPlot()
	local base = plot and plot.PrimaryPart
	if not root or not base then
		return State.zone:get(false)
	end
	local p = base.CFrame:PointToObjectSpace(root.Position)
	local inside = math.abs(p.X) <= base.Size.X / 2 + MARGIN and math.abs(p.Z) <= base.Size.Z / 2 + MARGIN
	return if inside then "plot" else "hub"
end

-- Your bag's worth on the Sell stall's roof sign ("💰 SELL $381K"), for you only: a local
-- change to the sign's text, so nothing extra floats in the world.
local function bagSign()
	local hub = workspace:WaitForChild("Map"):WaitForChild("Hub")
	local stall = hub:WaitForChild("SellShop", 60)
	local board = stall and stall:WaitForChild("Sign", 60)
	local gui = board and board:FindFirstChildOfClass("SurfaceGui")
	local label = gui and gui:FindFirstChildOfClass("TextLabel")
	if not label then
		return
	end
	local plain = label.Text
	local function update()
		local snap = State.snapshot:get(false)
		local value = 0
		if snap then
			for _, item in snap.inventory do
				value += Valuation.sellValue(item, snap.cashMultiplier)
			end
		end
		label.Text = if value > 0 then plain .. " " .. Format.cash(value) else plain
	end
	Observer(State.snapshot):onChange(update)
	update()
end

-- "REBIRTH 1 · $700K · unlocks Toxic Egg" (or "· Cash x2" when it unlocks no tier) on the Rebirth
-- Altar's sign, and its bar filled to Cash / cost. Local text, like the Sell sign.
function ZoneController.altarText(rebirths: number, cost: number): string
	local tier = ShopRules.unlockedAtRebirth(rebirths + 1)
	local reward = if tier
		then "unlocks " .. Eggs.tiers[tier].name
		else "Cash x" .. tostring(Valuation.rebirthMultiplier(rebirths + 1))
	return string.format("REBIRTH %d · %s\n%s", rebirths + 1, Format.cash(cost), reward)
end

local function altarSign()
	local hub = workspace:WaitForChild("Map"):WaitForChild("Hub")
	local sign = hub:WaitForChild("RebirthSign", 60)
	local board = sign and sign:WaitForChild("Board", 60)
	local gui = board and board:WaitForChild("AltarGui", 60)
	local title = gui and gui:FindFirstChild("Title") :: TextLabel?
	local fill = gui and gui:FindFirstChild("Bar") and gui.Bar:FindFirstChild("Fill") :: Frame?
	if not title or not fill then
		return
	end
	local function update()
		local snap = State.snapshot:get(false)
		if not snap then
			return
		end
		title.Text = ZoneController.altarText(snap.rebirths, snap.rebirthCost)
		fill.Size = UDim2.fromScale(math.clamp(snap.cash / math.max(snap.rebirthCost, 1), 0, 1), 1)
	end
	Observer(State.snapshot):onChange(update)
	update()
end

function ZoneController.Init() end

function ZoneController.Start()
	task.spawn(bagSign)
	task.spawn(altarSign)
	while true do
		local zone = zoneNow()
		if zone ~= State.zone:get(false) then
			State.zone:set(zone)
		end
		task.wait(0.25)
	end
end

return ZoneController
