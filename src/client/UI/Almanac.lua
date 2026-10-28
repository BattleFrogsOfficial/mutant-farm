--!strict
-- The Almanac: every species (400, plus each limited egg's), Pokedex-style. Limited eggs get their
-- own tab after the tiers, and their species say "LIMITED · <event>". Undiscovered species are black
-- silhouettes marked "???". Discovered ones open a detail page with a spinning 3D model,
-- description, traits, size range, your biggest one, hatch count, first-hatch date and a fun fact.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local Rarities = require(Shared.Config.Rarities)
local Mutants = require(Shared.Config.Mutants)
local MutantModel = require(Shared.MutantModel)
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Viewport = require(script.Parent.Viewport)

local New, Children, Computed, Value = Fusion.New, Fusion.Children, Fusion.Computed, Fusion.Value

local PER_PAGE = 12 -- 6 x 2
local TOTAL = 0
for _ in Mutants.species do
	TOTAL += 1
end

-- Tabs: the tiers, then the limited eggs. Species ids per tab, Common -> Legendary, then by id.
local TABS = table.clone(Eggs.order)
for _, id in Eggs.limitedOrder do
	table.insert(TABS, id)
end
local byTier: { [string]: { string } } = {}
for _, tier in TABS do
	local list = {}
	for _, rarity in Rarities.order do
		for _, id in (Mutants.buckets[tier] or {})[rarity] or {} do
			table.insert(list, id)
		end
	end
	byTier[tier] = list
end

local TRAIT_NAMES = {
	body = {
		blob = "Round",
		tall = "Tall",
		flat = "Flat",
		spiky = "Spiky",
		pear = "Pear",
		worm = "Wiggly",
		puff = "Puffy",
	},
	mouth = {
		smile = "Grin",
		fangs = "Fangs",
		tooth = "Big tooth",
		wide = "Huge mouth",
		tongue = "Tongue out",
		none = "None",
	},
}

-- Height in studs of a species at a given size roll.
local function height(e, size: number): number
	return 3.6
		* MutantModel.visualScale({ tier = e.tier, rarity = e.rarity, species = e.id, mutations = {}, size = size })
end

local function chip(text: string, color: Color3, order: number)
	return New("Frame")({
		LayoutOrder = order,
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		ZIndex = 12,
		[Children] = {
			C.stroke(Theme.colors.slate, 2),
			New("UIPadding")({ PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
			New("TextLabel")({
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromScale(0, 1),
				Font = Theme.font,
				TextSize = 18,
				TextColor3 = Theme.colors.white,
				Text = text,
				ZIndex = 13,
				[Children] = C.textStroke(1.5),
			}),
		},
	})
end

local function line(label: string, value: string, order: number)
	return New("TextLabel")({
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
		TextColor3 = Theme.colors.cream,
		Text = string.format('<font face="FredokaOne" color="#7CFF4A">%s</font>  %s', label, value),
		ZIndex = 12,
	})
end

local function detailPage(id: string, entry: { n: number, first: number, best: number })
	local e = Mutants.species[id]
	local rarityColor = Color3.fromHex(Rarities.info[e.rarity].color)
	local minH, maxH = height(e, 0.8), height(e, 3)
	local first = os.date("%b %d, %Y", math.floor(entry.first))
	local data = { tier = e.tier, rarity = e.rarity, species = id, mutations = {}, size = entry.best }
	return {
		New("Frame")({
			Name = "Stage",
			Size = UDim2.fromOffset(230, 300),
			BackgroundColor3 = Theme.colors.slate,
			ZIndex = 11,
			[Children] = {
				C.stroke(rarityColor, 3),
				New("UIGradient")({
					Rotation = 90,
					Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 170)),
				}),
				Viewport.new({
					Build = function()
						return MutantModel.build(data)
					end,
					Spin = true,
					Size = UDim2.new(1, -16, 1, -16),
					Position = UDim2.fromOffset(8, 8),
					ZIndex = 12,
				}),
			},
		}),
		New("ScrollingFrame")({
			Name = "Info",
			Position = UDim2.fromOffset(246, 0),
			Size = UDim2.new(1, -246, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 5,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ZIndex = 11,
			[Children] = {
				New("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
				C.label({
					LayoutOrder = 1,
					Text = e.name,
					Size = UDim2.new(1, -8, 0, 40),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = rarityColor,
					MaxTextSize = 34,
					StrokeThickness = 3,
					ZIndex = 12,
				}),
				New("Frame")({
					LayoutOrder = 2,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 30),
					ZIndex = 12,
					[Children] = {
						New("UIListLayout")({
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 6),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
						chip(e.rarity, rarityColor, 1),
						chip(
							Eggs.tiers[e.tier].name,
							Color3.fromHex(Eggs.tiers[e.tier].color):Lerp(Theme.colors.slate, 0.35),
							2
						),
						if Eggs.tiers[e.tier].limited
							then chip("LIMITED · " .. Eggs.tiers[e.tier].event, Theme.colors.purpleDark, 3)
							else nil,
					},
				}),
				New("TextLabel")({
					LayoutOrder = 3,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -8, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Font = Enum.Font.GothamMedium,
					TextSize = 17,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = Theme.colors.white,
					Text = e.description,
					ZIndex = 12,
				}),
				line("Body", TRAIT_NAMES.body[e.body] or e.body, 4),
				line("Eyes", tostring(e.eyes), 5),
				line("Mouth", TRAIT_NAMES.mouth[e.mouth] or e.mouth, 6),
				line("Wears", if e.accessory == "none" then "Nothing" else (e.accessory:gsub("^%l", string.upper)), 7),
				line("Size", string.format("%.1f to %.1f studs tall", minH, maxH), 8),
				line("Your biggest", string.format("x%.2f size (%.1f studs)", entry.best, height(e, entry.best)), 9),
				line("Hatched", string.format("%d time%s", entry.n, if entry.n == 1 then "" else "s"), 10),
				line("First found", first, 11),
				New("Frame")({
					LayoutOrder = 12,
					Size = UDim2.new(1, -8, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = Theme.colors.purpleDark,
					ZIndex = 12,
					[Children] = {
						C.padding(10),
						New("TextLabel")({
							BackgroundTransparency = 1,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							Font = Enum.Font.GothamMedium,
							TextSize = 16,
							TextWrapped = true,
							RichText = true,
							TextXAlignment = Enum.TextXAlignment.Left,
							TextColor3 = Theme.colors.white,
							Text = '<font face="FredokaOne" color="#FFD24A">Fun fact!</font>  ' .. e.funFact,
							ZIndex = 13,
						}),
					},
				}),
			},
		}),
	}
end

local function card(id: string, order: number, entry: any, onOpen: (string) -> ())
	local e = Mutants.species[id]
	local found = entry ~= nil
	local rarityColor = Color3.fromHex(Rarities.info[e.rarity].color)
	return New("Frame")({
		Name = id,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		ZIndex = 11,
		[Children] = C.button({
			Size = UDim2.fromScale(1, 1),
			Color = if found then Theme.colors.slateLight else Theme.colors.slate,
			Text = "",
			Silent = not found,
			OnClick = function()
				if found then
					onOpen(id)
				else
					State.toast(
						string.format("Hatch %s eggs to find this %s mutant!", Eggs.tiers[e.tier].name, e.rarity),
						"info"
					)
				end
			end,
			Children = {
				Viewport.new({
					Build = function()
						return MutantModel.build({
							tier = e.tier,
							rarity = e.rarity,
							species = id,
							mutations = {},
							size = 1,
						})
					end,
					Silhouette = not found,
					Size = UDim2.new(1, -8, 1, -34),
					Position = UDim2.fromOffset(4, 2),
					ZIndex = 3,
				}),
				C.label({
					Text = if found then e.name else "???",
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -6),
					Size = UDim2.new(1, -8, 0, 20),
					MaxTextSize = 15,
					TextColor3 = if found then Theme.colors.white else Theme.colors.muted,
					ZIndex = 3,
				}),
				New("Frame")({
					Name = "Rarity",
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -1),
					Size = UDim2.new(0.6, 0, 0, 4),
					BackgroundColor3 = rarityColor,
					ZIndex = 3,
				}),
				-- Limited species: "LIMITED · Halloween 2026" across the top of the card.
				if Eggs.tiers[e.tier].limited
					then C.label({
						Name = "Limited",
						Text = "LIMITED · " .. Eggs.tiers[e.tier].event,
						Position = UDim2.fromOffset(4, 3),
						Size = UDim2.new(1, -48, 0, 14), -- clear of the "x3" count on the right
						TextXAlignment = Enum.TextXAlignment.Left,
						MaxTextSize = 11,
						TextColor3 = Color3.fromHex(Eggs.tiers[e.tier].color),
						ZIndex = 4,
					})
					else nil,
				found and C.label({
					Text = "x" .. entry.n,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -4, 0, 2),
					Size = UDim2.fromOffset(40, 18),
					MaxTextSize = 14,
					TextColor3 = Theme.colors.gold,
					ZIndex = 4,
				}) or nil,
			},
		}),
	})
end

return function()
	local isOpen = Computed(function()
		return State.panel:get() == "almanac"
	end)
	local tab = Value(Eggs.order[1])
	local page = Value(1)
	local selected = Value(nil :: string?)

	local foundCount = Computed(function()
		local n = 0
		for _ in State.almanac:get() do
			n += 1
		end
		return n
	end)

	local tabs: { any } = {
		New("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	-- Tabs share the content width (728): 6 tiers fit at 112, more get narrower.
	local tabWidth = math.min(112, math.floor((728 - 6 * (#TABS - 1)) / #TABS))
	for i, tierId in TABS do
		local limitedIcon = Eggs.tiers[tierId].limited and Eggs.tiers[tierId].icon
		table.insert(
			tabs,
			C.button({
				Name = tierId,
				LayoutOrder = i,
				Size = UDim2.fromOffset(tabWidth, 46),
				Color = Color3.fromHex(Eggs.tiers[tierId].color):Lerp(Theme.colors.slateLight, 0.4),
				MaxTextSize = 17,
				Selected = Computed(function()
					return tab:get() == tierId
				end),
				Text = Computed(function()
					local almanac = State.almanac:get()
					local n = 0
					for _, id in byTier[tierId] do
						if almanac[id] then
							n += 1
						end
					end
					return string.format("%s %d/%d", limitedIcon or tierId, n, #byTier[tierId])
				end),
				OnClick = function()
					tab:set(tierId)
					page:set(1)
					selected:set(nil)
				end,
			})
		)
	end

	local pageCount = Computed(function()
		return math.max(1, math.ceil(#byTier[tab:get()] / PER_PAGE))
	end)

	-- Grid cards for the current tab/page (built only while the Almanac is open).
	local grid = Computed(function()
		if not isOpen:get() or selected:get() ~= nil then
			return {}
		end
		local almanac = State.almanac:get()
		local list = byTier[tab:get()]
		local p = math.clamp(page:get(), 1, pageCount:get())
		local out = {}
		for i = (p - 1) * PER_PAGE + 1, math.min(#list, p * PER_PAGE) do
			local id = list[i]
			table.insert(
				out,
				card(id, i, almanac[id], function(openId)
					selected:set(openId)
				end)
			)
		end
		return out
	end, Fusion.cleanup)

	local detail = Computed(function()
		local id = selected:get()
		if not isOpen:get() or not id then
			return {}
		end
		local entry = State.almanac:get()[id]
		if not entry then
			return {}
		end
		return detailPage(id, entry)
	end, Fusion.cleanup)

	return C.panel({
		Title = Computed(function()
			-- Next milestone (every 25 found pays Gems automatically, see GrowthService).
			local every = GameConfig.almanacMilestones.every
			local nextAt = (foundCount:get() // every + 1) * every
			if nextAt > TOTAL then
				return string.format("📖 Almanac   %d / %d found", foundCount:get(), TOTAL)
			end
			local big = GameConfig.almanacMilestones.big[nextAt]
			local reward = string.format("💎 %d", GameConfig.almanacMilestones.gems)
			if big and big.luck then
				reward = string.format("🍀 +%d%% LUCK", math.floor(big.luck * 100 + 0.5))
			elseif big and big.eggs then
				local eggId = next(big.eggs)
				reward = "🥚 " .. string.upper(eggId :: string) .. " EGG"
			end
			return string.format("📖 Almanac  %d / %d  ·  %s at %d", foundCount:get(), TOTAL, reward, nextAt)
		end),
		Accent = Theme.colors.purple,
		Size = UDim2.fromOffset(760, 480),
		IsOpen = isOpen,
		OnClose = function()
			selected:set(nil)
			State.panel:set("none")
		end,
		Content = {
			-- Overall progress bar.
			New("Frame")({
				Name = "Progress",
				Size = UDim2.new(1, 0, 0, 10),
				BackgroundColor3 = Theme.colors.slate,
				ZIndex = 11,
				[Children] = {
					New("Frame")({
						BackgroundColor3 = Theme.colors.toxic,
						Size = Computed(function()
							return UDim2.fromScale(foundCount:get() / TOTAL, 1)
						end),
						ZIndex = 12,
						[Children] = C.shine(),
					}),
				},
			}),
			New("Frame")({
				Name = "Tabs",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 18),
				Size = UDim2.new(1, 0, 0, 48),
				Visible = Computed(function()
					return selected:get() == nil
				end),
				ZIndex = 11,
				[Children] = tabs,
			}),
			New("Frame")({
				Name = "Grid",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 74),
				Size = UDim2.new(1, 0, 1, -128),
				Visible = Computed(function()
					return selected:get() == nil
				end),
				ZIndex = 11,
				[Children] = {
					New("UIGridLayout")({
						-- 2 rows must fit the grid height (480 panel - 90 chrome - 74 tabs - 54 pager).
						-- 6 columns must fit the content width (760 - 32): 6 x 110 + 5 x 8 = 700.
						CellSize = UDim2.fromOffset(110, 120),
						CellPadding = UDim2.fromOffset(8, 9),
						SortOrder = Enum.SortOrder.LayoutOrder,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
					}),
					grid,
				},
			}),
			New("Frame")({
				Name = "Pager",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.fromOffset(320, 48),
				Visible = Computed(function()
					return selected:get() == nil
				end),
				ZIndex = 11,
				[Children] = {
					C.button({
						Text = "<",
						Size = UDim2.fromOffset(70, 46),
						Color = Theme.colors.purple,
						Disabled = Computed(function()
							return page:get() <= 1
						end),
						OnClick = function()
							page:set(math.max(1, page:get(false) - 1))
						end,
					}),
					C.label({
						Position = UDim2.fromOffset(80, 6),
						Size = UDim2.fromOffset(160, 34),
						MaxTextSize = 22,
						ZIndex = 12,
						Text = Computed(function()
							return string.format("Page %d / %d", page:get(), pageCount:get())
						end),
					}),
					C.button({
						Text = ">",
						Size = UDim2.fromOffset(70, 46),
						Position = UDim2.fromOffset(250, 0),
						Color = Theme.colors.purple,
						Disabled = Computed(function()
							return page:get() >= pageCount:get()
						end),
						OnClick = function()
							page:set(math.min(pageCount:get(false), page:get(false) + 1))
						end,
					}),
				},
			}),
			-- Detail page for one species.
			New("Frame")({
				Name = "Detail",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 70),
				Size = UDim2.new(1, 0, 1, -70),
				Visible = Computed(function()
					return selected:get() ~= nil
				end),
				ZIndex = 11,
				[Children] = detail,
			}),
			C.button({
				Name = "Back",
				Text = "< Back",
				Size = UDim2.fromOffset(120, 46),
				Position = UDim2.fromOffset(0, 16),
				Color = Theme.colors.purple,
				MaxTextSize = 20,
				Visible = Computed(function()
					return selected:get() ~= nil
				end),
				OnClick = function()
					selected:set(nil)
				end,
			}),
		},
	})
end
