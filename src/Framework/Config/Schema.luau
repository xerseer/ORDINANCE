--!strict
--[[
	Schema
	Checks a user-written config table against Defaults and returns a clean
	copy. It never throws: anything wrong is reported and left out, so the
	default applies instead.

	The type of each field comes from its value in Defaults. This file only
	adds what a value alone cannot say: ranges, fixed choices and a one-line
	description. The plugin's config editor and the docs read the same rules.
]]

local Defaults = require(script.Parent.Defaults)

export type Rule = {
	doc: string,
	min: number?,
	max: number?,
	integer: boolean?,
	choices: { string }?,
	-- "keys": list of Enum.KeyCode / Enum.UserInputType names
	-- "choices": list where every item must be one of `choices`
	-- "strings": list of free strings
	-- "model": a child name or an Instance
	-- "free": anything; copied through unchecked
	-- "frame": exactly six numbers (position x, y, z; rotation x, y, z in degrees)
	kind: ("keys" | "choices" | "strings" | "model" | "free" | "frame")?,
}

export type Problem = {
	path: string,
	message: string,
}

local FIRE_MODES = { "Safe", "Semi", "Burst", "Auto" }

local RULES: { [string]: Rule } = {
	["Preset"] = { doc = "Name of a module in Ordnance.Presets to start from. Global config only." },
	["Name"] = { doc = "Display name. Defaults to the weapon module's name." },
	["Description"] = { doc = "Short text shown in menus and the catalogue." },
	["Model"] = {
		doc = "The weapon model: a child of the weapon module by name, or an Instance.",
		kind = "model",
	},
	["Scale"] = {
		doc = "Resizes the weapon model, in first and third person alike. Use it when a model was built too big or too small for a character.",
		min = 0.1,
		max = 10,
	},
	["Custom"] = { doc = "Your own data. Ordnance copies it through untouched.", kind = "free" },

	["Fire.Mode"] = { doc = "Fire mode the weapon starts in.", choices = FIRE_MODES },
	["Fire.Modes"] = {
		doc = "Fire modes the player can switch between.",
		kind = "choices",
		choices = FIRE_MODES,
	},
	["Fire.RPM"] = { doc = "Rounds per minute.", min = 1, max = 6000 },
	["Fire.BurstCount"] = {
		doc = "Rounds fired per trigger pull in Burst mode.",
		min = 2,
		max = 20,
		integer = true,
	},
	["Fire.BurstRPM"] = { doc = "Rate of fire inside a burst. 0 uses RPM.", min = 0, max = 6000 },
	["Fire.Pellets"] = {
		doc = "Projectiles per round. More than 1 makes a shotgun.",
		min = 1,
		max = 64,
		integer = true,
	},
	["Fire.Action"] = {
		doc = "SelfLoading cycles by itself. Bolt and Pump need a cycle after every shot.",
		choices = { "SelfLoading", "Bolt", "Pump" },
	},
	["Fire.CycleTime"] = { doc = "Seconds a bolt or pump cycle takes.", min = 0, max = 10 },
	["Fire.InputBuffer"] = {
		doc = "Seconds a trigger pull is remembered if the weapon is not ready yet.",
		min = 0,
		max = 1,
	},

	["Ammo.Magazine"] = { doc = "Rounds a magazine holds.", min = 1, max = 9999, integer = true },
	["Ammo.Reserve"] = { doc = "Spare rounds carried. math.huge is allowed.", min = 0 },
	["Ammo.Infinite"] = { doc = "Reloading never uses up the reserve." },
	["Ammo.ReloadType"] = {
		doc = "Magazine swaps the whole magazine. Single loads one round at a time and can be interrupted.",
		choices = { "Magazine", "Single" },
	},
	["Ammo.ReloadTime"] = { doc = "Seconds for a magazine reload.", min = 0, max = 30 },
	["Ammo.ReloadEmptyTime"] = {
		doc = "Seconds for a reload from empty. 0 uses ReloadTime.",
		min = 0,
		max = 30,
	},
	["Ammo.ShellTime"] = { doc = "Seconds per round for a Single reload.", min = 0.05, max = 10 },
	["Ammo.AutoReload"] = { doc = "Pulling the trigger on an empty weapon starts a reload." },

	["Ballistics.Type"] = {
		doc = "Hitscan hits instantly. Projectile flies, drops and can bounce or explode.",
		choices = { "Hitscan", "Projectile" },
	},
	["Ballistics.Range"] = { doc = "Furthest a round travels, in studs.", min = 1, max = 20000 },
	["Ballistics.Penetration"] = {
		doc = "Studs of material a round can pass through. Hitscan only.",
		min = 0,
		max = 50,
	},
	["Ballistics.Velocity"] = {
		doc = "Muzzle velocity in studs per second. Projectile only.",
		min = 1,
		max = 20000,
	},
	["Ballistics.Gravity"] = {
		doc = "Multiplier on workspace.Gravity. 0 flies straight.",
		min = -10,
		max = 10,
	},
	["Ballistics.Drag"] = { doc = "Fraction of speed lost per second.", min = 0, max = 20 },
	["Ballistics.Lifetime"] = { doc = "Seconds before a projectile is removed.", min = 0.05, max = 120 },
	["Ballistics.Bounce.Count"] = {
		doc = "Times a projectile may bounce before it stops.",
		min = 0,
		max = 50,
		integer = true,
	},
	["Ballistics.Bounce.Elasticity"] = { doc = "Speed kept after a bounce, 0 to 1.", min = 0, max = 1 },
	["Ballistics.Bounce.MinSpeed"] = {
		doc = "Below this speed a projectile stops instead of bouncing.",
		min = 0,
		max = 1000,
	},
	["Ballistics.Explosive.Enabled"] = { doc = "The projectile explodes." },
	["Ballistics.Explosive.Damage"] = { doc = "Damage at the centre of the blast.", min = 0, max = 100000 },
	["Ballistics.Explosive.Radius"] = { doc = "Blast radius in studs.", min = 0.5, max = 500 },
	["Ballistics.Explosive.Falloff"] = {
		doc = "How damage fades toward the edge of the blast.",
		choices = { "None", "Linear", "Quadratic" },
	},
	["Ballistics.Explosive.MinScale"] = {
		doc = "Damage multiplier at the very edge of the blast.",
		min = 0,
		max = 1,
	},
	["Ballistics.Explosive.Fuse"] = {
		doc = "Seconds until it explodes by itself. 0 turns the fuse off.",
		min = 0,
		max = 60,
	},
	["Ballistics.Explosive.DetonateOnImpact"] = { doc = "Explode on the first thing it touches." },
	["Ballistics.Explosive.RequireLineOfSight"] = { doc = "Walls protect from the blast." },
	["Ballistics.Explosive.SelfDamageScale"] = {
		doc = "Multiplier on damage to the shooter. 0 makes them immune.",
		min = 0,
		max = 10,
	},
	["Ballistics.Explosive.Knockback"] = {
		doc = "Push applied to characters in the blast.",
		min = 0,
		max = 2000,
	},

	["Damage.Base"] = { doc = "Damage per round, before multipliers.", min = 0, max = 100000 },
	["Damage.Multipliers.Head"] = { doc = "Multiplier for head hits.", min = 0, max = 100 },
	["Damage.Multipliers.Torso"] = { doc = "Multiplier for torso hits.", min = 0, max = 100 },
	["Damage.Multipliers.Limb"] = { doc = "Multiplier for arm and leg hits.", min = 0, max = 100 },
	["Damage.Falloff.Start"] = {
		doc = "Distance in studs where damage starts to drop.",
		min = 0,
		max = 20000,
	},
	["Damage.Falloff.End"] = { doc = "Distance in studs where damage stops dropping.", min = 0, max = 20000 },
	["Damage.Falloff.MinScale"] = { doc = "Damage multiplier at and beyond Falloff.End.", min = 0, max = 1 },
	["Damage.FriendlyFire"] = { doc = "Players on the same team can damage each other." },

	["Spread.Hip"] = { doc = "Cone half-angle in degrees when not aiming.", min = 0, max = 45 },
	["Spread.Aim"] = { doc = "Cone half-angle in degrees when aiming.", min = 0, max = 45 },
	["Spread.Moving"] = { doc = "Degrees added while moving.", min = 0, max = 45 },
	["Spread.Airborne"] = { doc = "Degrees added while in the air.", min = 0, max = 45 },
	["Spread.PerShot"] = { doc = "Degrees added by each shot.", min = 0, max = 45 },
	["Spread.Max"] = { doc = "Most the cone can open, in degrees.", min = 0, max = 60 },
	["Spread.Recovery"] = { doc = "Degrees of shot bloom recovered per second.", min = 0, max = 500 },

	["Recoil.Vertical"] = { doc = "Upward camera kick per shot, in degrees.", min = 0, max = 45 },
	["Recoil.Horizontal"] = { doc = "Largest sideways kick per shot, in degrees.", min = 0, max = 45 },
	["Recoil.AimScale"] = { doc = "Recoil multiplier while aiming.", min = 0, max = 4 },
	["Recoil.Recovery"] = { doc = "Fraction of the kick the camera returns from, 0 to 1.", min = 0, max = 1 },
	["Recoil.Speed"] = { doc = "How fast the kick is applied and recovered.", min = 1, max = 200 },
	["Recoil.Damping"] = {
		doc = "Spring damping. Below 1 overshoots, 1 settles cleanly.",
		min = 0.05,
		max = 3,
	},

	["Handling.EquipTime"] = {
		doc = "Seconds before the weapon can fire after equipping.",
		min = 0,
		max = 10,
	},
	["Handling.AimTime"] = { doc = "Seconds to aim down sights.", min = 0, max = 5 },
	["Handling.AimFOV"] = { doc = "Camera field of view while aiming.", min = 5, max = 120 },
	["Handling.WalkSpeedScale"] = {
		doc = "Walk speed multiplier while holding the weapon.",
		min = 0,
		max = 4,
	},
	["Handling.AimWalkSpeedScale"] = { doc = "Walk speed multiplier while aiming.", min = 0, max = 4 },

	["Realism.Chambering"] = {
		doc = "Track the chambered round separately: reloading early keeps one extra.",
	},
	["Realism.ManualCycle"] = {
		doc = "Bolt and pump weapons wait for the Cycle key instead of cycling by themselves.",
	},
	["Realism.DropMagazine"] = { doc = "Rounds left in a swapped magazine are lost." },
	["Realism.Malfunctions.Enabled"] = { doc = "The weapon can jam. Clear a jam with the Cycle key." },
	["Realism.Malfunctions.Chance"] = { doc = "Chance per shot of a jam, 0 to 1.", min = 0, max = 1 },

	["Tuning.Damage"] = { doc = "Multiplier on bullet and explosion damage.", min = 0, max = 100 },
	["Tuning.Recoil"] = { doc = "Multiplier on camera kick.", min = 0, max = 10 },
	["Tuning.Spread"] = { doc = "Multiplier on every spread angle.", min = 0, max = 10 },
	["Tuning.ReloadTime"] = { doc = "Multiplier on reload and shell times.", min = 0.05, max = 10 },
	["Tuning.FireRate"] = { doc = "Multiplier on rounds per minute.", min = 0.05, max = 10 },

	["Camera.Mode"] = {
		doc = "Both follows the player's zoom. FirstPerson and ThirdPerson lock the view while a weapon is held.",
		choices = { "Both", "FirstPerson", "ThirdPerson" },
	},
	["Camera.ShoulderOffset"] = {
		doc = "Camera shift in third person, so the character is not in the way of the crosshair.",
	},
	["Camera.FaceAim"] = { doc = "In third person the character turns to face where it is aiming." },

	["Scope.Enabled"] = {
		doc = "Show the view through a scope, and hide the weapon, once aimed in first person. Pair it with a low Handling.AimFOV.",
	},
	["Scope.Reticle"] = { doc = "Colour of the scope's crosshairs." },
	["Scope.Overlay"] = { doc = "Colour around the lens." },

	["Viewmodel.Enabled"] = {
		doc = "Show first-person arms and weapon. Off leaves first person to the plain character.",
	},
	["Viewmodel.Offset"] = {
		doc = "Where the weapon's handle sits relative to the camera at the hip.",
		kind = "frame",
	},
	["Viewmodel.AimDistance"] = {
		doc = "Studs from the camera to the weapon's Aim attachment when aiming.",
		min = 0.2,
		max = 6,
	},
	["Viewmodel.Sleeves"] = { doc = "Show the character's shirt on the first-person arms." },
	["Viewmodel.ArmWidth"] = {
		doc = "Thickness of the first-person arms compared with the character's. Lower takes up less of the screen.",
		min = 0.2,
		max = 1,
	},
	["Viewmodel.ArmLength"] = {
		doc = "Stretches the first-person upper arms so they run off the screen. Only the viewmodel changes.",
		min = 1,
		max = 4,
	},
	["Viewmodel.HandScale"] = {
		doc = "Size of the first-person hands compared with the character's.",
		min = 0.3,
		max = 1,
	},

	["ThirdPerson.Offset"] = {
		doc = "Where the handle sits relative to the character's eyes at the hip.",
		kind = "frame",
	},
	["ThirdPerson.AimOffset"] = {
		doc = "Where the handle sits relative to the character's eyes when aiming.",
		kind = "frame",
	},

	["ThirdPerson.BodyTurn"] = {
		doc = "Degrees the upper body turns side-on while holding a weapon, so the support hand can reach. R15 only.",
		min = 0,
		max = 60,
	},
	["ThirdPerson.BodyPitch"] = {
		doc = "How much of the aim's up and down the upper body leans with, 0 to 1. R15 only.",
		min = 0,
		max = 1,
	},

	["Animation.Mode"] = {
		doc = "Procedural, Encoded, or Both (encoded where the weapon has one, procedural otherwise).",
		choices = { "Procedural", "Encoded", "Both" },
	},
	["Animations"] = { doc = "Encoded animations: keyframe tables by action name.", kind = "free" },

	["Sway.Enabled"] = { doc = "Procedural weapon sway in first person." },
	["Sway.Mouse"] = {
		doc = "How much the weapon lags behind the camera when you look around.",
		min = 0,
		max = 10,
	},
	["Sway.Bob"] = { doc = "How much the weapon bobs while walking.", min = 0, max = 10 },
	["Sway.Breath"] = { doc = "How much the weapon drifts while standing still.", min = 0, max = 10 },
	["Sway.Landing"] = { doc = "How much the weapon dips when you land.", min = 0, max = 10 },
	["Sway.Tilt"] = { doc = "How much the weapon rolls when strafing.", min = 0, max = 10 },
	["Sway.Kick"] = { doc = "How much the weapon jumps in the hands per shot.", min = 0, max = 10 },
	["Sway.AimScale"] = { doc = "Sway multiplier while aiming.", min = 0, max = 2 },
	["Sway.Speed"] = { doc = "How quickly sway springs respond.", min = 1, max = 60 },
	["Sway.Damping"] = { doc = "Sway spring damping. Lower is looser.", min = 0.1, max = 2 },

	["Keybinds.Fire"] = { doc = "Fire.", kind = "keys" },
	["Keybinds.Aim"] = { doc = "Aim down sights.", kind = "keys" },
	["Keybinds.Reload"] = { doc = "Reload.", kind = "keys" },
	["Keybinds.FireMode"] = { doc = "Switch fire mode.", kind = "keys" },
	["Keybinds.Cycle"] = { doc = "Cycle the action or clear a jam.", kind = "keys" },
	["Keybinds.Light"] = { doc = "Turn the weapon's flashlights and lasers on and off.", kind = "keys" },
	["Keybinds.Attachments"] = {
		doc = "Open the attachment menu, when Attachments.Menu is on.",
		kind = "keys",
	},

	["Attachments.Allowed"] = {
		doc = "Per slot (Optic, Muzzle, Underbarrel, Side), the attachment ids this weapon accepts. A slot left out accepts any; an empty list accepts none.",
		kind = "free",
	},
	["Attachments.Default"] = { doc = "Per slot, the attachment id the weapon comes with.", kind = "free" },
	["Attachments.Menu"] = { doc = "Let players change attachments in game with the Attachments key." },

	["Controls.AimToggle"] = { doc = "Press to aim instead of hold." },
	["Controls.TouchButtons"] = { doc = "Show on-screen buttons on touch devices." },

	["Effects.Tracer.Enabled"] = { doc = "Draw tracers." },
	["Effects.Tracer.Color"] = { doc = "Tracer colour." },
	["Effects.Tracer.Width"] = { doc = "Tracer thickness in studs.", min = 0.005, max = 2 },
	["Effects.Tracer.Length"] = { doc = "Tracer length in studs.", min = 0.1, max = 200 },
	["Effects.Tracer.Speed"] = {
		doc = "Tracer speed in studs per second. Hitscan only.",
		min = 10,
		max = 20000,
	},
	["Effects.Tracer.Every"] = { doc = "Draw a tracer every N shots.", min = 1, max = 100, integer = true },
	["Effects.MuzzleFlash.Enabled"] = { doc = "Flash a light at the muzzle." },
	["Effects.MuzzleFlash.Color"] = { doc = "Flash colour." },
	["Effects.MuzzleFlash.Brightness"] = { doc = "Flash brightness.", min = 0, max = 40 },
	["Effects.MuzzleFlash.Range"] = { doc = "Flash range in studs.", min = 0, max = 60 },
	["Effects.MuzzleFlash.Duration"] = { doc = "Seconds the flash lasts.", min = 0.01, max = 1 },
	["Effects.Impact.Enabled"] = { doc = "Leave a mark where rounds land." },
	["Effects.Impact.Size"] = { doc = "Mark size in studs.", min = 0.02, max = 10 },
	["Effects.Impact.Lifetime"] = { doc = "Seconds a mark stays.", min = 0, max = 120 },
	["Effects.Sounds.Fire"] = { doc = "Sound played per shot." },
	["Effects.Sounds.FirePitch"] = { doc = "Playback speed of the fire sound.", min = 0.05, max = 10 },
	["Effects.Sounds.FireVolume"] = { doc = "Volume of the fire sound.", min = 0, max = 10 },
	["Effects.Sounds.Empty"] = { doc = "Sound played when the trigger is pulled on an empty weapon." },
	["Effects.Sounds.Reload"] = { doc = "Sound played when a reload starts." },
	["Effects.Sounds.Explosion"] = { doc = "Sound played by explosions." },
	["Effects.Sounds.RollOffMax"] = {
		doc = "Distance in studs at which shots can no longer be heard.",
		min = 10,
		max = 10000,
	},
	["Effects.Projectile.Size"] = {
		doc = "Diameter of the visible projectile in studs.",
		min = 0.02,
		max = 20,
	},
	["Effects.Projectile.Color"] = { doc = "Colour of the visible projectile." },
	["Effects.Projectile.Trail"] = { doc = "Draw a trail behind the projectile." },

	["HUD.Enabled"] = { doc = "Show the built-in ammo display." },
	["HUD.Crosshair"] = { doc = "Show the built-in crosshair." },
	["HUD.Hitmarker"] = { doc = "Flash a marker when a shot lands." },
	["HUD.Accent"] = { doc = "Accent colour of the built-in HUD." },

	["Crosshair.Style"] = {
		doc = "Cross: four lines. T: no top line. Circle: a ring. Dot: only a dot. None: nothing at the hip.",
		choices = { "Cross", "T", "Circle", "Dot", "None" },
	},
	["Crosshair.CenterDot"] = { doc = "Add a dot in the middle of the Cross, T or Circle." },
	["Crosshair.Color"] = { doc = "Colour of the lines and the dot." },
	["Crosshair.Opacity"] = { doc = "1 is solid, 0 is invisible.", min = 0, max = 1 },
	["Crosshair.Length"] = { doc = "Length of each line, in pixels.", min = 1, max = 60 },
	["Crosshair.Thickness"] = { doc = "Width of the lines and the ring, in pixels.", min = 1, max = 12 },
	["Crosshair.Gap"] = {
		doc = "Space between the centre and the lines, in pixels, before spread is added.",
		min = 0,
		max = 60,
	},
	["Crosshair.DotSize"] = {
		doc = "Size of the centre dot and of the aimed dot, in pixels.",
		min = 1,
		max = 16,
	},
	["Crosshair.Outline"] = { doc = "Draw a thin border around the crosshair so it shows on any background." },
	["Crosshair.OutlineColor"] = { doc = "Colour of the border." },
	["Crosshair.OutlineThickness"] = { doc = "Width of the border, in pixels.", min = 1, max = 6 },
	["Crosshair.Dynamic"] = {
		doc = "Open the crosshair with the weapon's current spread. Off keeps it a fixed size.",
	},
	["Crosshair.AimStyle"] = {
		doc = "What it becomes when aiming. Auto: a dot, or nothing in first person when the weapon has a sight (an Aim attachment or an optic). Dot: always a dot. Hidden: nothing. Same: no change.",
		choices = { "Auto", "Dot", "Hidden", "Same" },
	},

	["Inventory.Mode"] = {
		doc = "Tool gives weapons as Backpack tools. Custom gives nothing; use Ordnance.Equip yourself.",
		choices = { "Tool", "Custom" },
	},
	["Inventory.Loadout"] = {
		doc = 'Weapon names every player receives. { "*" } means all of them.',
		kind = "strings",
	},
	["Inventory.GiveOnSpawn"] = { doc = "Hand out the loadout whenever a character spawns." },

	["Security.LagCompensation"] = { doc = "Rewind other players to where the shooter saw them." },
	["Security.MaxRewind"] = { doc = "Most the server will rewind, in seconds.", min = 0, max = 1 },
	["Security.InterpolationDelay"] = {
		doc = "Extra rewind for client-side interpolation, in seconds.",
		min = 0,
		max = 0.3,
	},
	["Security.SnapshotRate"] = {
		doc = "Position snapshots recorded per second.",
		min = 5,
		max = 60,
		integer = true,
	},
	["Security.MaxOriginError"] = {
		doc = "Studs a shot may start from the server's idea of the shooter's head.",
		min = 1,
		max = 100,
	},
	["Security.FireRateTolerance"] = {
		doc = "How much faster than RPM a client may fire before shots are dropped.",
		min = 1,
		max = 3,
	},
	["Security.ReloadTolerance"] = {
		doc = "Fraction of a reload the server forgives for network delay.",
		min = 0,
		max = 0.9,
	},
	["Security.ValidateLineOfSight"] = {
		doc = "Reject shots whose origin is on the other side of a wall from the shooter.",
	},

	["Debug.Logger.Level"] = {
		doc = "Most detailed message level to print.",
		choices = { "None", "Error", "Warn", "Info", "Debug" },
	},
	["Debug.Logger.ErrorBehavior"] = {
		doc = "What a framework error does.",
		choices = { "Throw", "Warn", "Info", "Print" },
	},
	["Debug.Logger.Tag"] = { doc = "Prefix on every message. Filter the Output window by it." },
	["Debug.Logger.History"] = {
		doc = "Messages kept for the debug overlay.",
		min = 0,
		max = 5000,
		integer = true,
	},
	["Debug.Logger.CaptureLogService"] = { doc = "Also record uncaught framework errors from LogService." },
	["Debug.Logger.Traceback"] = { doc = "Add a stack trace to caught errors." },
	["Debug.Overlay"] = { doc = "Show framework messages on screen." },
	["Debug.Visualize.Rays"] = { doc = "Draw hitscan rays." },
	["Debug.Visualize.Projectiles"] = { doc = "Draw projectile paths." },
	["Debug.Visualize.Hitboxes"] = { doc = "Draw the rewound hitboxes the server tested." },
	["Debug.Visualize.IK"] = { doc = "Mark where each first-person hand is being asked to grip." },
	["Debug.Visualize.Attachments"] = { doc = "Mark the first-person weapon's attachments." },
	["Debug.Visualize.Lifetime"] = { doc = "Seconds debug drawings stay.", min = 0.05, max = 60 },
}

