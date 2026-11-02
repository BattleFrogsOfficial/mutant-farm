--!strict
-- How each egg tier's mutants look, as data: MutantModel builds every generated species from
-- this, and tools/gen-mutants.luau picks from it. One table per tier, nothing shared between
-- tiers (the generator and tests/mutants.spec.luau check it): its own bodies (silhouettes),
-- skin (material, palette, secondary tone, sheen, specks, particles), signature features (every
-- species gets exactly one), feature pool (the rest of its look), Epic / Legendary props (each
-- species in a tier gets a different one), name grammar, face, feet and idle animation.
--
-- A piece (P below) is one primitive, sized and placed in units of the mutant's scale (1 unit =
-- 1 stud for a size-1 Starter Common):
--   shape   ball | ellipsoid | block | cyl (a cylinder along X) | wedge
--   size    { x, y, z }
--   at      anchor: root (the feet) | body | head | top | face | front | back | side | neck |
--           above | beside (the ground next to it, for props) | hand (Lab arms; else beside)
--   pos     offset from the anchor, in the anchor's frame
--   color   skin | skin2 (secondary tone) | skinDark | skinLight | accent | prop (a prop's tint)
--           | dark | white | "#RRGGBB"
--   rot     { x, y, z } degrees; mirror = true also builds it at -x; ring = { n, r, axis = "y" |
--           "z", phase } repeats it around the anchor (the first copy in front, or `phase` steps
--           round, 0.5 = a gap in front); mat / tr / refl override material, transparency,
--           reflectance; neon = true for small glowing details only (the art rules); anim tags it
--           for the idle animation (orbit | drip | flicker | float); name names the part.
-- Eye styles (MutantModel): normal | baby | sleepy | angry | bulge (frog eyes on bumps) | frog
-- (gold, slit pupil) | toxic (acid yellow, angry) | hollow (dark sockets) | glow (one white
-- glowing eye) | star (gold star pupils) | starlit (dark glossy eyes with a star glint) | goggle.
-- Mouths: smile | line | frog | fangs | tooth | tongue | whisper | none.
-- Features: { id, slot, label, text, parts, face?, particles? }. One feature per slot, so a
-- species never wears two hats. `face` overrides the tier's default eyes / eyeStyle / mouth.
-- Props: { id, label, text, tint, parts } (tint is the "prop" color).
-- Art rules: no Neon on large surfaces (only specks, eyes, sparks), PointLights only from
-- mutations (MutantModel), particles slow and faint.

export type Piece = { [string]: any }
export type Feature = {
	id: string,
	slot: string,
	label: string,
	text: string,
	parts: { Piece },
	face: { [string]: any }?,
	particles: { [string]: any }?,
}

local function P(
	shape: string,
	size: { number },
	at: string,
	pos: { number },
	color: string,
	extra: { [string]: any }?
): Piece
	local p: Piece = { shape = shape, size = size, at = at, pos = pos, color = color }
	for k, v in extra or {} do
		p[k] = v
	end
	return p
end

-- Three props from one kind: the same parts, a different tint (and label) each.
local function props(
	base: { id: string, label: string, text: string, parts: { Piece } },
	tints: { { string } }
): { any }
	local out = {}
	for _, t in tints do
		table.insert(out, {
			id = base.id .. t[1],
			label = t[2] .. " " .. base.label,
			text = string.format(base.text, t[2]:lower()),
			tint = t[3],
			parts = base.parts,
		})
	end
	return out
end

local function concat(...: { any }): { any }
	local out = {}
	for _, list in { ... } do
		for _, v in list do
			table.insert(out, v)
		end
	end
	return out
end

local WARM = { { "Red", "Cherry", "#FF5A6E" }, { "Blue", "Sky", "#5AB0FF" }, { "Yellow", "Lemon", "#FFD84A" } }

local Style = {}

-------------------------------------------------------------------------------- Starter

Style.Starter = {
	label = "Starter",
	skin = {
		material = "SmoothPlastic",
		palette = { "#B8F07A", "#FFE37A", "#7FD8FF", "#FFB0C8", "#C9F2A0", "#FFC98A", "#A8E6CF", "#D7B8FF" },
		secondary = { "#FFFFFF", "#FFF4D6", "#FFE8F0" },
		accent = { "#FF8FB8", "#7CC8FF", "#FFD24A", "#8FE07A" },
	},
	face = { eyes = 2, eyeStyle = "normal", mouth = "smile" },
	feet = "nub",
	bodies = {
		{
			id = "starterBlob",
			label = "Round",
			text = "a round, squishy body",
			parts = { P("ellipsoid", { 2.4, 2.1, 2.2 }, "root", { 0, 1.1, 0 }, "skin") },
			head = { pos = { 0, 1.25, 0 }, r = { 1.2, 1.05, 1.1 } },
		},
		{
			id = "starterPuff",
			label = "Puffy",
			text = "a soft cloud of little puffs",
			parts = {
				P("ellipsoid", { 2.0, 1.9, 1.9 }, "root", { 0, 1.1, 0 }, "skin"),
				P(
					"ball",
					{ 1.05, 1.05, 1.05 },
					"root",
					{ 0, 0.95, 0 },
					"skin",
					{ ring = { n = 5, r = 0.9, phase = 0.5 } }
				),
			},
			head = { pos = { 0, 1.3, 0 }, r = { 1.0, 0.95, 0.95 } },
		},
		{
			id = "starterPear",
			label = "Pear",
			text = "a pear-shaped body with a little round head",
			parts = {
				P("ellipsoid", { 2.4, 1.8, 2.2 }, "root", { 0, 0.95, 0 }, "skin"),
				P("ellipsoid", { 1.6, 1.4, 1.5 }, "root", { 0, 2.2, 0 }, "skin"),
			},
			head = { pos = { 0, 2.2, 0 }, r = { 0.8, 0.7, 0.75 } },
		},
	},
	signatures = {
		{
			id = "sprout",
			slot = "top",
			label = "Sprout",
			text = "a sprout growing from its head",
			parts = {
				P("cyl", { 0.7, 0.14, 0.14 }, "top", { 0, 0.3, 0 }, "#5BA84A", { rot = { 0, 0, 90 } }),
				P(
					"ellipsoid",
					{ 0.7, 0.12, 0.38 },
					"top",
					{ 0.28, 0.66, 0 },
					"#7CD65A",
					{ rot = { 0, 0, 25 }, mirror = true }
				),
			},
		},
		{
			id = "singleAntenna",
			slot = "top",
			label = "Antenna",
			text = "one wobbly antenna",
			parts = {
				P("cyl", { 1.0, 0.12, 0.12 }, "top", { 0, 0.45, 0 }, "dark", { rot = { 0, 0, 80 } }),
				P("ball", { 0.42, 0.42, 0.42 }, "top", { 0.08, 0.98, 0 }, "accent"),
			},
		},
		{
			id = "babyEyes",
			slot = "eyes",
			label = "Baby eyes",
			text = "huge, sparkly baby eyes",
			parts = {},
			face = { eyeStyle = "baby" },
		},
		{
			id = "leafHat",
			slot = "top",
			label = "Leaf hat",
			text = "a leaf worn like a hat",
			parts = {
				P("ellipsoid", { 1.7, 0.14, 1.5 }, "top", { 0, 0.05, 0 }, "#4FB54A", { rot = { 0, 0, 8 } }),
				P("cyl", { 0.35, 0.1, 0.1 }, "top", { 0, 0.2, 0 }, "#3B7A2E", { rot = { 0, 0, 90 } }),
			},
		},
		{
			id = "rosyCheeks",
			slot = "cheeks",
			label = "Rosy cheeks",
			text = "two rosy cheeks",
			parts = { P("ellipsoid", { 0.42, 0.26, 0.1 }, "face", { 0.62, -0.32, 0.02 }, "#FF8FA8", { mirror = true }) },
		},
	},
	features = {
		{
			id = "bellyPatch",
			slot = "pattern",
			label = "Belly patch",
			text = "a soft pale belly",
			parts = { P("ellipsoid", { 1.5, 1.3, 0.5 }, "front", { 0, -0.15, 0.1 }, "skin2") },
		},
		{
			id = "polkaDots",
			slot = "pattern",
			label = "Polka dots",
			text = "polka dots all over",
			parts = {
				P("ellipsoid", { 0.42, 0.42, 0.12 }, "body", { 0, 0.15, 0 }, "accent", { ring = { n = 6, r = 1.1 } }),
			},
		},
		{
			id = "bowTie",
			slot = "neck",
			label = "Bow tie",
			text = "a tiny bow tie",
			parts = {
				P(
					"wedge",
					{ 0.2, 0.32, 0.36 },
					"neck",
					{ 0.2, 0, -0.95 },
					"accent",
					{ rot = { 0, 90, 0 }, mirror = true }
				),
				P("ball", { 0.18, 0.18, 0.18 }, "neck", { 0, 0, -1.02 }, "accent"),
			},
		},
		{
			id = "tongueOut",
			slot = "mouth",
			label = "Tongue out",
			text = "a tongue that pokes out",
			parts = {},
			face = { mouth = "tongue" },
		},
		{
			id = "earFlower",
			slot = "ear",
			label = "Flower",
			text = "a flower tucked behind one ear",
			parts = {
				P("ball", { 0.24, 0.24, 0.24 }, "head", { 0.95, 0.55, 0 }, "#FFD24A"),
				P(
					"ellipsoid",
					{ 0.3, 0.3, 0.12 },
					"head",
					{ 0.95, 0.55, 0 },
					"#FFFFFF",
					{ ring = { n = 5, r = 0.2, axis = "z" } }
				),
			},
		},
		{
			id = "hairTuft",
			slot = "top",
			label = "Hair tuft",
			text = "a curly tuft of hair",
			parts = {
				P("ellipsoid", { 0.3, 0.6, 0.3 }, "top", { 0, 0.22, 0 }, "skinDark", { ring = { n = 3, r = 0.14 } }),
			},
		},
		{
			id = "puffTail",
			slot = "back",
			label = "Puff tail",
			text = "a tiny round tail",
			parts = { P("ball", { 0.6, 0.6, 0.6 }, "back", { 0, -0.4, 0.15 }, "skin2") },
		},
		{
			id = "sleepyLids",
			slot = "eyes",
			label = "Sleepy eyes",
			text = "sleepy, half-shut eyes",
			parts = {},
			face = { eyeStyle = "sleepy" },
		},
		{
			id = "bib",
			slot = "chest",
			label = "Bib",
			text = "a little bib",
			parts = { P("ellipsoid", { 1.1, 0.8, 0.2 }, "front", { 0, 0.25, 0.05 }, "white") },
		},
	},
	props = concat(
		props({
			id = "balloon",
			label = "balloon",
			text = "holds on to a %s balloon",
			parts = {
				P("cyl", { 2.4, 0.04, 0.04 }, "beside", { 0, 1.2, 0 }, "white", { rot = { 0, 0, 90 } }),
				P("ellipsoid", { 0.9, 1.1, 0.9 }, "beside", { 0, 2.8, 0 }, "prop", { anim = "float" }),
			},
		}, WARM),
		props({
			id = "toyBlocks",
			label = "toy blocks",
			text = "stacks %s toy blocks",
			parts = {
				P("block", { 0.6, 0.6, 0.6 }, "beside", { 0, 0.3, 0 }, "prop"),
				P("block", { 0.5, 0.5, 0.5 }, "beside", { 0.05, 0.85, 0 }, "white", { rot = { 0, 20, 0 } }),
				P("block", { 0.4, 0.4, 0.4 }, "beside", { -0.05, 1.3, 0 }, "prop", { rot = { 0, -15, 0 } }),
			},
		}, WARM),
		props({
			id = "rattle",
			label = "rattle",
			text = "never lets go of its %s rattle",
			parts = {
				P("cyl", { 0.9, 0.12, 0.12 }, "beside", { 0, 0.45, 0 }, "white", { rot = { 0, 0, 90 } }),
				P("ball", { 0.55, 0.55, 0.55 }, "beside", { 0, 1.0, 0 }, "prop"),
			},
		}, WARM),
		props({
			id = "beachBall",
			label = "beach ball",
			text = "plays with a %s beach ball",
			parts = {
				P("ball", { 0.9, 0.9, 0.9 }, "beside", { 0, 0.45, 0 }, "white"),
				P("ellipsoid", { 0.92, 0.92, 0.3 }, "beside", { 0, 0.45, 0 }, "prop"),
			},
		}, { { "Pink", "Pink", "#FF7AC0" }, { "Green", "Mint", "#6FE0A0" }, { "Orange", "Sunny", "#FF9A3C" } }),
		props({
			id = "pinwheel",
			label = "pinwheel",
			text = "spins a %s pinwheel",
			parts = {
				P("cyl", { 1.4, 0.08, 0.08 }, "beside", { 0, 0.7, 0 }, "white", { rot = { 0, 0, 90 } }),
				P(
					"wedge",
					{ 0.08, 0.4, 0.4 },
					"beside",
					{ 0, 1.4, 0 },
					"prop",
					{ ring = { n = 4, r = 0.22, axis = "z" } }
				),
			},
		}, { { "Violet", "Violet", "#B07AFF" }, { "Teal", "Teal", "#3FD0C8" }, { "Coral", "Coral", "#FF7A5A" } }),
		props({
			id = "teddy",
			label = "teddy",
			text = "hugs a %s teddy",
			parts = {
				P("ellipsoid", { 0.6, 0.7, 0.5 }, "beside", { 0, 0.35, 0 }, "prop"),
				P("ball", { 0.5, 0.5, 0.5 }, "beside", { 0, 0.9, 0 }, "prop"),
				P("ball", { 0.2, 0.2, 0.2 }, "beside", { 0.2, 1.12, 0 }, "prop", { mirror = true }),
			},
		}, { { "Brown", "Cocoa", "#B07A4A" }, { "Cream", "Vanilla", "#F2E2C2" }, { "Rose", "Rosy", "#F2A2B8" } }),
		props({
			id = "drum",
			label = "toy drum",
			text = "bangs a %s toy drum",
			parts = {
				P("cyl", { 0.6, 0.8, 0.8 }, "beside", { 0, 0.3, 0 }, "prop", { rot = { 0, 0, 90 } }),
				P("cyl", { 0.06, 0.82, 0.82 }, "beside", { 0, 0.62, 0 }, "white", { rot = { 0, 0, 90 } }),
			},
		}, { { "Scarlet", "Scarlet", "#E8404A" }, { "Navy", "Navy", "#3A4AA0" }, { "Gold", "Gold", "#E8B83A" } })
	),
	-- Two soft syllables ("Pombo"). Epic: "<name> Prime" / "<name> Rex". Legendary: "Big <name>".
	names = {
		first = {
			"Bo",
			"Mi",
			"Pu",
			"Lu",
			"Nu",
			"Wim",
			"Pip",
			"Tu",
			"Fi",
			"Bi",
			"Dee",
			"Nim",
			"Pom",
			"Yo",
			"Ju",
			"Ki",
			"Wu",
			"Zu",
			"Ree",
			"Bu",
			"Ti",
			"Lo",
		},
		second = { "bo", "lu", "mi", "pip", "nu", "by", "boo", "li", "sy", "pa", "ki", "doo", "ni", "ma", "ble", "pi" },
		title = "Big",
	},
	idle = "bob",
	idleVariants = { "Happy Hop", "Wiggle Dance", "Sleepy Sway" },
	habitats = {
		"Hatches on brand-new farms everywhere",
		"The first mutant most farmers ever meet",
		"Found wobbling around beginner farms",
		"Naps in the soft soil of fresh soil patches",
	},
	funFacts = {
		"%s falls asleep the moment anyone hums a lullaby.",
		"%s counts its toes every morning. It gets a different number each time.",
		"%s thinks every egg is its little sibling.",
		"%s can bounce higher than the farm fence (it just never tries).",
		"%s giggles whenever a watering can comes near.",
		"A group of %ss is called a 'squish'.",
		"%s's favorite game is peekaboo. It always hides behind its own hands.",
		"%s once got lost in a flowerpot for a whole afternoon.",
	},
}

-------------------------------------------------------------------------------- Swamp

local MOSS = { { "Moss", "Mossy", "#6E8F3A" }, { "Mud", "Muddy", "#8B6B3A" }, { "Lily", "Lily", "#E8A0C8" } }

Style.Swamp = {
	label = "Swamp",
	skin = {
		material = "SmoothPlastic",
		palette = { "#6E8F3A", "#4E7F4A", "#7C9A4E", "#5A7A3A", "#3F6E4E", "#8AA65A", "#4C7A60", "#6B8B5E" },
		secondary = { "#8B7B4A", "#A89A6A", "#6B5B3A" },
		accent = { "#C8E07A", "#E8A0C8", "#7AC8B0", "#D8C07A" },
		-- A wet sheen: a slightly bigger Glass shell over the body parts.
		overlay = { material = "Glass", transparency = 0.6, reflectance = 0.35, grow = 1.05 },
	},
	face = { eyes = 2, eyeStyle = "frog", mouth = "smile" },
	feet = "webbed",
	bodies = {
		{
			id = "swampFlat",
			label = "Flat",
			text = "a low, flat body like a lily pad",
			parts = { P("ellipsoid", { 3.2, 1.5, 2.7 }, "root", { 0, 0.95, 0 }, "skin") },
			head = { pos = { 0, 1.1, 0 }, r = { 1.6, 0.75, 1.35 } },
		},
		{
			id = "swampPear",
			label = "Toad",
			text = "a fat toad body with a heavy head",
			parts = {
				P("ellipsoid", { 2.8, 2.0, 2.5 }, "root", { 0, 1.1, 0 }, "skin"),
				P("ellipsoid", { 1.8, 1.4, 1.7 }, "root", { 0, 2.4, 0 }, "skin"),
			},
			head = { pos = { 0, 2.4, 0 }, r = { 0.9, 0.7, 0.85 } },
		},
		{
			id = "swampLumpy",
			label = "Lumpy",
			text = "a lumpy, mud-caked body",
			parts = {
				P("ellipsoid", { 2.7, 2.0, 2.4 }, "root", { 0, 1.15, 0 }, "skin"),
				P("ball", { 1.0, 1.0, 1.0 }, "root", { -1.0, 1.6, 0.4 }, "skin"),
				P("ball", { 0.9, 0.9, 0.9 }, "root", { 0.95, 1.85, 0.5 }, "skin"),
				P("ball", { 0.8, 0.8, 0.8 }, "root", { 0.3, 0.6, 1.0 }, "skin2"),
			},
			head = { pos = { 0, 1.4, 0 }, r = { 1.3, 1.0, 1.2 } },
		},
	},
	signatures = {
		{
			id = "lilyPadHat",
			slot = "top",
			label = "Lily pad hat",
			text = "a lily pad hat with a pink flower",
			parts = {
				P("cyl", { 0.1, 1.9, 1.9 }, "top", { 0, 0.06, 0 }, "#3F9A4A", { rot = { 0, 0, 90 } }),
				P("ball", { 0.42, 0.42, 0.42 }, "top", { 0.35, 0.25, 0 }, "#F2A0C8"),
			},
		},
		{
			id = "reeds",
			slot = "back",
			label = "Reeds",
			text = "reeds sprouting from its back",
			parts = {
				P("cyl", { 2.0, 0.12, 0.12 }, "back", { -0.3, 0.9, 0.1 }, "#6E8A3A", { rot = { 0, 0, 84 } }),
				P("cyl", { 2.4, 0.12, 0.12 }, "back", { 0.1, 1.1, 0.15 }, "#6E8A3A", { rot = { 0, 0, 92 } }),
				P("cyl", { 1.8, 0.12, 0.12 }, "back", { 0.45, 0.8, 0.1 }, "#6E8A3A", { rot = { 0, 0, 100 } }),
				P("ellipsoid", { 0.2, 0.55, 0.2 }, "back", { 0.1, 2.3, 0.15 }, "#7A4A2A"),
			},
		},
		{
			id = "frogMouth",
			slot = "mouth",
			label = "Frog mouth",
			text = "a huge frog mouth",
			parts = {},
			face = { mouth = "frog" },
		},
		{
			id = "algaeDrips",
			slot = "chin",
			label = "Dripping algae",
			text = "algae dripping from its chin",
			parts = {
				P("ellipsoid", { 0.22, 0.6, 0.22 }, "face", { -0.35, -0.95, 0.05 }, "#5BB04A", { anim = "drip" }),
				P("ellipsoid", { 0.2, 0.45, 0.2 }, "face", { 0.2, -0.9, 0.05 }, "#5BB04A", { anim = "drip" }),
				P("ellipsoid", { 0.9, 0.18, 0.4 }, "face", { 0, -0.7, 0.08 }, "#4A9A3A"),
			},
		},
		{
			id = "bubbles",
			slot = "aura",
			label = "Bubbles",
			text = "a trail of slow swamp bubbles",
			parts = {
				P(
					"ball",
					{ 0.35, 0.35, 0.35 },
					"head",
					{ 0.9, 0.9, 0 },
					"#D8F0F8",
					{ mat = "Glass", tr = 0.4, anim = "float" }
				),
				P(
					"ball",
					{ 0.22, 0.22, 0.22 },
					"head",
					{ 1.15, 1.4, 0.1 },
					"#D8F0F8",
					{ mat = "Glass", tr = 0.4, anim = "float" }
				),
			},
			particles = { color = "#D8F0F8", rate = 1.5, size = 0.25, lifetime = 3, speed = 0.6, transparency = 0.35 },
		},
	},
	features = {
		{
			id = "mudSplotches",
			slot = "pattern",
			label = "Mud splotches",
			text = "splotches of dried mud",
			parts = {
				P("ellipsoid", { 0.7, 0.5, 0.14 }, "body", { 0, -0.1, 0 }, "skin2", { ring = { n = 5, r = 1.25 } }),
			},
		},
		{
			id = "warts",
			slot = "pattern",
			label = "Warts",
			text = "a back full of warts",
			parts = {
				P("ball", { 0.28, 0.28, 0.28 }, "back", { 0, 0.3, 0 }, "skinDark", { ring = { n = 6, r = 0.6 } }),
			},
		},
		{
			id = "cattail",
			slot = "side",
			label = "Cattail",
			text = "a cattail it chews on",
			parts = {
				P("cyl", { 2.0, 0.08, 0.08 }, "side", { 0.3, 0.4, -0.2 }, "#6E8A3A", { rot = { 0, 0, 75 } }),
				P("ellipsoid", { 0.22, 0.6, 0.22 }, "side", { 0.55, 1.3, -0.2 }, "#7A4A2A"),
			},
		},
		{
			id = "snailShell",
			slot = "back",
			label = "Snail shell",
			text = "a snail shell it lives in half the time",
			parts = {
				P("ball", { 1.2, 1.2, 1.2 }, "back", { 0, 0.3, 0.3 }, "#C8A06A"),
				P("cyl", { 0.12, 1.0, 1.0 }, "back", { 0, 0.3, 0.32 }, "#8A6A3A", { rot = { 0, 90, 0 } }),
			},
		},
		{
			id = "bulgeEyes",
			slot = "eyes",
			label = "Bulging eyes",
			text = "bulging eyes on top of its head",
			parts = {},
			face = { eyeStyle = "bulge" },
		},
		{
			id = "barbels",
			slot = "face",
			label = "Whiskers",
			text = "long catfish whiskers",
			parts = {
				P(
					"cyl",
					{ 1.0, 0.07, 0.07 },
					"face",
					{ 0.65, -0.45, 0 },
					"skinDark",
					{ rot = { 0, 20, -25 }, mirror = true }
				),
			},
		},
		{
			id = "mossTuft",
			slot = "crown",
			label = "Moss tuft",
			text = "a tuft of moss on its head",
			parts = { P("ball", { 0.5, 0.4, 0.5 }, "top", { 0, 0.1, 0 }, "#3F7A2E", { ring = { n = 4, r = 0.3 } }) },
		},
		{
			id = "dragonfly",
			slot = "aura",
			label = "Dragonfly",
			text = "a pet dragonfly",
			parts = {
				P("cyl", { 0.5, 0.08, 0.08 }, "above", { 0.6, 0.2, 0 }, "#3FB0C8", { anim = "orbit" }),
				P(
					"ellipsoid",
					{ 0.5, 0.05, 0.2 },
					"above",
					{ 0.6, 0.25, 0 },
					"#D8F0F8",
					{ tr = 0.4, anim = "orbit", rot = { 0, 90, 0 } }
				),
			},
		},
	},
	props = concat(
		props({
			id = "toadstool",
			label = "toadstool",
			text = "sits by a %s toadstool",
			parts = {
				P("cyl", { 0.8, 0.3, 0.3 }, "beside", { 0, 0.4, 0 }, "#F2E6C9", { rot = { 0, 0, 90 } }),
				P("ellipsoid", { 1.1, 0.5, 1.1 }, "beside", { 0, 0.85, 0 }, "prop"),
			},
		}, { { "Red", "Red", "#D84A3A" }, { "Brown", "Brown", "#8A5A3A" }, { "Violet", "Violet", "#8A5AC0" } }),
		props({
			id = "fireflyJar",
			label = "firefly jar",
			text = "keeps a jar of %s fireflies",
			parts = {
				P(
					"cyl",
					{ 0.8, 0.6, 0.6 },
					"beside",
					{ 0, 0.4, 0 },
					"#D8F0F8",
					{ rot = { 0, 0, 90 }, mat = "Glass", tr = 0.5 }
				),
				P(
					"ball",
					{ 0.1, 0.1, 0.1 },
					"beside",
					{ 0, 0.4, 0 },
					"prop",
					{ neon = true, ring = { n = 4, r = 0.15 } }
				),
			},
		}, { { "Gold", "Gold", "#FFE07A" }, { "Green", "Green", "#9AFF7A" }, { "Blue", "Blue", "#7AE0FF" } }),
		props({
			id = "driftLog",
			label = "log",
			text = "naps on a %s log",
			parts = {
				P("cyl", { 1.6, 0.6, 0.6 }, "beside", { 0, 0.3, 0 }, "prop"),
				P("ball", { 0.3, 0.3, 0.3 }, "beside", { 0.4, 0.6, 0 }, "#4A8A3A"),
			},
		}, { { "Oak", "Oak", "#7A5A3A" }, { "Birch", "Birch", "#D8D0B8" }, { "Mossy", "Mossy", "#5A6A3A" } }),
		props({
			id = "rubberBoot",
			label = "boot",
			text = "found a %s rubber boot",
			parts = {
				P("block", { 0.45, 0.8, 0.45 }, "beside", { 0, 0.4, 0 }, "prop"),
				P("block", { 0.45, 0.3, 0.75 }, "beside", { 0, 0.15, -0.15 }, "prop"),
			},
		}, { { "Yellow", "Yellow", "#FFD24A" }, { "Red", "Red", "#E04A4A" }, { "Green", "Green", "#4AA05A" } }),
		props({
			id = "waterLily",
			label = "water lily",
			text = "guards a %s water lily",
			parts = {
				P("cyl", { 0.08, 1.2, 1.2 }, "beside", { 0, 0.05, 0 }, "#3F9A4A", { rot = { 0, 0, 90 } }),
				P(
					"ellipsoid",
					{ 0.25, 0.35, 0.15 },
					"beside",
					{ 0, 0.22, 0 },
					"prop",
					{ ring = { n = 6, r = 0.18 }, rot = { 25, 0, 0 } }
				),
			},
		}, { { "Pink", "Pink", "#F2A0C8" }, { "White", "White", "#F8F8F0" }, { "Blue", "Blue", "#A0C8F8" } }),
		props({
			id = "reedBasket",
			label = "reed basket",
			text = "carries a %s reed basket",
			parts = {
				P("cyl", { 0.6, 0.9, 0.9 }, "beside", { 0, 0.3, 0 }, "prop", { rot = { 0, 0, 90 } }),
				P("cyl", { 0.08, 0.95, 0.95 }, "beside", { 0, 0.62, 0 }, "#6A4A2A", { rot = { 0, 0, 90 } }),
			},
		}, MOSS),
		props({
			id = "froglet",
			label = "froglet",
			text = "is followed by a %s froglet",
			parts = {
				P("ellipsoid", { 0.6, 0.35, 0.5 }, "beside", { 0, 0.18, 0 }, "prop"),
				P("ball", { 0.16, 0.16, 0.16 }, "beside", { 0.12, 0.38, -0.15 }, "white", { mirror = true }),
			},
		}, { { "Spring", "Spring", "#7ADC5A" }, { "Dusk", "Dusky", "#5A7AA0" }, { "Ember", "Ember", "#E07A3A" } })
	),
	-- Muddy compounds ("Mossgrub"). Legendary: "Elder <name>".
	names = {
		first = {
			"Muck",
			"Bog",
			"Mire",
			"Silt",
			"Moss",
			"Reed",
			"Peat",
			"Fen",
			"Slosh",
			"Marsh",
			"Mud",
			"Puddle",
			"Loam",
			"Squelch",
			"Murk",
			"Sedge",
		},
		second = {
			"grub",
			"snout",
			"toad",
			"belly",
			"wort",
			"lump",
			"gill",
			"croak",
			"foot",
			"tail",
			"nose",
			"skipper",
			"waddle",
			"slop",
		},
		title = "Elder",
	},
	idle = "sag",
	idleVariants = { "Deep Breath", "Mud Wallow", "Big Croak" },
	habitats = {
		"Lurks in Swamp Eggs and smells faintly of pond",
		"Loves mud baths and soggy socks",
		"Grown in the murkiest corner of the bog",
		"Sleeps half-sunk in warm mud",
	},
	funFacts = {
		"%s can hold its breath under the mud for an entire afternoon.",
		"%s croaks a different song for every kind of rain.",
		"%s's favorite snack is a mosquito that gets too close.",
		"Every puddle %s sits in turns a little greener.",
		"%s keeps a collection of shiny pebbles at the bottom of the pond.",
		"%s squelches when it walks. It does this on purpose.",
		"A group of %ss is called a 'slosh'.",
		"%s has never once been dry, and never wants to be.",
	},
}

-------------------------------------------------------------------------------- Lab

Style.Lab = {
	label = "Lab",
	skin = {
		material = "SmoothPlastic",
		palette = { "#F2F5FA", "#E8EEF5", "#FFD6E8", "#D6F4FF", "#E8FFF6", "#F5E6FF", "#FFFFFF", "#DDE6F0" },
		secondary = { "#8FD3FF", "#FF8FB8", "#7CFFC8" },
		accent = { "#4AB8FF", "#FF5A9A", "#3AD8A0", "#8A9AB0" },
	},
	face = { eyes = 2, eyeStyle = "normal", mouth = "line" },
	feet = "nub",
	-- The only tier with arms (a capsule each side; `hand` anchors held things at the right one).
	arms = true,
	bodies = {
		{
			id = "labTall",
			label = "Tall",
			text = "a tall, bean-shaped body and two little arms",
			parts = { P("ellipsoid", { 1.9, 3.4, 1.9 }, "root", { 0, 1.95, 0 }, "skin") },
			head = { pos = { 0, 2.6, 0 }, r = { 0.95, 1.15, 0.95 } },
			arms = { y = 1.8, x = 0.95 },
		},
		{
			id = "labCapsule",
			label = "Capsule",
			text = "a smooth capsule body and two little arms",
			parts = {
				P("cyl", { 1.8, 1.8, 1.8 }, "root", { 0, 1.7, 0 }, "skin", { rot = { 0, 0, 90 } }),
				P("ball", { 1.8, 1.8, 1.8 }, "root", { 0, 2.6, 0 }, "skin"),
				P("ball", { 1.8, 1.8, 1.8 }, "root", { 0, 0.85, 0 }, "skin"),
			},
			head = { pos = { 0, 2.6, 0 }, r = { 0.9, 0.9, 0.9 } },
			arms = { y = 1.7, x = 0.9 },
		},
	},
	signatures = {
		{
			id = "glassDome",
			slot = "top",
			label = "Glass dome",
			text = "a glass dome over a pink brain",
			parts = {
				P("ellipsoid", { 1.0, 0.65, 0.9 }, "top", { 0, 0.15, 0 }, "#FF9AC0"),
				P("ball", { 1.4, 1.4, 1.4 }, "top", { 0, 0.25, 0 }, "#D8F4FF", { mat = "Glass", tr = 0.55 }),
			},
		},
		{
			id = "goggles",
			slot = "eyes",
			label = "Goggles",
			text = "lab goggles it never takes off",
			parts = { P("ellipsoid", { 2.0, 0.28, 2.0 }, "head", { 0, 0.25, 0 }, "dark", { name = "Strap" }) },
			face = { eyeStyle = "goggle" },
		},
		{
			id = "neckBolts",
			slot = "neck",
			label = "Bolts",
			text = "a bolt on each side of its neck",
			parts = {
				P("cyl", { 0.5, 0.22, 0.22 }, "neck", { 0.9, 0.1, 0 }, "#8A9AB0"),
				P("cyl", { 0.12, 0.34, 0.34 }, "neck", { 1.15, 0.1, 0 }, "#6A7A90", { mirror = true }),
				P("cyl", { 0.5, 0.22, 0.22 }, "neck", { -0.9, 0.1, 0 }, "#8A9AB0"),
			},
		},
		{
			id = "clipboard",
			slot = "hand",
			label = "Clipboard",
			text = "a clipboard full of notes",
			parts = {
				P("block", { 0.7, 0.9, 0.08 }, "hand", { 0, 0.2, -0.15 }, "#B0804A", { rot = { -15, 0, 0 } }),
				P("block", { 0.6, 0.7, 0.04 }, "hand", { 0, 0.18, -0.21 }, "white", { rot = { -15, 0, 0 } }),
			},
		},
		{
			id = "bodyVials",
			slot = "chest",
			label = "Vials",
			text = "glowing vials built into its body",
			parts = {
				P(
					"cyl",
					{ 0.6, 0.3, 0.3 },
					"front",
					{ -0.35, 0.1, 0.05 },
					"#D8F4FF",
					{ rot = { 0, 0, 90 }, mat = "Glass", tr = 0.3 }
				),
				P(
					"cyl",
					{ 0.6, 0.3, 0.3 },
					"front",
					{ 0.35, 0.1, 0.05 },
					"#D8F4FF",
					{ rot = { 0, 0, 90 }, mat = "Glass", tr = 0.3 }
				),
				P("cyl", { 0.36, 0.2, 0.2 }, "front", { -0.35, 0, 0.0 }, "skin2", { rot = { 0, 0, 90 } }),
				P("cyl", { 0.36, 0.2, 0.2 }, "front", { 0.35, 0, 0.0 }, "accent", { rot = { 0, 0, 90 } }),
			},
		},
	},
	features = {
		{
			id = "labCollar",
			slot = "front",
			label = "Lab coat",
			text = "the collar of a tiny lab coat",
			parts = {
				P(
					"wedge",
					{ 0.15, 0.6, 0.5 },
					"neck",
					{ 0.3, -0.15, -0.75 },
					"white",
					{ rot = { 0, 90, 20 }, mirror = true }
				),
			},
		},
		{
			id = "earPencil",
			slot = "ear",
			label = "Pencil",
			text = "a pencil behind its ear",
			parts = { P("cyl", { 0.9, 0.1, 0.1 }, "head", { 0.9, 0.4, 0 }, "#FFD24A", { rot = { 0, 70, 20 } }) },
		},
		{
			id = "barcode",
			slot = "pattern",
			label = "Barcode",
			text = "a barcode stamped on its side",
			parts = {
				P(
					"block",
					{ 0.06, 0.5, 0.04 },
					"side",
					{ 0, 0, 0 },
					"dark",
					{ ring = { n = 7, r = 0.08, axis = "y" } }
				),
			},
		},
		{
			id = "seams",
			slot = "pattern",
			label = "Stitches",
			text = "a line of neat stitches",
			parts = {
				P(
					"block",
					{ 0.4, 0.06, 0.06 },
					"front",
					{ 0, -0.2, 0.02 },
					"dark",
					{ ring = { n = 5, r = 0.05, axis = "z" } }
				),
			},
		},
		{
			id = "radarDish",
			slot = "crown",
			label = "Radar dish",
			text = "a tiny radar dish on its head",
			parts = {
				P("cyl", { 0.5, 0.1, 0.1 }, "top", { 0, 0.2, 0 }, "#8A9AB0", { rot = { 0, 0, 90 } }),
				P("ellipsoid", { 0.7, 0.2, 0.7 }, "top", { 0, 0.5, 0 }, "white", { rot = { 25, 0, 0 } }),
			},
		},
		{
			id = "monocle",
			slot = "eyes",
			label = "Monocle",
			text = "a monocle on a gold chain",
			parts = { P("cyl", { 0.08, 0.6, 0.6 }, "face", { 0.42, 0.05, -0.12 }, "#FFD24A", { rot = { 0, 90, 0 } }) },
		},
		{
			id = "wheel",
			slot = "base",
			label = "Wheel",
			text = "a squeaky wheel instead of feet",
			parts = { P("cyl", { 0.4, 0.9, 0.9 }, "root", { 0, 0.45, 0 }, "dark", { name = "Wheel" }) },
			face = { feet = "none" },
		},
		{
			id = "statusLight",
			slot = "back",
			label = "Status light",
			text = "a blinking status light",
			parts = {
				P("ball", { 0.25, 0.25, 0.25 }, "back", { 0, 0.6, 0.05 }, "#FF5A6E", { neon = true, anim = "flicker" }),
			},
		},
	},
	props = concat(
		props({
			id = "beaker",
			label = "beaker",
			text = "carries a beaker of %s liquid",
			parts = {
				P(
					"cyl",
					{ 0.7, 0.55, 0.55 },
					"hand",
					{ 0, 0.15, -0.1 },
					"#D8F4FF",
					{ rot = { 0, 0, 90 }, mat = "Glass", tr = 0.5 }
				),
				P("cyl", { 0.4, 0.45, 0.45 }, "hand", { 0, 0.02, -0.1 }, "prop", { rot = { 0, 0, 90 } }),
			},
		}, { { "Pink", "Pink", "#FF7AB8" }, { "Cyan", "Cyan", "#5AE0FF" }, { "Lime", "Lime", "#9AFF5A" } }),
		props({
			id = "tubeRack",
			label = "test tube rack",
			text = "sorts a rack of %s test tubes",
			parts = {
				P("block", { 1.0, 0.15, 0.4 }, "beside", { 0, 0.5, 0 }, "#B0804A"),
				P("cyl", { 0.8, 0.14, 0.14 }, "beside", { -0.3, 0.6, 0 }, "prop", { rot = { 0, 0, 90 } }),
				P(
					"cyl",
					{ 0.8, 0.14, 0.14 },
					"beside",
					{ 0, 0.6, 0 },
					"#D8F4FF",
					{ rot = { 0, 0, 90 }, mat = "Glass", tr = 0.3 }
				),
				P("cyl", { 0.8, 0.14, 0.14 }, "beside", { 0.3, 0.6, 0 }, "prop", { rot = { 0, 0, 90 } }),
			},
		}, { { "Violet", "Violet", "#B07AFF" }, { "Orange", "Orange", "#FF9A3C" }, { "Mint", "Mint", "#6FE0B0" } }),
		props({
			id = "microscope",
			label = "microscope",
			text = "peers into a %s microscope",
			parts = {
				P("block", { 0.7, 0.12, 0.5 }, "beside", { 0, 0.06, 0 }, "dark"),
				P("block", { 0.15, 0.9, 0.15 }, "beside", { 0, 0.5, 0.15 }, "prop"),
				P("cyl", { 0.6, 0.18, 0.18 }, "beside", { 0, 0.9, 0 }, "prop", { rot = { 0, 0, 70 } }),
			},
		}, { { "White", "Snow", "#F2F5FA" }, { "Black", "Ink", "#2A2F4F" }, { "Red", "Red", "#E04A4A" } }),
		props({
			id = "teslaCoil",
			label = "Tesla coil",
			text = "keeps a %s Tesla coil buzzing",
			parts = {
				P("cyl", { 1.0, 0.2, 0.2 }, "beside", { 0, 0.5, 0 }, "#8A9AB0", { rot = { 0, 0, 90 } }),
				P("ball", { 0.5, 0.5, 0.5 }, "beside", { 0, 1.15, 0 }, "#B0B8C8"),
				P("ball", { 0.12, 0.12, 0.12 }, "beside", { 0.35, 1.3, 0 }, "prop", { neon = true, anim = "flicker" }),
			},
		}, { { "Blue", "Blue", "#7AC8FF" }, { "Violet", "Violet", "#C89AFF" }, { "White", "White", "#F8F8FF" } }),
		props({
			id = "brainJar",
			label = "brain jar",
			text = "talks to a %s brain in a jar",
			parts = {
				P(
					"cyl",
					{ 0.9, 0.7, 0.7 },
					"beside",
					{ 0, 0.45, 0 },
					"#D8F4FF",
					{ rot = { 0, 0, 90 }, mat = "Glass", tr = 0.55 }
				),
				P("ellipsoid", { 0.5, 0.4, 0.45 }, "beside", { 0, 0.45, 0 }, "prop"),
			},
		}, { { "Pink", "Pink", "#FF9AC0" }, { "Green", "Green", "#9AE07A" }, { "Blue", "Blue", "#8AB0FF" } }),
		props({
			id = "magnifier",
			label = "magnifying glass",
			text = "inspects everything with a %s magnifying glass",
			parts = {
				P("cyl", { 0.5, 0.1, 0.1 }, "hand", { 0, -0.1, -0.1 }, "prop", { rot = { 0, 0, 90 } }),
				P("cyl", { 0.08, 0.55, 0.55 }, "hand", { 0, 0.35, -0.1 }, "prop", { rot = { 0, 90, 0 } }),
				P(
					"cyl",
					{ 0.04, 0.45, 0.45 },
					"hand",
					{ 0, 0.35, -0.1 },
					"#D8F4FF",
					{ rot = { 0, 90, 0 }, mat = "Glass", tr = 0.4 }
				),
			},
		}, { { "Brass", "Brass", "#C8A04A" }, { "Steel", "Steel", "#8A9AB0" }, { "Ruby", "Ruby", "#C83A5A" } }),
		props({
			id = "dnaModel",
			label = "DNA model",
			text = "built a %s DNA model",
			parts = {
				P("cyl", { 1.4, 0.06, 0.06 }, "beside", { 0, 0.7, 0 }, "white", { rot = { 0, 0, 90 } }),
				P(
					"ball",
					{ 0.2, 0.2, 0.2 },
					"beside",
					{ 0, 0.7, 0 },
					"prop",
					{ ring = { n = 8, r = 0.3, axis = "z" } }
				),
			},
		}, { { "Rose", "Rose", "#FF7A9A" }, { "Aqua", "Aqua", "#5AD8E8" }, { "Gold", "Gold", "#FFD24A" } })
	),
	-- "Specimen 42", "Dr. Volt", "Proto-Vex". Legendary: "Professor <word>".
	names = {
		forms = { "Specimen %d", "Dr. %s", "Proto-%s" },
		words = {
			"Vex",
			"Kelvin",
			"Gauss",
			"Zed",
			"Quill",
			"Nox",
			"Rho",
			"Tesla",
			"Volt",
			"Flux",
			"Pascal",
			"Hertz",
			"Boyle",
			"Ohm",
			"Joule",
			"Watt",
			"Newton",
			"Faraday",
			"Bunsen",
			"Curie",
			"Petri",
			"Becker",
			"Lumen",
			"Dalton",
		},
		title = "Professor",
	},
	idle = "twitch",
	idleVariants = { "Eureka Jump", "Spin Check", "Nervous Tic" },
	habitats = {
		"Escaped from a very important experiment",
		"Was cloned by accident during lunch break",
		"Hatched under bright lab lights and won't stop beeping",
		"Lives in a fridge labeled DO NOT OPEN",
	},
	funFacts = {
		"%s writes notes on everything, including the other mutants.",
		"%s has been cloned 41 times. This one is the original. Probably.",
		"%s beeps quietly when it's thinking.",
		"%s's favorite word is 'fascinating'.",
		"%s once tried to measure how long a nap is. It fell asleep.",
		"%s labels its snacks with their chemical formulas.",
		"A group of %ss is called an 'experiment'.",
		"%s can't walk past a button without pressing it.",
	},
}

-------------------------------------------------------------------------------- Toxic

Style.Toxic = {
	label = "Toxic",
	skin = {
		material = "Glass", -- slime: glassy, very reflective
		reflectance = 0.45,
		transparency = 0.1,
		palette = { "#9BE04A", "#C8FF3A", "#7CFF4A", "#E4FF6A", "#B6F03A", "#D8FF4A", "#8CD63A", "#F0FF5A" },
		secondary = { "#FFD23A", "#FF9A3C", "#3A3A2A" },
		accent = { "#2A2A1A", "#FFD23A", "#FF7A2A", "#5A3A8A" },
		-- A faint green haze.
		particles = { color = "#B8FF6A", rate = 1.2, size = 1.4, lifetime = 3, speed = 0.3, transparency = 0.85 },
	},
	face = { eyes = 2, eyeStyle = "toxic", mouth = "fangs" },
	feet = "nub",
	bodies = {
		{
			id = "toxicSpiky",
			label = "Spiky",
			text = "a slimy body bristling with spikes",
			parts = {
				P("ellipsoid", { 2.6, 2.3, 2.4 }, "root", { 0, 1.25, 0 }, "skin"),
				P("wedge", { 0.4, 0.9, 0.7 }, "root", { 0, 2.3, 0.4 }, "skinDark", { ring = { n = 6, r = 0.8 } }),
			},
			head = { pos = { 0, 1.4, 0 }, r = { 1.3, 1.15, 1.2 } },
		},
		{
			id = "toxicLopsided",
			label = "Lopsided",
			text = "a lopsided, swollen body",
			parts = {
				P("ellipsoid", { 2.8, 2.2, 2.4 }, "root", { 0.2, 1.2, 0 }, "skin", { rot = { 0, 0, 12 } }),
				P("ball", { 1.4, 1.4, 1.4 }, "root", { -1.05, 1.85, 0.1 }, "skin"),
			},
			head = { pos = { -0.1, 1.5, 0 }, r = { 1.2, 1.0, 1.1 } },
		},
		{
			id = "toxicMelted",
			label = "Melted",
			text = "a half-melted body in a puddle of itself",
			parts = {
				P("ellipsoid", { 2.6, 2.0, 2.4 }, "root", { 0, 1.15, 0 }, "skin"),
				P("cyl", { 0.2, 3.4, 3.2 }, "root", { 0, 0.1, 0 }, "skin", { rot = { 0, 0, 90 } }),
				P("ellipsoid", { 0.5, 1.0, 0.5 }, "root", { 0, 0.6, 0 }, "skin", { ring = { n = 4, r = 1.15 } }),
			},
			head = { pos = { 0, 1.35, 0 }, r = { 1.3, 1.0, 1.2 } },
		},
	},
	signatures = {
		{
			id = "hazardStripes",
			slot = "pattern",
			label = "Hazard stripes",
			text = "yellow-and-black hazard stripes",
			parts = {
				P(
					"block",
					{ 0.35, 0.35, 0.1 },
					"body",
					{ 0, -0.2, 0 },
					"#FFD23A",
					{ ring = { n = 10, r = 1.28 }, rot = { 0, 0, 45 } }
				),
				P(
					"block",
					{ 0.35, 0.35, 0.1 },
					"body",
					{ 0, 0.25, 0 },
					"#2A2A1A",
					{ ring = { n = 10, r = 1.22 }, rot = { 0, 0, 45 } }
				),
			},
		},
		{
			id = "leakyBarrel",
			slot = "back",
			label = "Leaking barrel",
			text = "a leaking barrel strapped to its back",
			parts = {
				P("cyl", { 1.1, 0.8, 0.8 }, "back", { 0, 0.4, 0.35 }, "#FFD23A", { rot = { 0, 0, 90 } }),
				P("cyl", { 0.08, 0.84, 0.84 }, "back", { 0, 0.6, 0.35 }, "#2A2A1A", { rot = { 0, 0, 90 } }),
				P("ellipsoid", { 0.25, 0.6, 0.25 }, "back", { 0.25, -0.3, 0.6 }, "#9AFF4A", { anim = "drip" }),
			},
		},
		{
			id = "thirdEye",
			slot = "eyes",
			label = "Third eye",
			text = "a third eye that never blinks",
			parts = {},
			face = { eyes = 3 },
		},
		{
			id = "fourthEye",
			slot = "eyes",
			label = "Four eyes",
			text = "four eyes looking four ways",
			parts = {},
			face = { eyes = 4 },
		},
		{
			id = "meltedSide",
			slot = "side",
			label = "Melted side",
			text = "one side that is slowly melting off",
			parts = {
				P("ellipsoid", { 0.9, 1.6, 0.9 }, "side", { 0.1, -0.5, 0 }, "skin", { rot = { 0, 0, -15 } }),
				P("ellipsoid", { 0.35, 0.7, 0.35 }, "side", { 0.25, -1.1, 0 }, "skin", { anim = "drip" }),
			},
		},
		{
			id = "fumes",
			slot = "aura",
			label = "Fumes",
			text = "a cloud of green fumes",
			parts = {},
			particles = { color = "#9AFF4A", rate = 3, size = 0.8, lifetime = 2.5, speed = 0.8, transparency = 0.6 },
		},
	},
	features = {
		{
			id = "blisters",
			slot = "pattern",
			label = "Blisters",
			text = "bubbling blisters",
			parts = {
				P("ball", { 0.35, 0.35, 0.35 }, "body", { 0, 0.3, 0 }, "skinLight", { ring = { n = 7, r = 1.22 } }),
			},
		},
		{
			id = "rustPatches",
			slot = "pattern",
			label = "Rust",
			text = "patches of rust",
			parts = {
				P("ellipsoid", { 0.7, 0.5, 0.12 }, "body", { 0, -0.35, 0 }, "#A0602A", { ring = { n = 4, r = 1.25 } }),
			},
		},
		{
			id = "gasMask",
			slot = "mouth",
			label = "Gas mask",
			text = "a gas mask snout",
			parts = {
				P("cyl", { 0.5, 0.6, 0.6 }, "face", { 0, -0.55, -0.15 }, "#3A3A2A", { rot = { 0, 90, 0 } }),
				P("cyl", { 0.12, 0.45, 0.45 }, "face", { 0, -0.55, -0.42 }, "#FFD23A", { rot = { 0, 90, 0 } }),
			},
			face = { mouth = "none" },
		},
		{
			id = "corrodedHorns",
			slot = "top",
			label = "Corroded horns",
			text = "two corroded horns",
			parts = {
				P(
					"ellipsoid",
					{ 0.35, 1.1, 0.35 },
					"top",
					{ 0.45, 0.25, 0 },
					"#8A7A4A",
					{ rot = { 0, 0, -28 }, mirror = true }
				),
			},
		},
		{
			id = "slimeCrown",
			slot = "crown",
			label = "Slime crown",
			text = "a dripping crown of slime",
			parts = {
				P("ellipsoid", { 0.3, 0.7, 0.3 }, "top", { 0, 0.15, 0 }, "skinLight", { ring = { n = 5, r = 0.45 } }),
			},
		},
		{
			id = "radBadge",
			slot = "chest",
			label = "Radiation badge",
			text = "a radiation badge",
			parts = {
				P("cyl", { 0.08, 0.6, 0.6 }, "front", { 0, 0.15, 0.02 }, "#FFD23A", { rot = { 0, 90, 0 } }),
				P(
					"wedge",
					{ 0.04, 0.2, 0.2 },
					"front",
					{ 0, 0.15, -0.04 },
					"#2A2A1A",
					{ ring = { n = 3, r = 0.12, axis = "z" } }
				),
			},
		},
		{
			id = "acidDrool",
			slot = "chin",
			label = "Acid drool",
			text = "acid drool that eats through the floor",
			parts = { P("ellipsoid", { 0.2, 0.55, 0.2 }, "face", { 0.15, -0.95, 0.02 }, "#E4FF6A", { anim = "drip" }) },
		},
		{
			id = "ventPipes",
			slot = "back",
			label = "Vent pipes",
			text = "smoking vent pipes",
			parts = {
				P("cyl", { 0.9, 0.25, 0.25 }, "back", { -0.3, 0.6, 0.2 }, "#6A6A5A", { rot = { 0, 0, 80 } }),
				P("cyl", { 0.7, 0.25, 0.25 }, "back", { 0.3, 0.5, 0.2 }, "#6A6A5A", { rot = { 0, 0, 100 } }),
			},
		},
	},
	props = concat(
		props({
			id = "chemDrum",
			label = "chemical drum",
			text = "guards a %s chemical drum",
			parts = {
				P("cyl", { 1.1, 0.8, 0.8 }, "beside", { 0, 0.55, 0 }, "prop", { rot = { 0, 0, 90 } }),
				P("cyl", { 0.08, 0.84, 0.84 }, "beside", { 0, 0.75, 0 }, "#2A2A1A", { rot = { 0, 0, 90 } }),
			},
		}, { { "Hazard", "Hazard", "#FFD23A" }, { "Rust", "Rusty", "#A0602A" }, { "Steel", "Steel", "#7A8A90" } }),
		props({
			id = "canister",
			label = "gas canister",
			text = "drags a %s gas canister around",
			parts = {
				P("cyl", { 1.0, 0.45, 0.45 }, "beside", { 0, 0.5, 0 }, "prop", { rot = { 0, 0, 90 } }),
				P("cyl", { 0.2, 0.15, 0.15 }, "beside", { 0, 1.1, 0 }, "#3A3A2A", { rot = { 0, 0, 90 } }),
			},
		}, { { "Green", "Green", "#4AA03A" }, { "Orange", "Orange", "#FF7A2A" }, { "Purple", "Purple", "#7A4AA0" } }),
		props({
			id = "warningSign",
			label = "warning sign",
			text = "plants a %s warning sign wherever it goes",
			parts = {
				P("cyl", { 1.4, 0.1, 0.1 }, "beside", { 0, 0.7, 0 }, "#6A6A5A", { rot = { 0, 0, 90 } }),
				P("block", { 0.7, 0.7, 0.06 }, "beside", { 0, 1.35, 0 }, "prop", { rot = { 0, 0, 45 } }),
			},
		}, { { "Yellow", "Yellow", "#FFD23A" }, { "Red", "Red", "#E04A3A" }, { "Lime", "Lime", "#B8FF3A" } }),
		props({
			id = "acidPool",
			label = "acid pool",
			text = "bathes in a %s acid pool",
			parts = {
				P(
					"cyl",
					{ 0.1, 1.4, 1.4 },
					"beside",
					{ 0, 0.05, 0 },
					"prop",
					{ rot = { 0, 0, 90 }, mat = "Glass", refl = 0.4 }
				),
				P("ball", { 0.2, 0.2, 0.2 }, "beside", { 0.3, 0.15, 0 }, "prop", { anim = "float" }),
			},
		}, { { "Lime", "Lime", "#B8FF3A" }, { "Amber", "Amber", "#FFB83A" }, { "Teal", "Teal", "#3AE0B0" } }),
		props({
			id = "valve",
			label = "pipe valve",
			text = "keeps turning a %s pipe valve",
			parts = {
				P("cyl", { 1.0, 0.25, 0.25 }, "beside", { 0, 0.5, 0 }, "#6A6A5A", { rot = { 0, 0, 90 } }),
				P("cyl", { 0.08, 0.6, 0.6 }, "beside", { 0, 1.05, 0 }, "prop", { rot = { 0, 0, 90 } }),
			},
		}, { { "Red", "Red", "#E04A3A" }, { "Blue", "Blue", "#3A7AE0" }, { "Brass", "Brass", "#C8A04A" } }),
		props({
			id = "sludgeBucket",
			label = "sludge bucket",
			text = "carries a bucket of %s sludge",
			parts = {
				P("cyl", { 0.7, 0.7, 0.7 }, "beside", { 0, 0.35, 0 }, "#8A9AA0", { rot = { 0, 0, 90 } }),
				P("cyl", { 0.06, 0.6, 0.6 }, "beside", { 0, 0.68, 0 }, "prop", { rot = { 0, 0, 90 } }),
			},
		}, { { "Green", "Green", "#7CFF4A" }, { "Violet", "Violet", "#B04AFF" }, { "Orange", "Orange", "#FF9A3C" } }),
		props({
			id = "geiger",
			label = "Geiger counter",
			text = "listens to a %s Geiger counter tick",
			parts = {
				P("block", { 0.6, 0.4, 0.35 }, "beside", { 0, 0.2, 0 }, "prop"),
				P(
					"ball",
					{ 0.1, 0.1, 0.1 },
					"beside",
					{ 0.15, 0.42, -0.1 },
					"#9AFF4A",
					{ neon = true, anim = "flicker" }
				),
			},
		}, { { "Yellow", "Yellow", "#E8C83A" }, { "Grey", "Grey", "#8A8A80" }, { "Olive", "Olive", "#7A8A3A" } })
	),
	-- Corrosive compounds ("Blightmaw"). Legendary: "Mega <name>".
	names = {
		first = {
			"Acid",
			"Rot",
			"Blight",
			"Fume",
			"Gunk",
			"Scorch",
			"Corro",
			"Rust",
			"Toxo",
			"Vapor",
			"Seep",
			"Etch",
			"Sizzle",
			"Caustic",
			"Grime",
			"Sear",
		},
		second = {
			"maw",
			"drip",
			"burn",
			"gut",
			"spit",
			"fang",
			"blister",
			"melt",
			"crust",
			"lung",
			"fizz",
			"belch",
			"ooze",
			"scab",
		},
		title = "Mega",
	},
	idle = "drip",
	idleVariants = { "Ooze Pulse", "Boil Over", "Lurch" },
	habitats = {
		"Glows a little when nobody is watching",
		"Bathed in barrel ooze since birth",
		"Its puddles have to be cleaned with tongs",
		"Crawled out of a leaking drum behind the lab",
	},
	funFacts = {
		"%s's footprints keep fizzing for an hour.",
		"%s can dissolve a spoon. It does this to every spoon.",
		"Nothing grows where %s naps, except more %s.",
		"%s smells like burnt lemons. It's proud of this.",
		"%s once melted through the floor and pretended it was on purpose.",
		"A group of %ss is called a 'spill'.",
		"%s gargles acid to keep its teeth shiny.",
		"%s's sneezes leave little holes in the fence.",
	},
}

-------------------------------------------------------------------------------- Void

Style.Void = {
	label = "Void",
	skin = {
		material = "SmoothPlastic", -- matte, no shine
		reflectance = 0,
		palette = { "#1A1424", "#221A33", "#2B2140", "#160F22", "#2A1E3A", "#1E1830", "#30224A", "#241A38" },
		secondary = { "#4A2E7A", "#5B3A9A", "#3A2A5A" },
		accent = { "#9A7AD8", "#C8B8F0", "#6A4AA0", "#E8E0FF" },
		-- Dark motes trailing behind.
		particles = { color = "#2A1A40", rate = 3, size = 0.5, lifetime = 2.5, speed = 0.4, transparency = 0.3 },
	},
	face = { eyes = 2, eyeStyle = "hollow", mouth = "none" },
	feet = "none", -- it floats
	bodies = {
		{
			id = "voidWisp",
			label = "Wisp",
			text = "a thin, wispy body that tapers to nothing",
			parts = {
				P("ellipsoid", { 1.2, 2.6, 1.2 }, "root", { 0, 2.1, 0 }, "skin"),
				P("ellipsoid", { 0.6, 1.6, 0.6 }, "root", { 0, 0.95, 0 }, "skin"),
			},
			head = { pos = { 0, 3.0, 0 }, r = { 0.7, 0.75, 0.7 } },
		},
		{
			id = "voidLong",
			label = "Long",
			text = "a long, stretched-out body",
			parts = { P("ellipsoid", { 1.5, 4.2, 1.3 }, "root", { 0, 2.25, 0 }, "skin") },
			head = { pos = { 0, 3.65, 0 }, r = { 0.75, 0.8, 0.65 } },
		},
		{
			id = "voidAdrift",
			label = "Adrift",
			text = "a head that floats above its body with nothing in between",
			parts = {
				P("ellipsoid", { 1.6, 1.4, 1.4 }, "root", { 0, 0.85, 0 }, "skin"),
				P("ball", { 1.6, 1.6, 1.6 }, "root", { 0, 2.75, 0 }, "skin", { anim = "float" }),
			},
			head = { pos = { 0, 2.75, 0 }, r = { 0.8, 0.8, 0.8 } },
		},
		{
			id = "voidRing",
			label = "Ring",
			text = "a ring of darkness where its body should be",
			parts = {
				P(
					"ball",
					{ 0.6, 0.6, 0.6 },
					"root",
					{ 0, 1.45, 0 },
					"skin",
					{ ring = { n = 12, r = 1.05, axis = "z" } }
				),
				P("ball", { 1.5, 1.5, 1.5 }, "root", { 0, 3.45, 0 }, "skin"),
			},
			head = { pos = { 0, 3.45, 0 }, r = { 0.75, 0.75, 0.75 } },
		},
	},
	signatures = {
		{
			id = "glowEye",
			slot = "eyes",
			label = "Glowing eye",
			text = "one glowing white eye",
			parts = {},
			face = { eyes = 1, eyeStyle = "glow" },
		},
		{
			id = "floatingRing",
			slot = "halo",
			label = "Floating ring",
			text = "a ring that floats around it",
			parts = {
				P(
					"ball",
					{ 0.2, 0.2, 0.2 },
					"above",
					{ 0, -0.2, 0 },
					"accent",
					{ ring = { n = 14, r = 1.0 }, anim = "orbit" }
				),
			},
		},
		{
			id = "bodyTears",
			slot = "pattern",
			label = "Tears",
			text = "tears in its body you can see straight through",
			parts = {
				P(
					"wedge",
					{ 0.08, 0.9, 0.3 },
					"body",
					{ 0, 0.1, 0 },
					"#06040A",
					{ ring = { n = 3, r = 0.68 }, rot = { 0, 90, 0 } }
				),
				P(
					"wedge",
					{ 0.06, 0.95, 0.34 },
					"body",
					{ 0, 0.1, 0 },
					"skin2",
					{ ring = { n = 3, r = 0.7 }, rot = { 0, 90, 0 } }
				),
			},
		},
		{
			id = "trail",
			slot = "aura",
			label = "Shadow trail",
			text = "a long trail of shadow",
			parts = {},
			particles = { color = "#140A20", rate = 6, size = 0.8, lifetime = 3.5, speed = 0.2, transparency = 0.2 },
		},
	},
	features = {
		{
			id = "hood",
			slot = "top",
			label = "Hood",
			text = "a hood of shadow",
			parts = {
				P("ellipsoid", { 1.75, 1.7, 1.5 }, "head", { 0, 0.18, 0.28 }, "skinDark", { name = "Hood" }),
				P("ellipsoid", { 0.5, 0.8, 0.5 }, "top", { 0, 0.15, 0.55 }, "skinDark", { rot = { -35, 0, 0 } }),
			},
		},
		{
			id = "whisper",
			slot = "mouth",
			label = "Whisper mouth",
			text = "a thin mouth that only whispers",
			parts = {},
			face = { mouth = "whisper" },
		},
		{
			id = "shards",
			slot = "back",
			label = "Shards",
			text = "dark shards drifting behind it",
			parts = {
				P(
					"block",
					{ 0.3, 0.6, 0.3 },
					"back",
					{ 0, 0.5, 0.6 },
					"skin2",
					{ ring = { n = 3, r = 0.6 }, rot = { 30, 45, 0 }, anim = "orbit" }
				),
			},
		},
		{
			id = "tendrils",
			slot = "side",
			label = "Tendrils",
			text = "long tendrils for arms",
			parts = {
				P(
					"ellipsoid",
					{ 0.18, 1.8, 0.18 },
					"side",
					{ 0.15, -0.5, 0 },
					"skin",
					{ rot = { 0, 0, 15 }, mirror = true }
				),
			},
		},
		{
			id = "echoEyes",
			slot = "eyes",
			label = "Echo eyes",
			text = "a row of dim echo eyes",
			parts = {},
			face = { eyes = 3, eyeStyle = "hollow" },
		},
		{
			id = "smokeCollar",
			slot = "neck",
			label = "Smoke collar",
			text = "a collar of smoke",
			parts = {
				P("ball", { 0.35, 0.35, 0.35 }, "neck", { 0, 0, 0 }, "skin2", { ring = { n = 8, r = 0.65 }, tr = 0.3 }),
			},
		},
		{
			id = "staticHalo",
			slot = "halo",
			label = "Static",
			text = "a crackle of static above its head",
			parts = {
				P(
					"ball",
					{ 0.1, 0.1, 0.1 },
					"above",
					{ 0, 0, 0 },
					"#E8E0FF",
					{ neon = true, ring = { n = 6, r = 0.5 }, anim = "flicker" }
				),
			},
		},
		{
			id = "motes",
			slot = "pattern",
			label = "Motes",
			text = "faint purple motes under its skin",
			parts = { P("ball", { 0.2, 0.2, 0.2 }, "body", { 0, 0, 0 }, "skin2", { ring = { n = 6, r = 0.62 } }) },
		},
	},
	props = concat(
		props({
			id = "hourglass",
			label = "hourglass",
			text = "carries a %s hourglass that runs upward",
			parts = {
				P("block", { 0.7, 0.08, 0.7 }, "beside", { 0, 0.04, 0 }, "prop"),
				P("ellipsoid", { 0.5, 0.6, 0.5 }, "beside", { 0, 0.35, 0 }, "#D8D0F0", { mat = "Glass", tr = 0.5 }),
				P("ellipsoid", { 0.5, 0.6, 0.5 }, "beside", { 0, 0.9, 0 }, "#D8D0F0", { mat = "Glass", tr = 0.5 }),
				P("block", { 0.7, 0.08, 0.7 }, "beside", { 0, 1.22, 0 }, "prop"),
			},
		}, { { "Silver", "Silver", "#B8B8C8" }, { "Bone", "Bone", "#E8E0C8" }, { "Onyx", "Onyx", "#2A2A3A" } }),
		props({
			id = "lantern",
			label = "lantern",
			text = "holds a %s lantern with no flame",
			parts = {
				P("block", { 0.5, 0.7, 0.5 }, "beside", { 0, 1.1, 0 }, "#D8D0F0", { mat = "Glass", tr = 0.55 }),
				P("block", { 0.6, 0.1, 0.6 }, "beside", { 0, 1.5, 0 }, "prop"),
				P("ball", { 0.12, 0.12, 0.12 }, "beside", { 0, 1.1, 0 }, "prop", { neon = true, anim = "flicker" }),
			},
		}, { { "Violet", "Violet", "#9A6AE8" }, { "Pale", "Pale", "#D8E8FF" }, { "Teal", "Teal", "#4AD8C8" } }),
		props({
			id = "mask",
			label = "mask",
			text = "wears a %s mask on the back of its head",
			parts = {
				P("ellipsoid", { 0.9, 1.1, 0.2 }, "head", { 0, 0, 0.75 }, "prop"),
				P("ellipsoid", { 0.2, 0.12, 0.05 }, "head", { 0.2, 0.15, 0.86 }, "#06040A", { mirror = true }),
			},
		}, { { "White", "White", "#F2F0F8" }, { "Gold", "Gold", "#C8A04A" }, { "Crimson", "Crimson", "#8A2A3A" } }),
		props({
			id = "floatingKey",
			label = "key",
			text = "is followed by a floating %s key",
			parts = {
				P("cyl", { 0.08, 0.4, 0.4 }, "above", { 1.0, -0.4, 0 }, "prop", { rot = { 0, 90, 0 }, anim = "float" }),
				P("block", { 0.6, 0.08, 0.08 }, "above", { 1.35, -0.4, 0 }, "prop", { anim = "float" }),
			},
		}, { { "Silver", "Silver", "#C8C8D8" }, { "Bronze", "Bronze", "#A0703A" }, { "Black", "Black", "#2A2A3A" } }),
		props({
			id = "tome",
			label = "spell book",
			text = "reads a floating %s book",
			parts = {
				P(
					"block",
					{ 0.7, 0.15, 0.5 },
					"above",
					{ 1.1, -0.9, 0 },
					"prop",
					{ rot = { 0, 0, 15 }, anim = "float" }
				),
				P(
					"block",
					{ 0.66, 0.06, 0.46 },
					"above",
					{ 1.1, -0.8, 0 },
					"#F2E8D0",
					{ rot = { 0, 0, 15 }, anim = "float" }
				),
			},
		}, { { "Plum", "Plum", "#5A2A6A" }, { "Midnight", "Midnight", "#1A2A5A" }, { "Ash", "Ash", "#5A5A60" } }),
		props({
			id = "mirrorShard",
			label = "mirror shard",
			text = "talks to its reflection in a %s mirror shard",
			parts = {
				P("wedge", { 0.08, 1.2, 0.7 }, "beside", { 0, 0.6, 0 }, "prop", { refl = 0.6, rot = { 0, 90, 0 } }),
			},
		}, { { "Clear", "Clear", "#C8D8E8" }, { "Smoky", "Smoky", "#5A5A6A" }, { "Rose", "Rose", "#C88AA0" } }),
		props({
			id = "bellJar",
			label = "bell jar",
			text = "keeps a %s star under a bell jar",
			parts = {
				P("ellipsoid", { 0.8, 1.1, 0.8 }, "beside", { 0, 0.6, 0 }, "#D8D0F0", { mat = "Glass", tr = 0.6 }),
				P("ball", { 0.15, 0.15, 0.15 }, "beside", { 0, 0.55, 0 }, "prop", { neon = true }),
			},
		}, { { "White", "White", "#F8F8FF" }, { "Blue", "Blue", "#8AB8FF" }, { "Violet", "Violet", "#C89AFF" } })
	),
	-- One quiet word, from quiet roots or two soft halves ("Hush", "Nyra"). Legendary: "The <word>".
	names = {
		words = {
			"Hush",
			"Lull",
			"Wane",
			"Ebb",
			"Dusk",
			"Still",
			"Faint",
			"Pale",
			"Shroud",
			"Gloam",
			"Sigh",
			"Murmur",
			"Vesper",
			"Ashen",
			"Mute",
			"Drift",
			"Veil",
			"Umbra",
			"Lethe",
			"Wisp",
			"Quell",
			"Calm",
			"Gone",
			"Echo",
		},
		first = {
			"Ae",
			"Ny",
			"Vo",
			"Sae",
			"Ume",
			"Oru",
			"Eth",
			"Iss",
			"Yl",
			"Wyn",
			"Esh",
			"Hal",
			"Ser",
			"Lir",
			"Vael",
			"Nal",
		},
		second = { "l", "n", "th", "ra", "sh", "ve", "ss", "ne", "ro", "wen", "iel", "ith" },
		title = "The",
	},
	idle = "hover",
	idleVariants = { "Phase Drift", "Slow Spin", "Blink Out" },
	habitats = {
		"Drifted in from a place with no up or down",
		"Casts a shadow even in the dark",
		"Whispers in a language made of static",
		"Only shows up in the corner of your eye",
	},
	funFacts = {
		"%s has never been heard walking. It doesn't walk.",
		"Nobody has ever seen %s arrive. It is simply there.",
		"%s hums at a pitch only eggs can hear.",
		"Lights flicker a little when %s is happy.",
		"%s is exactly as heavy as a shadow.",
		"A group of %ss is called a 'hush'.",
		"%s keeps a list of everything it has forgotten.",
		"If you stare at %s long enough, it stares back first.",
	},
}

-------------------------------------------------------------------------------- Cosmic

Style.Cosmic = {
	label = "Cosmic",
	skin = {
		material = "Foil",
		reflectance = 0.2,
		palette = { "#3B2A8A", "#5A2DFF", "#2A3A9A", "#6A3FCF", "#1F2A6E", "#7A5CFF", "#4B1F8A", "#2C4FA0" },
		secondary = { "#FF8AF0", "#5CE1FF", "#FFD24A" },
		accent = { "#FFD24A", "#5CE1FF", "#FF8AF0", "#F8F8FF" },
		-- A starfield: tiny Neon specks on the body (specks only: the art rules).
		specks = { n = 10, size = 0.12, color = "#FFFFFF" },
	},
	face = { eyes = 2, eyeStyle = "starlit", mouth = "none" },
	feet = "none",
	bodies = {
		{
			id = "cosmicCrystal",
			label = "Crystal",
			text = "a body of faceted crystal",
			parts = {
				P("block", { 1.8, 2.4, 1.8 }, "root", { 0, 1.3, 0 }, "skin", { rot = { 0, 45, 0 } }),
				P("block", { 1.25, 1.25, 1.25 }, "root", { 0, 2.65, 0 }, "skin", { rot = { 45, 45, 0 } }),
				P("block", { 0.9, 0.9, 0.9 }, "root", { 0, 0.8, 0 }, "skin2", { rot = { 45, 45, 0 } }),
			},
			head = { pos = { 0, 1.7, 0 }, r = { 0.95, 0.85, 0.95 } },
		},
		{
			id = "cosmicPrism",
			label = "Prism",
			text = "a tall glassy prism",
			parts = {
				P("wedge", { 2.2, 3.0, 1.2 }, "root", { 0, 1.5, -0.6 }, "skin"),
				P("wedge", { 2.2, 3.0, 1.2 }, "root", { 0, 1.5, 0.6 }, "skin", { rot = { 0, 180, 0 } }),
			},
			head = { pos = { 0, 1.5, 0 }, r = { 1.0, 0.9, 0.75 } },
		},
		{
			id = "cosmicOrbs",
			label = "Orb cluster",
			text = "a cluster of glowing orbs",
			parts = {
				P("ball", { 2.0, 2.0, 2.0 }, "root", { 0, 1.1, 0 }, "skin"),
				P("ball", { 1.1, 1.1, 1.1 }, "root", { 0, 0.6, 0 }, "skin2", { ring = { n = 3, r = 1.2 } }),
				P("ball", { 0.8, 0.8, 0.8 }, "root", { 0.4, 2.3, 0.3 }, "skin"),
			},
			head = { pos = { 0, 1.15, 0 }, r = { 1.0, 1.0, 1.0 } },
		},
	},
	signatures = {
		{
			id = "satellites",
			slot = "orbit",
			label = "Satellites",
			text = "little moons that orbit it",
			parts = {
				P(
					"ball",
					{ 0.4, 0.4, 0.4 },
					"body",
					{ 0, 0.4, 0 },
					"skin2",
					{ ring = { n = 3, r = 2.0 }, anim = "orbit" }
				),
			},
		},
		{
			id = "halo",
			slot = "halo",
			label = "Halo",
			text = "a halo of starlight",
			parts = {
				P(
					"ball",
					{ 0.18, 0.18, 0.18 },
					"above",
					{ 0, -0.3, 0 },
					"#FFE8A0",
					{ neon = true, ring = { n = 12, r = 0.7 } }
				),
			},
		},
		{
			id = "ringCrown",
			slot = "top",
			label = "Ring crown",
			text = "a crown of tilted rings",
			parts = {
				P("cyl", { 0.06, 1.4, 1.4 }, "top", { 0, 0.35, 0 }, "accent", { rot = { 20, 0, 90 } }),
				P("cyl", { 0.06, 1.1, 1.1 }, "top", { 0, 0.5, 0 }, "accent", { rot = { -25, 0, 90 } }),
			},
		},
		{
			id = "nebula",
			slot = "pattern",
			label = "Nebula",
			text = "a nebula swirling across its body",
			parts = {
				P(
					"ellipsoid",
					{ 1.0, 0.7, 0.3 },
					"body",
					{ 0, 0.1, 0 },
					"skin2",
					{ ring = { n = 3, r = 1.0 }, mat = "Glass", tr = 0.35 }
				),
			},
		},
	},
	features = {
		{
			id = "starEyes",
			slot = "eyes",
			label = "Star eyes",
			text = "eyes like two gold stars",
			parts = {},
			face = { eyeStyle = "star" },
		},
		{
			id = "cometTail",
			slot = "back",
			label = "Comet tail",
			text = "a comet tail streaming behind it",
			parts = {
				P("ellipsoid", { 0.6, 0.6, 1.6 }, "back", { 0, 0.3, 0.8 }, "accent", { mat = "Glass", tr = 0.4 }),
				P("ellipsoid", { 0.35, 0.35, 1.2 }, "back", { 0, 0.3, 1.9 }, "accent", { mat = "Glass", tr = 0.6 }),
			},
		},
		{
			id = "moonlet",
			slot = "side",
			label = "Moonlet",
			text = "a pet moon with craters",
			parts = {
				P("ball", { 0.7, 0.7, 0.7 }, "side", { 0.8, 0.6, 0 }, "#C8C8D0", { anim = "float" }),
				P("ball", { 0.2, 0.2, 0.2 }, "side", { 0.6, 0.75, -0.25 }, "#9A9AA8", { anim = "float" }),
			},
		},
		{
			id = "constellation",
			slot = "pattern",
			label = "Constellation",
			text = "a constellation drawn on its chest",
			parts = {
				P(
					"ball",
					{ 0.12, 0.12, 0.12 },
					"front",
					{ 0, 0.1, 0.02 },
					"#FFFFFF",
					{ neon = true, ring = { n = 5, r = 0.35, axis = "z" } }
				),
				P(
					"block",
					{ 0.4, 0.03, 0.03 },
					"front",
					{ 0, 0.1, 0.03 },
					"#C8D8FF",
					{ ring = { n = 5, r = 0.3, axis = "z" } }
				),
			},
		},
		{
			id = "sunCrest",
			slot = "crown",
			label = "Sun crest",
			text = "a tiny sun for a crest",
			parts = {
				P("ball", { 0.5, 0.5, 0.5 }, "top", { 0, 0.4, 0 }, "#FFB83A"),
				P(
					"wedge",
					{ 0.1, 0.3, 0.2 },
					"top",
					{ 0, 0.4, 0 },
					"#FFD24A",
					{ ring = { n = 8, r = 0.35, axis = "z" } }
				),
			},
		},
		{
			id = "meteorBelt",
			slot = "base",
			label = "Meteor belt",
			text = "a belt of tumbling meteors",
			parts = {
				P(
					"block",
					{ 0.3, 0.25, 0.3 },
					"root",
					{ 0, 0.3, 0 },
					"#7A6A8A",
					{ ring = { n = 7, r = 1.6 }, rot = { 20, 30, 10 }, anim = "orbit" }
				),
			},
		},
		{
			id = "planetRing",
			slot = "waist",
			label = "Planet ring",
			text = "a planet's ring around its middle",
			parts = { P("cyl", { 0.06, 3.4, 3.4 }, "body", { 0, 0, 0 }, "accent", { rot = { 12, 0, 90 }, tr = 0.2 }) },
		},
	},
	props = concat(
		props({
			id = "telescope",
			label = "telescope",
			text = "stargazes through a %s telescope",
			parts = {
				P("cyl", { 1.2, 0.08, 0.08 }, "beside", { -0.2, 0.6, 0 }, "#6A6A7A", { rot = { 0, 0, 70 } }),
				P("cyl", { 1.2, 0.08, 0.08 }, "beside", { 0.2, 0.6, 0 }, "#6A6A7A", { rot = { 0, 0, 110 } }),
				P("cyl", { 1.3, 0.3, 0.3 }, "beside", { 0, 1.25, 0 }, "prop", { rot = { 0, 0, 30 } }),
			},
		}, { { "Brass", "Brass", "#C8A04A" }, { "Silver", "Silver", "#C8C8D8" }, { "Navy", "Navy", "#2A3A7A" } }),
		props({
			id = "armillary",
			label = "armillary sphere",
			text = "spins a %s armillary sphere",
			parts = {
				P("cyl", { 0.6, 0.12, 0.12 }, "beside", { 0, 0.3, 0 }, "#6A6A7A", { rot = { 0, 0, 90 } }),
				P("cyl", { 0.05, 0.9, 0.9 }, "beside", { 0, 0.95, 0 }, "prop", { rot = { 0, 0, 0 } }),
				P("cyl", { 0.05, 0.9, 0.9 }, "beside", { 0, 0.95, 0 }, "prop", { rot = { 0, 90, 30 } }),
				P("ball", { 0.2, 0.2, 0.2 }, "beside", { 0, 0.95, 0 }, "#FFD24A"),
			},
		}, { { "Gold", "Gold", "#E8B83A" }, { "Copper", "Copper", "#C8783A" }, { "Pearl", "Pearl", "#E8E8F0" } }),
		props({
			id = "meteorite",
			label = "meteorite",
			text = "guards a %s meteorite",
			parts = {
				P("block", { 0.8, 0.6, 0.7 }, "beside", { 0, 0.3, 0 }, "#5A4A5A", { rot = { 15, 30, 10 } }),
				P("ball", { 0.14, 0.14, 0.14 }, "beside", { 0.2, 0.55, -0.2 }, "prop", { neon = true }),
			},
		}, { { "Cyan", "Cyan", "#5CE1FF" }, { "Magenta", "Magenta", "#FF5CE1" }, { "Amber", "Amber", "#FFB83A" } }),
		props({
			id = "rocket",
			label = "rocket",
			text = "built a %s toy rocket",
			parts = {
				P("cyl", { 1.0, 0.4, 0.4 }, "beside", { 0, 0.6, 0 }, "prop", { rot = { 0, 0, 90 } }),
				P("ball", { 0.4, 0.4, 0.4 }, "beside", { 0, 1.1, 0 }, "prop"),
				P("wedge", { 0.06, 0.4, 0.3 }, "beside", { 0, 0.25, 0 }, "#E04A4A", { ring = { n = 3, r = 0.22 } }),
			},
		}, { { "White", "White", "#F2F2F8" }, { "Red", "Red", "#E04A4A" }, { "Silver", "Silver", "#B8C0D0" } }),
		props({
			id = "planetGlobe",
			label = "planet globe",
			text = "keeps a %s planet on a stand",
			parts = {
				P("cyl", { 0.5, 0.1, 0.1 }, "beside", { 0, 0.25, 0 }, "#6A6A7A", { rot = { 0, 0, 90 } }),
				P("ball", { 0.8, 0.8, 0.8 }, "beside", { 0, 0.9, 0 }, "prop"),
				P("cyl", { 0.04, 1.2, 1.2 }, "beside", { 0, 0.9, 0 }, "#E8E0C8", { rot = { 15, 0, 90 } }),
			},
		}, { { "Ruby", "Ruby", "#C83A5A" }, { "Ocean", "Ocean", "#3A7AE0" }, { "Jade", "Jade", "#3AB08A" } }),
		props({
			id = "starJar",
			label = "star jar",
			text = "caught a %s star in a jar",
			parts = {
				P(
					"cyl",
					{ 0.8, 0.6, 0.6 },
					"beside",
					{ 0, 0.4, 0 },
					"#D8E8FF",
					{ rot = { 0, 0, 90 }, mat = "Glass", tr = 0.5 }
				),
				P("ball", { 0.16, 0.16, 0.16 }, "beside", { 0, 0.4, 0 }, "prop", { neon = true }),
			},
		}, { { "Gold", "Gold", "#FFE07A" }, { "Blue", "Blue", "#8AC8FF" }, { "Pink", "Pink", "#FF9AE8" } }),
		props({
			id = "compassRose",
			label = "star compass",
			text = "navigates by a %s star compass",
			parts = {
				P("cyl", { 0.08, 1.0, 1.0 }, "beside", { 0, 0.05, 0 }, "prop", { rot = { 0, 0, 90 } }),
				P("wedge", { 0.06, 0.1, 0.45 }, "beside", { 0, 0.12, 0 }, "#F8F8FF", { ring = { n = 4, r = 0.25 } }),
			},
		}, { { "Gold", "Gold", "#E8B83A" }, { "Indigo", "Indigo", "#4A3AA0" }, { "Teal", "Teal", "#3AB0B0" } })
	),
	-- Grand, Greek/Latin-sounding ("Stellaris"). Legendary: "Emperor <name>".
	names = {
		first = {
			"Astr",
			"Cel",
			"Lumin",
			"Sol",
			"Aether",
			"Ori",
			"Veg",
			"Zenith",
			"Nebul",
			"Hyper",
			"Polar",
			"Stell",
			"Cosm",
			"Andro",
			"Galact",
			"Sider",
			"Aur",
			"Lyr",
			"Hel",
			"Equin",
		},
		second = {
			"aeus",
			"ion",
			"ara",
			"ix",
			"onis",
			"ius",
			"os",
			"ea",
			"yx",
			"aris",
			"andra",
			"emis",
			"icus",
			"ora",
			"eon",
		},
		title = "Emperor",
	},
	idle = "orbit",
	idleVariants = { "Grand Orbit", "Pulsar", "Slow Revolve" },
	habitats = {
		"Fell from the sky inside a shooting star",
		"Hums the tune of a faraway galaxy",
		"Weighs less on Tuesdays, for space reasons",
		"Was born where two constellations touch",
	},
	funFacts = {
		"%s is older than the farm, the valley and possibly the sky.",
		"%s can name every star. It made most of the names up.",
		"%s glows a little brighter during a full moon.",
		"%s's satellites argue about which one is the moon.",
		"Light takes a while to reach %s. It doesn't mind waiting.",
		"A group of %ss is called a 'galaxy'.",
		"%s bows to every shooting star it sees.",
		"%s once orbited the fountain for a whole day.",
	},
}

-- Tier order (the egg tiers, Config/Eggs). Rarity budgets: features per species (the signature
-- counts as one); Epic and Legendary also get a unique prop; Legendary a named idle variant and
-- a bigger base size.
Style.order = { "Starter", "Swamp", "Lab", "Toxic", "Void", "Cosmic" }
Style.budget = {
	Common = { features = 1, prop = false },
	Uncommon = { features = 2, prop = false },
	Rare = { features = 3, prop = false },
	Epic = { features = 4, prop = true },
	Legendary = { features = 5, prop = true, idleVariant = true, scale = 1.2 },
}
-- Epic names end in one of these (the only affixes shared by every tier); Legendary names start
-- with the tier's `names.title`.
Style.epicSuffixes = { "Prime", "Rex" }

-- Idle animations (MutantModel.idlePose): amplitude (studs at scale 1), speed (rad/s), and
-- extras. A Legendary's named variant multiplies them.
Style.idles = {
	bob = { amp = 0.25, speed = 5 },
	sag = { amp = 0.12, speed = 1.6, tilt = 3 },
	twitch = { amp = 4, speed = 9 }, -- degrees of a quick jerk now and then
	drip = { amp = 0.1, speed = 2.2 },
	hover = { amp = 0.3, speed = 1.4, lift = 0.4 },
	orbit = { amp = 0.15, speed = 1.0, spin = 0.25 },
}
Style.variantBoost = { amp = 1.6, speed = 1.25 }

return Style
