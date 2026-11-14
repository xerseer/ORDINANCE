title: Presets
description: Ordnance's ready-made configs, from Arcade to Realistic, what each one changes, and how to write your own.
order: 4
---

# Presets

A preset is a config you start from. Pick one by name and your own settings go on top of it.

```lua Ordnance.Config
return {
	Preset = "Tactical",
}
```

## The four {#list}

{{preset-list}}

## What each changes {#compare}

Every setting a preset touches, beside its default. A dash means the preset leaves it alone. `Tuning` values multiply every weapon's own numbers, so a preset retunes the whole arsenal without knowing what weapons you have.

{{presets}}

## Your own {#custom}

A preset is a ModuleScript in `Ordnance.Presets` that returns a partial config, exactly like `Ordnance.Config`. It cannot name another preset, and it cannot set weapon-only fields such as `Name` or `Model`.

```lua Presets.Hardcore
--[[
	Hardcore
	Tactical handling, no HUD, and every hit counts double.
]]

return {
	Tuning = { Damage = 2, Recoil = 1.25 },
	Realism = { Chambering = true, DropMagazine = true },
	HUD = { Enabled = false },
}
```

The first line of the comment block is the name and the paragraph under it is the description; the plugin and the catalogue show both. The plugin's [Presets tab](plugin.html#presets) can also save your current `Ordnance.Config` as a new preset, and export or import one as text to share.

Updates add presets that ship with new versions and never touch the ones you made or edited.