-- Sections that are read once from the global config and cannot differ per weapon.
local GLOBAL_ONLY: { [string]: boolean } = {
	Preset = true,
	Inventory = true,
	Security = true,
	Debug = true,
}

-- Fields that only make sense inside a weapon module.
local WEAPON_ONLY: { [string]: boolean } = {
	Name = true,
	Description = true,
	Model = true,
	Scale = true,
	Custom = true,
	Animations = true,
}

local Schema = {}

Schema.Rules = RULES
Schema.GlobalOnly = GLOBAL_ONLY
Schema.WeaponOnly = WEAPON_ONLY

local function editDistance(a: string, b: string): number
	local previous = table.create(#b + 1, 0)
	for column = 0, #b do
		previous[column + 1] = column
	end
	for row = 1, #a do
		local current = table.create(#b + 1, 0)
		current[1] = row
		for column = 1, #b do
			local cost = if string.byte(a, row) == string.byte(b, column) then 0 else 1
			current[column + 1] =
				math.min(previous[column + 1] + 1, current[column] + 1, previous[column] + cost)
		end
		previous = current
	end
	return previous[#b + 1]
end

local function suggest(key: string, known: { [string]: any }): string?
	local lowered = string.lower(key)
	local best: string? = nil
	local bestDistance = 3
	for candidate in known do
		if type(candidate) == "string" then
			local distance = editDistance(lowered, string.lower(candidate))
			if distance < bestDistance then
				best = candidate
				bestDistance = distance
			end
		end
	end
	return best
end

local function isInputName(name: any): boolean
	if type(name) ~= "string" then
		return false
	end
	local ok = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	if ok then
		return true
	end
	return (pcall(function()
		return (Enum.UserInputType :: any)[name]
	end))
end

local function checkList(value: any, rule: Rule?, path: string, problems: { Problem }): { any }?
	if type(value) ~= "table" then
		table.insert(problems, { path = path, message = `expected a list, got {typeof(value)}` })
		return nil
	end
	local kind = if rule then rule.kind else nil
	local result = {}
	for index, item in value do
		if type(index) ~= "number" then
			table.insert(
				problems,
				{ path = path, message = `expected a list, found the key "{tostring(index)}"` }
			)
			continue
		end
		if kind == "keys" then
			if isInputName(item) then
				table.insert(result, item)
			else
				table.insert(problems, {
					path = `{path}[{index}]`,
					message = `"{tostring(item)}" is not an Enum.KeyCode or Enum.UserInputType name`,
				})
			end
		elseif kind == "choices" and rule and rule.choices then
			if table.find(rule.choices, item) then
				table.insert(result, item)
			else
				table.insert(problems, {
					path = `{path}[{index}]`,
					message = `"{tostring(item)}" is not one of {table.concat(rule.choices, ", ")}`,
				})
			end
		elseif type(item) == "string" then
			table.insert(result, item)
		else
			table.insert(
				problems,
				{ path = `{path}[{index}]`, message = `expected a string, got {typeof(item)}` }
			)
		end
	end
	return result
end

local function checkValue(value: any, default: any, rule: Rule?, path: string, problems: { Problem }): any
	if rule and rule.kind == "free" then
		return value
	end
	if rule and rule.kind == "model" then
		if type(value) == "string" or typeof(value) == "Instance" then
			return value
		end
		table.insert(
			problems,
			{ path = path, message = `expected a name or an Instance, got {typeof(value)}` }
		)
		return nil
	end

	if rule and rule.kind == "frame" then
		local ok = type(value) == "table" and #value == 6
		if ok then
			for index = 1, 6 do
				local item = value[index]
				ok = ok and type(item) == "number" and item == item
			end
		end
		if not ok then
			table.insert(
				problems,
				{ path = path, message = "expected six numbers: x, y, z, then rotation x, y, z" }
			)
			return nil
		end
		return table.clone(value)
	end

	local expected = typeof(default)
	if expected == "table" then
		-- Only lists reach here; maps are walked by checkMap.
		return checkList(value, rule, path, problems)
	end

	if typeof(value) ~= expected then
		table.insert(problems, { path = path, message = `expected a {expected}, got {typeof(value)}` })
		return nil
	end

	if expected == "number" then
		local number = value :: number
		if number ~= number then
			table.insert(problems, { path = path, message = "is NaN" })
			return nil
		end
		if rule then
			if rule.integer and number ~= math.huge and number % 1 ~= 0 then
				table.insert(problems, { path = path, message = `{number} was rounded to a whole number` })
				number = math.round(number)
			end
			if rule.min and number < rule.min then
				table.insert(
					problems,
					{ path = path, message = `{number} is below the minimum {rule.min}; using {rule.min}` }
				)
				number = rule.min
			elseif rule.max and number > rule.max then
				table.insert(
					problems,
					{ path = path, message = `{number} is above the maximum {rule.max}; using {rule.max}` }
				)
				number = rule.max
			end
		end
		return number
	end

	if expected == "string" and rule and rule.choices then
		if not table.find(rule.choices, value) then
			table.insert(problems, {
				path = path,
				message = `"{value}" is not one of {table.concat(rule.choices, ", ")}`,
			})
			return nil
		end
	end

	return value
end

local function checkMap(input: any, defaults: any, prefix: string, problems: { Problem }): { [string]: any }
	local result = {}
	for key, value in input do
		local path = if prefix == "" then tostring(key) else `{prefix}.{tostring(key)}`
		local default = defaults[key]
		if default == nil then
			local hint = if type(key) == "string" then suggest(key, defaults) else nil
			table.insert(problems, {
				path = path,
				message = if hint then `unknown setting. Did you mean "{hint}"?` else "unknown setting",
			})
			continue
		end

		local rule = RULES[path]
		local isSection = type(default) == "table" and #default == 0 and not (rule and rule.kind == "free")
		if isSection then
			if type(value) == "table" then
				result[key] = checkMap(value, default, path, problems)
			else
				table.insert(problems, { path = path, message = `expected a table, got {typeof(value)}` })
			end
		else
			local checked = checkValue(value, default, rule, path, problems)
			if checked ~= nil then
				result[key] = checked
			end
		end
	end
	return result
end

--[[
	Returns a cleaned copy of `input` and the list of problems found.
	`scope` is "Global", "Preset" or "Weapon" and controls which sections are
	allowed: a weapon cannot set global-only sections and vice versa.
]]
function Schema.validate(input: any, scope: "Global" | "Preset" | "Weapon"): ({ [string]: any }, { Problem })
	local problems: { Problem } = {}
	if type(input) ~= "table" then
		table.insert(problems, { path = "", message = `the config must be a table, got {typeof(input)}` })
		return {}, problems
	end

	local cleaned = checkMap(input, Defaults, "", problems)

	if scope == "Weapon" then
		for key in GLOBAL_ONLY do
			if cleaned[key] ~= nil then
				cleaned[key] = nil
				table.insert(
					problems,
					{ path = key, message = "is a global setting and is ignored in a weapon module" }
				)
			end
		end
	else
		for key in WEAPON_ONLY do
			if cleaned[key] ~= nil then
				cleaned[key] = nil
				table.insert(
					problems,
					{ path = key, message = "only belongs in a weapon module and is ignored here" }
				)
			end
		end
		if scope == "Preset" and cleaned.Preset ~= nil then
			cleaned.Preset = nil
			table.insert(problems, { path = "Preset", message = "a preset cannot name another preset" })
		end
	end

	return cleaned, problems
end

-- The rule for a dotted path such as "Fire.RPM", if it has one.
function Schema.rule(path: string): Rule?
	return RULES[path]
end

return Schema
