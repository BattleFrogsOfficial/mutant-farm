--!strict
-- Assigns each player a plot, spawns them inside its gate, and mirrors their state onto the plot
-- as attributes: slot states (owned / buy / locked), growing eggs, and the pen display.
-- Every client draws every plot from those attributes, so visitors see the same farm.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage.Shared
local Growth = require(Shared.Growth)
local GateSign = require(Shared.GateSign)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local World = require(script.Parent.Parent.Util.World)

local PlotService = {}

local plots: { World.Plot } = {}
local owners: { [Player]: World.Plot } = {}

function PlotService.getPlot(player: Player): World.Plot?
	return owners[player]
end

-- Shows or hides the sign board a SurfaceGui label sits on (label -> SurfaceGui -> board part).
local function setBoardVisible(label: TextLabel, visible: boolean)
	local gui = label.Parent
	local board = gui and gui.Parent
	if board and board:IsA("BasePart") then
		board.Transparency = if visible then 0 else 1
	end
end

-- The owner's best mutants (by sell value) for the pen, as JSON.
-- The pen's mutants (DataService.penItems) as JSON for clients to draw.
local function penJson(data: Types.Profile): string
	local out = {}
	for i, item in DataService.penItems(data) do
		out[i] = {
			id = item.id,
			tier = item.tier,
			rarity = item.rarity,
			species = item.species,
			mutations = item.mutations,
			size = item.size,
		}
	end
	return HttpService:JSONEncode(out)
end

-- Writes the player's current state to their plot. Runs after every batched data change.
function PlotService.refresh(player: Player, data: Types.Profile)
	local plot = owners[player]
	if not plot then
		return
	end
	plot.model:SetAttribute("WateredUntil", data.wateredUntil)
	plot.model:SetAttribute("Speed", DataService.speed(data))
	-- The gate's second line: live pen income ("$0/min · plant eggs to earn" before the first harvest).
	plot.income.Text = GateSign.incomeText(DataService.incomePerMinute(data), data.stats.harvested)
	setBoardVisible(plot.income, true)
	local pen = penJson(data)
	if plot.model:GetAttribute("Pen") ~= pen then
		plot.model:SetAttribute("Pen", pen)
	end
	for i, part in plot.slots do
		local total = DataService.totalSlots(data)
		local state = if i <= total then "owned" elseif i == total + 1 then "buy" else "locked"
		part:SetAttribute("State", state)
		local click = part:FindFirstChildOfClass("ClickDetector")
		if click then
			click.MaxActivationDistance = if state == "locked" then 0 else 60
		end
		if state == "owned" then
			part.Transparency = 0
			part.Color = World.colors.soil
			part.Material = Enum.Material.Ground
		elseif state == "buy" then
			part.Transparency = 0.3
			part.Color = World.colors.buy
			part.Material = Enum.Material.SmoothPlastic
			-- The owner's client draws the price on the patch (PlotController's soil marker).
			part:SetAttribute("Price", DataService.nextSlotCost(data) or 0)
		else
			part.Transparency = 1
		end

		local slot = data.slots[tostring(i)]
		if slot and state == "owned" then
			part:SetAttribute("EggId", slot.eggId)
			part:SetAttribute("Mutations", table.concat(slot.mutations, ","))
			part:SetAttribute("Growth", slot.growth)
			part:SetAttribute("UpdatedAt", slot.updatedAt)
			part:SetAttribute("Required", Growth.requiredSeconds(slot.eggId, slot.rarity))
		else
			part:SetAttribute("EggId", "")
			part:SetAttribute("Mutations", "")
		end
	end
end

local function clear(plot: World.Plot)
	plot.model:SetAttribute("OwnerUserId", 0)
	plot.model:SetAttribute("WateredUntil", 0)
	plot.model:SetAttribute("Pen", "[]")
	plot.sign.Text = "Empty Plot"
	plot.income.Text = ""
	setBoardVisible(plot.income, false)
	for _, part in plot.slots do
		part:SetAttribute("State", "locked")
		part:SetAttribute("EggId", "")
		part:SetAttribute("Mutations", "")
		part.Transparency = 1
		local click = part:FindFirstChildOfClass("ClickDetector")
		if click then
			click.MaxActivationDistance = 0
		end
	end
end

-- Characters load only once the plot is assigned, so players appear inside their own gate.
local function spawn(player: Player)
	if player.Parent == Players and owners[player] then
		player:LoadCharacter()
	end
end

local function assign(player: Player, data: Types.Profile)
	for _, plot in plots do
		if plot.model:GetAttribute("OwnerUserId") == 0 then
			owners[player] = plot
			plot.model:SetAttribute("OwnerUserId", player.UserId)
			plot.sign.Text = player.DisplayName .. "'s Farm"
			player.RespawnLocation = plot.spawn
			PlotService.refresh(player, data)
			spawn(player)
			return
		end
	end
	-- Only possible if Max Players in Game Settings is above islandCount.
	warn("[PlotService] no free plot for", player.Name)
	player:Kick("This server is full. Please join another one!")
end

local function watchDeaths(player: Player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(function()
				task.delay(Players.RespawnTime, spawn, player)
			end)
		end
	end)
end

function PlotService.Init()
	plots = World.build()
	Players.CharacterAutoLoads = false
end

function PlotService.Start()
	DataService.Loaded:Connect(assign)
	DataService.Changed:Connect(PlotService.refresh)
	Players.PlayerAdded:Connect(watchDeaths)
	for _, player in Players:GetPlayers() do
		watchDeaths(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local plot = owners[player]
		owners[player] = nil
		if plot then
			clear(plot)
		end
	end)
end

return PlotService
