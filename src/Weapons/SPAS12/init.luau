--[[
	SPAS-12
	A pump-action shotgun. Pump between shots; shells load one at a time.
]]

return {
	Name = "SPAS-12",
	Description = "12 gauge pump-action shotgun.",
	Scale = 0.62,

	Fire = { Modes = { "Semi" }, RPM = 260, Pellets = 8, Action = "Pump", CycleTime = 0.5 },
	Ammo = { Magazine = 8, Reserve = 32, ReloadType = "Single", ShellTime = 0.5 },
	Ballistics = { Range = 260 },
	Damage = {
		Base = 13,
		Multipliers = { Head = 1.4, Torso = 1, Limb = 0.85 },
		Falloff = { Start = 25, End = 110, MinScale = 0.2 },
	},
	Spread = { Hip = 4.2, Aim = 3.2, Moving = 0.6, PerShot = 0, Max = 6 },
	Recoil = { Vertical = 3.6, Horizontal = 1.1, Recovery = 0.7 },

	Effects = {
		Tracer = { Width = 0.04, Length = 5 },
		Sounds = { Fire = "rbxassetid://9114726684", FirePitch = 0.72, FireVolume = 1 },
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
