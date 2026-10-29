--!strict
-- The HUD's design-to-pixel scale: the shorter edge of the area the GUI covers (below Roblox's top
-- bar) against Config/Hud.designHeight, clamped to [minScale, maxScale] (maxScaleTouch on touch
-- screens). UIController applies it; the UI preview (ui-export / ui-render) uses the same numbers.

local Hud = require(script.Parent.Config.Hud)

local HudScale = {}

function HudScale.of(width: number, height: number, touch: boolean): number
	local s = math.min(width, height) / Hud.designHeight
	return math.clamp(s, Hud.minScale, if touch then Hud.maxScaleTouch else Hud.maxScale)
end

return HudScale
