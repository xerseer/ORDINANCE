--!strict
--[[
	Server entry point. RunContext = Server, so it runs from wherever the
	Ordnance object lives; there is nothing to install in ServerScriptService.
]]

local RunService = game:GetService("RunService")

if not RunService:IsRunning() then
	return
end

local Framework = script.Parent

local Logger = require(Framework.Core.Logger)
local Version = require(Framework.Version)

local log = Logger.scope("Server")

log:Try(function()
	log:Info(`v{Version} started`)
end)
