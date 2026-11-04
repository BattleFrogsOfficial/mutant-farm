-- HUD scenes (tools/preview/checks/hud.js checks them): the egg tray with 0 / 1 / 2 / 6 owned egg
-- types (the "next egg" tile and gated tiers; two-egg trays with Gem / limited eggs), the 6-egg tray on a touch screen, the growth
-- circle at each of its spots (offering, and on its cooldown while a boost runs), every red dot
-- lit (hud-dots, hud-plot-dots), and the right column at its tallest over a touch layout's
-- mid-right SHOP (phone and hybrid device). Every scene is captured at every preview size through captureHud, so it also runs
-- through the HUD overlap check. The hub at every size is the built-in hud@WxH set.
return function(api)
	local State = api.State
	local set = api.set
	local NOW = 1_800_000_000

	local Eggs = api.requireModule(api.Shared.Config.Eggs)
	-- One Swamp egg growing, so the growth circle shows (it hides with nothing to grow).
	local growing = {
		["1"] = {
			index = 1,
			eggId = "Swamp",
			growth = 40,
			required = Eggs.tiers.Swamp.growTime,
			updatedAt = NOW,
			mutations = {},
		},
	}
	local function snapWith(eggs, earned, extra)
		local s = table.clone(api.snapshot)
		s.eggs = eggs
		s.stats = table.clone(api.snapshot.stats)
		s.stats.totalCashEarned = earned
		s.wateredUntil = 0 -- no boost running: the circle offers the next one ("CLICK" / "4x" / "FOR 5s")
		s.slots = growing
		for k, v in extra or {} do
			s[k] = v
		end
		return s
	end

	-- The main UI mount (scene files start from it).
	api.restoreRoot()

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
	-- 2 owned with long names (they wrap onto two lines): still fits with the next egg tile.
	set(State.snapshot, snapWith({ Starter = 2, StarterGem = 1 }, 0))
	api.captureHud("hud-plot-eggs2-gem")
	set(State.snapshot, snapWith({ Starter = 2, Pumpkin = 1 }, 0))
	api.captureHud("hud-plot-eggs2-pumpkin")
	-- Only Gem eggs: the next egg is Starter, the longest Cash egg name.
	set(State.snapshot, snapWith({ StarterGem = 1, SwampGem = 1 }, 0))
	api.captureHud("hud-plot-eggs2-gemsonly")
	-- 6 owned: Starter, Swamp, Lab and three Gem/limited eggs; Toxic (Rebirth 1) never shows.
	local six = { Starter = 3, Swamp = 2, Lab = 1, StarterGem = 2, SwampGem = 1, Pumpkin = 1 }
	set(State.snapshot, snapWith(six, 26_000))
	api.captureHud("hud-plot-eggs6")
	set(State.touch, true)
	api.captureHud("hud-plot-eggs6-touch")
	set(State.touch, false)

	-- Auto-Harvest owner: a shorter HATCH with REPLANT ALL under it (all on; some on), the 6-egg
	-- tray so the cards still fit beside the column.
	local auto = { AutoHarvest = true }
	local allOn = {}
	for i = 1, api.snapshot.totalSlots do
		allOn[tostring(i)] = true
	end
	set(State.snapshot, snapWith(six, 26_000, { ownedPasses = auto, replant = allOn }))
	api.captureHud("hud-plot-replant-all", { { 1280, 720 }, { 844, 390 }, { 667, 375 }, { 1000, 658 } })
	set(State.snapshot, snapWith({ Starter = 2 }, 0, { ownedPasses = auto, replant = { ["1"] = true } }))
	api.captureHud("hud-plot-replant-some", { { 1280, 720 }, { 800, 360 } })
	set(State.touch, true)
	api.captureHud("hud-plot-replant-some-touch", { { 844, 390 }, { 667, 375 } })
	set(State.touch, false)

	-- Onboarding's buy step: the tray's BUY 2 / STARTER / $100 tile (no eggs in the bag yet), on a
	-- mouse screen and a phone.
	local onboardingSnap = snapWith({}, 215, {
		cash = 215,
		slots = {},
		onboarding = { active = true, shopOpened = false, weather = false },
	})
	local objectiveBefore = State.objective:get(false)
	set(State.snapshot, onboardingSnap)
	set(State.objective, { title = "BUY 2 EGGS", text = "Tap BUY on your egg tray", step = 3, ui = "TrayBuy" })
	api.captureHud("hud-plot-traybuy", { { 1280, 720 }, { 1000, 658 }, { 800, 600 } })
	set(State.touch, true)
	api.captureHud("hud-plot-traybuy-touch", { { 844, 390 }, { 667, 375 } })
	set(State.touch, false)
	set(State.objective, objectiveBefore)

	-- The growth circle at each of its spots (offering), then on its cooldown (a 7x boost running:
	-- "ACTIVE" / "7x" / "0:04" under the shade), on mouse and touch screens.
	local GameConfig = api.requireModule(api.Shared.Config.Game)
	local Hud = api.requireModule(api.Shared.Config.Hud)
	-- (Spots at the sizes that squeeze them: the 900-wide canvases where the chat and the right
	-- column come closest, a tall screen, and the phones; the scene JSON stays small.)
	local MOUSE = { { 800, 600 }, { 1000, 658 }, { 960, 720 }, { 1280, 720 }, { 1920, 1080 } }
	local PHONES = { { 844, 390 }, { 667, 375 }, { 800, 360 } }
	for spot = 1, #Hud.boost.spots do
		set(State.boostSpot, spot)
		set(State.snapshot, snapWith({ Starter = 3, Swamp = 2 }, 12_400, { waterOffer = 10, onPad = true }))
		api.captureHud("hud-plot-boost" .. spot, MOUSE)
		set(State.touch, true)
		api.captureHud("hud-plot-boost" .. spot .. "-touch", PHONES)
		set(State.touch, false)
	end
	set(State.boostSpot, 1)
	local boosted = snapWith({ Starter = 3, Swamp = 2 }, 12_400, {
		wateredUntil = NOW + GameConfig.water.boostSeconds - 1,
		waterMult = 7,
		onPad = true,
	})
	set(State.snapshot, boosted)
	api.captureHud("hud-plot-boosted", { { 1280, 720 }, { 800, 600 } })
	set(State.touch, true)
	api.captureHud("hud-plot-boosted-touch", { { 844, 390 } })
	set(State.touch, false)

	-- Icon sheet (not a "hud" scene): every UI/Icons glyph large and at a HUD size, on navy, 10 per row.
	do
		local Icons = api.requireModule(api.UI.Icons)
		local Theme = api.requireModule(api.UI.Theme)
		local UDim2 = api.roblox.UDim2
		local holder = api.Instance.new("Frame")
		holder.Name = "Root"
		holder.Size = UDim2.fromScale(1, 1)
		holder.BackgroundTransparency = 1
		local sheet = api.Instance.new("Frame")
		sheet.Name = "GlyphSheet"
		sheet.BackgroundColor3 = Theme.colors.navy
		sheet.Position = UDim2.fromOffset(10, 10)
		sheet.Size = UDim2.fromOffset(880, 500)
		sheet.Parent = holder
		local names = {}
		for name in Icons.shapes do
			table.insert(names, name)
		end
		table.sort(names)
		for i, name in names do
			local col, row = (i - 1) % 10, (i - 1) // 10
			local big = Icons.new(name, { Size = 56, Position = UDim2.fromOffset(16 + col * 86, 16 + row * 120) })
			big.Parent = sheet
			local small = Icons.new(name, { Size = 22, Position = UDim2.fromOffset(32 + col * 86, 84 + row * 120) })
			small.Parent = sheet
		end
		api.setRoot(holder)
		api.capture("glyphs")
	end

	-- All three red dots lit (Upgrades affordable, Daily claimable, a new Almanac species), so the
	-- dot checks run on every tile instead of skipping unlit ones.
	api.reset()
	api.restoreRoot()
	do
		local found = 0
		for _ in api.almanac do
			found += 1
		end
		set(State.almanacSeen, found - 1)
		set(State.zone, "hub")
		api.captureHud("hud-dots")
		set(State.zone, "plot")
		api.captureHud("hud-plot-dots")
		set(State.almanacSeen, -1)
	end

	-- Weather line: far from an event (plain), 5 min before (chip), running (chip, time left).
	set(State.zone, "hub")
	set(State.weather, { nextId = "SolarFlare", nextAt = NOW + 564, id = "", endsAt = 0 })
	api.captureHud("hud-weather-idle")
	set(State.weather, { nextId = "GlitchStorm", nextAt = NOW + 252, id = "", endsAt = 0 })
	api.captureHud("hud-weather-soon")
	set(State.zone, "plot")
	set(State.weather, { nextId = "AcidRain", nextAt = NOW + 1500, id = "SolarFlare", endsAt = NOW + 102 })
	api.captureHud("hud-plot-weather-active")

	-- The right column at its tallest (no global event soon, so Instant Weather shows; the Starter
	-- Bundle runs; the bag at the plot) above the mid-right SHOP / WATER of a touch layout: on a
	-- phone (touch device, 1.0x cap) and on a hybrid device (touch layout, mouse cap up to 1.25x).
	set(State.weather, { nextId = "GlitchStorm", nextAt = NOW + 1200, id = "", endsAt = 0 })
	set(State.touch, true)
	set(State.zone, "hub")
	api.captureHud("hud-instant-weather-touch")
	set(State.zone, "plot")
	api.captureHud("hud-plot-instant-weather-touch")
	api.setTouchDevice(false)
	api.captureHud("hud-plot-hybrid-touch")
	set(State.zone, "hub")
	api.captureHud("hud-hybrid-touch")

	api.reset()
	api.restoreRoot()
end
