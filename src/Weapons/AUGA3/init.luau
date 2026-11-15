--[[
	Steyr AUG A3
	A bullpup rifle: a long barrel in a short weapon. It has its own foregrip.
]]

return {
	Name = "AUG A3",
	Description = "5.56mm bullpup assault rifle.",
	Scale = 0.62,

	Fire = { Mode = "Auto", Modes = { "Auto", "Semi" }, RPM = 700 },
	Ammo = { Magazine = 30, Reserve = 150, ReloadTime = 2.6, ReloadEmptyTime = 3.0 },
	Ballistics = { Penetration = 0.6 },
	Damage = { Base = 24, Falloff = { Start = 170, End = 550 } },
	Spread = { Hip = 2.6, Aim = 0.22, PerShot = 0.26 },
	Recoil = { Vertical = 0.75, Horizontal = 0.45 },

	Attachments = {
		Allowed = {
			Optic = { "RedDot", "Holographic", "ACOG" },
			Underbarrel = {},
		},
	},
}
