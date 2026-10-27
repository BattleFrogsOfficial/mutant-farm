--!strict
-- Palette and shared UI helpers. Colors match the design doc.

local Theme = {}

Theme.colors = {
	toxic = Color3.fromHex("#7CFF4A"),
	purple = Color3.fromHex("#9B5CFF"),
	cream = Color3.fromHex("#FFF4D6"),
	slate = Color3.fromHex("#1E2230"),
	slateLight = Color3.fromHex("#2C3245"),
	gold = Color3.fromHex("#FFD24A"),
	water = Color3.fromHex("#4AB8FF"),
	danger = Color3.fromHex("#FF5A5A"),
	white = Color3.new(1, 1, 1),
	muted = Color3.fromHex("#9AA0B4"),
}

Theme.font = Enum.Font.FredokaOne

return Theme
