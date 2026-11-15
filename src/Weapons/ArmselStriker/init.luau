--[[
	Armsel Striker
	A shotgun with a twelve-round drum. It fires as fast as you pull the
	trigger and reloads a shell at a time.
]]

return {
	Name = "Armsel Striker",
	Description = "12 gauge semi-automatic drum shotgun.",
	Scale = 0.62,

	Fire = { Modes = { "Semi" }, RPM = 300, Pellets = 9 },
	Ammo = { Magazine = 12, Reserve = 36, ReloadType = "Single", ShellTime = 0.45 },
	Ballistics = { Range = 240 },
	Damage = {
		Base = 11,
		Multipliers = { Head = 1.4, Torso = 1, Limb = 0.85 },
		Falloff = { Start = 20, End = 100, MinScale = 0.2 },
	},
	Spread = { Hip = 4.6, Aim = 3.6, Moving = 0.6, PerShot = 0, Max = 6 },
	Recoil = { Vertical = 3.4, Horizontal = 1.2, Recovery = 0.7 },

	Effects = {
		Tracer = { Width = 0.04, Length = 5 },
		Sounds = { Fire = "rbxassetid://9114726684", FirePitch = 0.75, FireVolume = 1 },
	},

	Attachments = {
		Allowed = {
			Optic = { "RedDot", "Holographic" },
			Muzzle = {},
			Underbarrel = {},
			Side = { "Flashlight", "Laser" },
		},
	},
}
