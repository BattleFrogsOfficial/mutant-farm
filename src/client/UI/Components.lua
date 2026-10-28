--!strict
-- Building blocks shared by every screen: chunky 3D buttons, panels that pop open, pills,
-- a drawn padlock, and labels with outlines. Everything uses Fusion 0.2.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Theme)
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

function Components.corner(radius: number?)
	return New("UICorner")({ CornerRadius = UDim.new(0, radius or 14) })
end

function Components.round()
	return New("UICorner")({ CornerRadius = UDim.new(1, 0) })
end

function Components.stroke(color: any?, thickness: number?)
	return New("UIStroke")({
		Color = color or Theme.colors.slate,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Components.textStroke(thickness: number?)
	return New("UIStroke")({ Color = Theme.colors.slate, Thickness = thickness or 2 })
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

-- Chunky simulator-style button: a darker "lip" underneath and a face that presses down into it.
-- props: Text, Icon (emoji), Color, Size, Position, AnchorPoint, LayoutOrder, Name, OnClick,
--        Disabled (state), Selected (state: gold ring), MaxTextSize, Children, Silent
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
	local push = Spring(
		Computed(function()
			return if pressed:get() then 4 else 0
		end),
		45,
		0.8
	)
	local scale = Spring(
		Computed(function()
			return if hovered:get() and not isDisabled() then 1.05 else 1
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
		BackgroundColor3 = Computed(function()
			return Theme.darker(color:get())
		end),
		[Children] = {
			Components.corner(14),
			New("UIScale")({ Scale = scale }),
			New("UIStroke")({
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Computed(function()
					return if props.Selected and props.Selected:get() then Theme.colors.gold else Theme.colors.slate
				end),
				Thickness = Computed(function()
					return if props.Selected and props.Selected:get() then 4 else 2.5
				end),
			}),
			New("TextButton")({
				Name = "Face",
				AutoButtonColor = false,
				Text = "",
				Size = UDim2.new(1, 0, 1, -5),
				Position = Computed(function()
					return UDim2.fromOffset(0, push:get())
				end),
				BackgroundColor3 = color,
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
					Components.corner(14),
					Components.shine(),
					New("Frame")({
						-- Glossy highlight along the top edge.
						Name = "Gloss",
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 0.82,
						Position = UDim2.new(0, 6, 0, 3),
						Size = UDim2.new(1, -12, 0.32, 0),
						[Children] = Components.corner(10),
					}),
					Components.label({
						Name = "Text",
						Text = Computed(function()
							local t = read(text) or ""
							local i = read(icon)
							return if i and i ~= "" then i .. "  " .. t else t
						end),
						Size = UDim2.new(1, -12, 1, -8),
						Position = UDim2.fromOffset(6, 4),
						MaxTextSize = props.MaxTextSize or 26,
						ZIndex = 2,
					}),
					props.Children,
				},
			}),
		},
	})
end

-- Round icon button (menu buttons on the side of the screen). props: Icon, Label, Color, OnClick, Badge (state)
function Components.iconButton(props: { [string]: any })
	return Components.button({
		Name = props.Name,
		Size = props.Size or UDim2.fromOffset(78, 78),
		LayoutOrder = props.LayoutOrder,
		Color = props.Color,
		Text = "",
		OnClick = props.OnClick,
		Selected = props.Selected,
		Children = {
			Components.label({
				Text = props.Icon,
				Size = UDim2.new(1, 0, 0.62, 0),
				MaxTextSize = 40,
				ZIndex = 3,
			}),
			Components.label({
				Text = props.Label,
				Position = UDim2.new(0, 0, 0.6, 0),
				Size = UDim2.new(1, 0, 0.36, 0),
				MaxTextSize = 16,
				ZIndex = 3,
			}),
			props.Badge and New("Frame")({
				Name = "Badge",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -4, 0, 4),
				Size = UDim2.fromOffset(44, 22),
				BackgroundColor3 = Theme.colors.danger,
				ZIndex = 4,
				[Children] = {
					Components.round(),
					Components.stroke(Theme.colors.slate, 2),
					Components.label({ Text = props.Badge, Size = UDim2.fromScale(1, 1), MaxTextSize = 16, ZIndex = 5 }),
				},
			}) or nil,
		},
	})
end

