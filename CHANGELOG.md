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

### Decisions

- **Name.** The framework is "Ordnance" (the weapons word). The GitHub repository is still `xerseer/ORDINANCE`.
- **Root object is a ModuleScript**, not a Folder, so `require(ReplicatedStorage.Ordnance)` is the public API and the object is still a single instance.
- **User files sit at the top level** (`Config`, `Weapons`, `Presets`) and internals under `Framework`. The updater replaces `Framework` and leaves the rest alone.
- **Updater reads a `dist` branch** over `raw.githubusercontent.com` instead of the GitHub Releases API. One domain to approve in Studio, no redirects, and no 60-requests-an-hour API limit. Releases are still created for people.
- **Weapon models are stored as text** (Rojo `.model.json`), so they diff in git and can travel in the JSON bundle.
- **Welds are created at runtime** from part names instead of being stored in the model, so a model only needs its parts named.
- **Toolchain is pinned with Aftman**: Rojo 7.7.0, StyLua 2.0.2, Selene 0.28.0.
