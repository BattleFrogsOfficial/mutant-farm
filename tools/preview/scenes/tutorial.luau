-- The tutorial card (Config/Tutorial, Hud's card in the Next Up slot): every step on your plot and
-- in the hub, the check animation, the WEATHER! card, and Next Up in the same chrome after the
-- tutorial. Names start with "hud" so the HUD overlap check runs on each (checks/tutorial.js
-- checks the card itself).
return function(api)
	local State = api.State
	local set = api.set
	local Tutorial = api.requireModule(api.Shared.Config.Tutorial)
	local Onboarding = api.requireModule(api.Shared.Onboarding)
	local Eggs = api.requireModule(api.Shared.Config.Eggs)
	local NOW = 1_800_000_000

	api.restoreRoot()
	local snap = table.clone(api.snapshot)
	snap.eggs = { Starter = 2 }
	snap.wateredUntil = 0
	snap.onPad = true -- so the growth circle shows at the plot with the card under it
	snap.slots = {
		["1"] = {
			index = 1,
			eggId = "Starter",
			growth = 20,
			required = Eggs.tiers.Starter.growTime,
			updatedAt = NOW,
			mutations = {},
		},
	}
	set(State.snapshot, snap)

	local SIZES = { { 1280, 720 }, { 1000, 658 }, { 800, 600 }, { 1920, 1080 } }
	local TOUCH = { { 844, 390 }, { 667, 375 } }
	local before = State.objective:get(false)

	local function stepObjective(st, extra)
		local o = {
			title = st.title,
			text = string.format(st.line, "$200"),
			step = Onboarding.stepIndex(st.id),
			hub = true,
		}
		for k, v in extra or {} do
			o[k] = v
		end
		return o
	end

	for _, zone in { "plot", "hub" } do
		set(State.zone, zone)
		for _, st in Tutorial.steps do
			set(State.objective, stepObjective(st, if st.id == "buy" then { ui = "TrayBuy" } else nil))
			api.captureHud(string.format("hud-%s-tut-%s", zone, st.id), SIZES)
		end
		-- A completed step's check, and the WEATHER! card.
		set(State.objective, stepObjective(Tutorial.steps[4], { done = true }))
		api.captureHud(string.format("hud-%s-tut-check", zone), SIZES)
		set(State.objective, {
			title = Tutorial.weather.title,
			text = Tutorial.weather.line,
			step = 5,
			hub = true,
		})
		api.captureHud(string.format("hud-%s-tut-weather", zone), SIZES)
		-- Touch layouts (phone): the longest title.
		set(State.touch, true)
		set(State.objective, stepObjective(Tutorial.steps[5]))
		api.captureHud(string.format("hud-%s-tut-water-touch", zone), TOUCH)
		set(State.touch, false)
	end

	-- After the tutorial: Next Up in the same chrome (the rebirth goal, the longest line).
	set(State.zone, "plot")
	set(State.objective, { title = "REBIRTH 2", text = "$1.2M / $3.15M earned this life", progress = 0.38 })
	api.captureHud("hud-plot-tut-nextup", SIZES)
	set(State.objective, before)
end
