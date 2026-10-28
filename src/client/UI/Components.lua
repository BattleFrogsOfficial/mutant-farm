--!strict
-- Small building blocks shared by every screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Theme)

local New, Children, OnEvent, Value, Computed, Spring =
	Fusion.New, Fusion.Children, Fusion.OnEvent, Fusion.Value, Fusion.Computed, Fusion.Spring

local Components = {}

function Components.corner(radius: number?)
	return New("UICorner")({ CornerRadius = UDim.new(0, radius or 14) })
end

function Components.stroke(color: Color3?, thickness: number?)
	return New("UIStroke")({
		Color = color or Theme.colors.slate,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Components.textStroke()
	return New("UIStroke")({ Color = Theme.colors.slate, Thickness = 2 })
end

function Components.padding(px: number)
	local u = UDim.new(0, px)
	return New("UIPadding")({ PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function Components.label(props: { [any]: any })
	local base = {
		BackgroundTransparency = 1,
		Font = Theme.font,
		TextColor3 = Theme.colors.white,
		TextScaled = true,
		[Children] = { Components.textStroke(), New("UITextSizeConstraint")({ MaxTextSize = props.MaxTextSize or 32 }) },
	}
	props.MaxTextSize = nil
	for k, v in props do
		if k == Children then
			-- Keep the stroke and size constraint; add the caller's children alongside.
			table.insert(base[Children], v)
		else
			base[k] = v
		end
	end
	return New("TextLabel")(base)
end

-- Big rounded button with a press bounce.
-- props: Text, Color, Size, Position, AnchorPoint, OnClick, Disabled (state), Selected (state: gold outline)
function Components.button(props: { [string]: any })
	local pressed = Value(false)
	local scale = Spring(
		Computed(function()
			return if pressed:get() then 0.92 else 1
		end),
		40,
		0.6
	)
	local disabled = props.Disabled
	return New("TextButton")({
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(140, 48),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		AutoButtonColor = false,
		BackgroundColor3 = Computed(function()
			local color = if typeof(props.Color) == "table" then props.Color:get() else props.Color
			return if disabled and disabled:get() then Theme.colors.slateLight else color or Theme.colors.toxic
		end),
		Font = Theme.font,
		Text = props.Text,
		TextColor3 = Theme.colors.white,
		TextScaled = true,
		[OnEvent("MouseButton1Down")] = function()
			pressed:set(true)
		end,
		[OnEvent("MouseButton1Up")] = function()
			pressed:set(false)
		end,
		[OnEvent("MouseLeave")] = function()
			pressed:set(false)
		end,
		[OnEvent("Activated")] = function()
			if not (disabled and disabled:get()) and props.OnClick then
				props.OnClick()
			end
		end,
		[Children] = {
			Components.corner(),
			-- One Border stroke per object, so selection recolors it instead of adding another.
			New("UIStroke")({
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Computed(function()
					return if props.Selected and props.Selected:get() then Theme.colors.gold else Theme.colors.slate
				end),
				Thickness = Computed(function()
					return if props.Selected and props.Selected:get() then 5 else 3
				end),
			}),
			Components.padding(6),
			Components.textStroke(),
			New("UIScale")({ Scale = scale }),
			New("UITextSizeConstraint")({ MaxTextSize = props.MaxTextSize or 26 }),
			props.Children,
		},
	})
end

-- Centered modal panel with a title and close button. Visible while `isOpen` is true.
function Components.panel(props: { Title: string, IsOpen: any, OnClose: () -> (), Size: UDim2?, Content: any })
	return New("Frame")({
		Name = props.Title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		-- Fixed design size; UIController's UIScale shrinks the whole GUI on small screens.
		Size = props.Size or UDim2.fromOffset(600, 520),
		BackgroundColor3 = Theme.colors.slate,
		Visible = props.IsOpen,
		[Children] = {
			Components.corner(20),
			Components.stroke(Theme.colors.purple, 4),
			Components.label({
				Text = props.Title,
				Size = UDim2.new(1, -120, 0, 44),
				Position = UDim2.fromOffset(20, 10),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 36,
			}),
			Components.button({
				Text = "X",
				Color = Theme.colors.danger,
				Size = UDim2.fromOffset(44, 44),
				Position = UDim2.new(1, -12, 0, 10),
				AnchorPoint = Vector2.new(1, 0),
				OnClick = props.OnClose,
			}),
			New("Frame")({
				Name = "Content",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 64),
				Size = UDim2.new(1, -32, 1, -80),
				[Children] = props.Content,
			}),
		},
	})
end

return Components
