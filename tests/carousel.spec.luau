-- Egg Shop carousel: snapping, focus rules, switch independence, auto-scroll gating, unlocks,
-- and the policy gates the shop relies on.
return function(t)
	local Carousel = t.require("src/shared/Carousel")
	local ShopRules = t.require("src/shared/ShopRules")
	local cfg = t.require("src/shared/Config/EggShopUI")
	local N, PITCH = 6, cfg.pitch

	-- Rebirth 0 with Lab next: Starter, Swamp buyable; Lab next (focusable); Toxic+ further-locked.
	local function focusable(i)
		return i <= 3
	end
	local function oneCentered(offset)
		local c = Carousel.centered(offset, PITCH, N, 2)
		return #c == 1
	end

	return {
		["snap: any drag settles with exactly one card centered (within 2px)"] = function()
			for raw = -0.35 * PITCH, (N - 1 + 0.35) * PITCH, 7 do
				for _, dir in { -1, 0, 1 } do
					local i =
						Carousel.settle(Carousel.clampDrag(raw, PITCH, N, cfg.dragOvershoot), PITCH, N, focusable, dir)
					t.ok(oneCentered(Carousel.offsetOf(i, PITCH)), "drag to " .. raw)
				end
			end
		end,
		["snap: steps, wheel notches and auto-scroll steps land centered"] = function()
			local i = 1
			for _, dir in { 1, 1, 1, 1, -1, -1, -1, -1, -1 } do
				i = Carousel.step(i, dir, N, focusable)
				t.ok(oneCentered(Carousel.offsetOf(i, PITCH)), "step")
			end
			for _, z in { -1, -1, -1, 1, 1 } do
				i = Carousel.wheel(i, z, N, focusable)
				t.ok(oneCentered(Carousel.offsetOf(i, PITCH)), "wheel")
			end
		end,
		["focus: a further-locked card is never focused after input settles"] = function()
			-- Dragging onto Toxic/Void/Cosmic while moving right falls back to Lab.
			for _, idx in { 4, 5, 6 } do
				local i = Carousel.settle(Carousel.offsetOf(idx, PITCH), PITCH, N, focusable, 1)
				t.ok(focusable(i), "settled on a focusable card")
				t.eq(i, 3)
			end
			-- Stepping right past the last focusable card stays put.
			t.eq(Carousel.step(3, 1, N, focusable), 3)
			t.eq(Carousel.wheel(3, -1, N, focusable), 3)
			-- A locked card in the middle is skipped in the direction of travel.
			local holes = function(i)
				return i ~= 2
			end
			t.eq(Carousel.step(1, 1, N, holes), 3)
			t.eq(Carousel.settle(Carousel.offsetOf(2, PITCH), PITCH, N, holes, 1), 3)
			t.eq(Carousel.settle(Carousel.offsetOf(2, PITCH), PITCH, N, holes, -1), 1)
		end,
		["switch: focusable cards don't depend on the Cash/Gems mode, so focus and offset hold"] = function()
			-- Unlock gating is identical for base tiers and their Gem variants.
			for _, base in { "Starter", "Swamp", "Lab", "Toxic", "Void", "Cosmic" } do
				for _, state in { { 0, 0 }, { 0, 30_000 }, { 1, 0 }, { 3, 0 }, { 6, 0 } } do
					t.eq(
						ShopRules.isUnlocked(base, state[1], state[2]),
						ShopRules.isUnlocked(base .. "Gem", state[1], state[2])
					)
				end
			end
		end,
		["auto-scroll: only for a mouse, never on touch, only in the edge zones"] = function()
			local dir, every = Carousel.autoScroll(cfg, 0, true, true, false)
			t.eq(dir, -1)
			t.near(every :: number, cfg.autoScrollOuter, 1e-9)
			dir, every = Carousel.autoScroll(cfg, 1 - cfg.edgeZone + 1e-9, true, true, false)
			t.eq(dir, 1)
			t.near(every :: number, cfg.autoScrollInner, 1e-6)
			t.eq((Carousel.autoScroll(cfg, 0.5, true, true, false)), 0)
			t.eq((Carousel.autoScroll(cfg, 0.02, false, true, false)), 0) -- left the panel
			t.eq((Carousel.autoScroll(cfg, 0.02, true, true, true)), 0) -- touch device
			t.eq((Carousel.autoScroll(cfg, 0.02, true, false, false)), 0) -- no mouse
		end,
		["device: drag, arrows and wheel each move the strip on their own"] = function()
			-- From Swamp (2), each input alone reaches Starter and Lab; none needs another.
			local function dragTo(offset, dir)
				return Carousel.settle(
					Carousel.clampDrag(offset, PITCH, N, cfg.dragOvershoot),
					PITCH,
					N,
					focusable,
					dir
				)
			end
			t.eq(dragTo(Carousel.offsetOf(2, PITCH) + 0.6 * PITCH, 1), 3)
			t.eq(dragTo(Carousel.offsetOf(2, PITCH) - 0.6 * PITCH, -1), 1)
			t.eq(Carousel.step(2, 1, N, focusable), 3)
			t.eq(Carousel.step(2, -1, N, focusable), 1)
			t.eq(Carousel.wheel(2, -1, N, focusable), 3)
			t.eq(Carousel.wheel(2, 1, N, focusable), 1)
			-- And at an end nothing moves past it (the arrow that way is hidden).
			t.eq(Carousel.step(3, 1, N, focusable), 3)
			t.eq(Carousel.step(1, -1, N, focusable), 1)
		end,
		["unlock: crossing $25K earned unlocks Lab mid-session"] = function()
			local new = ShopRules.newlyUnlocked(
				{ rebirths = 0, totalCashEarned = 24_900 },
				{ rebirths = 0, totalCashEarned = 25_100 }
			)
			t.eq(#new, 1)
			t.eq(new[1], "Lab")
			t.eq(
				#ShopRules.newlyUnlocked({ rebirths = 0, totalCashEarned = 0 }, { rebirths = 0, totalCashEarned = 100 }),
				0
			)
		end,
		["policy: restricted players can't buy the Luck Potion or Gem eggs"] = function()
			t.ok(not ShopRules.canBuyPotion(true), "potion refused")
			t.ok(ShopRules.canBuyPotion(false), "potion allowed")
			local ok, reason = ShopRules.canBuy(
				"LabGem",
				1,
				{ rebirths = 1, totalCashEarned = 1e9, cash = 1e12, gems = 1e9, paidRandomRestricted = true }
			)
			t.ok(not ok and reason == "restricted", "gem egg refused")
		end,
		["every tier has a tagline"] = function()
			local Eggs = t.require("src/shared/Config/Eggs")
			for _, id in Eggs.order do
				t.ok(type(Eggs.tiers[id].tagline) == "string" and #Eggs.tiers[id].tagline > 0, id)
			end
			t.eq(Eggs.tiers.Lab.tagline, "Where things go wrong")
		end,
	}
end
