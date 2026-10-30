--!strict
-- The farm gate's second line (PlotService writes it under the "<name>'s Farm" board): the live
-- pen income, alone ("$3.4K/min"). Before the first harvest a hint goes under it on its own line
-- ("$0/min" / "plant eggs to earn"), so the board never breaks the hint mid-phrase.

local Format = require(script.Parent.Format)

local GateSign = {}

-- "$0/min\nplant eggs to earn" until the first harvest, then "$3.4K/min" (also "$0/min" with an
-- empty pen).
function GateSign.incomeText(incomePerMinute: number, harvested: number): string
	local rate = Format.cash(math.max(0, incomePerMinute)) .. "/min"
	if harvested <= 0 then
		return rate .. "\nplant eggs to earn"
	end
	return rate
end

return GateSign
