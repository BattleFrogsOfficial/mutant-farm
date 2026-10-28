--!strict
-- Instant Weather picker: Acid Rain / Solar Flare / Glitch Storm, each with its per-tick odds and
-- the mutation it gives, and a pink Gems button. Buying runs that event on your plot only for its
-- 120 s (server: WeatherService BuyInstantWeather). While yours runs, the buttons say so. Short on
-- Gems opens the Gem shop. Never shown to policy-restricted players (the server refuses too).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Weather = require(Shared.Config.Weather)
local Mutations = require(Shared.Config.Mutations)
local Products = require(Shared.Config.Products)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed = Fusion.New, Fusion.Children, Fusion.Computed

local COST = Products.gems.InstantWeather.cost

local function option(eventId: string, order: number)
	local event = (Weather.events :: any)[eventId]
	local color = Color3.fromHex(event.color)
	local running = Computed(function()
		return State.plotWeather:get().id ~= ""
	end)
	return New("Frame")({
		Name = eventId,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundColor3 = Theme.colors.slateLight,
		BorderSizePixel = 0,
		ZIndex = 3,
		[Children] = {
			C.stroke(color, 3),
			C.label({
				Text = event.icon,
				Position = UDim2.fromOffset(10, 10),
				Size = UDim2.fromOffset(64, 64),
				MaxTextSize = 48,
				ZIndex = 4,
			}),
			C.label({
				Text = string.upper(event.name),
				Position = UDim2.fromOffset(84, 10),
				Size = UDim2.new(1, -290, 0, 30),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = color,
				MaxTextSize = 24,
				ZIndex = 4,
			}),
			C.label({
				Text = string.format(
					"%s per tick · %s x%d",
					Format.percent(event.chancePerRoll * 100),
					string.upper(event.mutation),
					Mutations.info[event.mutation].multiplier
				),
				Position = UDim2.fromOffset(84, 44),
				Size = UDim2.new(1, -290, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.colors.cream,
				MaxTextSize = 17,
				ZIndex = 4,
			}),
			C.button({
				Name = "Buy",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(190, 56),
				Color = Theme.colors.spend,
				MaxTextSize = 22,
				ZIndex = 5,
				Disabled = running,
				Text = Computed(function()
					local mine = State.plotWeather:get()
					if mine.id ~= "" then
						local left = math.max(0, mine.endsAt - State.now:get())
						return string.format("RUNNING %d:%02d", left // 60, left % 60)
					end
					return string.format("%d 💎", COST)
				end),
				OnClick = function()
					if State.gems:get(false) < COST then
						State.panel:set("store")
						return
					end
					Remotes.get("BuyInstantWeather"):FireServer(eventId)
					State.panel:set("none")
				end,
			}),
		},
	})
end

return function()
	local options: { any } = {
		New("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }),
	}
	for i, id in Weather.order do
		table.insert(options, option(id, i))
	end
	return C.panel({
		Title = "⛈ Instant Weather",
		Accent = Theme.colors.spend,
		Size = UDim2.fromOffset(600, 420),
		IsOpen = Computed(function()
			return State.panel:get() == "instantWeather"
		end),
		OnClose = function()
			State.panel:set("none")
		end,
		Content = {
			C.label({
				Text = "A 2-minute weather event on YOUR farm only. Rolls every 30 s on every growing egg.",
				Size = UDim2.new(1, 0, 0, 40),
				TextWrapped = true,
				TextColor3 = Theme.colors.cream,
				MaxTextSize = 18,
				ZIndex = 3,
			}),
			New("Frame")({
				Name = "Options",
				Position = UDim2.fromOffset(0, 50),
				Size = UDim2.new(1, 0, 1, -50),
				BackgroundTransparency = 1,
				ZIndex = 3,
				[Children] = options,
			}),
		},
	})
end
