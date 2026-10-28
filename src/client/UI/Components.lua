--!strict
-- Building blocks shared by every screen, in one boxy style: square corners, 3px ink outlines,
-- hard offset shadows, and a darker "lip" under every button face. Chunky 3D buttons, menu tiles
-- with badges, stat boxes, panels that pop open over a dimmed screen, a drawn padlock, outlined
-- labels, and a pulse helper for anything that wants attention. Everything uses Fusion 0.2.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Theme)
local State = require(script.Parent.Parent.State)
local Sfx = require(script.Parent.Parent.Sfx)

local New, Children, OnEvent, Value, Computed, Spring =
	Fusion.New, Fusion.Children, Fusion.OnEvent, Fusion.Value, Fusion.Computed, Fusion.Spring

local Components = {}

local function read(v: any): any
	if typeof(v) == "table" and v.get then
		return v:get()
	end
	return v
end
Components.read = read

-- The style has no rounded corners. These stay so call sites read the same; they add nothing.
function Components.corner(_radius: number?): any
	return nil
end

function Components.round(): any
	return nil
end

function Components.stroke(color: any?, thickness: number?)
	return New("UIStroke")({
		Color = color or Theme.colors.ink,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
	})
end

function Components.textStroke(thickness: number?)
	return New("UIStroke")({ Color = Theme.colors.ink, Thickness = thickness or 2 })
end

function Components.padding(px: number)
	local u = UDim.new(0, px)
	return New("UIPadding")({ PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

-- Top-lit gradient: multiplies the surface so the top is bright and the bottom a bit darker.
function Components.shine()
	return New("UIGradient")({
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 215)),
	})
end

-- A two-color vertical gradient (top -> bottom) on a white surface.
function Components.gradient(top: Color3, bottom: Color3)
	return New("UIGradient")({ Rotation = 90, Color = ColorSequence.new(top, bottom) })
end

-- A thin light strip along the top inside edge: the "bevel" that makes flat boxes look physical.
function Components.bevel(z: number?, transparency: number?)
	return New("Frame")({
		Name = "Bevel",
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = transparency or 0.72,
		Size = UDim2.new(1, 0, 0, 3),
		ZIndex = z or 2,
	})
end

-- UIScale that gently pulses while `active` is true (attention without being annoying).
function Components.pulse(active: any, amount: number?)
	local a = amount or 0.06
	return New("UIScale")({
		Scale = Computed(function()
			if not read(active) then
				return 1
			end
			return 1 + a * math.abs(math.sin(State.clock:get() * 3.2))
		end),
	})
end

function Components.label(props: { [any]: any })
	local base = {
		BackgroundTransparency = 1,
		Font = Theme.font,
		TextColor3 = Theme.colors.white,
		TextScaled = true,
		[Children] = {
			Components.textStroke(props.StrokeThickness),
			New("UITextSizeConstraint")({ MaxTextSize = props.MaxTextSize or 32 }),
		},
	}
	props.MaxTextSize = nil
	props.StrokeThickness = nil
	for k, v in props do
		if k == Children then
			table.insert(base[Children], v)
		else
			base[k] = v
		end
	end
	return New("TextLabel")(base)
end

-- Hard drop shadow: put it first in a transparent container, behind the real face.
function Components.shadow(_radius: number?, offset: number?)
	local o = offset or Theme.shadow
	return New("Frame")({
		Name = "Shadow",
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.colors.ink,
		BackgroundTransparency = 0.2,
		Position = UDim2.fromOffset(o, o),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	})
end

