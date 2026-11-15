--[[
	Honeybadger
	A rifle with a suppressor built in: quiet, no muzzle flash, short reach.
]]

return {
	Name = "Honeybadger",
	Description = ".300 Blackout integrally suppressed rifle.",
	Scale = 0.62,

	Fire = { Mode = "Auto", Modes = { "Auto", "Semi" }, RPM = 800 },
	Ammo = { Magazine = 30, Reserve = 150, ReloadTime = 2.2, ReloadEmptyTime = 2.7 },
	Damage = { Base = 25, Falloff = { Start = 100, End = 320 } },
	Spread = { Hip = 2.4, Aim = 0.3, PerShot = 0.25 },
	Recoil = { Vertical = 0.7, Horizontal = 0.45 },

	Effects = {
		MuzzleFlash = { Enabled = false },
		Sounds = { Fire = "rbxassetid://9114727096", FirePitch = 1.4, FireVolume = 0.3, RollOffMax = 160 },
	},

	Attachments = {
		Allowed = {
			Optic = { "RedDot", "Holographic", "ACOG" },
			Muzzle = {},
		},
	},
}
