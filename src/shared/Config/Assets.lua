--!strict
-- Every asset ID in the game. Empty string = not chosen yet; code must treat "" as "skip".
-- Swap in real art/sound here without touching logic.

return {
	-- Placeholders use sounds that ship with every Roblox client (rbxasset://).
	-- Swap for library sounds (rbxassetid://...) when picking final audio.
	sounds = {
		hatchCommon = "rbxasset://sounds/action_jump.mp3",
		hatchUncommon = "rbxasset://sounds/action_jump.mp3",
		hatchRare = "rbxasset://sounds/electronicpingshort.wav",
		hatchEpic = "rbxasset://sounds/electronicpingshort.wav",
		hatchLegendary = "rbxasset://sounds/electronicpingshort.wav",
		mutate = "rbxasset://sounds/electronicpingshort.wav",
		harvest = "rbxasset://sounds/action_jump.mp3",
		sell = "rbxasset://sounds/electronicpingshort.wav",
		buy = "rbxasset://sounds/clickfast.wav",
		click = "rbxasset://sounds/clickfast.wav",
		crack = "rbxasset://sounds/clickfast.wav",
		explode = "rbxasset://sounds/action_get_up.mp3",
		plant = "rbxasset://sounds/clickfast.wav",
		water = "rbxasset://sounds/impact_water.mp3",
		weatherSiren = "",
		error = "rbxasset://sounds/clickfast.wav",
	},
	meshes = {
		blob = "",
		spiky = "",
		tall = "",
		flat = "",
	},
	images = {
		cashIcon = "",
		gemIcon = "",
		robuxIcon = "rbxasset://textures/ui/common/robux.png",
	},
}
