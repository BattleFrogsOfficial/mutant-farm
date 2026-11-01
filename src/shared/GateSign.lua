--!strict
-- The farm's income line, on the gate sign (PlotService writes it under the "<name>'s Farm" board)
-- and under Cash: the expected Cash per minute (DataService.incomePerMinute: eggs still growing +
-- pen), alone while eggs grow ("$3.4K/min"). Under $10 it keeps its cents, so a lone pen mutant
-- still reads as earning ("$0.04/min"). With nothing growing it says what to do: hatch the ready
-- eggs, or plant some.

local Format = require(script.Parent.Format)

local GateSign = {}

-- The rate: "$0", "$0.04" .. "$9.99" (cents under $10), then "$12", "$3.4K".
function GateSign.rate(incomePerMinute: number): string
	local n = math.max(0, incomePerMinute)
	if n > 0 and n < 10 then
		return string.format("$%.2f", math.floor(n * 100) / 100)
	end
	return Format.cash(math.floor(n))
end

-- "$3.4K/min" while eggs grow; with none growing "$0.04/min · HATCH EGGS" (some are ready) or
-- "$0/min · PLANT EGGS".
function GateSign.incomeText(incomePerMinute: number, growing: number, ready: number): string
	local text = GateSign.rate(incomePerMinute) .. "/min"
	if growing > 0 then
		return text
	end
	return text .. (if ready > 0 then " · HATCH EGGS" else " · PLANT EGGS")
end

return GateSign
