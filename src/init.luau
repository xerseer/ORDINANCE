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

	Requiring this module gives you the public API. You never need to: the
	framework starts by itself. Use it when your game wants to hand out
	weapons, react to hits or change damage.

		local Ordnance = require(game.ReplicatedStorage.Ordnance)

		Ordnance.Killed:Connect(function(info)
			print(info.attacker, "killed", info.victim.Parent, "with", info.weapon)
		end)
]]

local RunService = game:GetService("RunService")

local Framework = script:WaitForChild("Framework")

local Config = require(Framework.Config)
local Events = require(Framework.Core.Events)
local Logger = require(Framework.Core.Logger)
local Registry = require(Framework.Weapons.Registry)
local Version = require(Framework.Version)

local IS_SERVER = RunService:IsServer()
local IS_RUNNING = RunService:IsRunning()

local log = Logger.scope("API")

local Ordnance = {}

Ordnance.Version = Version
Ordnance.Logger = Logger

------------------------------------------------------------------------------
-- Signals
------------------------------------------------------------------------------

-- Server: (info) after damage is applied. See Framework.Core.Events for the fields.
Ordnance.Damaged = Events.Damaged
-- Server: (info) when a hit kills.
Ordnance.Killed = Events.Killed
-- Server: (player, weaponId, origin, direction). Client: (weaponId, origin, direction).
Ordnance.Fired = Events.Fired
-- Server: (player, weaponId). Client: (weaponId).
Ordnance.Equipped = Events.Equipped
Ordnance.Unequipped = Events.Unequipped
Ordnance.Reloaded = Events.Reloaded
-- Both: (position, weaponId).
Ordnance.Exploded = Events.Exploded

------------------------------------------------------------------------------
-- Shared
------------------------------------------------------------------------------

-- Names of every loaded weapon, in alphabetical order.
function Ordnance.GetWeapons(): { string }
	return Registry.ids()
end

-- The resolved config of a weapon, or the global config when no name is given.
-- The table is frozen. Returns nil for a weapon that does not exist.
function Ordnance.GetConfig(weaponId: string?): Config.Config?
	if weaponId == nil then
		return Config.global()
	end
	local entry = Registry.get(weaponId)
	return if entry then entry.config else nil
end

--[[
	Attachment ids. Give a weapon id to list only what that weapon accepts,
	and a slot ("Optic", "Muzzle", "Underbarrel" or "Side") to list one slot.
]]
function Ordnance.ListAttachments(weaponId: string?, slot: string?): { string }
	local Attachments = require(Framework.Weapons.Attachments) :: any
	if weaponId == nil then
		return Attachments.ids(slot)
	end
	local entry = Registry.get(weaponId)
	if entry == nil then
		return {}
	end
	local result = {}
	for _, eachSlot in Attachments.Slots do
		if slot == nil or slot == eachSlot then
			for _, id in Registry.options(entry, eachSlot) do
				table.insert(result, id)
			end
		end
	end
	return result
end

------------------------------------------------------------------------------
-- Server
------------------------------------------------------------------------------

local function server(method: string): any
	if not IS_SERVER then
		log:Error(`Ordnance.{method} can only be called from the server`)
		return nil
	end
	return require(Framework.Server) :: any
end

--[[
	Fits an attachment to one of a player's weapons, or empties the slot when
	attachmentId is nil. The player keeps it for the rest of the session,
	through respawns. Returns false if the weapon does not accept it.

		Ordnance.SetAttachment(player, "G36C", "Optic", "RedDot")
]]
function Ordnance.SetAttachment(
	player: Player,
	weaponId: string,
	slot: string,
	attachmentId: string?
): boolean
	local module = server("SetAttachment")
	return if module then module.Sessions.setAttachment(player, weaponId, slot, attachmentId) else false
end

-- What is fitted to one of a player's weapons, as { [slot] = attachmentId }.
function Ordnance.GetAttachments(player: Player, weaponId: string): { [string]: string }
	local module = server("GetAttachments")
	return if module then module.Sessions.getAttachments(player, weaponId) else {}
end

-- Adds a weapon to a player's inventory.
function Ordnance.Give(player: Player, weaponId: string): boolean
	local module = server("Give")
	return if module then module.Sessions.give(player, weaponId) else false
end

-- Removes a weapon from a player's inventory.
function Ordnance.Take(player: Player, weaponId: string)
	local module = server("Take")
	if module then
		module.Sessions.take(player, weaponId)
	end
end

-- Puts a weapon in a player's hands.
function Ordnance.Equip(player: Player, weaponId: string): boolean
	local module = server("Equip")
	return if module then module.Sessions.equip(player, weaponId) else false
end

-- Puts away whatever a player is holding.
function Ordnance.Unequip(player: Player)
	local module = server("Unequip")
	if module then
		module.Sessions.unequip(player)
	end
end

-- Sets a player's rounds for a weapon. Leave either number out to keep it.
function Ordnance.SetAmmo(player: Player, weaponId: string, magazine: number?, reserve: number?)
	local module = server("SetAmmo")
	local entry = Registry.get(weaponId)
	if module == nil or entry == nil then
		return
	end
	local session = module.Sessions.get(player)
	if session == nil then
		return
	end
	local state = module.Sessions.state(session, entry)
	if magazine then
		state.mag = math.clamp(math.floor(magazine), 0, entry.config.Ammo.Magazine)
	end
	if reserve then
		state.reserve = math.max(0, reserve)
	end
	module.Sessions.sync(session, weaponId)
end

--[[
	Sets a function that sees every hit before damage is applied.
	Return a number to change the damage, false to cancel it, or nothing to
	leave it alone. Use it for armour, safe zones or team rules of your own.

		Ordnance.SetDamageHandler(function(info)
			if info.victim:GetAttribute("Armoured") then
				return info.damage * 0.5
			end
		end)
]]
function Ordnance.SetDamageHandler(handler: ((info: Events.DamageInfo) -> (number | boolean)?)?)
	local module = server("SetDamageHandler")
	if module then
		module.Combat.setDamageHandler(handler)
	end
end

------------------------------------------------------------------------------
-- Client
------------------------------------------------------------------------------

local function client(method: string): any
	if IS_SERVER then
		log:Error(`Ordnance.{method} can only be called from a client`)
		return nil
	end
	return require(Framework.Client) :: any
end

-- The name of the weapon the local player is holding, if any.
function Ordnance.GetEquipped(): string?
	local module = client("GetEquipped")
	return if module then module.getEquipped() else nil
end

-- (loaded rounds, reserve) of the held weapon, for custom HUDs.
function Ordnance.GetAmmo(): (number?, number?)
	local module = client("GetAmmo")
	if module then
		return module.getAmmo()
	end
	return nil, nil
end

function Ordnance.IsAiming(): boolean
	local module = client("IsAiming")
	return if module then module.isAiming() else false
end

--[[
	Gives the local player their own crosshair, laid over the game's for every
	weapon. Takes the same fields as the Crosshair config section; pass nil to
	go back to the game's.

		Ordnance.SetCrosshair({ Style = "Circle", Color = Color3.new(0, 1, 0) })
]]
function Ordnance.SetCrosshair(settings: { [string]: any }?)
	local module = client("SetCrosshair")
	if module then
		module.setCrosshair(settings)
	end
end

------------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------------

-- Whoever requires this module first starts the framework, so game scripts
-- never see it half-initialised.
if IS_RUNNING then
	if IS_SERVER then
		(require(Framework.Server) :: any).start(script)
	else
		(require(Framework.Client) :: any).start(script)
	end
end

return Ordnance
