--[[
	PKM
	A belt-fed machine gun with a hundred-round box. Slow to move with, slow
	to reload, and it does not stop.
]]

return {
	Name = "PKM",
	Description = "7.62mm general-purpose machine gun.",
	Scale = 0.62,

	Fire = { Mode = "Auto", Modes = { "Auto" }, RPM = 650 },
	Ammo = { Magazine = 100, Reserve = 200, ReloadTime = 5.5, ReloadEmptyTime = 6 },
	Ballistics = { Penetration = 1.2 },
	Damage = { Base = 34, Falloff = { Start = 200, End = 600, MinScale = 0.6 } },
	Spread = { Hip = 3.6, Aim = 0.7, PerShot = 0.25, Max = 7 },
	Recoil = { Vertical = 1.0, Horizontal = 0.7 },
	Handling = { EquipTime = 0.8, AimTime = 0.3, WalkSpeedScale = 0.82, AimWalkSpeedScale = 0.55 },

	Effects = {
		Sounds = { Fire = "rbxassetid://9118173739", FirePitch = 1.0, FireVolume = 0.9, RollOffMax = 1000 },
	},

	Attachments = {
		Allowed = {
			Optic = { "RedDot", "ACOG" },
			Muzzle = {},
			Underbarrel = {},
			Side = {},
		},
	},
}