-- Chunky simulator-style button: a darker lip underneath and a face that presses down into it.
-- props: Text, Icon (emoji), Color, Size, Position, AnchorPoint, LayoutOrder, Name, ZIndex, Visible,
--        OnClick, Disabled (state), Selected (state: gold outline), Pulse (state), MaxTextSize, Children, Silent
function Components.button(props: { [string]: any })
	local pressed = Value(false)
	local hovered = Value(false)
	local disabled = props.Disabled
	local function isDisabled(): boolean
		return disabled ~= nil and disabled:get() == true
	end
	local color = Computed(function()
		if isDisabled() then
			return Theme.colors.locked
		end
		return read(props.Color) or Theme.colors.toxic
	end)
	local LIP = 6
	local push = Spring(
		Computed(function()
			return if pressed:get() then LIP - 1 else 0
		end),
		50,
		0.8
	)
	local hover = Spring(
		Computed(function()
			return if hovered:get() and not isDisabled() then 1.04 else 1
		end),
		30,
		0.6
	)
	local text = props.Text
	local icon = props.Icon

	return New("Frame")({
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(140, 52),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		BackgroundTransparency = 1,
		[Children] = {
			New("UIScale")({
				Scale = Computed(function()
					local pulse = if props.Pulse and read(props.Pulse)
						then 1 + 0.05 * math.abs(math.sin(State.clock:get() * 3.2))
						else 1
					return hover:get() * pulse
				end),
			}),
			Components.shadow(),
			New("Frame")({
				Name = "Lip",
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Computed(function()
					return Theme.darker(color:get(), 0.45)
				end),
				ZIndex = 1,
				[Children] = New("UIStroke")({
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					LineJoinMode = Enum.LineJoinMode.Miter,
					Color = Computed(function()
						return if props.Selected and props.Selected:get() then Theme.colors.gold else Theme.colors.ink
					end),
					Thickness = Computed(function()
						return if props.Selected and props.Selected:get() then 4 else 3
					end),
				}),
			}),
			New("TextButton")({
				Name = "Face",
				AutoButtonColor = false,
				BorderSizePixel = 0,
				Text = "",
				Size = UDim2.new(1, 0, 1, -LIP),
				Position = Computed(function()
					return UDim2.fromOffset(0, push:get())
				end),
				BackgroundColor3 = Color3.new(1, 1, 1),
				ZIndex = 2,
				[OnEvent("MouseButton1Down")] = function()
					pressed:set(true)
				end,
				[OnEvent("MouseButton1Up")] = function()
					pressed:set(false)
				end,
				[OnEvent("MouseEnter")] = function()
					hovered:set(true)
				end,
				[OnEvent("MouseLeave")] = function()
					hovered:set(false)
					pressed:set(false)
				end,
				[OnEvent("Activated")] = function()
					if isDisabled() then
						Sfx.play("error", 0.4)
						return
					end
					if not props.Silent then
						Sfx.play("click", 0.5)
					end
					if props.OnClick then
						props.OnClick()
					end
				end,
				[Children] = {
					-- Flat face, a touch lighter at the top.
					New("UIGradient")({
						Rotation = 90,
						Color = Computed(function()
							local c = color:get()
							return ColorSequence.new(c:Lerp(Color3.new(1, 1, 1), 0.18), c)
						end),
					}),
					Components.bevel(3, 0.55),
					Components.label({
						Name = "Text",
						Text = Computed(function()
							local t = read(text) or ""
							local i = read(icon)
							return if i and i ~= "" then i .. " " .. t else t
						end),
						Size = UDim2.new(1, -14, 1, -10),
						Position = UDim2.fromOffset(7, 5),
						MaxTextSize = props.MaxTextSize or 26,
						StrokeThickness = 2.5,
						ZIndex = 3,
					}),
					props.Children,
				},
			}),
		},
	})
end

-- Square menu tile. props: Icon, Label, Color, OnClick, Badge (state text),
-- Alert (state: red marker + pulse), Selected (state), LayoutOrder, Name, Size
function Components.tile(props: { [string]: any })
	return Components.button({
		Name = props.Name,
		Size = props.Size or UDim2.fromOffset(76, 82),
		LayoutOrder = props.LayoutOrder,
		Color = props.Color,
		Text = "",
		OnClick = props.OnClick,
		Selected = props.Selected,
		Pulse = props.Alert,
		Children = {
			Components.label({
				Text = props.Icon,
				Position = UDim2.fromOffset(0, 5),
				Size = UDim2.new(1, 0, 0.52, 0),
				MaxTextSize = 34,
				ZIndex = 4,
			}),
			Components.label({
				Text = props.Label,
				Position = UDim2.new(0, 4, 0.6, 0),
				Size = UDim2.new(1, -8, 0.28, 0),
				MaxTextSize = 14,
				ZIndex = 4,
			}),
			props.Badge and New("Frame")({
				Name = "Badge",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 1, 4),
				Size = UDim2.new(1, 4, 0, 22),
				BackgroundColor3 = Theme.colors.ink,
				BorderSizePixel = 0,
				ZIndex = 6,
				[Children] = Components.label({
					Text = props.Badge,
					Size = UDim2.new(1, -8, 1, -6),
					Position = UDim2.fromOffset(4, 3),
					MaxTextSize = 13,
					TextColor3 = Theme.colors.cream,
					StrokeThickness = 0,
					ZIndex = 7,
				}),
			}) or nil,
			props.Alert and New("Frame")({
				Name = "Alert",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -2, 0, 2),
				Size = UDim2.fromOffset(22, 22),
				Rotation = 45,
				BackgroundColor3 = Theme.colors.danger,
				BorderSizePixel = 0,
				Visible = props.Alert,
				ZIndex = 6,
				[Children] = {
					Components.stroke(Theme.colors.ink, 2.5),
					Components.label({
						Text = "!",
						Rotation = -45,
						Size = UDim2.fromScale(1, 1),
						MaxTextSize = 16,
						ZIndex = 7,
					}),
				},
			}) or nil,
		},
	})
end

