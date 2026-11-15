title: Scripting API
nav: Scripting API
description: The Ordnance scripting API: give and equip weapons, set ammo, change damage, and listen for shots, hits and kills.
order: 6
---

# Scripting API

You never have to require Ordnance: it starts by itself. Require it when your game wants to hand out weapons, react to hits or change damage.

```lua
local Ordnance = require(game.ReplicatedStorage.Ordnance)
```

Calling a server function from a client, or the other way round, logs an error and does nothing. It never throws.

## Examples {#examples}

:::pair
```lua ServerScriptService.KillFeed
local Ordnance = require(game.ReplicatedStorage.Ordnance)

Ordnance.Killed:Connect(function(info)
	local killer = info.attacker and info.attacker.Name or "The world"
	local victim = info.victimPlayer and info.victimPlayer.Name or info.victim.Parent.Name
	print(`{killer} killed {victim} with {info.weapon}`)
end)
```
```lua ServerScriptService.Armour
local Ordnance = require(game.ReplicatedStorage.Ordnance)

Ordnance.SetDamageHandler(function(info)
	if info.victim.Parent:GetAttribute("SafeZone") then
		return false
	end
	if info.group == "Torso" and info.victim:GetAttribute("Vest") then
		return info.damage * 0.6
	end
end)
```
:::

A class-based loadout, with `Inventory.Mode = "Custom"` so nothing is handed out automatically:

```lua ServerScriptService.Loadouts
local Players = game:GetService("Players")
local Ordnance = require(game.ReplicatedStorage.Ordnance)

local CLASSES = {
	Assault = { "G36C", "Glock17" },
	Marksman = { "Remington700", "Glock17" },
}

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		local class = player:GetAttribute("Class") or "Assault"
		for _, weapon in CLASSES[class] do
			Ordnance.Give(player, weapon)
		end
		Ordnance.Equip(player, CLASSES[class][1])
	end)
end)
```

## Shared {#shared}

### GetWeapons {#getweapons}

```lua
Ordnance.GetWeapons(): { string }
```

The ids of every loaded weapon, alphabetically. An id is the weapon module's name.

### GetConfig {#getconfig}

```lua
Ordnance.GetConfig(weaponId: string?): Config?
```

A weapon's resolved config, after every layer and `Tuning` has been applied, or the global config when no id is given. The table is frozen; read it, do not write it. Returns nil for a weapon that does not exist.

```lua
local glock = Ordnance.GetConfig("Glock17")
print(glock.Ammo.Magazine, glock.Damage.Base) -- 17 26
```

### ListAttachments {#listattachments}

```lua
Ordnance.ListAttachments(weaponId: string?, slot: string?): { string }
```

Attachment ids. Give a weapon id for only the ones that weapon accepts, and a slot (`"Optic"`, `"Muzzle"`, `"Underbarrel"` or `"Side"`) for one slot. Use it to build your own loadout screen.

### Version

`Ordnance.Version` is the framework's version string, such as `"{{version}}"`.

## Server {#server}

Weapons a player is given last for that life. A new character starts with full ammunition, nothing in hand and, in `Tool` mode, the loadout from `Inventory.Loadout`. In `Custom` mode give weapons again from `CharacterAdded`.

### Give {#give}

```lua
Ordnance.Give(player: Player, weaponId: string): boolean
```

Adds a weapon to a player's inventory, with full ammunition. In `Tool` mode it appears in their Backpack. Giving a weapon they already have does nothing. Returns false if no weapon has that id.

### Take {#take}

```lua
Ordnance.Take(player: Player, weaponId: string)
```

Removes a weapon, unequipping it first if it is in their hands.

### Equip {#equip}

```lua
Ordnance.Equip(player: Player, weaponId: string): boolean
```

Puts a weapon in the player's hands, giving it first if they do not have it. Returns false if they have no character, or no weapon has that id.

### Unequip {#unequip}

```lua
Ordnance.Unequip(player: Player)
```

Puts away whatever the player is holding.

### SetAmmo {#setammo}

```lua
Ordnance.SetAmmo(player: Player, weaponId: string, magazine: number?, reserve: number?)
```

Sets the rounds loaded and in reserve. Leave either out to keep it. The magazine is clamped to the weapon's capacity. The player's client is corrected straight away.

```lua
-- An ammo crate: top up the reserve of whatever they are holding.
Ordnance.SetAmmo(player, weaponId, nil, 120)
```

### SetAttachment {#setattachment}

