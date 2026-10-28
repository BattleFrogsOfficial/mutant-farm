--!strict
-- Redeem codes from Config/Codes.lua (case-insensitive), once per player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Codes = require(Shared.Config.Codes)
local Eggs = require(Shared.Config.Eggs)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local Net = require(script.Parent.Parent.Util.Net)
local Validate = require(script.Parent.Parent.Util.Validate)

local CodesService = {}

local function onRedeem(player: Player, data: Types.Profile, raw: any)
	if not Validate.string(raw, 32) then
		return
	end
	local code = string.upper(((raw :: string):gsub("%s", "")))
	local reward = (Codes :: any)[code]
	if not reward or reward.expired then
		Net.notify(player, "That code doesn't exist (or expired)", "info")
		return
	end
	if data.redeemedCodes[code] then
		Net.notify(player, "You already used that code", "info")
		return
	end
	data.redeemedCodes[code] = true
	local parts = {}
	if reward.gems then
		EconomyService.addGems(player, data, reward.gems, "Gameplay", "Code_" .. code)
		table.insert(parts, reward.gems .. " Gems")
	end
	for eggId, count in reward.eggs or {} do
		if Eggs.tiers[eggId] then
			data.eggs[eggId] = (data.eggs[eggId] or 0) + count
			table.insert(parts, count .. " " .. Eggs.tiers[eggId].name .. (if count > 1 then "s" else ""))
		end
	end
	Net.notify(player, "Code redeemed: " .. table.concat(parts, " + "), "success")
	DataService.changed(player)
end

function CodesService.Init() end

function CodesService.Start()
	Net.on("RedeemCode", onRedeem)
end

return CodesService
