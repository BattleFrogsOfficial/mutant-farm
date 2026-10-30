--!strict
-- The farm's income line, on the gate sign (PlotService writes it under the "<name>'s Farm" board)
-- and under Cash: the expected Cash per minute (DataService.incomePerMinute: growing eggs + pen),
-- alone ("$3.4K/min"). With nothing earning before the first harvest it says what to do.

local Format = require(script.Parent.Format)

local GateSign = {}

-- "$0/min · PLANT EGGS" while nothing earns before the first harvest, else "$3.4K/min" (also
-- "$0/min" later with nothing growing and an empty pen).
function GateSign.incomeText(incomePerMinute: number, harvested: number): string
	local rate = Format.cash(math.max(0, incomePerMinute)) .. "/min"
	if harvested <= 0 and incomePerMinute <= 0 then
		return rate .. " · PLANT EGGS"
	end
	return rate
end

return GateSign
