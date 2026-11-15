--[[
	MP5
	A 9mm submachine gun: accurate and easy to control. Its magazine drops
	out on a reload.
]]

return {
	Name = "MP5",
	Description = "9mm submachine gun with automatic, burst and semi-automatic fire.",
	Scale = 0.62,

	Fire = { Mode = "Auto", Modes = { "Auto", "Burst", "Semi" }, RPM = 800, BurstCount = 3 },
	Ammo = { Magazine = 30, Reserve = 150, ReloadTime = 2.0, ReloadEmptyTime = 2.5 },
	Damage = { Base = 19, Falloff = { Start = 60, End = 200 } },
	Spread = { Hip = 2.2, Aim = 0.35, PerShot = 0.2 },
	Recoil = { Vertical = 0.6, Horizontal = 0.4 },

	Effects = {
		Sounds = { Fire = "rbxassetid://9114727096", FirePitch = 1.15, FireVolume = 0.7 },
	},

	Attachments = {
		Allowed = {
			Optic = { "RedDot", "Holographic" },
			Muzzle = { "Suppressor" },
			Underbarrel = { "VerticalGrip" },
		},
	},
}
