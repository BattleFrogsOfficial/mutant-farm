--!strict
-- Mounts the ScreenGui. Everything is laid out at a 900x540 design size and scaled down
-- with one UIScale so phones (the main audience) see the same layout, just smaller.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local UI = script.Parent.Parent.UI
local Root = require(UI.Root)

local New, Children, Value, Computed = Fusion.New, Fusion.Children, Fusion.Value, Fusion.Computed

local UIController = {}

local DESIGN_SIZE = Vector2.new(900, 540)

function UIController.Init() end

function UIController.Start()
	local scale = Value(1)

	local gui = New("ScreenGui")({
		Name = "MutantFarm",
		ResetOnSpawn = false,
		-- Use the whole screen: the currency bar sits in the top strip, centered, clear of
		-- Roblox's own buttons at the top-left.
		IgnoreGuiInset = true,
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
				Root(),
			},
		}),
	})

	-- Scale from the area the GUI actually covers (the full screen, with IgnoreGuiInset).
	local function updateScale()
		local size = gui.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return
		end
		scale:set(math.clamp(math.min(size.X / DESIGN_SIZE.X, size.Y / DESIGN_SIZE.Y), 0.5, 1.4))
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
	updateScale()
end

return UIController
