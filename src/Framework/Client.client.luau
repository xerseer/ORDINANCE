--!strict
--[[
	Client entry point. RunContext = Client, so it runs from ReplicatedStorage
	with nothing copied into StarterPlayerScripts.
]]

local RunService = game:GetService("RunService")

if not RunService:IsRunning() then
	return
end

local Framework = script.Parent

local Logger = require(Framework.Core.Logger)
local Version = require(Framework.Version)

local log = Logger.scope("Client")

log:Try(function()
	log:Info(`v{Version} started`)
end)
