return function(t)
	local Streak = t.require("src/shared/Streak")
	return {
		["first ever claim is day 1"] = function()
			t.eq({ Streak.status(0, 0, 20_000, 7) }, { 1, true, 0 })
		end,
		["claiming the next day continues the streak"] = function()
			t.eq({ Streak.status(3, 19_999, 20_000, 7) }, { 4, true, 3 })
		end,
		["already claimed today"] = function()
			t.eq({ Streak.status(4, 20_000, 20_000, 7) }, { 4, false, 4 })
		end,
		["missing a day resets"] = function()
			t.eq({ Streak.status(5, 19_998, 20_000, 7) }, { 1, true, 0 })
		end,
		["after day 7 it loops to day 1"] = function()
			t.eq({ Streak.status(7, 19_999, 20_000, 7) }, { 1, true, 7 })
		end,
		["streak count keeps growing past the 7-day loop"] = function()
			t.eq({ Streak.status(1, 19_999, 20_000, 7, 8) }, { 2, true, 8 })
			t.eq({ Streak.status(1, 20_000, 20_000, 7, 8) }, { 1, false, 8 })
		end,
	}
end
