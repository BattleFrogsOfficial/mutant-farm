-- Almanac milestone track scenes, each at every preview size (almanac-<found>@WxH): 5, 24, 26 and
-- 399 species found, and one with the tooltip of the 100 marker open (almanac-tip-26). Checked by
-- tools/preview/checks/almanac.js.
return function(api)
	local State = api.State
	local Mutants = api.requireModule(api.Shared.Config.Mutants)
	local Almanac = api.requireModule(api.UI.Almanac)

	-- Capture just the Almanac panel (its own mount, in a full-size holder named "Root": ui-render
	-- draws the root's children). Independent of whatever the default root is at this point.
	local holder = api.Instance.new("Frame")
	holder.Name = "Root"
	holder.Size = api.roblox.UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	Almanac().Parent = holder
	api.setRoot(holder)

	local ids = {}
	for id in Mutants.species do
		table.insert(ids, id)
	end
	table.sort(ids)
	local function found(n: number)
		local entries = {}
		for i = 1, n do
			entries[ids[i]] = { n = 1, first = 1_799_000_000, best = 1.2 }
		end
		return entries
	end

	for _, n in { 5, 24, 26, 399 } do
		api.set(State.almanac, found(n))
		api.set(State.panel, "almanac")
		api.captureHud("almanac-" .. n)
		api.set(State.panel, "none")
	end

	-- A tapped marker: the 100 (Toxic Egg) tooltip with 26 found.
	api.set(State.almanac, found(26))
	api.set(State.panel, "almanac")
	api.set(Almanac.tip, 100)
	api.captureHud("almanac-tip-26")
	api.set(Almanac.tip, nil)
	api.set(State.panel, "none")
	api.restoreRoot()
	holder:Destroy()
	api.reset()
end