```lua
Ordnance.SetAttachment(player: Player, weaponId: string, slot: string, attachmentId: string?): boolean
```

Fits an [attachment](attachments.html) to one of a player's weapons, or empties the slot when `attachmentId` is nil. The weapon is rebuilt with it straight away, in their hands if it was there. The player keeps it for the rest of their session, through respawns. Returns false if the weapon does not accept it.

```lua
-- A loadout screen sends the player's choice; check it is theirs to make first.
Ordnance.SetAttachment(player, "G36C", "Optic", "ACOG")
```

### GetAttachments {#getattachments}

```lua
Ordnance.GetAttachments(player: Player, weaponId: string): { [string]: string }
```

What is fitted to one of a player's weapons, as `{ [slot] = attachmentId }`. Save it to a DataStore and pass it back to `SetAttachment` when they rejoin.

### SetDamageHandler {#setdamagehandler}

```lua
Ordnance.SetDamageHandler(handler: ((info: DamageInfo) -> number | false | nil)?)
```

Sets one function that sees every hit before damage is applied, bullets and explosions alike. Return a number to change the damage, `false` to cancel it, or nothing to leave it alone. Pass nil to remove it. An error inside the handler is reported and the hit goes ahead unchanged.

## Client {#client}

For custom HUDs and client effects, from a LocalScript.

### GetEquipped {#getequipped}

```lua
Ordnance.GetEquipped(): string?
```

The id of the weapon the local player is holding, or nil.

### GetAmmo {#getammo}

```lua
Ordnance.GetAmmo(): (number?, number?)
```

Rounds loaded and in reserve for the held weapon. With chambering on, the loaded count includes the chambered round.

### IsAiming {#isaiming}

```lua
Ordnance.IsAiming(): boolean
```

### SetCrosshair {#setcrosshair}

```lua
Ordnance.SetCrosshair(settings: { [string]: any }?)
```

Gives the local player their own crosshair, laid over the game's [Crosshair settings](config.html#crosshair) for every weapon. It takes the same fields; anything left out keeps the game's value. Pass nil to go back to the game's. Invalid fields are reported in the output and ignored. Nothing is saved: store the choice yourself (a DataStore, an attribute) and call this again when the player joins.

```lua LocalScript
local Ordnance = require(game.ReplicatedStorage.Ordnance)

Ordnance.SetCrosshair({
	Style = "Circle",
	Color = Color3.fromRGB(120, 255, 160),
	AimStyle = "Dot",
})
```

## Signals {#signals}

Connect with `:Connect(handler)`, which returns a connection with `:Disconnect()`. `:Once` and `:Wait` work too. Handlers run in their own thread, so an error in one never stops the others.

The server and each client have their own copy of every signal. On the server, `Fired` means the server accepted a shot; on a client it means the local player fired.

### Damaged {#damaged}

Server. `(info: DamageInfo)` after damage has been applied.

### Killed {#killed}

Server. `(info: DamageInfo)` when that damage killed.

### Fired {#fired}

Server: `(player, weaponId, origin, direction)`. Client: `(weaponId, origin, direction)`.

### Equipped {#equipped}

Server: `(player, weaponId)`. Client: `(weaponId)`.

### Unequipped {#unequipped}

Same arguments as `Equipped`.

### Reloaded {#reloaded}

Same arguments as `Equipped`, when a reload starts.

### Exploded {#exploded}

Both sides: `(position: Vector3, weaponId)`.

### DamageInfo {#damageinfo}

| Field | Type | Meaning |
|---|---|---|
| `attacker` | `Player?` | Who fired. |
| `victim` | `Humanoid` | What was hit. Works for NPCs as well as players. |
| `victimPlayer` | `Player?` | The victim's player, if they have one. |
| `weapon` | `string` | The weapon's id. |
| `damage` | `number` | The damage, after multipliers and falloff. |
| `part` | `string` | The name of the body part hit. |
| `group` | `string` | `"Head"`, `"Torso"` or `"Limb"`. |
| `distance` | `number` | Studs from the shooter. |
| `position` | `Vector3` | Where the hit landed. |
| `explosive` | `boolean` | True for blast damage. |

## Logging {#logging}

Everything Ordnance prints is tagged `[Ordnance:Scope]`, so it can be filtered in the Output window. How much it prints, and whether a framework error warns or throws, is set under [`Debug.Logger`](config.html#debug). `Ordnance.Logger` is the same logger, for your own scripts that want to match.
