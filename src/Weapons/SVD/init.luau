--[[
	SVD Dragunov
	A semi-automatic marksman rifle with its own PSO-1 scope.
]]

return {
	Name = "SVD",
	Description = "7.62x54mmR semi-automatic marksman rifle.",
	Scale = 0.62,

	Fire = { Modes = { "Semi" }, RPM = 300 },
	Ammo = { Magazine = 10, Reserve = 40, ReloadTime = 2.6, ReloadEmptyTime = 3.2 },
	Ballistics = { Range = 2000, Penetration = 1.5 },
	Damage = {
		Base = 70,
		Multipliers = { Head = 2.5, Torso = 1, Limb = 0.8 },
		Falloff = { Start = 400, End = 1200, MinScale = 0.7 },
	},
	Spread = { Hip = 4, Aim = 0.05, PerShot = 0.6 },
	Recoil = { Vertical = 2.4, Horizontal = 0.8 },
	Handling = { AimFOV = 18, AimTime = 0.3, AimWalkSpeedScale = 0.5 },
	Scope = { Enabled = true },

	Effects = {
		Sounds = { Fire = "rbxassetid://9118173739", FirePitch = 1.05, FireVolume = 0.9, RollOffMax = 1500 },
	},

	Attachments = {
		Allowed = { Optic = {}, Muzzle = {}, Underbarrel = {}, Side = {} },
	},
}
