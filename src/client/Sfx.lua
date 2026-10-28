--!strict
-- Plays one-shot sounds by name from Config/Assets.sounds. Empty ids are skipped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Assets = require(ReplicatedStorage.Shared.Config.Assets)

local Sfx = {}

function Sfx.play(name: string, volume: number?, pitch: number?)
	local id = (Assets.sounds :: any)[name]
	if not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.6
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(10, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

return Sfx
