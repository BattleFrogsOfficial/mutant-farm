--!strict
-- Number and time formatting shared by UI and server messages.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trimZero(s: string): string
	return (s:gsub("%.0$", ""))
end

-- 950 -> "950", 1234 -> "1.2K", 45_600_000 -> "45.6M", 123_456 -> "123K"
function Format.number(n: number): string
	if n ~= n then
		return "0"
	end
	local sign = n < 0 and "-" or ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	-- Truncate rather than round so 999.96K never shows as "1000K".
	local text
	if scaled < 100 then
		text = trimZero(string.format("%.1f", math.floor(scaled * 10) / 10))
	else
		text = tostring(math.floor(scaled))
	end
	return sign .. text .. SUFFIXES[tier + 1]
end

function Format.cash(n: number): string
	return "$" .. Format.number(n)
end

-- 42 -> "42s", 125 -> "2m 05s", 7260 -> "2h 01m"
function Format.duration(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds < 60 then
		return string.format("%ds", seconds)
	elseif seconds < 3600 then
		return string.format("%dm %02ds", seconds // 60, seconds % 60)
	else
		return string.format("%dh %02dm", seconds // 3600, (seconds % 3600) // 60)
	end
end

-- Odds display: 80 -> "80%", 4.45 -> "4.45%", 2.875 -> "2.88%", 0.125 -> "0.125%"
function Format.percent(p: number): string
	local text = string.format(if p >= 10 then "%.1f" elseif p >= 1 then "%.2f" else "%.3f", p)
	text = text:gsub("0+$", ""):gsub("%.$", "")
	return text .. "%"
end

return Format
