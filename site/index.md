title: Ordnance
nav: Start here
description: A modular gun framework for Roblox. One object in ReplicatedStorage gives you working, server-checked weapons; open the config when you want more.
order: 1
---

# Ordnance

A modular gun framework for Roblox. Put one object in ReplicatedStorage and you have working weapons. Open the config when you want more.

<p class="actions"><a class="btn" href="https://github.com/xerseer/ORDINANCE/releases" target="_blank" rel="noopener">Download v{{version}}&nbsp;↗</a> <a class="btn plain" href="weapons.html">Make a weapon →</a></p>

## What you get {#what}

- **One object.** Everything lives in `ReplicatedStorage.Ordnance`. Nothing goes in ServerScriptService or StarterPlayer, and deleting the object removes the framework completely.
- **Nothing to configure first.** Every setting has a default. A weapon can be a model and a name.
- **As deep as you want to go.** Fire modes, chambered rounds, bolt and pump actions, jams, projectiles with drop and bounce, explosives, penetration. Every one of them is opt-in, per weapon.
- **The server decides what was hit.** The client predicts so shooting feels instant; the server checks every shot against where players were when it was fired.
- **First and third person, R6 and R15.** Arms are solved onto the weapon in both views, on both rigs, from the player's own character.
- **Animations without uploads.** Weapons move procedurally from a few attachments, or play keyframes written as numbers in the weapon's module.
- **It does not take your game down.** Errors in a weapon or a config are reported and skipped. Nothing the framework does is allowed to throw into your code.

## Install {#install}

Pick one. They give the same result.

### With the Studio plugin

1. Download `OrdnancePlugin.rbxm` from the [latest release](https://github.com/xerseer/ORDINANCE/releases).
2. In Studio, open the Plugins tab, choose **Plugins Folder**, and put the file there.
3. Open the **Ordnance** panel and press **Install**.

The plugin carries a copy of the framework, so this works offline. With HTTP allowed it also tells you when an update is out. See [Studio plugin](plugin.html).

### By hand

1. Download `Ordnance.rbxm` from the [latest release](https://github.com/xerseer/ORDINANCE/releases).
2. Drag it into Studio and put it in **ReplicatedStorage**.

> Ordnance is not on the Creator Store yet. Releases on GitHub are the only official copies.

Press Play. Every player spawns with every example weapon in their backpack.

## The object {#layout}

<div class="tree">Ordnance                 <span class="dim">require() this for the scripting API</span>
├─ Config                <span class="dim">your global settings</span>
├─ Weapons               <span class="dim">one module per weapon</span>
│  ├─ Glock17
│  └─ ...
├─ Presets               <span class="dim">ready-made configs, Arcade to Realistic</span>
└─ Framework             <span class="dim">internals; replaced when you update</span></div>

Edit `Config`, `Weapons` and `Presets` as much as you like. Updating replaces `Framework` and the root module and nothing else, so your weapons and settings survive every update. Do not edit `Framework`: your changes would be lost.

## Your first weapon {#first-weapon}

A weapon is a ModuleScript in `Ordnance.Weapons` that returns a table, with its model inside it as a child named `Model`. The model needs one part named `Handle`, whose front face points down the barrel.

```lua Weapons.Revolver
return {
	Name = "Revolver",
	Fire = { Modes = { "Semi" }, RPM = 160 },
	Ammo = { Magazine = 6, Reserve = 36 },
	Damage = { Base = 45 },
}
```

That is a complete weapon. Everything it does not say comes from the global config, which falls back to the defaults. [Weapons](weapons.html) covers models, attachments and every kind of gun.

## How settings stack {#precedence}

Four layers, lowest to highest. Each one only needs the values it changes.

| Layer | Where it lives | Use it for |
|---|---|---|
| Defaults | `Framework.Config.Defaults` | Read-only. Every setting with a sensible value. |
| Preset | `Ordnance.Presets.<Name>` | The feel of the whole game: Arcade, Tactical, Realistic. |
| Global config | `Ordnance.Config` | Your game's own rules, keybinds, HUD, security. |
| Weapon | `Ordnance.Weapons.<Name>` | What makes this gun this gun. |

A setting you misspell or give the wrong type is reported in the Output window with the closest real name, and the default is used instead:

```text Output
[Ordnance:Config] Weapon "Revolver": Fire.RMP unknown setting. Did you mean "RPM"?
```

## Examples {#examples}

Five weapons ship with the framework, one for each kind of gun. Read them as templates.

{{weapons}}

## Where next {#next}

- [Weapons](weapons.html): models, attachments, fire modes, actions, reloads, projectiles.
- [Configuration](config.html): every setting, with its default and range.
- [Animation](animation.html): procedural motion, encoded keyframes, first and third person.
- [Scripting API](api.html): give weapons, react to kills, change damage.
- [Security](security.html): what the server checks, and what it trusts.
