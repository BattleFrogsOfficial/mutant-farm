--!strict
-- Opens Roblox purchase prompts for passes and developer products by config id
-- (Config/Passes, Config/Products.robux). The server grants on its own (MonetizationService);
-- this only prompts. Items whose id is still 0 aren't on sale yet and just say so.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Passes = require(ReplicatedStorage.Shared.Config.Passes)
local Products = require(ReplicatedStorage.Shared.Config.Products)
local State = require(script.Parent.State)

local Purchase = {}

function Purchase.owns(passId: string): boolean
	local snap = State.get()
	return snap ~= nil and snap.ownedPasses ~= nil and snap.ownedPasses[passId] == true
end

function Purchase.pass(passId: string)
	local pass = (Passes :: any)[passId]
	if not pass or Purchase.owns(passId) then
		return
	end
	if pass.id == 0 then
		State.toast(pass.name .. " isn't on sale yet", "info")
		return
	end
	MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.id)
end

function Purchase.product(productId: string)
	local product = (Products.robux :: any)[productId]
	if not product then
		return
	end
	if product.id == 0 then
		State.toast("This pack isn't on sale yet", "info")
		return
	end
	MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.id)
end

return Purchase
