--[[
	Snipex T-Rex
	A single-shot 14.5mm rifle. It goes through nearly anything.
]]

return {
	Name = "Snipex T-Rex",
	Description = "14.5x114mm single-shot anti-materiel rifle.",
	Scale = 0.62,

	Fire = { Modes = { "Semi" }, RPM = 50 },
	Ammo = { Magazine = 1, Reserve = 15, ReloadTime = 3.2 },
	Ballistics = { Range = 3500, Penetration = 4 },
	Damage = {
		Base = 180,
		Multipliers = { Head = 2, Torso = 1, Limb = 0.9 },
		Falloff = { Start = 800, End = 2500, MinScale = 0.8 },
	},
	Spread = { Hip = 6, Aim = 0.03 },
	Recoil = { Vertical = 8, Horizontal = 2, Recovery = 0.6 },
	Handling = { EquipTime = 0.9, AimFOV = 9, AimTime = 0.45, WalkSpeedScale = 0.8, AimWalkSpeedScale = 0.4 },
	Scope = { Enabled = true },

	Effects = {
		Sounds = { Fire = "rbxassetid://9118173739", FirePitch = 0.7, FireVolume = 1, RollOffMax = 3000 },
	},

	Attachments = {
		Allowed = { Optic = {}, Muzzle = {}, Underbarrel = {}, Side = {} },
	},
}
