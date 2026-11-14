title: Troubleshooting
nav: Troubleshooting
description: Fixes for the common Ordnance problems, answers to common questions, and what Ordnance cannot do yet.
order: 9
---

# Troubleshooting

Start with the Output window. Everything Ordnance reports is tagged `[Ordnance:…]`; type `Ordnance` in its filter box to see only that.

## Common problems {#problems}

### A weapon does not appear {#missing-weapon}

- It must be a **ModuleScript** directly in `Ordnance.Weapons` (or in a folder there) that returns a table. A Script or LocalScript is not a weapon.
- If it fails to load, Output says why, naming the weapon. The other weapons still load.
- With `Inventory.Loadout` set to a list, a weapon that is not in it is not handed out. `{ "*" }` hands out all of them.
- With `Inventory.Mode = "Custom"`, nothing is handed out; [`Ordnance.Give`](api.html#give) is up to you.

### A setting has no effect {#setting-ignored}

Look for a warning naming it. The usual causes:

- A misspelt name. The warning suggests the closest real one.
- The wrong type, such as `"30"` for `30`. It is left out and the default used.
- A global-only section (`Inventory`, `Security`, `Debug`) set in a weapon module. Set it in `Ordnance.Config`.
- A weapon module that sets the same thing. The weapon's value wins over the global config.

### The gun is held backwards, sideways, or shoots from the stock {#backwards}

The `Handle` part is turned the wrong way. Its front face (−Z) must point down the barrel and its top face (+Y) up. Rotate the part, not the model. The plugin's [IK Helper](plugin.html#helper) says when the muzzle is behind the handle.

### The hands are in the wrong place {#hands}

Add or move the `MainHandle` and `Grip` attachments on the handle. `Debug.Visualize.IK` marks where each first-person hand is being asked to grip, and `Debug.Visualize.Attachments` marks the weapon's attachments.

### Shots that clearly hit do no damage {#no-damage}

- `Damage.FriendlyFire` is off and the target is on the same team.
- Your [damage handler](api.html#setdamagehandler) returned `false` or 0.
- The server rejected the shot. Set `Debug.Logger.Level = "Debug"` to see each rejection and its reason. `origin too far from the character` on a fast-moving character means `Security.MaxOriginError` is too small for your game.

`Debug.Visualize.Hitboxes` draws the rewound hitboxes the server tested, which shows whether lag compensation is the cause.

### Everything is silent, or sounds wrong {#sounds}

The default sounds are placeholders made from sounds that ship with Roblox, so that something always plays. Set `Effects.Sounds.Fire` and the others to your own asset ids.

## Questions {#questions}

### Does it work with my own character rig? {#rigs}

Any R15 or R6 character works, including custom bodies and the newer AnimationConstraint joints. Rigs built some other way are not supported.

### Can NPCs be shot? {#npcs}

Yes. Anything with a Humanoid takes damage. NPCs cannot use Ordnance weapons themselves.

### Can I use Roblox animations instead? {#roblox-animations}

Not directly: weapon animations are encoded or procedural. The plugin's [Converter](plugin.html#converter) turns a KeyframeSequence into an encoded animation, which then needs no upload and works on every rig.

### Does it work on phones and gamepads? {#devices}

Keybinds take gamepad buttons alongside keys, and touch devices get on-screen buttons for each action. In `Tool` mode the hotbar works as it does in any Roblox game.

### How do I update? {#update}

With the plugin, press **Update & Install**. By hand, replace the `Framework` folder and the root module's source with the new release's; keep your own `Config`, `Weapons` and `Presets`.

### How do I remove it? {#remove}

Delete `ReplicatedStorage.Ordnance`. Nothing was put anywhere else.

## Not there yet {#limits}

Said plainly, so you can plan around it:

- **Real sounds.** The defaults are placeholders.
- **Attachments as items.** Sights, grips and suppressors that players swap are not built in. `Custom` and the API leave room for your own.
- **R6 stance.** R6 bodies do not turn or lean, and R6 arms may slide at the shoulder to reach.
- **Third-person bolts.** In third person the trigger hand stays on the grip, so bolts are only worked by hand in first person.
- **Aimbot detection.** See [Security](security.html#limits).
- **Creator Store.** The framework and the plugin are not listed there yet; releases on GitHub are the official copies.
