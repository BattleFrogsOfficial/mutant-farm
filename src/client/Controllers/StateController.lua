--!strict
-- Receives server snapshots and notifications and feeds them into State.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.Parent.State)

local StateController = {}

function StateController.Init() end

function StateController.Start()
	Remotes.get("State").OnClientEvent:Connect(function(snapshot)
		State.snapshot:set(snapshot)
		-- Keep the selected egg valid: fall back to any egg the player owns.
		local selected = State.selectedEgg:get(false)
		if not snapshot.eggs[selected] then
			for eggId in snapshot.eggs do
				State.selectedEgg:set(eggId)
				break
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
