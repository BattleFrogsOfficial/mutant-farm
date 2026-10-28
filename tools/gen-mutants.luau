-- Generates src/shared/Config/Mutants.lua: 400 mutant species spread across the 6 egg tiers
-- and 5 rarities. Deterministic (fixed seed), so re-running gives the same roster.
-- The file it writes is plain data: edit names/looks there by hand after generating.
--   lune run tools/gen-mutants
-- WARNING: re-running overwrites hand edits in Mutants.lua.

local fs = require("@lune/fs")
local harness = require("./harness")
local Rng = harness.require("src/shared/Rng")

local rng = Rng.new(400)
local function pick<T>(list: { T }): T
	return list[rng:integer(1, #list)]
end

local TIERS = { "Starter", "Swamp", "Lab", "Toxic", "Void", "Cosmic" }
local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
-- 66 or 67 per tier, 400 total. More commons = more to collect at the bottom.
local COUNTS = { Common = 20, Uncommon = 16, Rare = 13, Epic = 10, Legendary = 7 }
local EXTRA_COMMONS = { Starter = 1, Swamp = 1, Lab = 1, Toxic = 1 } -- 4 x 67 + 2 x 66 = 400

-- The original hand-made 30 lead each bucket.
local ORIGINALS = {
	Starter = {
		Common = { "Blorp", "blob", "#B8F07A", 1, "none" },
		Uncommon = { "Snorkle", "blob", "#7FE0C8", 2, "antennae" },
		Rare = { "Toothy Pip", "tall", "#6FB7FF", 2, "none", "tooth" },
		Epic = { "Triclops", "blob", "#C38BFF", 3, "none" },
		Legendary = { "King Goober", "tall", "#FFB347", 2, "crown" },
	},
	Swamp = {
		Common = { "Muckling", "flat", "#7C9A4E", 2, "ears" },
		Uncommon = { "Bogwump", "blob", "#4E9E6A", 2, "leaf" },
		Rare = { "Croakzilla", "pear", "#3FA7A0", 2, "none", "wide" },
		Epic = { "Mire Hydra", "spiky", "#2F7F5A", 3, "none" },
		Legendary = { "Swamp Sovereign", "tall", "#5DBB63", 2, "crown" },
	},
	Lab = {
		Common = { "Beaker Bean", "tall", "#DDE6F0", 2, "none" },
		Uncommon = { "Gogglegunk", "blob", "#B9C7D9", 2, "goggles" },
		Rare = { "Clonelet", "puff", "#8FD3FF", 2, "antennae" },
		Epic = { "Brainiac Blob", "blob", "#FF8FB8", 3, "goggles" },
		Legendary = { "Dr. Splice", "tall", "#FFFFFF", 2, "halo" },
	},
	Toxic = {
		Common = { "Sludgeling", "flat", "#9BE04A", 2, "none" },
		Uncommon = { "Fumefang", "spiky", "#6FCB3A", 2, "none", "fangs" },
		Rare = { "Rad Roach", "flat", "#C8FF3A", 2, "antennae" },
		Epic = { "Glowgutter", "blob", "#5CFF8A", 3, "horns" },
		Legendary = { "Toxic Titan", "tall", "#7CFF4A", 2, "goggles" },
	},
	Void = {
		Common = { "Nullnub", "blob", "#4A3D66", 1, "none" },
		Uncommon = { "Echo Eye", "blob", "#5B4A8A", 1, "antennae" },
		Rare = { "Shadewing", "flat", "#3A2F5C", 2, "wings" },
		Epic = { "Rift Gremlin", "spiky", "#6A3FA0", 3, "horns" },
		Legendary = { "The Hollow", "tall", "#2B2140", 2, "crown" },
	},
	Cosmic = {
		Common = { "Stardrop", "blob", "#8A7CFF", 2, "antennae" },
		Uncommon = { "Moonmunch", "flat", "#B7A8FF", 2, "none", "wide" },
		Rare = { "Nebulord", "puff", "#9B5CFF", 3, "horns" },
		Epic = { "Quasar Kid", "spiky", "#FF5CE1", 2, "antennae" },
		Legendary = { "Galaxy Gobbler", "worm", "#5A2DFF", 3, "crown", "wide" },
	},
}

-- Per-tier palette (body colors) and naming flavor.
local PALETTES = {
	Starter = { "#B8F07A", "#FFE37A", "#7FD8FF", "#FFB0C8", "#C9F2A0", "#FFC98A", "#A8E6CF", "#D7B8FF" },
	Swamp = { "#7C9A4E", "#4E9E6A", "#3FA7A0", "#8B7B4A", "#5DBB63", "#2F7F5A", "#6E8F3A", "#4C7A70" },
	Lab = { "#E8EEF5", "#B9C7D9", "#8FD3FF", "#FF8FB8", "#C8F0FF", "#F5D0FF", "#D0FFE8", "#FFFFFF" },
	Toxic = { "#9BE04A", "#C8FF3A", "#7CFF4A", "#FFD23A", "#FF9A3C", "#5CFF8A", "#E4FF6A", "#3ACB6A" },
	Void = { "#4A3D66", "#2B2140", "#5B4A8A", "#3A2F5C", "#6A3FA0", "#1F2A4A", "#40205A", "#2C3E6E" },
	Cosmic = { "#8A7CFF", "#B7A8FF", "#9B5CFF", "#FF5CE1", "#5A2DFF", "#5CE1FF", "#FF8AF0", "#7A5CFF" },
}
local ACCENTS = { "#FFFFFF", "#FFD24A", "#FF5A7A", "#7CFF4A", "#4AB8FF", "#1E2230", "#FF9A3C", "#C29BFF" }
local TIER_WORDS = {
	Starter = { "Lil", "Baby", "Tiny", "Pocket" },
	Swamp = { "Bog", "Muck", "Mire", "Marsh", "Swamp" },
	Lab = { "Proto", "Beaker", "Clone", "Lab", "Dr." },
	Toxic = { "Rad", "Sludge", "Toxi", "Fume", "Acid" },
	Void = { "Null", "Shade", "Rift", "Void", "Hollow" },
	Cosmic = { "Star", "Nova", "Astro", "Luna", "Comet" },
}
local START = {
	"B",
	"Bl",
	"Gl",
	"Sn",
	"Pl",
	"Squ",
	"Gr",
	"Fl",
	"Z",
	"W",
	"M",
	"G",
	"Sk",
	"Dr",
	"Fr",
	"Ch",
	"Sl",
	"Qu",
	"N",
	"J",
	"P",
	"Sp",
	"Tw",
	"Kr",
	"Br",
	"Sm",
	"Wh",
	"D",
	"T",
	"L",
}
local MID = { "o", "u", "oo", "i", "a", "ee", "oi", "ou", "o", "u", "a" }
local FINISH = {
	"rp",
	"bble",
	"mp",
	"nk",
	"mble",
	"zzle",
	"ggle",
	"ppy",
	"bby",
	"nch",
	"mbo",
	"ngo",
	"lly",
	"ster",
	"pkin",
	"blet",
	"pling",
	"wump",
	"zog",
	"rb",
	"gg",
	"b",
	"x",
	"sh",
	"rk",
	"dle",
	"mpus",
	"bert",
	"nkus",
	"po",
	"ky",
	"nks",
	"ffle",
	"mpy",
	"zy",
}
local EPIC_SUFFIX = { "Prime", "the Mighty", "Max", "Supreme", "Ultra", "Rex", "the Huge" }
local LEGEND_PREFIX = { "King", "Queen", "Lord", "Emperor", "Grand", "Overlord", "Baron", "Duchess", "Mega" }

local BODIES = { "blob", "tall", "flat", "spiky", "pear", "worm", "puff" }
local ACCESSORIES = { "none", "antennae", "horns", "ears", "leaf", "goggles", "mohawk", "wings", "halo", "crown" }
local MOUTHS = { "smile", "smile", "fangs", "tooth", "wide", "tongue", "none" }
local PATTERNS = { "plain", "spots", "stripes", "belly", "belly" }
local EYE_STYLES = { "normal", "normal", "normal", "stalk", "sleepy", "angry" }

local used: { [string]: boolean } = {}
local function word(): string
	return pick(START) .. pick(MID) .. pick(FINISH)
end
local function makeName(tier: string, rarity: string): string
	for _ = 1, 200 do
		local base = word()
		local name
		if rarity == "Common" then
			name = if rng:next() < 0.3 then pick(TIER_WORDS[tier]) .. " " .. base else base
		elseif rarity == "Uncommon" then
			name = if rng:next() < 0.4 then pick(TIER_WORDS[tier]) .. " " .. base else base
		elseif rarity == "Rare" then
			name = pick(TIER_WORDS[tier]) .. " " .. base
		elseif rarity == "Epic" then
			name = base .. " " .. pick(EPIC_SUFFIX)
		else
			name = pick(LEGEND_PREFIX) .. " " .. base
		end
		if not used[name] then
			used[name] = true
			return name
		end
	end
	error("ran out of names")
end

local species = {}
local buckets = {}
local order = {}

local function add(entry)
	species[entry.id] = entry
	table.insert(buckets[entry.tier][entry.rarity], entry.id)
	table.insert(order, entry.id)
end

for tierIndex, tier in TIERS do
	buckets[tier] = {}
	for rarityIndex, rarity in RARITIES do
		buckets[tier][rarity] = {}
		local count = COUNTS[rarity] + (if rarity == "Common" then EXTRA_COMMONS[tier] or 0 else 0)
		for n = 1, count do
			local id = string.format("%s_%s_%02d", tier, rarity, n)
			local entry
			local original = n == 1 and ORIGINALS[tier][rarity]
			if original then
				used[original[1]] = true
				entry = {
					id = id,
					tier = tier,
					rarity = rarity,
					name = original[1],
					body = original[2],
					color = original[3],
					accent = pick(ACCENTS),
					pattern = "belly",
					eyes = original[4],
					eyeStyle = "normal",
					mouth = original[6] or "smile",
					accessory = original[5],
					scale = 1,
				}
			else
				-- Rarer = more eyes, fancier accessories, bigger base size.
				local eyes = if rarity == "Epic"
					then rng:integer(2, 4)
					elseif rarity == "Legendary" then rng:integer(2, 3)
					else rng:integer(1, 3)
				local accessory = pick(ACCESSORIES)
				if rarity == "Legendary" and rng:next() < 0.6 then
					accessory = pick({ "crown", "halo", "wings", "horns" })
				elseif rarity == "Common" and (accessory == "crown" or accessory == "halo") then
					accessory = "none"
				end
				entry = {
					id = id,
					tier = tier,
					rarity = rarity,
					name = makeName(tier, rarity),
					body = pick(BODIES),
					color = pick(PALETTES[tier]),
					accent = pick(ACCENTS),
					pattern = pick(PATTERNS),
					eyes = eyes,
					eyeStyle = pick(EYE_STYLES),
					mouth = pick(MOUTHS),
					accessory = accessory,
					scale = math.floor((0.85 + rng:next() * 0.4 + (rarityIndex - 1) * 0.04) * 100 + 0.5) / 100,
				}
			end
			add(entry)
		end
	end
	local _ = tierIndex
end

-- Write the Luau data file.
local lines = {
	"--!strict",
	"-- 400 mutant species, generated by tools/gen-mutants.luau (re-running overwrites edits).",
	"-- Edit any entry by hand. Fields:",
	"--   name, body (blob tall flat spiky pear worm puff), color/accent (hex),",
	"--   pattern (plain spots stripes belly), eyes (1-4), eyeStyle (normal stalk sleepy angry),",
	"--   mouth (smile fangs tooth wide tongue none),",
	"--   accessory (none antennae horns ears leaf goggles mohawk wings halo crown), scale (base size).",
	"-- Each hatch picks a species uniformly from buckets[tier][rarity]. Value depends only on",
	"-- tier, rarity, mutations and size, so species is a collectible look, not a power level.",
	"",
	"local species = {",
}
local function q(s: string): string
	return string.format("%q", s)
end
for _, id in order do
	local e = species[id]
	table.insert(
		lines,
		string.format(
			"\t%s = { tier = %s, rarity = %s, name = %s, body = %s, color = %s, accent = %s, pattern = %s, eyes = %d, eyeStyle = %s, mouth = %s, accessory = %s, scale = %s },",
			e.id,
			q(e.tier),
			q(e.rarity),
			q(e.name),
			q(e.body),
			q(e.color),
			q(e.accent),
			q(e.pattern),
			e.eyes,
			q(e.eyeStyle),
			q(e.mouth),
			q(e.accessory),
			tostring(e.scale)
		)
	)
end
table.insert(lines, "}")
table.insert(lines, "")
table.insert(lines, "local buckets = {}")
table.insert(lines, "for id, entry in species do")
table.insert(lines, "\tentry.id = id")
table.insert(lines, "\tbuckets[entry.tier] = buckets[entry.tier] or {}")
table.insert(lines, "\tbuckets[entry.tier][entry.rarity] = buckets[entry.tier][entry.rarity] or {}")
table.insert(lines, "\ttable.insert(buckets[entry.tier][entry.rarity], id)")
table.insert(lines, "end")
table.insert(lines, "-- Stable order so a given roll maps to the same species on every server.")
table.insert(lines, "for _, byRarity in buckets do")
table.insert(lines, "\tfor _, ids in byRarity do")
table.insert(lines, "\t\ttable.sort(ids)")
table.insert(lines, "\tend")
table.insert(lines, "end")
table.insert(lines, "")
table.insert(lines, "return { species = species, buckets = buckets }")
fs.writeFile("src/shared/Config/Mutants.lua", table.concat(lines, "\n") .. "\n")
print(string.format("wrote %d species", #order))
