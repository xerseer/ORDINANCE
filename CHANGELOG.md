# Changelog

All notable changes to Ordnance are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

Decisions made without asking are listed under **Decisions** so they are easy to find and overturn.

## [Unreleased]

### Added

- Rojo project structure: `default.project.json` (place, for `rojo serve`), `framework.project.json` (the drop-in model) and `plugin.project.json` (the Studio plugin).
- The single `Ordnance` object: public API module with `Config`, `Weapons`, `Presets` and `Framework` inside it.
- Server and client entry points that boot themselves from ReplicatedStorage through `RunContext`. Verified in a Studio playtest.
- `Logger`: levels (`None`, `Error`, `Warn`, `Info`, `Debug`), a configurable error behaviour (`Throw`, `Warn`, `Info`, `Print`), consistent `[Ordnance:Scope]` tags, a history buffer for the in-game overlay, `Try`/`Wrap` helpers that catch and report, and capture of uncaught framework errors from `LogService`.
- `Signal`: a small typed event.
- `tools/bundle.mjs`: writes the framework as a JSON instance tree for the plugin updater.
- `tools/serve.mjs` and `tools/sync.luau`: local development sync without the Rojo plugin.
- CI (StyLua, Selene, Rojo builds, bundle) and a release workflow that publishes a GitHub Release and a `dist` branch.

#### Phase 2: core framework

- **Config.** `Defaults` is the single table of every setting; `Schema` adds ranges, choices and a description per setting; `Merge` deep-merges. Precedence is defaults, preset, `Ordnance.Config`, weapon module. Bad input is clamped or dropped and reported with its path (and a "did you mean" for misspelt keys); it never throws.
- **Tuning multipliers** (`Tuning.Damage`, `Recoil`, `Spread`, `ReloadTime`, `FireRate`) to retune every weapon at once.
- **Presets:** `Arcade`, `Standard`, `Tactical`, `Realistic`.
- **Weapons.** A weapon is one ModuleScript with its model inside. `Registry` loads them; `Rig` welds the model, finds the handle and fills in missing `MainHandle` and `Barrel` attachments. A weapon with no model gets a placeholder.
- **Weapon state machine** shared by client and server: magazine and reserve, optional chambered round, fire modes (`Safe`, `Semi`, `Burst`, `Auto`), self-loading, bolt and pump actions, magazine and shell-by-shell reloads, manual cycling, dropped magazines and jams.
- **Hitscan** with wall penetration, and **projectiles** with gravity, drag, bounces, fuses and explosions (falloff, line of sight, self-damage, knockback).
- **Server authority.** Shots are checked for ammo, cadence, origin distance and line of sight. Pellet patterns come from a per-player seed instead of the client. Player hitboxes are rewound to the shot's time (lag compensation). NPC humanoids can be hit too.
- **Client.** Instant prediction, camera recoil, spread bloom, aim down sights (FOV and walk speed), tracers, muzzle flash, impact marks, explosion effects, and a small HUD (ammo, fire mode, reload bar, spread crosshair, hitmarker).
- **Input** through ContextActionService: keyboard and mouse, gamepad, and on-screen touch buttons from one keybind list.
- **Inventory.** `Tool` mode hands every weapon out as a Backpack tool; `Custom` mode leaves equipping to `Ordnance.Equip`.
- **Public API:** `Give`, `Take`, `Equip`, `Unequip`, `SetAmmo`, `SetDamageHandler`, `GetWeapons`, `GetConfig`, `GetEquipped`, `GetAmmo`, `IsAiming`, and the signals `Damaged`, `Killed`, `Fired`, `Equipped`, `Unequipped`, `Reloaded`, `Exploded`.
- **Example weapons** rigged from the gun kit: Glock 17 (semi pistol), G36C (select-fire rifle), Remington 700 (bolt action), Remington 870 (pump shotgun), M203 (grenade launcher).
- `tools/studio/RigExamples.luau` and `tools/import-models.mjs` (rig the kit models in Studio and bring them into the repo as text), and `tools/studio/SelfTest.luau` (28 checks of the config and state logic).

### Fixed

- Walk speed collapsed toward zero while a weapon was held, because the speed written and the 32-bit value read back differed and were mistaken for an outside change.

### Known gaps

- Default sounds are placeholders built from the few sounds that ship with Roblox. Real gunshots need asset ids.
- Arms are posed by Roblox's stock tool-hold animation until phase 3 adds the animation systems.
- `Debug.Overlay` is accepted by the config but the on-screen log is not built yet.

### Decisions

- **Name.** The framework is "Ordnance" (the weapons word). The GitHub repository is still `xerseer/ORDINANCE`.
- **Root object is a ModuleScript**, not a Folder, so `require(ReplicatedStorage.Ordnance)` is the public API and the object is still a single instance.
- **User files sit at the top level** (`Config`, `Weapons`, `Presets`) and internals under `Framework`. The updater replaces `Framework` and leaves the rest alone.
- **Updater reads a `dist` branch** over `raw.githubusercontent.com` instead of the GitHub Releases API. One domain to approve in Studio, no redirects, and no 60-requests-an-hour API limit. Releases are still created for people.
- **Weapon models are stored as text** (Rojo `.model.json`), so they diff in git and can travel in the JSON bundle.
- **Welds are created at runtime** from part names instead of being stored in the model, so a model only needs its parts named.
- **Toolchain is pinned with Aftman**: Rojo 7.7.0, StyLua 2.0.2, Selene 0.28.0.
- **Shots start at the character's head, aimed where the camera looks.** The server can then check the origin tightly in third person, at the cost of some parallax next to cover.
- **Pellet spread is seeded, not sent.** The client sends one aim direction and its cone angle; both sides derive the pellets from a server-issued seed. A cheat can still claim the tightest honest cone, but cannot pick pellet directions.
- **Rate of fire uses an allowance, not a timestamp check.** It refills at the weapon's RPM (with `Security.FireRateTolerance`) and holds three shots, so jitter is forgiven but the average rate is enforced.
- **The G36C is the example rifle instead of the AKM**, because the kit's AK models contain MeshParts and the text model format was only verified for Parts with SpecialMeshes.
- **The M203 example fires grenades only.** It uses the M4 with underbarrel launcher model; the rifle itself is not a second fire mode yet.
- **Entry scripts moved** to `Framework/Server/Main` and `Framework/Client/Main`, and requiring the public module is what starts the framework.
- **Weapon attachment names:** `MainHandle` (trigger hand), `Barrel` (muzzle), `Grip` (support hand), `Side` (bolt or charging handle), `Mag`, plus `Aim` for the sight line.
