--!strict
-- Chat: the gold [VIP] tag in front of VIP owners' names (the server sets the player's `VIP`
-- attribute), the system lines everyone sees for big Robux buys ("Ana just went VIP!"), and the
-- weather announcements (a toast for each; the T-5:00 one also as a chat line).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.Parent.State)

local ChatController = {}

local GOLD = "#FFD24A"

function ChatController.Init() end

function ChatController.Start()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local source = message.TextSource
		local speaker = source and Players:GetPlayerByUserId(source.UserId)
		if not speaker or speaker:GetAttribute("VIP") ~= true then
			return nil
		end
		local props = Instance.new("TextChatMessageProperties")
		props.PrefixText = string.format('<font color="%s">[VIP]</font> %s', GOLD, message.PrefixText)
		return props
	end

	local function systemLine(text: string, color: string)
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral") :: TextChannel?
		if general then
			pcall(general.DisplaySystemMessage, general, string.format('<font color="%s">%s</font>', color, text))
		end
	end

	Remotes.get("PurchaseFx").OnClientEvent:Connect(function(_userId: number, line: string?)
		if line then
			systemLine("✨ " .. line, GOLD)
		end
	end)

	Remotes.get("WeatherAnnounce").OnClientEvent:Connect(function(text: string, chat: boolean)
		State.toast(text, "info")
		if chat then
			systemLine(text, "#7CFF4A")
		end
	end)
end

return ChatController
