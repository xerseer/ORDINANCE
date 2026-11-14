# Changelog

All notable changes to Ordnance are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

Decisions made without asking are listed under **Decisions** so they are easy to find and overturn.

## [Unreleased]

## [0.1.0] - 2026-11-14

The first release.

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

#### Phase 3: animation, first and third person, R6 and R15

- **Encoded animations.** A weapon's `Animations` table holds keyframes as plain numbers (six per value: position, then rotation in degrees), with per-keyframe easing and optional sounds. Channels are `Weapon`, `Left`, `Right` and any named part of the model. The framework plays `Equip`, `Reload`, `ReloadEmpty`, `Cycle`, `Fire` and `Idle`. Bad animations are reported and skipped.
- **Procedural animation.** With no keyframes at all, hands travel to the weapon's `Mag` and `Side` attachments to reload and cycle, parts named `Mag`, `Bolt`, `Slide` and `Pump` move by themselves, and the weapon tips and settles.
- **`Animation.Mode`**: `Procedural`, `Encoded`, or `Both` (encoded where the weapon has one, procedural otherwise). `Both` is the default.
- **Arm IK** for R15 (two-bone) and R6 (single arm), used for both views. It accepts `Motor6D` and the new `AnimationConstraint` joints.
- **First-person viewmodel** built at runtime from the player's own arms (rig, skin and shirt), with aim-down-sights that lines the weapon's `Aim` attachment up with the camera.
- **Procedural sway**: mouse lag, walk bob, breathing, landing dip, strafe tilt and per-shot kick, each a multiplier under `Sway`, on springs.
- **Third person**: the trigger hand is placed where the weapon should be, the support hand is solved onto the weapon, arms follow the aim pitch, and R15 bodies turn side-on and lean with the aim while the head stays on target. Runs on every client for every visible character.
- **Replication of pose**: aim pitch and aiming state ten times a second over an unreliable remote, and reload and cycle actions as events, so other players see the same animation.
- **Camera**: `Camera.Mode` (`Both`, `FirstPerson`, `ThirdPerson`), an over-the-shoulder offset in third person, the character turning to face its aim, and aiming through the cursor when the mouse is free. The crosshair follows the aim point. Everything is restored when the weapon is put away.
- **Debug**: the on-screen log (`Debug.Overlay`) and gizmos for IK targets and weapon attachments (`Debug.Visualize.IK`, `Debug.Visualize.Attachments`).
- The Glock 17 carries an encoded `Fire` and `Reload` as a worked example; the other four weapons are fully procedural.
- `tools/studio/PosePreview.luau` draws the first-person view as text, and the self-test grew to 40 checks.

#### Phase 4: Studio plugin

- **One dock widget, seven tabs**, each its own module under `plugin/src/Tabs`. A tab that fails to load is replaced by its error; the rest keep working.
- **Look.** Hand-built components (`UI.luau`) on one palette (`Theme.luau`) that follows Studio's light or dark theme live: flat, square, hairline-separated, one olive accent, the docs site's language.
- **Install.** Shows installed and latest versions, installs or updates in one undo step, can remove the framework completely, and falls back to a copy of the framework embedded in the plugin when offline or when HTTP is declined. An update replaces `Framework` and the root module only; Config, Weapons and your own presets are never touched.
- **Config.** A form generated from the installed framework's own schema and defaults (range, choices, description per setting), searchable, grouped, with per-setting reset. Only values that differ from the defaults are written to `Ordnance.Config`.
- **Presets.** Use, export, import (validated before it is added), delete your own, and save your current Config as a preset.
- **Previewer.** A viewport that runs the installed Animator and arm solver in first or third person, R15 or R6, with scrubber, play and pause, speed and an aim toggle.
- **Converter.** Turns a selected KeyframeSequence (or an Animation you own) into an `Animations` entry, with pose renaming and easing carried over, and can add it to the selected weapon module.
- **IK Helper.** Checks a weapon model for the attachments the animation system uses and places missing ones from the model's geometry.
- **Catalogue.** Browses `catalogue.json` on the release branch and inserts weapons and presets. Feasible, with limits: weapons built from Unions need a Creator Store asset id, and thumbnails cannot be shown by a plugin.
- `tools/bundle.mjs` now also writes the catalogue index and one JSON file per weapon and preset, and `--embed` puts the bundle inside the plugin. CI and the release workflow build the bundle before the plugin.

**Tested in Studio:** every tab builds and shows without errors. The embedded bundle rebuilds the framework identically to the Rojo-synced copy (208 instances, every source, size and attachment equal). Fresh install, update (keeps Config, your weapons, and restores a deleted shipped preset) and uninstall work. Writing `Ordnance.Config` keeps every value, the IK helper places all five attachments on a stripped model, and converted animations load when added to a weapon module.

**Not verified:** how the panel looks (Studio screenshots come back black to the tools used), the live HTTP update and catalogue (nothing has been released yet, and the test connection cannot make HTTP requests), and the previewer's camera framing.

#### Phase 5: documentation site

