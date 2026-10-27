--!strict
-- Mounts the ScreenGui. Everything is laid out at a 900x600 design size and scaled down
-- with one UIScale so phones (the main audience) see the same layout, just smaller.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local UI = script.Parent.Parent.UI
local Hud = require(UI.Hud)
local EggShop = require(UI.EggShop)
local SellPanel = require(UI.SellPanel)
local Toasts = require(UI.Toasts)

local New, Children, Value, Computed = Fusion.New, Fusion.Children, Fusion.Value, Fusion.Computed

local UIController = {}

local DESIGN_SIZE = Vector2.new(900, 600)

function UIController.Init() end

function UIController.Start()
	local camera = workspace.CurrentCamera
	local scale = Value(1)
	local function updateScale()
		local viewport = camera.ViewportSize
		scale:set(math.clamp(math.min(viewport.X / DESIGN_SIZE.X, viewport.Y / DESIGN_SIZE.Y), 0.55, 1.25))
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()

	New("ScreenGui")({
		Name = "MutantFarm",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		[Children] = New("Frame")({
			-- A UIScale shrinks toward the top-left, so the root is oversized by 1/scale
			-- to keep scale-anchored elements (bottom bar, right buttons) on the screen edges.
			Name = "Root",
			BackgroundTransparency = 1,
			Size = Computed(function()
				return UDim2.fromScale(1 / scale:get(), 1 / scale:get())
			end),
			[Children] = {
				New("UIScale")({ Scale = scale }),
				Hud(),
				Toasts(),
				EggShop(),
				SellPanel(),
			},
		}),
	})
end

return UIController
