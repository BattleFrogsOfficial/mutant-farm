--!strict
-- Minimal signal for server/client-internal events.

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} :: { (...any) -> () } }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	table.insert(self._handlers, fn)
	return {
		Disconnect = function()
			local i = table.find(self._handlers, fn)
			if i then
				table.remove(self._handlers, i)
			end
		end,
	}
end

function Signal:Fire(...)
	for _, fn in table.clone(self._handlers) do
		task.spawn(fn, ...)
	end
end

return Signal
