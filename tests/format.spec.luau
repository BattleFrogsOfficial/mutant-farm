return function(t)
	local Format = t.require("src/shared/Format")
	return {
		["numbers use suffixes"] = function()
			t.eq(Format.number(0), "0")
			t.eq(Format.number(950), "950")
			t.eq(Format.number(1234), "1.2K")
			t.eq(Format.number(12_340), "12.3K")
			t.eq(Format.number(123_456), "123K")
			t.eq(Format.number(4_500_000), "4.5M")
			t.eq(Format.number(162_500_000), "162M")
			t.eq(Format.number(2_000_000_000), "2B")
		end,
		["never rounds up into the next unit"] = function()
			t.eq(Format.number(999_960), "999K")
			t.eq(Format.number(99_990), "99.9K")
		end,
		["durations"] = function()
			t.eq(Format.duration(42), "42s")
			t.eq(Format.duration(125), "2m 05s")
			t.eq(Format.duration(7260), "2h 01m")
			t.eq(Format.duration(-5), "0s")
		end,
		["odds percentages keep table precision"] = function()
			t.eq(Format.percent(80), "80%")
			t.eq(Format.percent(4.45), "4.45%")
			t.eq(Format.percent(2.875), "2.88%")
			t.eq(Format.percent(0.05), "0.05%")
			t.eq(Format.percent(0.125), "0.125%")
			t.eq(Format.percent(0.93), "0.93%")
		end,
	}
end
