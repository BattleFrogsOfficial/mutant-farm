--!strict
-- Argument checks for remote intents. Anything that fails is rejected silently.

local Validate = {}

function Validate.integer(value: any, min: number, max: number): boolean
	return typeof(value) == "number" and value == value and value % 1 == 0 and value >= min and value <= max
end

function Validate.string(value: any, maxLength: number): boolean
	return typeof(value) == "string" and #value > 0 and #value <= maxLength
end

return Validate