- **Nine pages**: start here, weapons, configuration, presets, animation, scripting API, security, Studio plugin, troubleshooting. Written for someone making a game, with the Roblox limits stated where they apply.
- **Generated where it can be.** `tools/docs.mjs` reads `Defaults.luau` and `Schema.luau` with a small Luau table parser, so the configuration reference (160 settings: default, accepted values, description, scope), the preset comparison and the example-weapon table always match the code. The build fails if a config section or a public API function or signal has no entry, and CI runs it.
- **Look.** The xnet docs' visual language: warm paper or warm near-black following the system theme, one olive accent, Schibsted Grotesk and JetBrains Mono, square corners, a left rail that lists the current page's sections. Code is highlighted at build time; the only scripts are copy buttons, the rail marker and a settings filter (press `/`).
- **No dependencies.** Markdown dialect, highlighter and dev server (`--serve`, rebuilds on change) are in the one script.
- The built site is committed in `docs/` (with `index.html` and `.nojekyll`) and GitHub Pages serves it from `main`; the Markdown sources live in `site/`. CI fails if `docs/` does not match a fresh build. This replaced an Actions deploy workflow so Pages needs only "Deploy from a branch".
- `main` is the only branch; the `dev` and `phase/*` branches were merged and deleted.

**Checked:** every page at 1280 and 375 pixels wide has no horizontal overflow, every internal link and anchor resolves, there are no duplicate ids or stray Markdown, and the filter works. **Not checked:** how it looks to the eye. The browser available to me could not paint while the app was in the background.

#### Phase 6: polish and final review

- **Real gunshots.** The default fire sound and the example weapons' sounds are recordings from Roblox's licensed Pro Sound Effects library, which any experience may use: a rifle shot by default, a pistol for the Glock, a heavy rifle for the Remington 700, and a slowed rifle shot for the 870. Each id was loaded in Studio on both server and client. Sounds ripped from commercial games are common on the Creator Store and were deliberately not used.
- **Final review** of the server's shot handling, sessions and networking: every client value is type-checked, bounded and rate-limited, state is cleaned up when a player leaves, and every handler is isolated.
- **Play-tested end to end** on the server: weapons come back after respawn; a torso shot does 26, a head shot 52 and a leg shot 20.8 with the Glock; a nine-pellet shotgun blast lands as one tallied hit; a shot before the pump finishes is refused; a shot from 40 studs off the head is refused; the M203 round arcs and explodes once for 132. The self-test still passes all 40 checks.

### Fixed

- Bullets stopped on hats and hair, and an accessory counted as a limb, so a head shot on a character wearing a hat did less damage than a body shot. They now pass through accessories to the body, matching how players are already hit through lag compensation.
- In the dev place, the plugin's source ran as a server script during every play test and failed on a Studio-only API. It is now disabled in `default.project.json`; the plugin build is unchanged.

- Plugin: the Config, Presets and Converter tabs could not load, because the plugin root is a Script and `script.Parent.Parent.Source` read its `Source` property instead of the module of that name. The module is now `Writer`.
- Plugin converter: the rig's root pose became an empty `Weapon` channel, and every conversion looped because KeyframeSequences loop by default. Root poses are skipped and only an Idle keeps `Loop`.
- Attachments that shared a name with a part (`Mag`, `Barrel`) were not found, so muzzle effects started at the head and reloads had no hand motion.
- The world weapon stayed visible in first person; Roblox hides the character there but not its Tool.
- Walk speed collapsed toward zero while a weapon was held, because the speed written and the 32-bit value read back differed and were mistaken for an outside change.

### Known gaps

- Only the gunshots are recordings. Reload, empty and explosion sounds are the simple ones that ship with Studio, and the M203 uses a slowed explosion as its launch thump.
- Not tested with more than one real player: the play tests ran one player against dummies on the server. Replication to other clients and touch and gamepad input were reviewed in the code, not played.
- In third person the trigger hand never leaves the grip (the weapon is welded to it, as every Roblox Tool is), so a bolt is worked by the right hand only in first person.
- R6 bodies do not turn or lean; an R6 torso is one piece. R6 arms slide at the shoulder to reach instead.
- With a long rifle an R15 support hand may still fall a little short of the handguard; it then holds the weapon as far forward as it can reach.

### Decisions

- The docs site is plain HTML built by a dependency-free Node script rather than a site generator such as VitePress or Docusaurus. Those bring a look of their own that is hard to undo, and the brief asked for the xnet design and nothing that looks generated. The cost is a small Markdown dialect of our own.
- Docs publish from `main` only, so the site always describes the latest release rather than work in progress.

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
- **Custom arm solver instead of `IKControl`.** One solver serves the anchored first-person arms, live R15 characters and R6, none of which `IKControl` covers alone.
- **Weapon parts are held by `Motor6D`, not welds**, each named after its part, so any part can be animated without rigging.
- **Third-person arms are driven through joint `Transform`** in `PreSimulation`, which is what Roblox recommends for the new avatar joints. Nothing about the pose is written to the server.
- **Aim follows the cursor when the mouse is free.** In third person without mouse lock the shot goes where the cursor is, as Roblox players expect; with the mouse locked or in first person it goes to the centre of the screen.
- **The example grips sit low on the pistol grip** so an R15 hand, which is a large mitten, does not cover the weapon.
- **Weapon attachment names:** `MainHandle` (trigger hand), `Barrel` (muzzle), `Grip` (support hand), `Side` (bolt or charging handle), `Mag`, plus `Aim` for the sight line.

[Unreleased]: https://github.com/xerseer/ORDINANCE/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/xerseer/ORDINANCE/releases/tag/v0.1.0
