-- Daily panel (UI/DailyPanel): day 1 to claim (no streak), day 4 to claim (3 claimed), day 7 to
-- claim (the wide Toxic card is today), and day 4 already claimed (the countdown button).
return function(api)
	local State, set = api.State, api.set
	set(State.panel, "daily")
	for _, case in { { 1, true, 0 }, { 4, true, 3 }, { 7, true, 6 }, { 4, false, 4 } } do
		local snap = table.clone(api.snapshot)
		snap.daily = { day = case[1], canClaim = case[2], streak = case[3] }
		set(State.snapshot, snap)
		api.capture(string.format("daily-day%d%s", case[1], if case[2] then "" else "-claimed"))
	end
	api.reset()
end
