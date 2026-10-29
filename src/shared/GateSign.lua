--!strict
-- The farm gate's second line (PlotService writes it under the "<name>'s Farm" board): the live
-- pen income. Before the first harvest it also says how to start earning.

local Format = require(script.Parent.Format)

local GateSign = {}

-- "$0/min · plant eggs to earn" until the first harvest, then "$3.4K/min" (also "$0/min" with an
-- empty pen).
function GateSign.incomeText(incomePerMinute: number, harvested: number): string
	local rate = Format.cash(math.max(0, incomePerMinute)) .. "/min"
	if harvested <= 0 then
		return rate .. " · plant eggs to earn"
	end
	return rate
end

return GateSign
