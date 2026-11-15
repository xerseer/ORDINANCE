title: Attachments
description: Scopes, sights, suppressors, grips, flashlights and lasers: how attachments are made, how they change a weapon, and how players and games fit them.
order: 2.5
---

# Attachments

An attachment is a module in `Ordnance.Attachments` with its model inside it, like a weapon. It goes in one of four slots, and when it is fitted it sits on the weapon, in first and third person, and changes the weapon's settings.

| Slot | For | Takes over from the weapon |
|---|---|---|
| `Optic` | Red dots, holographic sights, scopes | The sight line (`Aim`) |
| `Muzzle` | Suppressors, brakes | The muzzle (`Barrel`) |
| `Underbarrel` | Foregrips | Where the support hand holds (`Grip`) |
| `Side` | Flashlights and lasers | Nothing |

Ordnance ships with eight, made from the attachment kit: `RedDot`, `Holographic`, `ACOG`, `SniperScope`, `Suppressor`, `VerticalGrip`, `Flashlight` and `Laser`.

## The module {#module}

```lua Attachments.ACOG
return {
	Name = "Trijicon ACOG 4x",
	Slot = "Optic",
	Config = {
		Handling = { AimFOV = 24, AimTime = 0.26 },
	},
}
```

`Config` is laid over the weapon's own settings, with the same fields as a weapon module, so an attachment can change anything a weapon can except its name and model. `Tuning` is multiplied onto the weapon's [tuning](config.html#tuning) instead of replacing it, so a grip that takes 15% off recoil does so on every weapon:

```lua Attachments.VerticalGrip
return {
	Name = "Vertical Grip",
	Slot = "Underbarrel",
	Tuning = { Recoil = 0.85, Spread = 0.95 },
}
```

The server reads the same combined settings, so an attachment that tightens spread is checked against the tighter spread. Settings live in the module, not the model, so a client cannot fit itself a better one.

### Lights, lasers and scopes {#behaviour}

Three optional tables give an attachment something to do. The Light key (`G` by default) switches lights and lasers on and off, and everyone sees them.

| Field | Settings | Does |
|---|---|---|
| `Light` | `Brightness`, `Range`, `Angle`, `Color` | A spotlight from the Emitter. |
| `Laser` | `Color`, `Width`, `Range` | A beam from the Emitter to whatever it points at, with a dot where it lands. |
| `Scope` | `Reticle`, `Overlay` | Once aimed in first person, the screen shows the view through the scope and the weapon is hidden. Pair it with a low `Handling.AimFOV`. |

```lua Attachments.Flashlight
return {
	Name = "SureFire Scout Light",
	Slot = "Side",
	Light = { Brightness = 5, Range = 55, Angle = 45 },
}
```

## The model {#model}

Face it the same way as a weapon: front toward −Z, top toward +Y. Attachments mark the places that matter, and anything missing is worked out from the model's shape:

| Attachment | Marks | Without it |
|---|---|---|
| `Mount` | The point that sits on the weapon. | The face that touches it: the bottom of an optic, the back of a muzzle device, the top of a grip, the left of a side attachment. |
| `Aim` | The sight line through an optic, at the back. | A little above the middle, at the back. |
| `Barrel` | The new muzzle, on a muzzle device. | The front. |
| `Grip` | Where the support hand holds a grip. | Just below the middle. |
| `Emitter` | Where a light or laser shines from, facing forward. | The front. |

An attachment is not resized with the weapon. Give it `Scale = 0.8` (in the module) if it is too big for a weapon set.

## On the weapon {#mounts}

A weapon can mark where each slot sits with `OpticMount`, `MuzzleMount`, `UnderMount` and `SideMount` attachments, facing forward. Without them the places are worked out: an optic on top of the receiver a little ahead of the grip, a muzzle device on the barrel, a grip under the handguard and a side attachment on the right of it. Mark them by hand where that guess is wrong; the plugin's [IK Helper](plugin.html#helper) shows where they are.

Which attachments a weapon accepts, and what it comes with, are weapon settings:

```lua Weapons.Glock17 (part)
Attachments = {
	Allowed = {
		Optic = { "RedDot" },
		Underbarrel = {}, -- no foregrip on a pistol
	},
	Default = { Side = "Flashlight" },
},
```

A slot left out of `Allowed` accepts every attachment for that slot. See the [Attachments settings](config.html#attachments).

## Fitting them {#fitting}

Players open the attachment menu with `T` and pick from what their weapon accepts. Turn that off with `Attachments.Menu = false` and fit them from your own scripts instead, for a loadout screen or an unlock system:

```lua Script
local Ordnance = require(game.ReplicatedStorage.Ordnance)

Ordnance.SetAttachment(player, "G36C", "Optic", "ACOG")
print(Ordnance.GetAttachments(player, "G36C")) --> { Optic = "ACOG" }
```

What a player has fitted lasts their session, through respawns. To keep it between sessions, save [`GetAttachments`](api.html#getattachments) and call [`SetAttachment`](api.html#setattachment) again when they join.

> Limit: A scope's view is the camera zoomed in with a picture over the screen. Roblox draws one camera at a time, so there is no true picture-in-picture lens with the world sharp around it.
