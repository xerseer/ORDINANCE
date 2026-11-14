--!strict
--[[
	Server
	Starts and stops the server half of the framework.
]]

local Framework = script.Parent

local Combat = require(script.Combat)
local Config = require(Framework.Config)
local LagCompensation = require(script.LagCompensation)
local Logger = require(Framework.Core.Logger)
local Net = require(Framework.Core.Net)
local Registry = require(Framework.Weapons.Registry)
local Sessions = require(script.Sessions)
local Version = require(Framework.Version)
local Visualizer = require(Framework.Core.Visualizer)

local log = Logger.scope("Server")

local Server = {}

Server.Combat = Combat
Server.Sessions = Sessions

local started = false
local removal: RBXScriptConnection? = nil

function Server.isStarted(): boolean
	return started
end

-- Starts everything. `root` is the Ordnance object. Safe to call twice.
function Server.start(root: Instance)
	if started then
		return
	end
	started = true

	log:Try(function()
		Config.load(root)
		Registry.load(root)
		Net.start(Framework)

		local security = Config.global().Security
		if security.LagCompensation then
			LagCompensation.start(security.SnapshotRate)
		end
		Combat.start()
		Sessions.start()

		-- Deleting the Ordnance object at runtime shuts the framework down
		-- instead of leaving connections running against missing instances.
		removal = root.AncestryChanged:Connect(function()
			if not root:IsDescendantOf(game) then
				Server.stop()
			end
		end)

		log:Info(`v{Version} started`)
	end)
end

function Server.stop()
	if not started then
		return
	end
	started = false
	if removal then
		removal:Disconnect()
		removal = nil
	end
	Sessions.stop()
	Combat.stop()
	LagCompensation.stop()
	Net.stop()
	Visualizer.clear()
	log:Info("stopped")
	Logger.shutdown()
end

return Server
