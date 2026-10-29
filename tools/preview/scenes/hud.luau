-- HUD scenes (tools/preview/checks/hud.js checks them): the egg tray with 0 / 1 / 2 / 6 owned egg
-- types (the "next egg" tile and gated tiers), the 6-egg tray on a touch screen, and the watered
-- state (drain ring running, WATER dimmed). Every scene is captured at every preview size through
-- captureHud, so it also runs through the HUD overlap check. The hub at every size is the built-in
-- hud@WxH set.
return function(api)
	local State = api.State
	local set = api.set
	local NOW = 1_800_000_000

	local function snapWith(eggs, earned, extra)
		local s = table.clone(api.snapshot)
		s.eggs = eggs
		s.stats = table.clone(api.snapshot.stats)
		s.stats.totalCashEarned = earned
		s.wateredUntil = 0 -- not watered (the label reads "WATER · 2x 30s")
		for k, v in extra or {} do
			s[k] = v
		end
		return s
	end

	-- Mount a fresh copy of the main UI (the same Root the game mounts; State is shared): the
	-- export's default root is left on the hatch screen by the built-in scenes.
	api.setRoot(api.requireModule(api.UI.Root)())

	set(State.zone, "plot")

	-- 0 owned: the tray shows only the next egg (Starter, $50).
	set(State.snapshot, snapWith({}, 0))
	api.captureHud("hud-plot-eggs0")
	-- A new player (2 Starter eggs): next egg Swamp, $500. Lab ($25K earned) never shows.
	set(State.snapshot, snapWith({ Starter = 2 }, 0))
	api.captureHud("hud-plot-eggs1-new")
	-- 2 owned, $26K earned: Lab is unlocked and not owned, so it's the next egg ($5K).
	set(State.snapshot, snapWith({ Starter = 3, Swamp = 1, Lab = 0 }, 26_000))
	api.captureHud("hud-plot-eggs2")
	-- 6 owned: Starter, Swamp, Lab and three Gem/limited eggs; Toxic (Rebirth 1) never shows.
	local six = { Starter = 3, Swamp = 2, Lab = 1, StarterGem = 2, SwampGem = 1, Pumpkin = 1 }
	set(State.snapshot, snapWith(six, 26_000))
	api.captureHud("hud-plot-eggs6")
	set(State.touch, true)
	api.captureHud("hud-plot-eggs6-touch")
	set(State.touch, false)

	-- Watered: the ring runs (a growing egg), WATER is dimmed and shows the countdown.
	local Eggs = api.requireModule(api.Shared.Config.Eggs)
	local watered = snapWith({ Starter = 3, Swamp = 2 }, 12_400, {
		wateredUntil = NOW + 18,
		slots = {
			["1"] = {
				index = 1,
				eggId = "Swamp",
				growth = 40,
				required = Eggs.tiers.Swamp.growTime,
				updatedAt = NOW,
				mutations = {},
			},
		},
	})
	set(State.snapshot, watered)
	api.captureHud("hud-plot-watered")
	set(State.touch, true)
	api.captureHud("hud-plot-watered-touch")
	set(State.touch, false)

	-- Glyph sheet (not a "hud" scene): every vector icon large and at its HUD size, on navy.
	do
		local Glyphs = api.requireModule(api.UI.Glyphs)
		local Theme = api.requireModule(api.UI.Theme)
		local UDim2 = api.roblox.UDim2
		local holder = api.Instance.new("Frame")
		holder.Name = "Root"
		holder.Size = UDim2.fromScale(1, 1)
		holder.BackgroundTransparency = 1
		local sheet = api.Instance.new("Frame")
		sheet.Name = "GlyphSheet"
		sheet.BackgroundColor3 = Theme.colors.navy
		sheet.Position = UDim2.fromOffset(20, 20)
		sheet.Size = UDim2.fromOffset(860, 300)
		sheet.Parent = holder
		local names = { "arrowUp", "gift", "book", "coin", "gem", "egg", "bag", "drop" }
		for i, name in names do
			local big = Glyphs.new(name, { Size = 80, Position = UDim2.fromOffset(20 + (i - 1) * 105, 30) })
			big.Parent = sheet
			local small = Glyphs.new(name, { Size = 24, Position = UDim2.fromOffset(48 + (i - 1) * 105, 170) })
			small.Parent = sheet
		end
		api.setRoot(holder)
		api.capture("glyphs")
	end

	api.reset()
	api.restoreRoot()
end
