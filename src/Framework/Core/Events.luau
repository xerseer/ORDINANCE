--!strict
--[[
	Events
	The signals games can listen to. Exposed on the public API as
	Ordnance.Damaged, Ordnance.Fired and so on.

	Server and client each have their own copy; "Fired" on the server means the
	server accepted a shot, on the client it means the local player fired.
]]

local Signal = require(script.Parent.Signal)

export type DamageInfo = {
	attacker: Player?,
	victim: Humanoid,
	victimPlayer: Player?,
	weapon: string,
	damage: number,
	part: string,
	group: string,
	distance: number,
	position: Vector3,
	explosive: boolean,
}

local Events = {
	-- (info: DamageInfo) after damage has been applied. Server only.
	Damaged = Signal.new() :: Signal.Signal<DamageInfo>,
	-- (info: DamageInfo) when the damage killed. Server only.
	Killed = Signal.new() :: Signal.Signal<DamageInfo>,
	-- Server: (player, weaponId, origin, direction). Client: (weaponId, origin, direction).
	Fired = Signal.new() :: Signal.Signal<...any>,
	-- Server: (player, weaponId). Client: (weaponId).
	Equipped = Signal.new() :: Signal.Signal<...any>,
	Unequipped = Signal.new() :: Signal.Signal<...any>,
	Reloaded = Signal.new() :: Signal.Signal<...any>,
	-- (position, weaponId) on both sides.
	Exploded = Signal.new() :: Signal.Signal<Vector3, string>,
}

return Events
