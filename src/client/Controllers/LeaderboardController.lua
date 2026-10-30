--!strict
-- Draws the two global boards in the hub (Top Pens, Top Rebirths) from the server's `Leaderboards`
-- message: a scrolling list of the top 100 on each board's face, and the viewer's own row pinned
-- at the bottom ("#12 YOU" or "#100+ YOU" when outside the top 100) with their live value. The
-- SurfaceGuis live in PlayerGui (adorned to the boards) so the lists can scroll.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.Game)
local Format = require(Shared.Format)
local Leaderboards = require(Shared.Leaderboards)
local Pen = require(Shared.Pen)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.Parent.State)

local Observer = Fusion.Observer

local LeaderboardController = {}

local ROW_H = 38
local OWN_H = 48
local INK = Color3.fromHex("#1E2230")
local GOLD = Color3.fromHex("#FFD24A")
local CREAM = Color3.fromHex("#FFF4D6")

type Board = { list: ScrollingFrame, own: TextLabel, entries: { Leaderboards.Entry } }

local BOARDS = {
	pens = { model = "TopPens", format = Format.cash },
	rebirths = {
		model = "TopRebirths",
		format = function(n: number): string
			return tostring(n)
		end,
	},
}

local boards: { [string]: Board } = {}

local function label(props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do
		(t :: any)[k] = v
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = INK
	stroke.Parent = t
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.Parent = t
	return t
end

local function rowText(rank: string, name: string, value: string): string
	return string.format("%s  %s  ·  %s", rank, name, value)
end

-- The viewer's value right now (the board itself refreshes every 120 s).
local function ownValue(id: string): number
	local snap = State.get()
	if not snap then
		return 0
	end
	if id == "pens" then
		return Leaderboards.penValue(
			Pen.select(snap.inventory :: any, snap.penCapacity or GameConfig.penDisplayCount) :: any
		)
	end
	return snap.rebirths
end

-- The viewer's own row: "#12  YOU  ·  $4.5M", or "#100+" outside the top list.
local function ownText(id: string, entries: { Leaderboards.Entry }): string
	local rank = Leaderboards.rankOf(entries, Players.LocalPlayer.UserId)
	return rowText(
		if rank then "#" .. rank else "#" .. Leaderboards.SIZE .. "+",
		"YOU",
		BOARDS[id].format(ownValue(id))
	)
end

local function render(id: string)
	local board = boards[id]
	if not board then
		return
	end
	local fmt = BOARDS[id].format
	for _, child in board.list:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local me = Players.LocalPlayer.UserId
	for i, entry in board.entries do
		label({
			Name = "Row" .. i,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, ROW_H),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if entry.userId == me then GOLD else Color3.new(1, 1, 1),
			Text = rowText(i .. ".", entry.name, fmt(entry.value)),
			Parent = board.list,
		})
	end
	if #board.entries == 0 then
		label({
			Name = "Empty",
			Size = UDim2.new(1, 0, 0, ROW_H),
			TextColor3 = CREAM,
			Text = "Loading...",
			Parent = board.list,
		})
	end
	board.own.Text = ownText(id, board.entries)
end

local function build(id: string, part: BasePart): Board
	local gui = Instance.new("SurfaceGui")
	gui.Name = BOARDS[id].model
	gui.Adornee = part
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.15
	gui.ResetOnSpawn = false
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.new(1, 0, 1, -OWN_H)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local ownBar = Instance.new("Frame")
	ownBar.Name = "You"
	ownBar.AnchorPoint = Vector2.new(0, 1)
	ownBar.Position = UDim2.fromScale(0, 1)
	ownBar.Size = UDim2.new(1, 0, 0, OWN_H)
	ownBar.BackgroundColor3 = Color3.fromHex("#5E2FB8")
	ownBar.BorderSizePixel = 0
	ownBar.Parent = gui
	local own = label({
		Name = "Own",
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GOLD,
		Text = "",
		Parent = ownBar,
	})
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return { list = list, own = own, entries = {} }
end

function LeaderboardController.Init() end

function LeaderboardController.Start()
	-- Listen first: the server sends the boards as soon as your profile loads.
	local latest: { [string]: { Leaderboards.Entry } } = {}
	Remotes.get("Leaderboards").OnClientEvent:Connect(function(lists)
		for id in BOARDS do
			if lists[id] then
				latest[id] = lists[id]
				if boards[id] then
					boards[id].entries = lists[id]
					render(id)
				end
			end
		end
	end)
	local hub = workspace:WaitForChild("Map"):WaitForChild("Hub")
	for id, info in BOARDS do
		local model = hub:WaitForChild(info.model, 60)
		local part = model and model:WaitForChild("Board", 60) :: BasePart?
		if part then
			boards[id] = build(id, part)
			boards[id].entries = latest[id] or {}
			render(id)
		else
			warn("[LeaderboardController] board missing:", info.model)
		end
	end
	-- Your own row follows your live value between board refreshes.
	Observer(State.snapshot):onChange(function()
		for id, board in boards do
			board.own.Text = ownText(id, board.entries)
		end
	end)
end

return LeaderboardController