-- Dark rounded pill with a colored rim, used for Cash, Bag and similar readouts.
function Components.pill(props: { [string]: any })
	return New("Frame")({
		Name = props.Name,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		BackgroundColor3 = Theme.colors.slate,
		[Children] = {
			Components.round(),
			Components.stroke(props.Rim or Theme.colors.toxic, 3),
			New("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 185)),
			}),
			props.Children,
		},
	})
end

-- A padlock drawn from frames (no image assets). Fits its parent; props: Size, Position, AnchorPoint, Color
function Components.padlock(props: { [string]: any })
	local color = props.Color or Theme.colors.gold
	return New("Frame")({
		Name = "Padlock",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(48, 56),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		ZIndex = props.ZIndex or 5,
		[Children] = {
			New("UIAspectRatioConstraint")({ AspectRatio = 48 / 56 }),
			New("Frame")({
				Name = "Shackle",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.02),
				Size = UDim2.fromScale(0.6, 0.62),
				ZIndex = props.ZIndex or 5,
				[Children] = {
					Components.round(),
					New("UIStroke")({ Color = Theme.darker(color, 0.15), Thickness = 6 }),
				},
			}),
			New("Frame")({
				Name = "Body",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.fromScale(0.9, 0.58),
				BackgroundColor3 = color,
				ZIndex = (props.ZIndex or 5) + 1,
				[Children] = {
					Components.corner(8),
					Components.stroke(Theme.colors.slate, 2.5),
					Components.shine(),
					New("Frame")({
						Name = "Keyhole",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.45),
						Size = UDim2.fromScale(0.18, 0.3),
						BackgroundColor3 = Theme.colors.slate,
						ZIndex = (props.ZIndex or 5) + 2,
						[Children] = Components.round(),
					}),
				},
			}),
		},
	})
end

-- Centered modal panel with a colored header and a close button. Pops in when opened.
function Components.panel(
	props: { Title: any, IsOpen: any, OnClose: () -> (), Size: UDim2?, Content: any, Accent: Color3? }
)
	local accent = props.Accent or Theme.colors.purple
	local scale = Spring(
		Computed(function()
			return if props.IsOpen:get() then 1 else 0.85
		end),
		28,
		0.62
	)
	return New("Frame")({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		-- Fixed design size; UIController's UIScale shrinks the whole GUI on small screens.
		Size = props.Size or UDim2.fromOffset(640, 500),
		BackgroundColor3 = Theme.colors.slateMid,
		Visible = props.IsOpen,
		Active = true, -- swallow taps so they don't reach the farm behind the panel
		ZIndex = 10,
		[Children] = {
			New("UIScale")({ Scale = scale }),
			Components.corner(22),
			Components.stroke(Theme.colors.slate, 4),
			New("Frame")({
				Name = "Header",
				Size = UDim2.new(1, 0, 0, 62),
				BackgroundColor3 = accent,
				ZIndex = 10,
				[Children] = {
					Components.corner(22),
					Components.shine(),
					-- Square off the header's bottom corners.
					New("Frame")({
						BackgroundColor3 = accent,
						BorderSizePixel = 0,
						Position = UDim2.new(0, 0, 1, -22),
						Size = UDim2.new(1, 0, 0, 22),
						ZIndex = 10,
						[Children] = New("UIGradient")({
							Rotation = 90,
							Color = ColorSequence.new(Color3.fromRGB(220, 220, 228), Color3.fromRGB(205, 205, 215)),
						}),
					}),
					Components.label({
						Text = props.Title,
						Size = UDim2.new(1, -110, 0, 44),
						Position = UDim2.fromOffset(22, 9),
						TextXAlignment = Enum.TextXAlignment.Left,
						MaxTextSize = 38,
						StrokeThickness = 3,
						ZIndex = 11,
					}),
				},
			}),
			Components.button({
				Text = "X",
				Color = Theme.colors.danger,
				Size = UDim2.fromOffset(50, 50),
				Position = UDim2.new(1, -10, 0, 6),
				AnchorPoint = Vector2.new(1, 0),
				MaxTextSize = 28,
				ZIndex = 12, -- above the header (siblings sort by ZIndex)
				OnClick = props.OnClose,
			}),
			New("Frame")({
				Name = "Content",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 76),
				Size = UDim2.new(1, -32, 1, -92),
				ZIndex = 10,
				[Children] = props.Content,
			}),
		},
	})
end

return Components
