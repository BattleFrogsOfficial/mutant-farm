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
State.panel = Value("none") -- "none" | "shop" | "sell"
State.toasts = Value({} :: { { id: number, text: string, kind: string } })

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
function State.toast(text: string, kind: string?)
	nextToastId += 1
	local id = nextToastId
	local list = table.clone(State.toasts:get(false))
	table.insert(list, { id = id, text = text, kind = kind or "info" })
	while #list > 4 do
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
