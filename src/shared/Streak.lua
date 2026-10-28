--!strict
-- Daily streak rules as a pure function so they can be tested.
-- `today` is a UTC day number (floor(unix seconds / 86400)).

local Streak = {}

-- Returns the reward day you would claim next (1..length, looping), whether you can claim now,
-- and how many days in a row you've claimed (`count`, which keeps growing past the 7-day loop).
function Streak.status(
	day: number,
	lastClaimDay: number,
	today: number,
	length: number,
	count: number?
): (number, boolean, number)
	local streak = count or day
	if lastClaimDay == today then
		return day, false, streak
	end
	if lastClaimDay == today - 1 then
		return (day % length) + 1, true, streak
	end
	return 1, true, 0
end

return Streak
