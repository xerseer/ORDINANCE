--[[
	MP7
	A compact personal defence weapon. Its rounds go through light cover.
]]

return {
	Name = "MP7",
	Description = "4.6mm personal defence weapon.",
	Scale = 0.62,

	Fire = { Mode = "Auto", Modes = { "Auto", "Semi" }, RPM = 950 },
	Ammo = { Magazine = 40, Reserve = 160, ReloadTime = 2.0, ReloadEmptyTime = 2.4 },
	Ballistics = { Penetration = 0.5 },
	Damage = { Base = 18, Falloff = { Start = 60, End = 200 } },
	Spread = { Hip = 2.2, Aim = 0.35, PerShot = 0.2 },
	Recoil = { Vertical = 0.55, Horizontal = 0.4 },

	Effects = {
		Sounds = { Fire = "rbxassetid://9114727096", FirePitch = 1.2, FireVolume = 0.65 },
	},

	Attachments = {
		Allowed = {
			Optic = { "RedDot", "Holographic" },
			Muzzle = { "Suppressor" },
			Underbarrel = {},
		},
	},
}
