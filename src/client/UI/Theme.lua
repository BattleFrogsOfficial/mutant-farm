--!strict
-- Palette and fonts. Boxy style: square corners, 3px ink outlines, hard offset shadows, flat
-- surfaces with a bevel lip, and a heavy geometric font. Accents match the design doc.

local Theme = {}

Theme.colors = {
	toxic = Color3.fromHex("#7CFF4A"),
	toxicDark = Color3.fromHex("#3FA82A"),
	purple = Color3.fromHex("#9B5CFF"),
	purpleDark = Color3.fromHex("#5E2FB8"),
	cream = Color3.fromHex("#FFF4D6"),
	slate = Color3.fromHex("#1E2230"),
	slateMid = Color3.fromHex("#262B3D"),
	slateLight = Color3.fromHex("#343A52"),
	gold = Color3.fromHex("#FFD24A"),
	goldDark = Color3.fromHex("#C9932A"),
	water = Color3.fromHex("#4AB8FF"),
	waterDark = Color3.fromHex("#2A78C9"),
	danger = Color3.fromHex("#FF5A5A"),
	dangerDark = Color3.fromHex("#B23A3A"),
	white = Color3.new(1, 1, 1),
	muted = Color3.fromHex("#9AA0B4"),
	locked = Color3.fromHex("#555B70"),
	ink = Color3.fromHex("#14111F"), -- outlines and hard shadows
	panel = Color3.fromHex("#201D33"),
	panelHi = Color3.fromHex("#2C2846"),
}

Theme.font = Enum.Font.GothamBlack
Theme.shadow = 4 -- hard shadow offset (px, down-right)

-- A darker version of any color, for button lips and shadows.
function Theme.darker(c: Color3, amount: number?): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, math.min(1, s * 1.1), v * (1 - (amount or 0.35)))
end

return Theme
