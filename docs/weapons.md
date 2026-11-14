title: Weapons
description: How to make an Ordnance weapon: the module, the model and its attachments, and the settings for each kind of gun.
order: 2
---

# Weapons

A weapon is a ModuleScript in `Ordnance.Weapons` with its model inside it. Drop one in and it loads at the next Play. There is no list to register it in.

## The module {#module}

The module returns a table of settings. Only write what differs from the global config; everything else falls through to it, and from there to the defaults.

```lua Weapons.Glock17
return {
	Name = "Glock 17",
	Description = "9mm semi-automatic pistol.",
	Fire = { Modes = { "Semi" }, RPM = 420 },
	Ammo = { Magazine = 17, Reserve = 68, ReloadTime = 1.6 },
	Damage = { Base = 26, Falloff = { Start = 60, End = 220 } },
	Recoil = { Vertical = 1.4, Horizontal = 0.5 },
}
```

The module's name is the weapon's id: what the scripting API, the loadout and the logs call it. `Name` is what players see. Leave `Name` out and the id is used.

Folders inside `Weapons` are fine for organising; only ModuleScripts are weapons. ModuleScripts inside a weapon belong to it and are not loaded as weapons of their own.

## The model {#model}

Put the model inside the module and call it `Model`, or point `Model` at a different child by name. It needs very little:

- **A part named `Handle`**, or a `PrimaryPart`. Its front face (−Z) points down the barrel and its top face (+Y) points up. This is the one thing that has to be right.
- **Everything else is joined to the handle for you** when the weapon loads. Models do not need welds, and anchored parts are fine: they are unanchored when the weapon is built. Parts you have already jointed yourself keep their joints.

The model can also be a single part, a Tool or a Folder of parts. A weapon with no model at all gets a plain block gun, so you can try out numbers before the art exists.

The handle's orientation is how the framework knows which way the weapon faces. If shots leave from the stock or the gun is held sideways, the handle is turned the wrong way; rotate the part, not the model.

### Attachments {#attachments}

