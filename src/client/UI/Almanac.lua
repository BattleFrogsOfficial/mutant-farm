--!strict
-- The Almanac: every species (400, plus each limited egg's), Pokedex-style. Limited eggs get their
-- own tab after the tiers, and their species say "LIMITED · <event>". Undiscovered species are black
-- silhouettes marked "???". Discovered ones open a detail page with a spinning 3D model,
-- description, traits, size range, your biggest one, hatch count, first-hatch date and a fun fact.
-- Under the title, the milestone track (math in shared/AlmanacTrack, layout in Config/AlmanacUI):
-- the fill runs from the last passed milestone to the next one (the big diamond), the later ones
-- sit proportionally along the rest; tapping a marker shows its reward as a tooltip.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local Rarities = require(Shared.Config.Rarities)
local Mutants = require(Shared.Config.Mutants)
local MutantModel = require(Shared.MutantModel)
local AlmanacUI = require(Shared.Config.AlmanacUI)
local AlmanacTrack = require(Shared.AlmanacTrack)
local HudConfig = require(Shared.Config.Hud)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Viewport = require(script.Parent.Viewport)

local New, Children, Computed, Value, OnEvent, Observer =
	Fusion.New, Fusion.Children, Fusion.Computed, Fusion.Value, Fusion.OnEvent, Fusion.Observer

local PER_PAGE = 12 -- 6 x 2
local CONTENT_W = AlmanacUI.panelWidth - 2 * AlmanacUI.contentPad
local TABS_TOP = AlmanacUI.trackHeight + AlmanacUI.tabsGap
local GRID_TOP = TABS_TOP + AlmanacUI.tabHeight + AlmanacUI.gridGap
local GRID_H = 2 * AlmanacUI.cellHeight + AlmanacUI.cellGap
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
					Size = UDim2.new(1, -8, 1, -42),
					Position = UDim2.fromOffset(4, 2),
					ZIndex = 3,
				}),
				C.label({
					Text = if found then e.name else "???",
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -6),
					Size = UDim2.new(1, -8, 0, 34),
					-- A fixed 14 px (the text-size rule); a long name wraps to a second line.
					TextScaled = false,
					TextSize = 14,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Bottom,
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
				-- Limited species: the limited egg's glyph in the top-left corner.
				if Eggs.tiers[e.tier].limited and Eggs.tiers[e.tier].glyph
					then C.icon(Eggs.tiers[e.tier].glyph, 18, nil, {
						Position = UDim2.fromOffset(5, 4),
						ZIndex = 4,
					})
					else nil,
				found and C.label({
					Text = "x" .. entry.n,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -4, 0, 2),
					Size = UDim2.fromOffset(40, 20),
					TextScaled = false,
					TextSize = 16,
					TextXAlignment = Enum.TextXAlignment.Right,
					TextColor3 = Theme.colors.gold,
					ZIndex = 4,
				}) or nil,
			},
		}),
	})
end

-------------------------------------------------------------------------- milestone track

-- The milestone whose tooltip is open (nil = none). Module-level so the UI preview can open one.
local tip = Value(nil :: number?)

local ROW_MID = AlmanacUI.markerRowHeight / 2
local LABEL_H = AlmanacUI.trackHeight - AlmanacUI.labelTop

-- A check mark from two ink bars (the font has no check glyph), centered on the marker.
local function checkMark(size: number, cx: number, z: number)
	local bars = {}
	for _, b in AlmanacUI.checkBars do
		table.insert(
			bars,
			New("Frame")({
				BorderSizePixel = 0,
				BackgroundColor3 = Theme.colors.ink,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(b.x, b.y),
				Size = UDim2.new(b.len, 0, 0, AlmanacUI.checkThickness),
				Rotation = b.angle,
				ZIndex = z,
			})
		)
	end
	return New("Frame")({
		Name = "Check",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, ROW_MID),
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
		[Children] = bars,
	})
end

local LUCK_COLOR = Color3.fromHex(AlmanacUI.luckColor)

