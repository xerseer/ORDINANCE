--[[
	Chiappa Rhino
	A revolver that fires from the bottom chamber, so it kicks less than it
	should. Six rounds, loaded one at a time.
]]

return {
	Name = "Chiappa Rhino",
	Description = ".357 Magnum revolver.",
	Scale = 0.62,

	Fire = { Modes = { "Semi" }, RPM = 220 },
	Ammo = { Magazine = 6, Reserve = 36, ReloadType = "Single", ShellTime = 0.45 },
	Damage = { Base = 42, Falloff = { Start = 70, End = 240 } },
	Recoil = { Vertical = 2.4, Horizontal = 0.7 },

	Effects = {
		Sounds = { Fire = "rbxassetid://9117396996", FirePitch = 0.75, FireVolume = 0.9 },
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
			Side = { "Laser" },
		},
	},
}
