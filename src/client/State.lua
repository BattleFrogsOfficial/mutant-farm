--!strict
-- Client-side reactive state. The server snapshot is the only source of truth;
-- everything here is either a copy of it or pure UI state (selection, open panel, toasts).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Growth = require(ReplicatedStorage.Shared.Growth)
local Types = require(ReplicatedStorage.Shared.Types)

local Value, Computed = Fusion.Value, Fusion.Computed

local State = {}

State.snapshot = Value(nil :: Types.Snapshot?)
State.now = Value(workspace:GetServerTimeNow())
State.selectedEgg = Value("Starter")
-- Seconds since start, ticked ~30x/s; drives pulses and glows.
State.clock = Value(0)
-- "Welcome back" summary from the server: { away, ready, mutations, capped } or nil.
State.welcome = Value(nil :: { away: number, ready: number, mutations: number, capped: boolean, earned: number? }?)
-- How many Almanac species the player had seen when they last opened it (for the NEW dot).
State.almanacSeen = Value(-1)
-- Last pen payout from the server: amount and client clock time it arrived (for the flash/pop).
State.lastPayout = Value({ amount = 0, at = -10 })
State.panel = Value("none") -- "none" | "shop" | "sell" | "almanac" | "daily" | "welcome"
State.toasts = Value({} :: { { id: number, text: string, kind: string } })
-- "Next up" panel: { text, progress?, ui? } where ui names a HUD button to pulse.
State.objective = Value({ text = "", progress = nil :: number?, ui = nil :: string? })
-- Almanac entries the player has discovered: speciesId -> { n, first, best }
State.almanac = Value({} :: { [string]: { n: number, first: number, best: number } })
-- True while the hatch cutscene owns the camera (pens hold their update until it ends).
State.hatching = Value(false)

function State.get(): Types.Snapshot?
	return State.snapshot:get(false)
end

State.cash = Computed(function()
	local snap = State.snapshot:get()
	return if snap then snap.cash else 0
end)

-- Growth of a slot right now, using the same math as the server.
function State.slotGrowth(snap: Types.Snapshot, slot: Types.SlotView, now: number): number
	return Growth.advance(slot.growth, slot.updatedAt, now, snap.wateredUntil, snap.speed)
end

State.readyCount = Computed(function()
	local snap = State.snapshot:get()
	local now = State.now:get()
	if not snap then
		return 0
	end
	local n = 0
	for _, slot in snap.slots do
		if State.slotGrowth(snap, slot, now) >= slot.required then
			n += 1
		end
	end
	return n
end)

local nextToastId = 0
local heldToasts: { { text: string, kind: string? } } = {}
local releasing = false
function State.toast(text: string, kind: string?)
	-- The HUD (and the toast stack) is hidden during the hatch cinematic; hold toasts until it ends.
	if State.hatching:get(false) then
		table.insert(heldToasts, { text = text, kind = kind })
		if not releasing then
			releasing = true
			task.spawn(function()
				while State.hatching:get(false) do
					task.wait(0.2)
				end
				releasing = false
				local held = heldToasts
				heldToasts = {}
				-- Keep the newest few; older ones would scroll off anyway.
				for i = math.max(1, #held - 2), #held do
					State.toast(held[i].text, held[i].kind)
				end
			end)
		end
		return
	end
	nextToastId += 1
	local id = nextToastId
	local list = table.clone(State.toasts:get(false))
	table.insert(list, { id = id, text = text, kind = kind or "info" })
	while #list > 3 do
		table.remove(list, 1)
	end
	State.toasts:set(list)
	task.delay(3, function()
		local current = table.clone(State.toasts:get(false))
		for i, toast in current do
			if toast.id == id then
				table.remove(current, i)
				break
			end
		end
		State.toasts:set(current)
	end)
end

return State