local function markerColor(mk: AlmanacTrack.Marker): Color3
	local m = mk.milestone
	if mk.role == "passed" then
		return Theme.colors.gold
	elseif mk.role == "next" then
		return Theme.colors.water
	elseif m.kind == "egg" and Eggs.tiers[m.egg :: string] then
		return Color3.fromHex(Eggs.tiers[m.egg :: string].color):Lerp(Theme.colors.white, AlmanacUI.eggMarkerTint)
	elseif m.kind == "luck" then
		return LUCK_COLOR
	end
	return Theme.colors.slateLight
end

local function labelColor(mk: AlmanacTrack.Marker): Color3
	return if mk.role == "passed"
		then Theme.colors.gold
		elseif mk.role == "next" then Theme.colors.white
		else Theme.colors.cream
end

local function toggleTip(at: number)
	tip:set(if tip:get(false) == at then nil else at)
end

-- One marker: a transparent tap target (its stretch of the track, full height, so the label row
-- under it counts too) holding the turned square.
local function marker(mk: AlmanacTrack.Marker)
	local at = mk.milestone.at
	local cx = mk.x - mk.hitLeft
	return New("TextButton")({
		Name = "Marker" .. at,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(mk.hitLeft, 0),
		Size = UDim2.fromOffset(mk.hitRight - mk.hitLeft, AlmanacUI.trackHeight),
		ZIndex = 14,
		[OnEvent("Activated")] = function()
			toggleTip(at)
		end,
		[Children] = {
			New("Frame")({
				-- Named by role so the preview checks can tell them apart.
				Name = if mk.role == "passed" then "Passed" elseif mk.role == "next" then "Next" else "Later",
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(cx, ROW_MID),
				Size = UDim2.fromOffset(mk.size, mk.size),
				Rotation = 45,
				BackgroundColor3 = markerColor(mk),
				ZIndex = 15,
				[Children] = C.stroke(Theme.colors.ink, mk.outline),
			}),
			if mk.role == "passed" then checkMark(math.floor(mk.size * AlmanacUI.checkRatio), cx, 16) else nil,
		},
	})
end

