--!strict
--[[
	Server entry point. RunContext = Server, so it runs from wherever the
	Ordnance object lives; there is nothing to install in ServerScriptService.

	Requiring the public module is what starts the framework, so a game script
	that requires Ordnance first gets a started framework too.
]]

local RunService = game:GetService("RunService")

if RunService:IsRunning() then
	require(script.Parent.Parent.Parent)
end
