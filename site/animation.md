title: Animation
description: How Ordnance animates weapons and arms: procedural motion from attachments, encoded keyframes stored as numbers, sway, and how first and third person, R6 and R15 are handled.
order: 5
---

# Animation

Weapons animate without uploading a single animation asset. Motion is either worked out from the weapon's attachments, or written as numbers in its module.

## Two systems {#systems}

| `Animation.Mode` | What plays |
|---|---|
| `Procedural` | Motion built from the weapon's attachments. Every weapon gets it for free. |
| `Encoded` | Only the keyframe tables in the weapon's `Animations`. Actions without one do not move. |
| `Both` | The default. An encoded animation where the weapon has one, procedural motion where it does not. |

Both systems produce the same thing: where the weapon is, where each hand grips, and where each moving part sits. So they can stand in for each other action by action, and the arms are solved the same way whichever one ran.

## Procedural {#procedural}

From a model and a few [attachments](weapons.html#attachments), a weapon equips, reloads, cycles and kicks without any keyframes.

- The trigger hand holds `MainHandle`; the support hand rests on `Grip`.
- On a magazine reload the support hand goes to `Mag`, and a part named `Mag` drops out and comes back.
- On a single-round reload the hand feeds shells at `Mag`, one per `ShellTime`.
- On a bolt or pump cycle a hand works `Side` (or the grip), and parts named `Bolt`, `Slide` or `Pump` travel with it.
- On every shot `Bolt` and `Slide` snap back.

Better attachments make better motion. The plugin's [IK Helper](plugin.html#helper) shows what a model is missing.

## Encoded {#encoded}

An encoded animation is a table of keyframes in the weapon's module. Nothing is uploaded, so it ships with the weapon wherever the module goes.

```lua Weapons.Glock17 (part)
Animations = {
	Reload = {
		Keyframes = {
			{ Time = 0, Weapon = { 0, 0, 0, 0, 0, 0 }, Left = { 0, 0, 0, 0, 0, 0 }, Mag = { 0, 0, 0, 0, 0, 0 } },
			{ Time = 0.18, Weapon = { 0.05, 0.05, 0.06, 20, 0, -24 }, Easing = "SineOut" },
			{ Time = 0.46, Left = { -0.2, -1.3, 0.25, 0, 0, 0 }, Mag = { 0, -1.5, 0.15, 0, 0, 0 }, Easing = "QuadIn" },
			{ Time = 0.78, Left = { 0, -0.3, 0.02, 0, 0, 0 }, Mag = { 0, 0, 0, 0, 0, 0 }, Easing = "BackOut" },
			{ Time = 1, Weapon = { 0, 0, 0, 0, 0, 0 }, Left = { 0, 0, 0, 0, 0, 0 }, Easing = "Sine" },
		},
	},
},
```

### Values {#values}

Every value is six numbers: position x, y, z in studs (right, up, back), then rotation x, y, z in degrees, in the same order as a part's Orientation. Each is an offset from rest, so six zeros always means "where it normally is".

### Channels {#channels}

| Channel | Moves |
|---|---|
| `Weapon` | The whole weapon, relative to where it is held. |
| `Right`, `Left` | Each hand, relative to its grip. The arms follow. |
| any other name | The part of the weapon model with that name: `Mag`, `Slide`, `Bolt`, a dust cover. |

A keyframe only lists the channels that change at that time. Between keyframes each channel eases from its last value.

### Keyframe fields {#keyframe-fields}

| Field | Meaning |
|---|---|
| `Time` | Seconds from the start. Required. |
| `Easing` | How this keyframe is approached: any `Enum.EasingStyle` name, optionally followed by `In`, `Out` or `InOut`. `Sine`, `QuadOut`, `BackOut`. Defaults to `Sine`, in and out. |
| `Sound` | An asset id played when the keyframe is reached. |

### Which animations play {#slots}

| Name | Plays |
|---|---|
| `Equip` | When the weapon is drawn. |
| `Reload` | For a reload. |
| `ReloadEmpty` | For a reload from empty, if the weapon has one; otherwise `Reload`. |
| `Cycle` | For a bolt or pump cycle, and when clearing a jam. |
| `Fire` | From the start on every shot, on top of whatever else is playing. |
| `Idle` | Looped the whole time the weapon is held. |

An animation is stretched to fit the action it plays for (`Reload` to the reload time, `Cycle` to `CycleTime`), so only the proportions of its times matter and changing `ReloadTime` never breaks it. Set `Fit = false` to play it at its written speed. `Length` overrides its length and `Loop = true` repeats it.

A keyframe the framework cannot read is reported and skipped; the rest of the animation still plays.

### From Roblox animations {#converter}

The plugin's [Converter](plugin.html#converter) turns a KeyframeSequence, from the Animation Editor or any tool that saves one, into an `Animations` entry, and can add it to the weapon module for you.

## Sway {#sway}

In first person the weapon is held, not bolted to the camera. Six small motions, each with its own multiplier under [`Sway`](config.html#sway):

- **Mouse**: the weapon lags behind when you look around.
- **Bob**: it bobs in step while you walk.
- **Breath**: it drifts while you stand still.
- **Landing**: it dips when you land.
- **Tilt**: it rolls into a strafe.
- **Kick**: it jumps in the hands with every shot.

All run on springs, and all but the kick shrink while aiming.

## First and third person {#views}

**First person** draws a copy of the weapon and of the player's own arms at the camera, so the arms match their rig, skin and, with `Viewmodel.Sleeves`, their shirt. Nothing is pre-built or uploaded. The copy is local and cannot be hit.

**Third person** is what everyone else sees, and what you see when zoomed out. Every client poses every visible character that holds a weapon: the trigger hand on the grip, the support hand on the weapon, the arms and (on R15) the upper body following where the player aims. Only a little state is replicated per player (aim pitch, whether they are aiming, which action started), so this costs almost no bandwidth.

`Camera.Mode` decides which views are allowed while a weapon is held: `Both` follows the player's zoom, `FirstPerson` and `ThirdPerson` lock it.

## R15 and R6 {#rigs}

Arms are solved with inverse kinematics on both rigs, with Motor6D joints or the newer AnimationConstraint joints.

- **R15** arms are two bones, so the elbow bends naturally and the hand lands exactly on the grip. The upper body turns side-on and leans with the aim.
- **R6** arms are a single block each. The trigger arm lines up with the weapon as a Roblox Tool does, and the support arm points at its grip from the shoulder.

> Limit: an R6 torso is one piece, so R6 characters cannot turn or lean their upper body, and an R6 arm may slide out of its shoulder to reach a grip. That is the accepted look for R6 weapons.

> Limit: in third person the weapon is welded to the trigger hand, as every Roblox Tool is. The trigger hand therefore never leaves the grip there, so a bolt is worked by the right hand only in first person.

With a long rifle an R15 support arm may fall a little short of the handguard; it then holds the weapon as far forward as it reaches.
