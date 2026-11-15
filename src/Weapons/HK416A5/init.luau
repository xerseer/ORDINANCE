--[[
	H&K HK416A5
	A modern carbine, handed out with a red dot.
]]

return {
	Name = "HK416A5",
	Description = "5.56mm assault rifle with automatic and semi-automatic fire.",

	Fire = { Mode = "Auto", Modes = { "Auto", "Semi" }, RPM = 800 },
	Ammo = { Magazine = 30, Reserve = 150, ReloadTime = 2.2, ReloadEmptyTime = 2.7 },
	Ballistics = { Penetration = 0.6 },
	Damage = { Base = 24, Falloff = { Start = 150, End = 500 } },
	Spread = { Hip = 2.5, Aim = 0.28, PerShot = 0.28 },
	Recoil = { Vertical = 0.85, Horizontal = 0.5 },

	Attachments = {
		Allowed = {
			Optic = { "RedDot", "Holographic", "ACOG" },
		},
		Default = { Optic = "RedDot" },
	},
}
