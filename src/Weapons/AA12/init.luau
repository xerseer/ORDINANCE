--[[
	AA-12
	A fully automatic shotgun fed from a box magazine.
]]

return {
	Name = "AA-12",
	Description = "12 gauge automatic shotgun.",
	Scale = 0.62,

	Fire = { Mode = "Auto", Modes = { "Auto", "Semi" }, RPM = 300, Pellets = 8 },
	Ammo = { Magazine = 8, Reserve = 40, ReloadTime = 2.6, ReloadEmptyTime = 3.1 },
	Ballistics = { Range = 220 },
	Damage = {
		Base = 10,
		Multipliers = { Head = 1.4, Torso = 1, Limb = 0.85 },
		Falloff = { Start = 20, End = 95, MinScale = 0.2 },
	},
	Spread = { Hip = 4.6, Aim = 3.6, Moving = 0.6, PerShot = 0, Max = 6 },
	Recoil = { Vertical = 2.4, Horizontal = 1.0, Recovery = 0.7 },

	Effects = {
		Tracer = { Width = 0.04, Length = 5 },
		Sounds = { Fire = "rbxassetid://9114726684", FirePitch = 0.8, FireVolume = 0.95 },
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
