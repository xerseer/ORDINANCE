title: Studio plugin
description: The Ordnance Studio plugin: install and update, a step-by-step weapon setup, a config editor, presets, an animation previewer and converter, an attachment helper and a catalogue of weapons.
order: 8
---

# Studio plugin

One panel with eight tabs. Everything it does, you could do by editing modules by hand; the plugin just makes it quicker and catches mistakes.

## Getting it {#install}

Download `OrdnancePlugin.rbxm` from the [latest release](https://github.com/xerseer/ORDINANCE/releases), open Studio's Plugins tab, choose **Plugins Folder**, and put the file there. An **Ordnance** button appears in the Plugins tab and opens the panel. The panel follows Studio's light or dark theme.

Every change the plugin makes is one step in Studio's undo history.

## Install {#install-tab}

Shows the installed version and the latest release, and installs, updates or removes the framework.

- **Update & Install** puts `Ordnance` in ReplicatedStorage, with the example weapons, attachments and presets, or updates the copy that is there. An update replaces `Framework` and the root module only. Your `Config`, your weapons, your attachments and your presets are never touched; presets that shipped with the new version and are missing are added.
- **Check for updates** asks GitHub for the latest version.
- **Install the bundled copy** uses the copy of the framework the plugin carries, so installing works offline, or when you decline its HTTP request.
- **Remove Ordnance from this place** deletes the framework completely. Nothing is left behind.

> Limit: Studio plugins can download text over HTTP but cannot load model files that way. So releases also ship the framework as a JSON description of its instances, and the plugin rebuilds it. Studio asks once whether the plugin may contact `raw.githubusercontent.com`; that is the only site it uses.

## Setup {#setup}

Turns any gun model into a weapon, one step at a time. The model can be made of anything (MeshParts, Parts with meshes, unions, models inside models) and can be lying in any direction.

1. Select the model and press **Start setup**.
2. Type the weapon's name and press **Next**. Every part is gathered directly under one model and the empty folders and models inside it are removed.
3. Click a part in the viewport and press **Select**, once for each of:
   - **Grip**: where the trigger hand holds.
   - **Muzzle**: the very front of the barrel.
   - **Sight**: the rear sight, or the top of the receiver.
   - **Magazine**, **Support hand** and **Slide or bolt**, which can each be skipped.
4. Pick what kind of weapon it is (Rifle, SMG, Pistol, Shotgun or Sniper) for its starting numbers, set a **Scale** if the model was built too big or too small, and press **Finish**.

Where you click on a part is what counts, not the part's centre, because kit models often put a whole gun in one mesh. The grip, muzzle and sight together say which way the weapon faces and which way is up.

Finish adds an invisible `Handle` with the [attachments](weapons.html#attachments) the animation system reads, names the magazine and the slide or bolt so they move, renames every other part `Part1`, `Part2` and so on, and puts the model inside a new module in `Ordnance.Weapons`, ready for the next Play. The attachments are left visible so you can drag any that are a little off. Each step is one undo.

## Config {#config}

A form for `Ordnance.Config`, built from the installed framework's own schema: every setting with its range, its choices and a line saying what it does. New settings in a future version appear without a plugin update.

Search by name or description, reset any setting to its default, and save. Only values that differ from the defaults are written, so the file stays short and readable. If `Ordnance.Config` was written by hand, the tab says so before saving over it, because comments are not kept.

## Presets {#presets}

Pick the preset your config starts from, and manage your own:

- **Use** makes a preset the starting point of your config; **Stop using** goes back to the defaults.
- **Save as preset** turns the settings you changed in `Ordnance.Config` into a new preset.
- **Export** shows a preset as text to copy; **Add preset** under Import checks pasted text against the schema before adding it.
- Presets you made can be deleted; the four that ship cannot.

## Previewer {#previewer}

A viewport that runs the installed framework's own animation code on a sample character, so what you see is what plays in game. Pick a weapon and an action, scrub through it or play it at any speed, and switch between first and third person, R15 and R6, hip and aimed.

The third-person preview does not turn the body side-on as the game does.

## Converter {#converter}

Turns an animation into an [encoded animation](animation.html#encoded).

1. Select a KeyframeSequence in the Explorer.
2. Choose which action it plays for, and press **Convert**.
3. Copy the result, or select the weapon's module and press **Add to selected weapon**.

Poses named like a hand become `Left` or `Right`, `Weapon`, `Gun` and `Handle` become `Weapon`, the rig's root and torso are skipped, and any other name is taken to be a part of the weapon. Rename poses with one line each, such as `Rig_R_Hand = Right`. Easing carries over.

> Limit: Studio only lets plugins download animations you own. For anyone else's, open it in the Animation Editor and save it as a KeyframeSequence first.

## IK Helper {#helper}

Select a weapon model and press **Check**. The helper reports the handle and each [attachment](weapons.html#attachments), says which are required, recommended or optional, and catches the common mistakes: a handle facing backwards, a muzzle in the same place as the grip. **Add missing attachments** places the missing attachments from the model's shape, for you to nudge into place.

## Catalogue {#catalogue}

Weapons and presets published with Ordnance releases. Insert one and it lands in your `Weapons` or `Presets` folder, ready to use. A name that is already taken gets a number added.

> Limit: a plugin builds catalogue items from data, so it can recreate parts, meshes and attachments but not Unions, and it cannot show thumbnails, because plugins cannot display images from the web.
