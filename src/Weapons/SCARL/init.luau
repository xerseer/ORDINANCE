--[[
	SCAR-L
	A steady rifle at a measured rate of fire.
]]

return {
	Name = "SCAR-L",
	Description = "5.56mm assault rifle with automatic and semi-automatic fire.",
	Scale = 0.62,

	Fire = { Mode = "Auto", Modes = { "Auto", "Semi" }, RPM = 625 },
	Ammo = { Magazine = 30, Reserve = 150, ReloadTime = 2.3, ReloadEmptyTime = 2.8 },
	Ballistics = { Penetration = 0.6 },
	Damage = { Base = 26, Falloff = { Start = 150, End = 500 } },
	Spread = { Hip = 2.5, Aim = 0.25, PerShot = 0.28 },
	Recoil = { Vertical = 0.9, Horizontal = 0.5 },

	Attachments = {
		Allowed = {
			Optic = { "RedDot", "Holographic", "ACOG" },
		},
	},
}