-- A label: the species needed on top ("100"), the reward under it ("Toxic Egg", smaller), centered
-- under its marker. Tapping it opens its marker's tooltip.
local function trackLabel(mk: AlmanacTrack.Marker, font: number)
	local l = mk.label :: AlmanacTrack.Label
	local at = mk.milestone.at
	local small = AlmanacTrack.rewardFont(font)
	local function line(order: number, text: string, size: number, color: Color3)
		return New("TextLabel")({
			Name = if order == 1 then "Need" else "Reward",
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, math.ceil(size * 1.05)),
			Font = Theme.font,
			TextSize = size,
			TextColor3 = color,
			Text = text,
			ZIndex = 15,
			[Children] = C.textStroke(1.5),
		})
	end
	return New("TextButton")({
		Name = "Label" .. at,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(l.x, AlmanacUI.labelTop),
		Size = UDim2.fromOffset(l.w, LABEL_H),
		Text = "",
		ZIndex = 15,
		[OnEvent("Activated")] = function()
			toggleTip(at)
		end,
		[Children] = {
			New("UIListLayout")({
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			line(1, l.pre, font, labelColor(mk)),
			if l.post ~= "" then line(2, l.post, small, Theme.colors.cream) else nil,
		},
	})
end

-- The track's contents for `found` species at label size `font`.
local function trackChildren(found: number, font: number, tipAt: number?, hit: number): { Instance }
	local layout = AlmanacTrack.layout(found, TOTAL, CONTENT_W, font, tipAt, hit)
	local barY = ROW_MID - AlmanacUI.barHeight / 2
	local out: { Instance } = {
		New("Frame")({
			Name = "BarShadow",
			BorderSizePixel = 0,
			BackgroundColor3 = Theme.colors.ink,
			BackgroundTransparency = 0.2,
			Position = UDim2.fromOffset(layout.barLeft + Theme.shadow, barY + Theme.shadow),
			Size = UDim2.fromOffset(layout.barRight - layout.barLeft, AlmanacUI.barHeight),
			ZIndex = 11,
		}),
		New("Frame")({
			Name = "Bar",
			BorderSizePixel = 0,
			BackgroundColor3 = Theme.colors.slate,
			Position = UDim2.fromOffset(layout.barLeft, barY),
			Size = UDim2.fromOffset(layout.barRight - layout.barLeft, AlmanacUI.barHeight),
			ZIndex = 12,
			[Children] = C.stroke(Theme.colors.ink, AlmanacUI.barOutline),
		}),
		New("Frame")({
			Name = "Fill",
			BorderSizePixel = 0,
			BackgroundColor3 = if layout.allPassed then Theme.colors.gold else Theme.colors.water,
			Position = UDim2.fromOffset(layout.segStart, barY),
			Size = UDim2.fromOffset(layout.fillWidth, AlmanacUI.barHeight),
			ZIndex = 13,
			[Children] = C.shine(),
		}),
	}
	-- The passed stretch (0 .. the last passed milestone) is done: gold under its markers.
	if not layout.allPassed and layout.segStart > layout.barLeft then
		table.insert(
			out,
			New("Frame")({
				Name = "Done",
				BorderSizePixel = 0,
				BackgroundColor3 = Theme.colors.gold,
				Position = UDim2.fromOffset(layout.barLeft, barY),
				Size = UDim2.fromOffset(layout.segStart - layout.barLeft, AlmanacUI.barHeight),
				ZIndex = 13,
				[Children] = C.shine(),
			})
		)
	end
	for _, mk in layout.markers do
		table.insert(out, marker(mk))
		if mk.label and not mk.label.covered then
			table.insert(out, trackLabel(mk, font))
		end
	end
	local t = layout.tooltip
	if t then
		table.insert(
			out,
			-- A button over the markers and labels under it: tapping the tooltip closes it.
			New("TextButton")({
				Name = "Tooltip",
				Text = "",
				AutoButtonColor = false,
				Active = true,
				BorderSizePixel = 0,
				BackgroundColor3 = Theme.colors.ink,
				Position = UDim2.fromOffset(t.x, AlmanacUI.labelTop),
				Size = UDim2.fromOffset(t.w, LABEL_H),
				ZIndex = 17,
				[OnEvent("Activated")] = function()
					tip:set(nil)
				end,
				[Children] = {
					C.stroke(Theme.colors.gold, AlmanacUI.tooltipOutline),
					New("TextLabel")({
						Name = "Text",
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						Font = Theme.font,
						TextSize = font,
						TextColor3 = Theme.colors.white,
						Text = t.text,
						ZIndex = 18,
					}),
				},
			})
		)
	end
	return out
end

local function build()
	local isOpen = Computed(function()
		return State.panel:get() == "almanac"
	end)
	local tab = Value(Eggs.order[1])
	local page = Value(1)
	local selected = Value(nil :: string?)
	-- Closing the panel (X, backdrop or anything else) closes the tooltip too.
	Observer(isOpen):onChange(function()
		if not isOpen:get(false) then
			tip:set(nil)
		end
	end)

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
	local tabWidth = math.min(112, math.floor((CONTENT_W - 6 * (#TABS - 1)) / #TABS))
	for i, tierId in TABS do
		local tierName = (Eggs.tiers[tierId].name:gsub(" Egg$", ""))
		table.insert(
			tabs,
			C.button({
				Name = tierId,
				LayoutOrder = i,
				Size = UDim2.fromOffset(tabWidth, AlmanacUI.tabHeight),
				Color = Color3.fromHex(Eggs.tiers[tierId].color):Lerp(Theme.colors.slateLight, 0.4),
				Selected = Computed(function()
					return tab:get() == tierId
				end),
				Text = "",
				Children = {
					C.label({
						Name = "TabName",
						Text = tierName,
						Position = UDim2.fromOffset(AlmanacUI.tabTextInset, AlmanacUI.tabName.y),
						Size = UDim2.new(1, -2 * AlmanacUI.tabTextInset, 0, AlmanacUI.tabName.height),
						MaxTextSize = AlmanacUI.tabName.text,
						StrokeThickness = 2.5,
						ZIndex = 3,
					}),
					C.label({
						Name = "TabCount",
						Text = Computed(function()
							local almanac = State.almanac:get()
							local n = 0
							for _, id in byTier[tierId] do
								if almanac[id] then
									n += 1
								end
							end
							return string.format("%d/%d", n, #byTier[tierId])
						end),
						Position = UDim2.fromOffset(AlmanacUI.tabTextInset, AlmanacUI.tabCount.y),
						Size = UDim2.new(1, -2 * AlmanacUI.tabTextInset, 0, AlmanacUI.tabCount.height),
						MaxTextSize = AlmanacUI.tabCount.text,
						TextColor3 = Theme.colors.cream,
						ZIndex = 3,
					}),
				},
				OnClick = function()
					tab:set(tierId)
					page:set(1)
					selected:set(nil)
					tip:set(nil)
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
					tip:set(nil)
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
		-- Found / total only: the rewards are on the milestone track.
		Title = Computed(function()
			return string.format("Almanac %d / %d", foundCount:get(), TOTAL)
		end),
		Icon = "book",
		Accent = Theme.colors.purple,
		Size = UDim2.fromOffset(AlmanacUI.panelWidth, AlmanacUI.panelHeight),
		IsOpen = isOpen,
		OnClose = function()
			selected:set(nil)
			tip:set(nil)
			State.panel:set("none")
		end,
		Content = {
			-- Taps anywhere else in the panel (header and padding included) close an open tooltip:
			-- under every control, over the panel's own blocker. The close X sits above it.
			New("TextButton")({
				Name = "TipCatcher",
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(-AlmanacUI.contentPad, -AlmanacUI.contentTop),
				Size = UDim2.new(1, 2 * AlmanacUI.contentPad, 1, AlmanacUI.contentTop + AlmanacUI.contentPad),
				ZIndex = 10,
				Visible = Computed(function()
					return tip:get() ~= nil
				end),
				[OnEvent("Activated")] = function()
					tip:set(nil)
				end,
			}),
			-- Milestone track (hidden on a species page). Its label size follows the on-screen
			-- scale (HUD scale x the panel's fit) so labels stay readable on small phones.
			New("Frame")({
				Name = "AlmanacTrack",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, AlmanacUI.trackHeight),
				Visible = Computed(function()
					return selected:get() == nil
				end),
				ZIndex = 11,
				[Children] = Computed(function()
					if State.panel:get() ~= "almanac" then
						return {}
					end
					local n = 0
					for _ in State.almanac:get() do
						n += 1
					end
					local screen = State.screen:get()
					local scale = math.max(screen.scale, 0.01)
					local fit = math.min(
						1,
						(screen.width / scale - 2 * HudConfig.panelMargin) / AlmanacUI.panelWidth,
						(screen.height / scale - 2 * HudConfig.panelMargin) / AlmanacUI.panelHeight
					)
					local onScreen = scale * fit
					local hit = math.max(AlmanacUI.hitWidth, AlmanacUI.minTapScreenPx / onScreen)
					return trackChildren(n, AlmanacTrack.fontSize(onScreen), tip:get(), hit)
				end, Fusion.cleanup),
			}),
			New("Frame")({
				Name = "Tabs",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, TABS_TOP),
				Size = UDim2.new(1, 0, 0, AlmanacUI.tabHeight),
				Visible = Computed(function()
					return selected:get() == nil
				end),
				ZIndex = 11,
				[Children] = tabs,
			}),
			New("Frame")({
				Name = "Grid",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, GRID_TOP),
				Size = UDim2.new(1, 0, 0, GRID_H),
				Visible = Computed(function()
					return selected:get() == nil
				end),
				ZIndex = 11,
				[Children] = {
					New("UIGridLayout")({
						-- 2 rows between the tabs and the pager, 6 columns in the content width.
						CellSize = UDim2.fromOffset(AlmanacUI.cellWidth, AlmanacUI.cellHeight),
						CellPadding = UDim2.fromOffset(AlmanacUI.cellGap, AlmanacUI.cellGap),
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
				Size = UDim2.fromOffset(320, AlmanacUI.pagerHeight),
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
							tip:set(nil)
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
							tip:set(nil)
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

-- Root mounts it with Almanac(); .tip is the open tooltip's milestone (nil = none), for the preview.
return setmetatable({ tip = tip }, {
	__call = function()
		return build()
	end,
}) :: any
