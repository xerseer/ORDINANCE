--!strict
--[[
	Ordnance
	A modular gun framework for Roblox.

	This one object is the whole framework. Put it in ReplicatedStorage and it
	runs; delete it and nothing is left behind.

		Ordnance
		├─ Config      your global settings (anything you leave out uses the default)
		├─ Weapons     one module per weapon; drop a module in and it works
		├─ Presets     ready-made configs, from Arcade to Realistic
		└─ Framework   internals; replaced on update, do not edit

	Requiring this module gives you the public API:

		local Ordnance = require(game.ReplicatedStorage.Ordnance)
		print(Ordnance.Version)
]]

local Framework = script:WaitForChild("Framework")

local Logger = require(Framework.Core.Logger)
local Version = require(Framework.Version)

local Ordnance = {
	Version = Version,
	Logger = Logger,
}

return Ordnance
