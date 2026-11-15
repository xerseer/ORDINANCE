--[[
	M1911
	A .45 service pistol. Eight rounds that hit hard.
]]

return {
	Name = "M1911",
	Description = ".45 ACP semi-automatic pistol.",
	Scale = 0.62,

	Fire = { Modes = { "Semi" }, RPM = 380 },
	Ammo = { Magazine = 8, Reserve = 48, ReloadTime = 1.7 },
	Damage = { Base = 32, Falloff = { Start = 60, End = 200 } },
	Recoil = { Vertical = 1.8, Horizontal = 0.6 },

	Effects = {
		Sounds = { Fire = "rbxassetid://9117396996", FirePitch = 0.9, FireVolume = 0.75 },
	},

	Viewmodel = {
		Offset = { 0.42, -0.58, -1.6, 0, 0, 0 },
		AimDistance = 1.5,
	},

	ThirdPerson = {
		Offset = { 0.28, -0.5, -1.0, 0, 5, 0 },
		AimOffset = { 0.06, -0.36, -1.15, 0, 0, 0 },
		BodyTurn = 12,
	},

	Attachments = {
		Allowed = {
			Optic = { "RedDot" },
			Muzzle = { "Suppressor" },
			Underbarrel = {},
			Side = { "Flashlight", "Laser" },
		},
	},
}
