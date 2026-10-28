--!strict
-- Robux purchases. Game passes: ownership is checked on join and granted the moment a purchase
-- finishes. Developer products (Gem packs, Starter Bundle): ProcessReceipt grants them once per
-- PurchaseId (recorded in processedPurchases). Ids of 0 in Config/Passes and Config/Products are
-- "not set up yet": the client never prompts those.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Passes = require(Shared.Config.Passes)
local Products = require(Shared.Config.Products)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local GrowthService = require(script.Parent.GrowthService)
local EconomyService = require(script.Parent.EconomyService)
local Net = require(script.Parent.Parent.Util.Net)
local Analytics = require(script.Parent.Parent.Util.Analytics)

local MonetizationService = {}

local MAX_RECEIPTS_KEPT = 100

local function passByGamePassId(id: number): string?
	for passId, pass in Passes do
		if pass.id ~= 0 and pass.id == id then
			return passId
		end
	end
	return nil
end

local function productByDevProductId(id: number): (string?, any)
	for productId, product in Products.robux do
		if product.id ~= 0 and product.id == id then
			return productId, product
		end
	end
	return nil, nil
end

local function grantPass(player: Player, data: Types.Profile, passId: string, announce: boolean)
	if data.ownedPasses[passId] then
		return
	end
	-- Settle at the old speed/luck first (passes change both).
	GrowthService.settleAndAnnounce(player, data)
	data.ownedPasses[passId] = true
	if announce then
		Net.notify(player, (Passes :: any)[passId].name .. " unlocked!", "success")
	end
	DataService.changed(player)
end

-- Keeps processedPurchases from growing forever: drop the oldest beyond MAX_RECEIPTS_KEPT.
local function trimReceipts(data: Types.Profile)
	local list = {}
	for key, at in data.processedPurchases do
		table.insert(list, { key = key, at = at })
	end
	if #list <= MAX_RECEIPTS_KEPT then
		return
	end
	table.sort(list, function(a, b)
		return a.at < b.at
	end)
	for i = 1, #list - MAX_RECEIPTS_KEPT do
		data.processedPurchases[list[i].key] = nil
	end
end

local function grantProduct(player: Player, data: Types.Profile, productId: string, product: any): boolean
	if product.gems and not product.grants then
		if not EconomyService.addGems(player, data, product.gems, "IAP", productId) then
			return false
		end
		Net.notify(player, string.format("+%d Gems!", product.gems), "success")
		return true
	end
	if productId == "StarterBundle" then
		for _, passId in product.grants.passes do
			grantPass(player, data, passId, false)
		end
		if product.grants.gems then
			EconomyService.addGems(player, data, product.grants.gems, "IAP", productId)
		end
		data.bundleBought = true
		Net.notify(player, "Starter Bundle unlocked! 2x Luck + Auto-Harvest + Gems", "success")
		return true
	end
	return false
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local data = player and DataService.get(player)
	if not player or not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox retries on next join
	end
	local key = tostring(receipt.PurchaseId)
	if data.processedPurchases[key] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local productId, product = productByDevProductId(receipt.ProductId)
	if not productId then
		warn("[Monetization] unknown product id", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not grantProduct(player, data, productId, product) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	data.processedPurchases[key] = DataService.now()
	trimReceipts(data)
	DataService.changed(player)
	-- Only report it granted once it's saved; otherwise a crash could lose a paid purchase.
	-- (processedPurchases stops a double grant when Roblox retries after a failed save.)
	if not DataService.saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Passes bought on the website (or in another server) show up here on join.
local function checkOwnedPasses(player: Player, data: Types.Profile)
	for passId, pass in Passes do
		if pass.id ~= 0 and not data.ownedPasses[passId] then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.id)
			if ok and owns and player.Parent == Players then
				grantPass(player, data, passId, false)
			end
		end
	end
end

function MonetizationService.Init()
	MarketplaceService.ProcessReceipt = processReceipt
end

function MonetizationService.Start()
	DataService.Loaded:Connect(function(player, data)
		task.spawn(checkOwnedPasses, player, data)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if not purchased then
			return
		end
		local data = DataService.get(player)
		local passId = passByGamePassId(gamePassId)
		if data and passId then
			grantPass(player, data, passId, true)
			Analytics.funnel(player, data, "FirstPurchasePrompt")
		end
	end)
end

return MonetizationService
