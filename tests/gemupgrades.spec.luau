-- Gem upgrades: costs per level, the once-per-rebirth Pen Slots, the pass making Offline
-- Mutations MAX, and what each level gives.
return function(t)
	local G = t.require("src/shared/GemUpgrades")
	local Game = t.require("src/shared/Config/Game")
	return {
		["costs and caps"] = function()
			t.eq(G.cost("luck", 0, 0, false), 200)
			t.eq(G.cost("luck", 1, 0, false), 400)
			t.eq(G.cost("luck", 2, 0, false), 800)
			t.eq(G.cost("luck", 3, 0, false), nil, "3 levels")
			t.eq(G.cost("offline", 0, 0, false), 100)
			t.eq(G.cost("offline", 2, 5, false), 400)
			t.eq(G.cost("offline", 3, 5, false), nil)
			t.eq(G.cost("offline", 0, 0, true), nil, "the pass already rolls the whole time")
			t.eq(G.cost("bogus", 0, 0, false), nil)
		end,
		["pen slots: once per rebirth level"] = function()
			t.eq(G.cost("penSlots", 0, 0, false), 150)
			t.eq(G.cost("penSlots", 1, 0, false), nil, "bought at Rebirth 0")
			t.eq(G.cost("penSlots", 1, 1, false), 150, "again at Rebirth 1")
			t.eq(G.cost("penSlots", 2, 1, false), nil)
			t.eq(G.penCapacity(0), Game.penDisplayCount)
			t.eq(G.penCapacity(2), Game.penDisplayCount + 8)
		end,
		["luck and offline effects"] = function()
			t.near(G.luckBonus(3), 0.3, 1e-9)
			t.eq(G.offlineCap(0), Game.offlineMutationCap)
			t.eq(G.offlineCap(3), Game.offlineMutationCap + 6 * 3600)
		end,
	}
end
