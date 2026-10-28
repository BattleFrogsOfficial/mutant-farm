--!strict
-- Receives server snapshots and notifications and feeds them into State.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Eggs = require(Shared.Config.Eggs)
local State = require(script.Parent.Parent.State)

local StateController = {}

function StateController.Init() end

function StateController.Start()
	local UserInputService = game:GetService("UserInputService")
	State.touch:set(UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	-- Touch switches to the touch layout; only real mouse/keyboard/gamepad input switches back
	-- (focus, on-screen keyboard text, gyro etc. must not flip a phone to the desktop layout).
	local DESKTOP_INPUT = {
		[Enum.UserInputType.Keyboard] = true,
		[Enum.UserInputType.MouseButton1] = true,
		[Enum.UserInputType.MouseButton2] = true,
		[Enum.UserInputType.MouseButton3] = true,
		[Enum.UserInputType.MouseMovement] = true,
		[Enum.UserInputType.MouseWheel] = true,
		[Enum.UserInputType.Gamepad1] = true,
	}
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		if inputType == Enum.UserInputType.Touch then
			State.touch:set(true)
		elseif DESKTOP_INPUT[inputType] and (UserInputService.KeyboardEnabled or UserInputService.MouseEnabled) then
			State.touch:set(false)
		end
	end)

	Remotes.get("State").OnClientEvent:Connect(function(snapshot)
		State.snapshot:set(snapshot)
		-- Keep the selected egg valid: fall back to a Cash egg the player owns, cheapest tier first.
		-- Never auto-select a Gem egg (bought with Gems): planting one must be the player's choice.
		local selected = State.selectedEgg:get(false)
		if not snapshot.eggs[selected] then
			for _, eggId in Eggs.order do
				if snapshot.eggs[eggId] then
					State.selectedEgg:set(eggId)
					break
				end
			end
		end
	end)

	Remotes.get("Payout").OnClientEvent:Connect(function(amount)
		State.lastPayout:set({ amount = amount, at = State.clock:get(false) })
	end)

	Remotes.get("WelcomeBack").OnClientEvent:Connect(function(info)
		State.welcome:set(info)
		State.panel:set("welcome")
	end)

	-- The group offer (once, after the first sale) waits until the Sell panel is closed.
	Remotes.get("GroupOffer").OnClientEvent:Connect(function()
		task.spawn(function()
			while State.panel:get(false) ~= "none" or State.hatching:get(false) do
				task.wait(0.5)
			end
			State.panel:set("groupOffer")
		end)
	end)

	Remotes.get("Almanac").OnClientEvent:Connect(function(entries)
		local merged = table.clone(State.almanac:get(false))
		for id, entry in entries do
			merged[id] = entry
		end
		State.almanac:set(merged)
	end)

	Remotes.get("Notify").OnClientEvent:Connect(function(message, kind)
		State.toast(message, kind)
	end)

	-- The first Almanac sync sets the baseline so old discoveries don't show as NEW.
	task.spawn(function()
		while State.almanacSeen:get(false) < 0 do
			local n = 0
			for _ in State.almanac:get(false) do
				n += 1
			end
			if n > 0 or State.snapshot:get(false) then
				task.wait(1)
				local count = 0
				for _ in State.almanac:get(false) do
					count += 1
				end
				State.almanacSeen:set(count)
			end
			task.wait(0.5)
		end
	end)

	-- Weather schedule from the server's Workspace attributes.
	local function readWeather()
		State.weather:set({
			nextId = (workspace:GetAttribute("WeatherNextId") or "") :: string,
			nextAt = (workspace:GetAttribute("WeatherNextAt") or 0) :: number,
			id = (workspace:GetAttribute("WeatherId") or "") :: string,
			endsAt = (workspace:GetAttribute("WeatherEndsAt") or 0) :: number,
		})
	end
	workspace.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 7) == "Weather" then
			readWeather()
		end
	end)
	readWeather()

	-- ~30 updates a second is plenty for pulses and glows.
	local start, last = os.clock(), 0
	game:GetService("RunService").Heartbeat:Connect(function()
		local t = os.clock() - start
		if t - last >= 1 / 30 then
			last = t
			State.clock:set(t)
		end
	end)

	while true do
		State.now:set(workspace:GetServerTimeNow())
		task.wait(0.2)
	end
end

return StateController