-- Dark stat box with an accent stripe down its left edge and a hard shadow, for top-bar readouts.
-- props: Name, AnchorPoint, Position, Size, Rim (accent, may be a state), ZIndex, Children
function Components.pill(props: { [string]: any })
	return New("Frame")({
		Name = props.Name,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex,
		[Children] = {
			Components.shadow(),
			New("Frame")({
				Name = "Face",
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				ZIndex = 1,
				[Children] = {
					Components.stroke(Theme.colors.ink, 3),
					Components.gradient(Theme.colors.panelHi, Theme.colors.panel),
					Components.bevel(1, 0.88),
					New("Frame")({
						Name = "Stripe",
						BorderSizePixel = 0,
						Size = UDim2.new(0, 5, 1, 0),
						BackgroundColor3 = props.Rim or Theme.colors.toxic,
						ZIndex = 2,
					}),
					props.Children,
				},
			}),
		},
	})
end

-- A padlock drawn from frames (no image assets). props: Size, Position, AnchorPoint, Color, ZIndex
function Components.padlock(props: { [string]: any })
	local color = props.Color or Theme.colors.gold
	local z = props.ZIndex or 5
	return New("Frame")({
		Name = "Padlock",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(48, 56),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		ZIndex = z,
		[Children] = {
			New("Frame")({
				-- Squared-off shackle: an outline box whose bottom is hidden behind the body.
				Name = "Shackle",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.04),
				Size = UDim2.fromScale(0.56, 0.6),
				ZIndex = z,
				[Children] = New("UIStroke")({
					Color = Theme.darker(color, 0.15),
					Thickness = 6,
					LineJoinMode = Enum.LineJoinMode.Miter,
				}),
			}),
			New("Frame")({
				Name = "Body",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.fromScale(0.9, 0.58),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = z + 1,
				[Children] = {
					Components.stroke(Theme.colors.ink, 2.5),
					Components.shine(),
					New("Frame")({
						Name = "Keyhole",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.45),
						Size = UDim2.fromScale(0.14, 0.34),
						BackgroundColor3 = Theme.colors.ink,
						BorderSizePixel = 0,
						ZIndex = z + 2,
					}),
				},
			}),
		},
	})
end

-- Centered modal panel: accent header bar with the title, square close button, hard shadow.
-- Pops in when opened. (Root draws the dim backdrop behind open panels.)
function Components.panel(
	props: { Title: any, IsOpen: any, OnClose: () -> (), Size: UDim2?, Content: any, Accent: Color3? }
)
	local accent = props.Accent or Theme.colors.purple
	local scale = Spring(
		Computed(function()
			return if props.IsOpen:get() then 1 else 0.86
		end),
		32,
		0.7
	)
	return New("Frame")({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = props.Size or UDim2.fromOffset(640, 480),
		BackgroundTransparency = 1,
		Visible = props.IsOpen,
		Active = true, -- swallow taps so they don't reach the farm behind the panel
		ZIndex = 10,
		[Children] = {
			New("UIScale")({ Scale = scale }),
			Components.shadow(nil, 8),
			New("Frame")({
				Name = "Body",
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				ZIndex = 1,
				[Children] = {
					Components.stroke(Theme.colors.ink, 4),
					Components.gradient(Theme.colors.panelHi, Theme.colors.panel),
				},
			}),
			New("Frame")({
				Name = "Header",
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 58),
				BackgroundColor3 = accent,
				ZIndex = 2,
				[Children] = {
					Components.bevel(3, 0.6),
					New("Frame")({
						-- Darker band along the bottom of the header.
						Name = "Lip",
						BorderSizePixel = 0,
						BackgroundColor3 = Theme.darker(accent, 0.35),
						Position = UDim2.new(0, 0, 1, -6),
						Size = UDim2.new(1, 0, 0, 6),
						ZIndex = 3,
					}),
					Components.label({
						Text = props.Title,
						Size = UDim2.new(1, -110, 0, 36),
						Position = UDim2.fromOffset(20, 9),
						TextXAlignment = Enum.TextXAlignment.Left,
						MaxTextSize = 30,
						StrokeThickness = 3,
						ZIndex = 3,
					}),
				},
			}),
			Components.button({
				Text = "✕",
				Color = Theme.colors.danger,
				Size = UDim2.fromOffset(48, 48),
				Position = UDim2.new(1, 10, 0, -10),
				AnchorPoint = Vector2.new(1, 0),
				MaxTextSize = 24,
				ZIndex = 5, -- above the header (siblings sort by ZIndex)
				OnClick = props.OnClose,
			}),
			New("Frame")({
				Name = "Content",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 72),
				Size = UDim2.new(1, -32, 1, -88),
				ZIndex = 3,
				[Children] = props.Content,
			}),
		},
	})
end

return Components
