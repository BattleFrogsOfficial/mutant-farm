--!strict
-- Mounts the ScreenGui. Everything is laid out at a 900x540 design size and scaled down
-- with one UIScale so phones (the main audience) see the same layout, just smaller.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local UI = script.Parent.Parent.UI
local Root = require(UI.Root)
local State = require(script.Parent.Parent.State)

local New, Children, Value, Computed = Fusion.New, Fusion.Children, Fusion.Value, Fusion.Computed

local UIController = {}

local DESIGN_SIZE = Vector2.new(900, 540)

function UIController.Init() end

-- Chat goes to the bottom-left, smaller, out of the top-left corner and the hatch framing.
local function placeChat()
	local ok, config = pcall(function()
		return game:GetService("TextChatService"):WaitForChild("ChatWindowConfiguration", 10)
	end)
	if not ok or not config then
		return
	end
	-- One pcall per property, so one rejected value can't skip the rest. Both scales accept
	-- 0.5-2; 0.5 is the smallest, which keeps the window clear of the egg tray.
	for prop, value in
		{
			WidthScale = 0.5,
			HeightScale = 0.5,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
		}
	do
		pcall(function()
			(config :: any)[prop] = value
		end)
	end
end

function UIController.Start()
	task.spawn(placeChat)
	local scale = Value(1)

	local gui = New("ScreenGui")({
		Name = "MutantFarm",
		ResetOnSpawn = false,
		-- The top row shares the top-bar strip with Roblox's buttons (they keep the top-left
		-- corner; nothing of ours goes there), so the HUD sits high instead of floating low.
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

	-- Scale from the area the GUI actually covers (the full screen).
	local function updateScale()
		local size = gui.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return
		end
		local s = math.clamp(math.min(size.X / DESIGN_SIZE.X, size.Y / DESIGN_SIZE.Y), 0.5, 1.4)
		scale:set(s)
		State.screen:set({ width = size.X, height = size.Y, scale = s })
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
	updateScale()
end

return UIController
