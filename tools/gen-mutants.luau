-- Generates src/shared/Config/Mutants.lua: 666 mutant species, 83 per egg tier (26 Common,
-- 20 Uncommon, 16 Rare, 13 Epic, 8 Legendary; Starter and Swamp get one more Common), plus the
-- hand-made limited species below. Deterministic (fixed seed), so re-running gives the same roster.
-- Every look comes from the tier's own vocabulary in Config/MutantStyle.lua (bodies, skin,
-- signatures, feature pool, props, name grammar, idle); nothing is shared between tiers, and this
-- script asserts it. Rarity is a feature budget (MutantStyle.budget): Common 1 (the signature
-- only), Uncommon 2, Rare 3, Epic 4 + a prop no other species in its tier has, Legendary 5 + a
-- unique prop + a named idle variant + 1.2x base size. Species stay cosmetic (value = tier x
-- rarity x mutations x size). The 30 original species keep their names (each bucket's _01).
--   lune run tools/gen-mutants
-- WARNING: re-running overwrites hand edits in Mutants.lua.

local fs = require("@lune/fs")
local harness = require("./harness")
local Rng = harness.require("src/shared/Rng")
local Style = harness.require("src/shared/Config/MutantStyle")

-- The first six tiers draw from one sequence (seed 500), so their 500 species stay exactly as
-- they were; each later tier (Magma, Quantum: 2026-11-03) has its own seeded sequence, for its
-- species and their Almanac text.
local MAIN_TIERS = 6
local mainRng = Rng.new(500)
local tierRngs: { [string]: any } = {}
local rng = mainRng
local function useTier(tier: string)
	local index = table.find(Style.order, tier) or 1
	if index <= MAIN_TIERS then
		rng = mainRng
	else
		tierRngs[tier] = tierRngs[tier] or Rng.new(500 + index * 1000)
		rng = tierRngs[tier]
	end
end
local function pick<T>(list: { T }): T
	return list[rng:integer(1, #list)]
end
local function shuffled<T>(list: { T }): { T }
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = rng:integer(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

local TIERS = Style.order
local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local COUNTS = { Common = 26, Uncommon = 20, Rare = 16, Epic = 13, Legendary = 8 }
local EXTRA_COMMONS = { Starter = 1, Swamp = 1 } -- 8 x 83 + 2 = 666

-- The original hand-made 30 keep their names (each bucket's first species).
local ORIGINALS = {
	Starter = {
		Common = "Blorp",
		Uncommon = "Snorkle",
		Rare = "Toothy Pip",
		Epic = "Triclops",
		Legendary = "King Goober",
	},
	Swamp = {
		Common = "Muckling",
		Uncommon = "Bogwump",
		Rare = "Croakzilla",
		Epic = "Mire Hydra",
		Legendary = "Swamp Sovereign",
	},
	Lab = {
		Common = "Beaker Bean",
		Uncommon = "Gogglegunk",
		Rare = "Clonelet",
		Epic = "Brainiac Blob",
		Legendary = "Dr. Splice",
	},
	Toxic = {
		Common = "Sludgeling",
		Uncommon = "Fumefang",
		Rare = "Rad Roach",
		Epic = "Glowgutter",
		Legendary = "Toxic Titan",
	},
	Void = {
		Common = "Nullnub",
		Uncommon = "Echo Eye",
		Rare = "Shadewing",
		Epic = "Rift Gremlin",
		Legendary = "The Hollow",
	},
	Cosmic = {
		Common = "Stardrop",
		Uncommon = "Moonmunch",
		Rare = "Nebulord",
		Epic = "Quasar Kid",
		Legendary = "Galaxy Gobbler",
	},
}

---------------------------------------------------------------------------- vocabulary checks

-- Nothing in one tier's vocabulary appears in another's: body, feature and prop ids, and every
-- name syllable / word (case-insensitive).
local function vocabulary(tier: string): { [string]: { string } }
	local st = Style[tier]
	local out = { bodies = {}, features = {}, props = {}, syllables = {} }
	for _, b in st.bodies do
		table.insert(out.bodies, b.id)
	end
	for _, f in st.signatures do
		table.insert(out.features, f.id)
	end
	for _, f in st.features do
		table.insert(out.features, f.id)
	end
	for _, p in st.props do
		table.insert(out.props, p.id)
	end
	for _, key in { "first", "second", "words" } do
		for _, w in st.names[key] or {} do
			table.insert(out.syllables, w:lower())
		end
	end
	table.insert(out.syllables, st.names.title:lower())
	return out
end
do
	local owner: { [string]: { [string]: string } } = {}
	for _, tier in TIERS do
		for kind, list in vocabulary(tier) do
			owner[kind] = owner[kind] or {}
			for _, id in list do
				local key = id:lower()
				assert(
					owner[kind][key] == nil or owner[kind][key] == tier,
					string.format("%s '%s' is shared by %s and %s", kind, id, tostring(owner[kind][key]), tier)
				)
				owner[kind][key] = tier
			end
		end
		-- Every signature / pool slot combination leaves room for a Legendary's 5 features.
		local slots = {}
		for _, f in Style[tier].features do
			slots[f.slot] = true
		end
		for _, sig in Style[tier].signatures do
			local free = 0
			for slot in slots do
				if slot ~= sig.slot then
					free += 1
				end
			end
			assert(free >= 4, tier .. ": too few feature slots beside " .. sig.id)
		end
		assert(#Style[tier].props >= COUNTS.Epic + COUNTS.Legendary, tier .. ": not enough unique props")
	end
end

---------------------------------------------------------------------------- names

local used: { [string]: boolean } = {}
-- Generated names must never read like rude words (kids' game; Roblox moderation).
local BLOCKED = {
	"twur",
	"twer",
	"bish",
	"bich",
	"fuk",
	"fuc",
	"phuk",
	"shit",
	"sht",
	"cum",
	"dik",
	"dic",
	"cok",
	"coc",
	"fag",
	"nig",
	"neg",
	"ass",
	"tit",
	"hoe",
	"sex",
	"kkk",
	"jiz",
	"wank",
	"cunt",
	"kunt",
	"slut",
	"whor",
	"pis",
	"nazi",
	"rape",
	"porn",
	"pen",
	"vag",
	"boob",
	"butt",
	"crap",
	"damn",
	"hell",
	"suk",
	"suc",
	"lick",
	"blow",
	"spunk",
	"bum",
	"poop",
	"poo",
	"dum",
	"gay",
	"wtf",
	"omg",
	"jew",
	"kill",
	"die",
	-- added with the 500-species roster
	"anal",
	"arse",
	"bastard",
	"bloody",
	"bollock",
	"bugger",
	"dildo",
	"drug",
	"fart",
	"goddam",
	"hentai",
	"horny",
	"nude",
	"nsfw",
	"prick",
	"pube",
	"queer",
	"retard",
	"sperm",
	"stfu",
	"thot",
	"twat",
	"weed",
	"kys",
	"pedo",
	"isis",
	"hitler",
	"slave",
	"wiener",
	"nuts",
	"pee",
	"turd",
	"barf",
	"puke",
	"gun",
	"blood",
	"dead",
	"death",
	"murder",
	"stab",
	"shoot",
	"bomb",
	"beer",
	"wine",
	"vodka",
	"smok",
}
local function clean(name: string): boolean
	local lower = name:lower():gsub("[^a-z]", "")
	for _, bad in BLOCKED do
		if lower:find(bad, 1, true) then
			return false
		end
	end
	return true
end

local specimen = 10
-- A base name in the tier's grammar (no rarity affix).
local function baseName(tier: string): string
	local n = Style[tier].names
	if tier == "Lab" then
		local form = pick(n.forms)
		if form == "Specimen %d" then
			specimen += rng:integer(3, 17)
			return string.format(form, specimen)
		end
		return string.format(form, pick(n.words))
	elseif tier == "Void" and rng:next() < 0.45 then
		return pick(n.words)
	end
	return pick(n.first) .. pick(n.second)
end

local function makeName(tier: string, rarity: string): string
	local n = Style[tier].names
	for _ = 1, 500 do
		local name
		if rarity == "Legendary" then
			-- Tier title + a name: "Big Pombo", "Professor Volt", "The Hush", "Emperor Stellaris".
			name = n.title .. " " .. (if tier == "Lab" then pick(n.words) else baseName(tier))
		elseif rarity == "Epic" then
			name = baseName(tier) .. " " .. pick(Style.epicSuffixes)
		else
			name = baseName(tier)
		end
		if not used[name] and clean(name) then
			used[name] = true
			return name
		end
	end
	error("ran out of names for " .. tier .. " " .. rarity)
end

---------------------------------------------------------------------------- species

local species = {}
local order = {}
local buckets = {}

local function add(entry)
	species[entry.id] = entry
	buckets[entry.tier] = buckets[entry.tier] or {}
	buckets[entry.tier][entry.rarity] = buckets[entry.tier][entry.rarity] or {}
	table.insert(buckets[entry.tier][entry.rarity], entry.id)
	table.insert(order, entry.id)
end

-- The signature, then pool features in slots nobody else has taken: `count` in all.
local function pickFeatures(tier: string, count: number): { string }
	local st = Style[tier]
	local sig = pick(st.signatures)
	local out = { sig.id }
	local taken = { [sig.slot] = true }
	for _, f in shuffled(st.features) do
		if #out >= count then
			break
		end
		if not taken[f.slot] then
			taken[f.slot] = true
			table.insert(out, f.id)
		end
	end
	assert(#out == count, tier .. ": could not fit " .. count .. " features")
	return out
end

local featureText: { [string]: { [string]: any } } = {}
for _, tier in TIERS do
	featureText[tier] = {}
	for _, list in { Style[tier].signatures, Style[tier].features } do
		for _, f in list do
			featureText[tier][f.id] = f
		end
	end
end

for _, name in ORIGINALS do
	for _, n in name do
		used[n] = true
	end
end

for _, tier in TIERS do
	useTier(tier)
	local st = Style[tier]
	local props = shuffled(st.props)
	local nextProp = 1
	for _, rarity in RARITIES do
		local budget = Style.budget[rarity]
		local count = COUNTS[rarity] + (if rarity == "Common" then EXTRA_COMMONS[tier] or 0 else 0)
		for n = 1, count do
			local id = string.format("%s_%s_%02d", tier, rarity, n)
			local entry = {
				id = id,
				tier = tier,
				rarity = rarity,
				name = if n == 1 and ORIGINALS[tier] then ORIGINALS[tier][rarity] else makeName(tier, rarity),
				body = pick(st.bodies).id,
				color = pick(st.skin.palette),
				skin2 = pick(st.skin.secondary),
				accent = pick(st.skin.accent),
				features = pickFeatures(tier, budget.features),
				prop = nil :: string?,
				idleVariant = nil :: string?,
				scale = math.floor((0.9 + rng:next() * 0.25) * (budget.scale or 1) * 100 + 0.5) / 100,
			}
			if budget.prop then
				entry.prop = props[nextProp].id
				nextProp += 1
			end
			if budget.idleVariant then
				entry.idleVariant = pick(st.idleVariants)
			end
			add(entry)
		end
	end
end

---------------------------------------------------------------------------- Almanac text

local RARITY_LINE = {
	Common = "",
	Uncommon = " Spotting one is a good sign.",
	Rare = " Farmers brag about hatching one.",
	Epic = " Only a lucky few have ever seen one up close.",
	Legendary = " Legends say only one in a thousand eggs holds one.",
}
local function list(parts: { string }): string
	if #parts == 1 then
		return parts[1]
	end
	return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

-- "<habitat>. It has <body>, <features>. It <prop>. <idle>.<rarity line>" from the tier's own words,
-- so the text always matches the model.
for _, id in order do
	local e = species[id]
	useTier(e.tier)
	local st = Style[e.tier]
	local bodyDef
	for _, b in st.bodies do
		if b.id == e.body then
			bodyDef = b
		end
	end
	local traits = { bodyDef.text }
	for _, f in e.features do
		table.insert(traits, featureText[e.tier][f].text)
	end
	local text = string.format("%s. It has %s.", pick(st.habitats), list(traits))
	if e.prop then
		for _, p in st.props do
			if p.id == e.prop then
				text ..= " It " .. p.text .. "."
			end
		end
	end
	if e.idleVariant then
		text ..= string.format(" Watch for its %s.", e.idleVariant)
	end
	e.description = text .. RARITY_LINE[e.rarity]
	e.funFact = (pick(st.funFacts):gsub("%%s", e.name))
end

-- Limited eggs' species (Config/LimitedEggs.lua): hand-made, bucket = the egg's id, appended
-- after the generated 666 so re-running the generator keeps them. They keep the older trait
-- builder (body / pattern / eyes / eyeStyle / mouth / accessory).
local LIMITED = {
	{
		id = "Pumpkin_Common_01",
		tier = "Pumpkin",
		rarity = "Common",
		name = "Pumpkinhead",
		body = "blob",
		color = "#FF8A1F",
		accent = "#3A1A06",
		pattern = "stripes",
		eyes = 2,
		eyeStyle = "angry",
		mouth = "fangs",
		accessory = "stem",
		scale = 1,
		description = "Grows in the pumpkin patch behind the farm every Halloween. It has a round, ridged orange body, two glowering eyes and a carved, toothy grin.",
		funFact = "Pumpkinhead lights up from the inside when it hears a scary story.",
	},
	{
		id = "Pumpkin_Common_02",
		tier = "Pumpkin",
		rarity = "Common",
		name = "Boo Blob",
		body = "puff",
		color = "#F4F4FF",
		accent = "#C8C8E8",
		pattern = "plain",
		eyes = 2,
		eyeStyle = "sleepy",
		mouth = "wide",
		accessory = "none",
		scale = 1.04,
		description = "Drifts through the farm after dark. It has a cloud of pale puffy lumps, two sleepy eyes and a mouth stuck mid-BOO.",
		funFact = "Boo Blob is scared of its own reflection.",
	},
	{
		id = "Pumpkin_Uncommon_01",
		tier = "Pumpkin",
		rarity = "Uncommon",
		name = "Flapperwing",
		body = "blob",
		color = "#2E2440",
		accent = "#6B4A8E",
		pattern = "belly",
		eyes = 2,
		eyeStyle = "angry",
		mouth = "fangs",
		accessory = "wings",
		scale = 1.08,
		description = "Hangs upside down under the barn roof. It has a round, dark body, two glowing eyes, tiny fangs and leathery wings.",
		funFact = "Flapperwing navigates by humming spooky songs.",
	},
	{
		id = "Pumpkin_Uncommon_02",
		tier = "Pumpkin",
		rarity = "Uncommon",
		name = "Rattlebones",
		body = "tall",
		color = "#F2EEDF",
		accent = "#2A2A2A",
		pattern = "stripes",
		eyes = 2,
		eyeStyle = "normal",
		mouth = "tooth",
		accessory = "none",
		scale = 1.1,
		description = "Clatters around the graveyard fence. It has a tall, bony body with rib stripes, two hollow eyes and one big tooth.",
		funFact = "Rattlebones uses its own leg as a drumstick.",
	},
	{
		id = "Pumpkin_Rare_01",
		tier = "Pumpkin",
		rarity = "Rare",
		name = "Midnight Mog",
		body = "pear",
		color = "#1E1B26",
		accent = "#FFD24A",
		pattern = "belly",
		eyes = 2,
		eyeStyle = "stalk",
		mouth = "smile",
		accessory = "ears",
		scale = 1.12,
		description = "Prowls the farm on moonless nights. It has a sleek black body, eyes on stalks that glow gold and pointy ears.",
		funFact = "Midnight Mog has nine lives and keeps them in a jar.",
	},
	{
		id = "Pumpkin_Rare_02",
		tier = "Pumpkin",
		rarity = "Rare",
		name = "Hexwick",
		body = "blob",
		color = "#6CC24A",
		accent = "#3B1A5E",
		pattern = "spots",
		eyes = 1,
		eyeStyle = "normal",
		mouth = "tooth",
		accessory = "witchHat",
		scale = 1.15,
		description = "Stirs a cauldron nobody else can see. It has a round green body, one big eye, a crooked tooth and a tall purple witch hat.",
		funFact = "Hexwick's hat is bigger on the inside.",
	},
	{
		id = "Pumpkin_Epic_01",
		tier = "Pumpkin",
		rarity = "Epic",
		name = "Candy Corny",
		body = "tall",
		color = "#FFF4D6",
		accent = "#FF8A1F",
		pattern = "stripes",
		eyes = 3,
		eyeStyle = "normal",
		mouth = "tongue",
		accessory = "none",
		scale = 1.22,
		description = "Only shows up when the trick-or-treat bags are full. It has a tall, striped candy body, three eyes and a tongue that never stops licking.",
		funFact = "Candy Corny is 100% sugar and 0% regret.",
	},
	{
		id = "Pumpkin_Epic_02",
		tier = "Pumpkin",
		rarity = "Epic",
		name = "Webweaver",
		body = "spiky",
		color = "#2B2B2B",
		accent = "#B03030",
		pattern = "spots",
		eyes = 4,
		eyeStyle = "angry",
		mouth = "fangs",
		accessory = "none",
		scale = 1.25,
		description = "Spins webs across the whole Egg Shop overnight. It has a spiky black body with red spots, four beady eyes and fangs.",
		funFact = "Webweaver knits tiny sweaters for the other mutants.",
	},
	{
		id = "Pumpkin_Legendary_01",
		tier = "Pumpkin",
		rarity = "Legendary",
		name = "Pharaoh Wrapz",
		body = "tall",
		color = "#E8DDBF",
		accent = "#A89C7A",
		pattern = "stripes",
		eyes = 1,
		eyeStyle = "angry",
		mouth = "none",
		accessory = "crown",
		scale = 1.35,
		description = "Woke up from a very long nap under the pyramid fountain. It is wrapped head to toe in bandages, with one fierce eye and a golden crown. Legends say only one in a thousand eggs holds one.",
		funFact = "Pharaoh Wrapz has been unwrapping itself for 3,000 years.",
	},
	{
		id = "Pumpkin_Legendary_02",
		tier = "Pumpkin",
		rarity = "Legendary",
		name = "Duke Zomboil",
		body = "pear",
		color = "#7FA85A",
		accent = "#4A2E5E",
		pattern = "belly",
		eyes = 2,
		eyeStyle = "sleepy",
		mouth = "fangs",
		accessory = "mohawk",
		scale = 1.38,
		description = "Rises from the compost pile once a year. It has a lumpy green body, two droopy eyes, fangs and a ragged purple mohawk. Legends say only one in a thousand eggs holds one.",
		funFact = "Duke Zomboil only eats brain freeze.",
	},
}
for _, e in LIMITED do
	buckets[e.tier] = buckets[e.tier] or {}
	buckets[e.tier][e.rarity] = buckets[e.tier][e.rarity] or {}
	add(e)
end

-- Write the Luau data file.
local lines = {
	"--!strict",
	"-- 666 mutant species, generated by tools/gen-mutants.luau (re-running overwrites edits), plus the",
	"-- limited eggs' species (bucket = the limited egg's id; hand-made, listed in gen-mutants.luau).",
	"-- Generated species (every egg tier) are built from their tier's vocabulary in",
	"-- Config/MutantStyle.lua: body (a body id), color / skin2 / accent (hex), features (feature ids,",
	"-- the signature first; 1 / 2 / 3 / 4 / 5 by rarity), prop (Epic and Legendary: unique in the",
	"-- tier), idleVariant (Legendary), scale (base size). Limited species use the older traits:",
	"--   body (blob tall flat spiky pear worm puff), pattern, eyes, eyeStyle, mouth, accessory.",
	"-- description and funFact are shown in the Almanac.",
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
	local fields
	if e.features then
		local feats = {}
		for _, f in e.features do
			table.insert(feats, q(f))
		end
		fields = string.format(
			"tier = %s, rarity = %s, name = %s, body = %s, color = %s, skin2 = %s, accent = %s, features = { %s },%s%s scale = %s",
			q(e.tier),
			q(e.rarity),
			q(e.name),
			q(e.body),
			q(e.color),
			q(e.skin2),
			q(e.accent),
			table.concat(feats, ", "),
			if e.prop then " prop = " .. q(e.prop) .. "," else "",
			if e.idleVariant then " idleVariant = " .. q(e.idleVariant) .. "," else "",
			tostring(e.scale)
		)
	else
		fields = string.format(
			"tier = %s, rarity = %s, name = %s, body = %s, color = %s, accent = %s, pattern = %s, eyes = %d, eyeStyle = %s, mouth = %s, accessory = %s, scale = %s",
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
	end
	table.insert(
		lines,
		string.format(
			"\t%s = { %s,\n\t\tdescription = %s,\n\t\tfunFact = %s },",
			e.id,
			fields,
			q(e.description),
			q(e.funFact)
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
do -- every name unique, limited ones included
	local seen = {}
	for _, id in order do
		local name = species[id].name
		assert(not seen[name:lower()], "duplicate name " .. name)
		seen[name:lower()] = true
	end
end
local generated = #order - #LIMITED
assert(generated == 666, "expected 666 generated species, got " .. generated)
print(string.format("wrote %d species (%d generated, %d limited)", #order, generated, #LIMITED))
