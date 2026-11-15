title: Configuration
description: Every Ordnance setting with its default, the values it accepts and what it does, generated from the framework's own schema.
order: 3
---

# Configuration

Every setting, its default, and what it accepts. This page is generated from the framework's schema, so it always matches the version you download.

## How it works {#how}

There is one shape of config. `Ordnance.Config`, every preset and every weapon module are partial copies of it, layered lowest to highest:

<div class="tree">Defaults  <span class="dim">&lt;</span>  Preset  <span class="dim">&lt;</span>  Ordnance.Config  <span class="dim">&lt;</span>  the weapon's module</div>

Write only what you change. Tables merge setting by setting, so `Damage = { Base = 30 }` keeps the default multipliers and falloff. Lists are the exception: `Fire.Modes` or a keybind list replaces the one below it whole.

```lua Ordnance.Config
return {
	Preset = "Tactical",

	Keybinds = { Reload = { "R", "ButtonX" } },
	HUD = { Accent = Color3.fromRGB(230, 120, 80) },
	Inventory = { Loadout = { "Glock17", "G36C" } },
}
```

Nothing here can break the game. A wrong type, an out-of-range number or a misspelt name is reported in the Output window with its path, and the value is clamped or left out so the default applies. The Studio plugin's [Config tab](plugin.html#config) edits this file with a form and checks each value as you enter it.

### Global and per-weapon {#scope}

Most settings work in both places: set them globally for every weapon, or in one weapon's module for just that one. A few only make sense once:

- `Inventory`, `Security` and `Debug` are global only. A weapon that sets them is told so and ignored.
- `Name`, `Description`, `Model`, `Custom` and `Animations` belong in a weapon module.

### Tuning {#tuning}

`Tuning` multiplies a weapon's own numbers: damage, recoil, spread, reload time, fire rate. Set it globally, or in a preset, to rebalance the whole game without touching a single weapon. Like any setting, the deepest layer wins: a weapon that sets `Tuning.Damage` replaces the global value for that weapon rather than multiplying it.

<div class="filter"><input type="search" placeholder="Filter settings (press /)" aria-label="Filter settings"><span class="count"></span></div>

## Identity {#identity}

Top-level settings.

{{config-identity}}

## Fire {#fire}

How the trigger behaves. See [Firing](weapons.html#firing).

{{config Fire}}

## Ammo {#ammo}

Rounds and reloading. See [Ammunition](weapons.html#ammo).

{{config Ammo}}

## Ballistics {#ballistics}

What leaves the barrel. `Range` and `Penetration` apply to hitscan; `Velocity` to `Lifetime`, `Bounce` and `Explosive` to projectiles.

{{config Ballistics}}

## Damage {#damage}

Per round, or per pellet for a shotgun.

{{config Damage}}

## Spread {#spread}

Accuracy, in degrees from the centre of the cone.

{{config Spread}}

## Recoil {#recoil}

Camera kick per shot.

{{config Recoil}}

## Handling {#handling}

{{config Handling}}

## Realism {#realism}

Opt-in. Everything is off by default; the Realistic preset turns it all on.

{{config Realism}}

## Tuning {#tuning-ref}

Multipliers on the numbers above. 1 changes nothing.

{{config Tuning}}

## Camera {#camera}

{{config Camera}}

## Scope {#scope}

For a weapon whose model has a scope built in, such as the example sniper rifles: once it is aimed in first person the screen shows the view through the lens and the weapon is hidden. A [scope attachment](attachments.html#behaviour) does the same for any weapon it is fitted to.

{{config Scope}}

## Viewmodel {#viewmodel}

The first-person weapon and arms. Offsets are six numbers: position right, up and back in studs, then rotation x, y, z in degrees.

{{config Viewmodel}}

## Third person {#thirdperson}

How a character holds the weapon, as everyone else sees it.

{{config ThirdPerson}}

## Animation {#animation}

See [Animation](animation.html).

{{config Animation}}

## Sway {#sway}

First-person weapon sway. Each motion is a multiplier: 0 turns it off, 2 doubles it.

{{config Sway}}

## Keybinds {#keybinds}

Each action takes a list of `Enum.KeyCode` or `Enum.UserInputType` names, keyboard, mouse and gamepad together. Touch devices get on-screen buttons for the same actions.

{{config Keybinds}}

## Controls {#controls}

{{config Controls}}

## Effects {#effects}

Sounds accept any asset id. The default gunshot comes from Roblox's licensed Pro Sound Effects library, which any experience may use; the other defaults ship with Studio. The example weapons each set their own fire sound.

{{config Effects}}

## HUD {#hud}

The built-in display is small on purpose: ammo, fire mode, a reload bar, a crosshair that opens with spread, and a hitmarker. Turn it off and build your own from the [client API](api.html#client) if your game needs more.

{{config HUD}}

## Crosshair {#crosshair}

How the crosshair looks, set in the global config, a preset or a single weapon (a shotgun can have a ring while rifles keep a cross). When aiming it becomes a small dot by default, and disappears in first person on a weapon that has a sight to look through: an `Aim` attachment for its iron sights, or an optic.

```lua Ordnance.Config
Crosshair = {
	Style = "T",
	Color = Color3.fromRGB(120, 255, 160),
	Length = 6,
	Gap = 3,
	CenterDot = true,
},
```

Players can have their own: call [`SetCrosshair`](api.html#setcrosshair) from a settings menu and their choices are laid over the game's for every weapon.

{{config Crosshair}}

## Attachments {#attachments}

Which [attachments](attachments.html) a weapon accepts and comes with, and whether players can change them in game. Set it in a weapon module; set `Menu` in the global config to decide for the whole game.

{{config Attachments}}

## Inventory {#inventory}

In `Tool` mode every weapon is a Backpack Tool, so the hotbar, gamepad and mobile all work as players expect. In `Custom` mode nothing is handed out, and your code gives and equips weapons with the [server API](api.html#server).

{{config Inventory}}

## Security {#security}

How strictly the server checks shots. The defaults suit most games; see [Security](security.html) before changing them.

{{config Security}}

## Debug {#debug}

{{config Debug}}
