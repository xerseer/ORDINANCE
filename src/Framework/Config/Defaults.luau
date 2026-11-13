--!strict
--[[
	Defaults
	Every setting the framework understands, with the value it has when nobody
	sets it. This table is also the shape of the config: the global Config
	module, presets and weapon modules are all partial copies of it.

	Rules for editing this file:
	  - Every field needs a real value (no nil), because types are read from it.
	  - Add a matching entry in Schema.luau when a field has a range or a fixed
	    set of choices, and always give it a description there.
	  - Lists (tables with numeric keys) are replaced whole when overridden,
	    never merged item by item.
]]

local Defaults = {
	------------------------------------------------------------------------
	-- Identity. Name, Description, Model and Custom are only meaningful inside
	-- a weapon module; Preset only in the global config.
	------------------------------------------------------------------------
	Preset = "",
	Name = "",
	Description = "",
	Model = "Model",
	Custom = {} :: { [string]: any },

	------------------------------------------------------------------------
	-- How the trigger behaves.
	------------------------------------------------------------------------
	Fire = {
		Mode = "Auto",
		Modes = { "Auto" },
		RPM = 600,
		BurstCount = 3,
		BurstRPM = 0,
		Pellets = 1,
		Action = "SelfLoading",
		CycleTime = 0.8,
		InputBuffer = 0.12,
	},

	------------------------------------------------------------------------
	-- Rounds and reloading.
	------------------------------------------------------------------------
	Ammo = {
		Magazine = 30,
		Reserve = 120,
		Infinite = false,
		ReloadType = "Magazine",
		ReloadTime = 2.2,
		ReloadEmptyTime = 0,
		ShellTime = 0.55,
		AutoReload = true,
	},

	------------------------------------------------------------------------
	-- What leaves the barrel.
	------------------------------------------------------------------------
	Ballistics = {
		Type = "Hitscan",
		Range = 1200,
		Penetration = 0,
		Velocity = 1800,
		Gravity = 1,
		Drag = 0,
		Lifetime = 6,
		Bounce = {
			Count = 0,
			Elasticity = 0.45,
			MinSpeed = 12,
		},
		Explosive = {
			Enabled = false,
			Damage = 120,
			Radius = 16,
			Falloff = "Linear",
			MinScale = 0.1,
			Fuse = 0,
			DetonateOnImpact = true,
			RequireLineOfSight = true,
			SelfDamageScale = 1,
			Knockback = 60,
		},
	},

	------------------------------------------------------------------------
	-- Damage per round (per pellet for shotguns).
	------------------------------------------------------------------------
	Damage = {
		Base = 24,
		Multipliers = {
			Head = 2,
			Torso = 1,
			Limb = 0.8,
		},
		Falloff = {
			Start = 120,
			End = 400,
			MinScale = 0.5,
		},
		FriendlyFire = false,
	},

	------------------------------------------------------------------------
	-- Accuracy. Angles are in degrees, measured from the centre of the cone.
	------------------------------------------------------------------------
	Spread = {
		Hip = 2.2,
		Aim = 0.25,
		Moving = 1.2,
		Airborne = 3,
		PerShot = 0.35,
		Max = 6,
		Recovery = 9,
	},

	------------------------------------------------------------------------
	-- Camera kick per shot, in degrees.
	------------------------------------------------------------------------
	Recoil = {
		Vertical = 1.1,
		Horizontal = 0.45,
		AimScale = 0.65,
		Recovery = 0.55,
		Speed = 22,
		Damping = 0.8,
	},

	------------------------------------------------------------------------
	-- How the weapon handles.
	------------------------------------------------------------------------
	Handling = {
		EquipTime = 0.35,
		AimTime = 0.18,
		AimFOV = 50,
		WalkSpeedScale = 1,
		AimWalkSpeedScale = 0.75,
	},

	------------------------------------------------------------------------
	-- Opt-in realism. Everything is off by default.
	------------------------------------------------------------------------
	Realism = {
		Chambering = false,
		ManualCycle = false,
		DropMagazine = false,
		Malfunctions = {
			Enabled = false,
			Chance = 0.003,
		},
	},

	------------------------------------------------------------------------
	-- Controls. Each action takes a list of Enum.KeyCode or
	-- Enum.UserInputType names; the first keyboard/mouse entry and the first
	-- gamepad entry are the ones shown in the HUD.
	------------------------------------------------------------------------
	Keybinds = {
		Fire = { "MouseButton1", "ButtonR2" },
		Aim = { "MouseButton2", "ButtonL2" },
		Reload = { "R", "ButtonX" },
		FireMode = { "V", "DPadUp" },
		Cycle = { "F", "ButtonY" },
	},

	Controls = {
		AimToggle = false,
		TouchButtons = true,
	},

	------------------------------------------------------------------------
	-- Sound and visuals. Sounds accept any asset id; the defaults use sounds
	-- that ship with Roblox so they always play.
	------------------------------------------------------------------------
	Effects = {
		Tracer = {
			Enabled = true,
			Color = Color3.fromRGB(255, 214, 140),
			Width = 0.06,
			Length = 9,
			Speed = 900,
			Every = 1,
		},
		MuzzleFlash = {
			Enabled = true,
			Color = Color3.fromRGB(255, 196, 120),
			Brightness = 4,
			Range = 12,
			Duration = 0.045,
		},
		Impact = {
			Enabled = true,
			Size = 0.25,
			Lifetime = 6,
		},
		Sounds = {
			Fire = "rbxasset://sounds/impact_explosion_03.mp3",
			FirePitch = 2.6,
			FireVolume = 0.55,
			Empty = "rbxasset://sounds/volume_slider.ogg",
			Reload = "rbxasset://sounds/action_jump_land.mp3",
			Explosion = "rbxasset://sounds/impact_explosion_03.mp3",
			RollOffMax = 600,
		},
		Projectile = {
			Size = 0.35,
			Color = Color3.fromRGB(64, 66, 60),
			Trail = true,
		},
	},

	HUD = {
		Enabled = true,
		Crosshair = true,
		Hitmarker = true,
		Accent = Color3.fromRGB(179, 191, 125),
	},

	------------------------------------------------------------------------
	-- Global only: the sections below are read once from the global config.
	-- A weapon module that sets them is ignored for these fields.
	------------------------------------------------------------------------
	Inventory = {
		Mode = "Tool",
		Loadout = { "*" },
		GiveOnSpawn = true,
	},

	Security = {
		LagCompensation = true,
		MaxRewind = 0.4,
		InterpolationDelay = 0.05,
		SnapshotRate = 30,
		MaxOriginError = 9,
		FireRateTolerance = 1.2,
		ReloadTolerance = 0.25,
		ValidateLineOfSight = true,
	},

	Debug = {
		Logger = {
			Level = "Info",
			ErrorBehavior = "Warn",
			Tag = "Ordnance",
			History = 200,
			CaptureLogService = true,
			Traceback = true,
		},
		Overlay = false,
		Visualize = {
			Rays = false,
			Projectiles = false,
			Hitboxes = false,
			Lifetime = 2,
		},
	},
}

export type Config = typeof(Defaults)

return Defaults
