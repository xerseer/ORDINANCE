--[[
	Uzi
	An open-bolt submachine gun: slow-firing for its class and loose from the hip.
]]

return {
	Name = "Uzi",
	Description = "9mm submachine gun.",
	Scale = 0.62,

	Fire = { Mode = "Auto", Modes = { "Auto", "Semi" }, RPM = 600 },
	Ammo = { Magazine = 32, Reserve = 128, ReloadTime = 2.1 },
	Damage = { Base = 20, Falloff = { Start = 50, End = 170 } },
	Spread = { Hip = 3.0, Aim = 0.6, PerShot = 0.25 },
	Recoil = { Vertical = 0.8, Horizontal = 0.6 },

	Effects = {
		Sounds = { Fire = "rbxassetid://9114727096", FirePitch = 1.05, FireVolume = 0.7 },
	},

	Attachments = {
		Allowed = {
			Optic = {},
			Muzzle = { "Suppressor" },
			Underbarrel = {},
		},
	},
}
