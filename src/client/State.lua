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
-- "none" | "shop" | "sell" | "almanac" | "daily" | "welcome" | "store" | "slotOffer" | "rebirth" | "upgrades"
State.panel = Value("none")
-- Weather from Workspace attributes (WeatherService): the next event and the one running now.
State.weather = Value({ nextId = "", nextAt = 0, id = "", endsAt = 0 })
State.toasts = Value({} :: { { id: number, text: string, kind: string } })
-- "Next up" panel: { text, progress?, ui? } where ui names a HUD button to pulse.
State.objective = Value({ text = "", progress = nil :: number?, ui = nil :: string?, hub = nil :: boolean? })
-- Almanac entries the player has discovered: speciesId -> { n, first, best }
State.almanac = Value({} :: { [string]: { n: number, first: number, best: number } })
-- Where the player is: "hub" (the plaza and paths) or "plot" (on their own island). The HUD
-- shows only what that place needs (ZoneController sets it).
State.zone = Value("hub")
-- Screen size in pixels and the HUD's design-to-pixel scale (UIController keeps it current).
State.screen = Value({ width = 1280, height = 720, scale = 1 })
-- Touch screen (phones/tablets): the thumbstick and jump button own the bottom corners.
State.touch = Value(false)
-- Egg Shop carousel: Cash/Gems switch (session only), focused tier (1..#Eggs.order) and the strip
-- offset in design px (card i is centered at (i - 1) * EggShopUI.pitch).
State.shopMode = Value("Cash")
State.shopFocus = Value(1)
State.shopOffset = Value(0)
-- True while the hatch cutscene owns the camera (pens hold their update until it ends).
State.hatching = Value(false)

function State.get(): Types.Snapshot?
	return State.snapshot:get(false)
end

State.cash = Computed(function()
	local snap = State.snapshot:get()
	return if snap then snap.cash else 0
end)

State.gems = Computed(function()
	local snap = State.snapshot:get()
	return if snap then snap.gems else 0
end)

-- Seconds until the soonest growing egg is ready (nil if nothing is growing).
State.nextReadyIn = Computed(function()
	local snap = State.snapshot:get()
	local now = State.now:get()
	if not snap then
		return nil
	end
	local best: number? = nil
	for _, slot in snap.slots do
		local left = Growth.secondsRemaining(
			State.slotGrowth(snap, slot, now),
			slot.required,
			now,
			snap.wateredUntil,
			snap.speed
		)
		if left > 0 and (best == nil or left < best) then
			best = left
		end
	end
	return best
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

-- One toast lane, one message at a time. New ones queue (newest few kept) and each shows for
-- TOAST_SECONDS. State.toasts holds the one on screen (a list of 0 or 1 for the UI).
local TOAST_SECONDS = 2.6
local MAX_QUEUED = 4
local nextToastId = 0
local queue: { { id: number, text: string, kind: string } } = {}
local showing = false

local function pump()
	if showing then
		return
	end
	showing = true
	task.spawn(function()
		while #queue > 0 do
			-- The HUD (and the toast lane) is hidden during the hatch cutscene; wait it out.
			while State.hatching:get(false) do
				task.wait(0.2)
			end
			local toast = table.remove(queue, 1)
			State.toasts:set({ toast })
			task.wait(TOAST_SECONDS)
			State.toasts:set({})
			task.wait(0.15)
		end
		showing = false
	end)
end

function State.toast(text: string, kind: string?)
	nextToastId += 1
	table.insert(queue, { id = nextToastId, text = text, kind = kind or "info" })
	while #queue > MAX_QUEUED do
		table.remove(queue, 1)
	end
	pump()
end

return State
