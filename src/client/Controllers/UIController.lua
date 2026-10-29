--!strict
-- Mounts the ScreenGui. Everything is laid out on a 900x540 design canvas and scaled with one
-- UIScale (shared/HudScale: the shorter screen edge against 540, never a canvas under 900 wide,
-- capped 1.25x with a mouse and 1.0x on touch), so phones (the main audience) see the same
-- layout, just smaller.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local UI = script.Parent.Parent.UI
local Root = require(UI.Root)
local Backdrop = require(UI.Backdrop)
local State = require(script.Parent.Parent.State)
local HudScale = require(ReplicatedStorage.Shared.HudScale)

local New, Children, Value, Computed = Fusion.New, Fusion.Children, Fusion.Value, Fusion.Computed

local UIController = {}

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

	-- The dim behind open panels, edge to edge (over the top-bar strip too), under the main GUI.
	New("ScreenGui")({
		Name = "MutantFarmBackdrop",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 0,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		[Children] = Backdrop(),
	})

	local gui = New("ScreenGui")({
		Name = "MutantFarm",
		DisplayOrder = 1,
		ResetOnSpawn = false,
		-- Directly below Roblox's top bar, which grows with chat, the menu, voice, captures and
		-- platform: never share its strip. (The hatch cutscene is the only full-screen GUI.)
		IgnoreGuiInset = false,
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

	-- Scale from the area the GUI actually covers (below the top bar): the shorter edge against
	-- the design height, capped lower on touch devices (shared/HudScale, Config/Hud). The cap is
	-- chosen once per device, not per input: a hybrid laptop switching between taps and the mouse
	-- would otherwise rescale the whole HUD mid-tap (State.touch still moves SHOP/WATER).
	local touchDevice = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local function updateScale()
		local size = gui.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return
		end
		local s = HudScale.of(size.X, size.Y, touchDevice)
		scale:set(s)
		State.screen:set({ width = size.X, height = size.Y, scale = s })
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
	updateScale()
end

return UIController
