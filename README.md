# Ordnance

A modular gun framework for Roblox. Drop one object into ReplicatedStorage and you have working guns; open the config when you want more.

**Documentation: [xerseer.github.io/ORDINANCE](https://xerseer.github.io/ORDINANCE/)**

> **Status: early development.** The framework, the Studio plugin and the docs site are in: config, weapons, hitscan and projectiles, server-authoritative damage, encoded and procedural animation, first and third person on R6 and R15, and five example weapons. Polish and a final review are next; see the [changelog](CHANGELOG.md).

## What it is

- **One object.** Everything lives inside `ReplicatedStorage.Ordnance`. There is nothing to put in ServerScriptService or StarterPlayer, and deleting the object removes the framework completely.
- **Works with no configuration.** Every setting has a default. A weapon can be as small as a model and a name.
- **Goes as deep as you want.** Fire modes, chambering, projectile ballistics, attachments, encoded and procedural IK animation, all opt-in per weapon.
- **Server-authoritative.** The client predicts for feel; the server decides what was hit.
- **Does not crash your game.** Framework errors are caught and reported through one logger you control.

## Layout

```
Ordnance                 require() this for the public API
├─ Config                your global settings
├─ Weapons               one module per weapon
├─ Presets               ready-made configs, Arcade to Realistic
└─ Framework             internals, replaced on update
```

Config precedence, lowest to highest: framework defaults, preset, `Config`, the weapon's own module.

## Developing

The code is a [Rojo](https://rojo.space) project.

```bash
aftman install
```

```bash
rojo serve
```

| Project file | Builds |
|---|---|
| `default.project.json` | A place mapping, for `rojo serve` |
| `framework.project.json` | `Ordnance.rbxm`, the drop-in object |
| `plugin.project.json` | The Studio plugin |

`node tools/bundle.mjs` writes `build/ordnance.bundle.json`, the text form of the framework that the plugin's updater downloads. Studio plugins can make HTTP requests but cannot load binary models from them, so releases ship the instance tree as JSON and the plugin rebuilds it.

Formatting is StyLua, linting is Selene. Both run in CI.

### Docs

The site is built from `docs/*.md` and the Luau sources by `tools/docs.mjs`, with no dependencies. The config reference, the preset comparison and the example-weapon tables are read from `Defaults.luau`, `Schema.luau`, `Presets` and `Weapons`, so they cannot go stale. The build fails if a config section or a public API function has no documentation.

```bash
node tools/docs.mjs --serve
```

That serves the site on `http://127.0.0.1:4173` and rebuilds on every change. Pushes to `main` publish it to GitHub Pages.

## Branches and releases

- `main` holds tagged releases.
- `dev` is where phases are integrated.
- `phase/N-name` branches hold work in progress.

Pushing a tag `vX.Y.Z` that matches `src/Framework/Version.luau` builds a GitHub Release and publishes the bundle to the `dist` branch.

## Credits

The example weapon models are rigged from "The Comprehensive Gun Kit", a free model kit by its original author. Ordnance adds the rigging and the code; the meshes are theirs.

## License

MIT. See [LICENSE](LICENSE).
