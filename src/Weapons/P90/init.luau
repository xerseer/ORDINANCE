--[[
	FN P90
	A bullpup personal defence weapon with a fifty-round magazine on top.
]]

return {
	Name = "FN P90",
	Description = "5.7mm bullpup personal defence weapon.",
	Scale = 0.62,

	Fire = { Mode = "Auto", Modes = { "Auto", "Semi" }, RPM = 900 },
	Ammo = { Magazine = 50, Reserve = 200, ReloadTime = 2.6, ReloadEmptyTime = 3.1 },
	Ballistics = { Penetration = 0.4 },
	Damage = { Base = 18, Falloff = { Start = 70, End = 220 } },
	Spread = { Hip = 2.3, Aim = 0.35, PerShot = 0.2 },
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