Attachments on the handle tell the animation system where things are. All are optional; missing ones are worked out from the model's shape. The plugin's [IK Helper](plugin.html#helper) checks a model and places any that are missing.

| Attachment | What it marks | Without it |
|---|---|---|
| `MainHandle` | Where the trigger hand holds. | The handle's centre. |
| `Barrel` | The muzzle. Shots, tracers and the flash start here. `Muzzle` is accepted too. | The furthest-forward point of the model. |
| `Grip` | Where the support hand rests. | The support hand cups the trigger hand, as on a pistol. |
| `Mag` | The magazine. The support hand goes here to reload. | The reload has no hand motion. |
| `Side` | The bolt or charging handle. | Bolts and pumps are worked from the grip. |
| `Aim` | The sight line, centred behind the sight, facing forward. | The weapon is raised toward the centre, roughly. |

Attachment names are only matched against Attachments. A part called `Barrel` and an attachment called `Barrel` can sit side by side.

### Moving parts {#moving-parts}

Parts with these names move by themselves. Give the part the name and nothing else is needed.

| Part | Moves |
|---|---|
| `Mag` | Drops out and comes back during a magazine reload. |
| `Bolt`, `Slide` | Snap back on every shot, and travel with the hand on a cycle. |
| `Pump` | Slides back and forward with the support hand. |

An [encoded animation](animation.html#encoded) can move any other part by naming it.

## Firing {#firing}

`Fire.Modes` is the list the fire-mode key steps through; `Fire.Mode` is where it starts. If the starting mode is not in the list, the first mode in the list is used.

| Mode | Behaviour |
|---|---|
| `Semi` | One round per trigger pull. |
| `Burst` | `Fire.BurstCount` rounds at `Fire.BurstRPM` (or `RPM` when that is 0). |
| `Auto` | Fires at `Fire.RPM` while held. |
| `Safe` | Does not fire. Useful as a position in the list. |

A trigger pull made a moment too early, before the next round is ready, is remembered for `Fire.InputBuffer` seconds, so fast clicking does not eat shots.

### Actions {#actions}

`Fire.Action` decides what happens between shots.

- `SelfLoading` cycles by itself. Pistols, rifles, machine guns.
- `Bolt` and `Pump` need a cycle after every shot, which takes `Fire.CycleTime` seconds. The cycle runs by itself unless `Realism.ManualCycle` is on, in which case the player presses the Cycle key.

### Pellets {#pellets}

`Fire.Pellets` above 1 makes a shotgun: every pellet is its own ray with its own damage. The pattern comes from a seed the server and the client share, so it is never sent over the network and cannot be forged.

## Ammunition {#ammo}

| You want | Set |
|---|---|
| A magazine swap | `ReloadType = "Magazine"`, with `ReloadTime`, and optionally a longer `ReloadEmptyTime`. |
| Shells one at a time | `ReloadType = "Single"`, with `ShellTime` per round. Firing interrupts the reload. |
| No reserve to manage | `Infinite = true`. |
| Unlimited spare rounds | `Reserve = math.huge`. |
| The trigger to reload an empty gun | `AutoReload = true` (the default). |

The realism options change how rounds are counted, and are all off by default:

- `Realism.Chambering`: the round in the chamber is separate from the magazine, so a reload before empty ends with one extra (30 + 1).
- `Realism.DropMagazine`: rounds left in a swapped magazine are lost, not returned to the reserve.
- `Realism.Malfunctions`: a shot can jam the weapon at `Chance` per shot. The Cycle key clears it.

## Ballistics {#ballistics}

### Hitscan {#hitscan}

The default. A round hits instantly along a ray up to `Ballistics.Range` studs. With `Ballistics.Penetration` above 0 it passes through that many studs of material in total. Damage drops with every stud crossed: a round that uses its whole allowance keeps 40% of its damage.

Bullets ignore parts with CanCollide off (decorations, invisible triggers), but still hit characters.

### Projectile {#projectile}

`Ballistics.Type = "Projectile"` fires something that flies: it leaves at `Velocity`, falls under `workspace.Gravity × Gravity`, slows with `Drag`, and is removed after `Lifetime` seconds. It can bounce (`Bounce.Count`), and it can explode.

```lua Weapons.M203 (part)
Ballistics = {
	Type = "Projectile",
	Velocity = 190,
	Drag = 0.05,
	Explosive = {
		Enabled = true,
		Damage = 140,
		Radius = 20,
		DetonateOnImpact = true,
		SelfDamageScale = 0.6,
	},
},
```

For a timed, bouncing grenade instead, turn impact detonation off and give it a fuse:

```lua
Explosive = { Enabled = true, DetonateOnImpact = false, Fuse = 3 },
Bounce = { Count = 4 },
```

Explosions hurt everyone in `Radius` with a clear line to the centre (turn that off with `RequireLineOfSight = false`), fading from `Damage` toward `Damage × MinScale` at the edge.

## Damage {#damage}

A hit's damage is `Damage.Base`, times the multiplier for the body part hit (`Head`, `Torso` or `Limb`), times the falloff for its distance:

- up to `Falloff.Start` studs, full damage;
- between `Start` and `End`, it drops in a straight line;
- from `End` on, `Base × Falloff.MinScale`.

`Damage.FriendlyFire = false` stops players on the same team hurting each other. For anything else (armour, safe zones, your own team rules) use [`SetDamageHandler`](api.html#setdamagehandler).

## Feel {#feel}

- **Spread** is a cone, in degrees from the centre: `Hip` or `Aim`, plus `Moving` and `Airborne` while those apply, plus `PerShot` for each round fired, capped at `Max` and recovering at `Recovery` degrees per second.
- **Recoil** kicks the camera by `Vertical` and up to `Horizontal` degrees per shot, and returns `Recovery` of the way back. `Speed` and `Damping` shape the spring.
- **Handling** covers equip and aim time, the aimed field of view, and walk speed while holding and aiming.

Offsets for how the weapon is held (`Viewmodel.Offset`, `ThirdPerson.Offset`, `ThirdPerson.AimOffset`) are six numbers: position right, up and back in studs, then rotation in degrees. A pistol is held further out and nearer the middle than a rifle; the Glock example shows the numbers.

## The examples {#examples}

{{weapons}}

### A complete weapon module {#complete}

The bolt-action rifle, with the realism options on:

{{source src/Weapons/Remington700/init.luau}}
