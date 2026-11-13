--!strict
--[[
	Client entry point. RunContext = Client, so it runs from ReplicatedStorage
	with nothing copied into StarterPlayerScripts.
]]

local RunService = game:GetService("RunService")

if RunService:IsRunning() then
	require(script.Parent.Parent.Parent)
end
