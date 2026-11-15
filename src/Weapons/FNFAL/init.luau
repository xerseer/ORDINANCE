--[[
	FN FAL
	A battle rifle: a heavy round that goes through cover, and kick to match.
]]

return {
	Name = "FN FAL",
	Description = "7.62mm battle rifle with semi-automatic and automatic fire.",
	Scale = 0.62,

	Fire = { Mode = "Semi", Modes = { "Semi", "Auto" }, RPM = 650 },
	Ammo = { Magazine = 20, Reserve = 100, ReloadTime = 2.4, ReloadEmptyTime = 2.9 },
	Ballistics = { Penetration = 1 },
	Damage = { Base = 36, Falloff = { Start = 200, End = 650, MinScale = 0.6 } },
	Spread = { Hip = 3.0, Aim = 0.22, PerShot = 0.5 },
	Recoil = { Vertical = 1.6, Horizontal = 0.7 },

	Effects = {
		Sounds = { Fire = "rbxassetid://9118173739", FirePitch = 1.15, FireVolume = 0.85, RollOffMax = 900 },
	},

	Attachments = {
		Allowed = {
			Optic = { "RedDot", "Holographic", "ACOG", "SniperScope" },
		},
	},
}
