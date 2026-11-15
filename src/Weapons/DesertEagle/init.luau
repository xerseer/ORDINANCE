--[[
	Desert Eagle
	A heavy semi-automatic pistol: few rounds, a lot of kick, a lot of damage.
]]

return {
	Name = "Desert Eagle",
	Description = ".50 AE semi-automatic pistol.",
	Scale = 0.62,

	Fire = { Modes = { "Semi" }, RPM = 260 },
	Ammo = { Magazine = 7, Reserve = 35, ReloadTime = 1.9 },
	Damage = { Base = 48, Falloff = { Start = 60, End = 220 } },
	Spread = { Hip = 2.4, Aim = 0.35, PerShot = 0.8 },
	Recoil = { Vertical = 3.2, Horizontal = 1.0, Recovery = 0.6 },

	Effects = {
		Sounds = { Fire = "rbxassetid://9117396996", FirePitch = 0.8, FireVolume = 0.9 },
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
			Muzzle = {},
			Underbarrel = {},
			Side = { "Flashlight", "Laser" },
		},
	},
}
