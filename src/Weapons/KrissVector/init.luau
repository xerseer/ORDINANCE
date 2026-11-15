--[[
	Kriss Vector
	A very fast-firing submachine gun with little kick.
]]

return {
	Name = "Kriss Vector",
	Description = ".45 ACP submachine gun with automatic, two-round burst and semi-automatic fire.",
	Scale = 0.62,

	Fire = { Mode = "Auto", Modes = { "Auto", "Burst", "Semi" }, RPM = 1100, BurstCount = 2 },
	Ammo = { Magazine = 25, Reserve = 125, ReloadTime = 2.1, ReloadEmptyTime = 2.4 },
	Damage = { Base = 17, Falloff = { Start = 50, End = 180 } },
	Spread = { Hip = 2.4, Aim = 0.4, PerShot = 0.18 },
	Recoil = { Vertical = 0.5, Horizontal = 0.45 },

	Effects = {
		Sounds = { Fire = "rbxassetid://9114727096", FirePitch = 1.1, FireVolume = 0.7 },
	},

	Attachments = {
		Allowed = {
			Optic = { "RedDot", "Holographic" },
			Muzzle = { "Suppressor" },
			Underbarrel = {},
		},
	},
}
