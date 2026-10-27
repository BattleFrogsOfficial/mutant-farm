--!strict
-- Mutant names and their one exaggerated feature, per tier and rarity. Edit freely.
-- body picks a base shape (blob, spiky, tall, flat) built from primitives until real meshes exist.

return {
	Starter = {
		Common = { name = "Blorp", feature = "one wobbly eye", body = "blob" },
		Uncommon = { name = "Snorkle", feature = "a snout like a trumpet", body = "blob" },
		Rare = { name = "Toothy Pip", feature = "a single giant tooth", body = "tall" },
		Epic = { name = "Triclops", feature = "three blinking eyes", body = "blob" },
		Legendary = { name = "King Goober", feature = "a tiny crown fused to its head", body = "tall" },
	},
	Swamp = {
		Common = { name = "Muckling", feature = "dripping mud ears", body = "flat" },
		Uncommon = { name = "Bogwump", feature = "lily-pad hat", body = "blob" },
		Rare = { name = "Croakzilla", feature = "a throat sac bigger than its body", body = "blob" },
		Epic = { name = "Mire Hydra", feature = "four tiny heads", body = "spiky" },
		Legendary = { name = "Swamp Sovereign", feature = "a glowing moss beard", body = "tall" },
	},
	Lab = {
		Common = { name = "Beaker Bean", feature = "a test-tube tail", body = "tall" },
		Uncommon = { name = "Gogglegunk", feature = "huge welding goggles", body = "blob" },
		Rare = { name = "Clonelet", feature = "a smaller copy growing on its back", body = "blob" },
		Epic = { name = "Brainiac Blob", feature = "a see-through brain dome", body = "blob" },
		Legendary = { name = "Dr. Splice", feature = "mismatched robot arm", body = "tall" },
	},
	Toxic = {
		Common = { name = "Sludgeling", feature = "a leaking barrel belly", body = "flat" },
		Uncommon = { name = "Fumefang", feature = "smoke-puffing nostrils", body = "spiky" },
		Rare = { name = "Rad Roach", feature = "antennae taller than itself", body = "spiky" },
		Epic = { name = "Glowgutter", feature = "a glowing see-through stomach", body = "blob" },
		Legendary = { name = "Toxic Titan", feature = "a gas-mask face", body = "tall" },
	},
	Void = {
		Common = { name = "Nullnub", feature = "no face at all", body = "blob" },
		Uncommon = { name = "Echo Eye", feature = "an eye that's a tiny black hole", body = "blob" },
		Rare = { name = "Shadewing", feature = "wings made of static", body = "flat" },
		Epic = { name = "Rift Gremlin", feature = "a portal for a mouth", body = "spiky" },
		Legendary = { name = "The Hollow", feature = "a body full of stars", body = "tall" },
	},
	Cosmic = {
		Common = { name = "Stardrop", feature = "a comet tail", body = "blob" },
		Uncommon = { name = "Moonmunch", feature = "a crescent-moon jaw", body = "flat" },
		Rare = { name = "Nebulord", feature = "a swirling galaxy belly", body = "blob" },
		Epic = { name = "Quasar Kid", feature = "laser-beam antennae", body = "spiky" },
		Legendary = { name = "Galaxy Gobbler", feature = "a mouth wider than its body", body = "tall" },
	},
}
