--[[
	Barrett M99
	A single-shot .50 calibre rifle: one round, then a reload.
]]

return {
	Name = "Barrett M99",
	Description = ".50 BMG single-shot anti-materiel rifle.",
	Scale = 0.62,

	Fire = { Modes = { "Semi" }, RPM = 60 },
	Ammo = { Magazine = 1, Reserve = 20, ReloadTime = 2.4 },
	Ballistics = { Range = 3000, Penetration = 3 },
	Damage = {
		Base = 140,
		Multipliers = { Head = 2, Torso = 1, Limb = 0.9 },
		Falloff = { Start = 600, End = 2000, MinScale = 0.8 },
	},
	Spread = { Hip = 5, Aim = 0.03 },
	Recoil = { Vertical = 6, Horizontal = 1.5, Recovery = 0.6 },
	Handling = { AimFOV = 10, AimTime = 0.4, WalkSpeedScale = 0.85, AimWalkSpeedScale = 0.45 },
	Scope = { Enabled = true },

	Effects = {
		Sounds = { Fire = "rbxassetid://9118173739", FirePitch = 0.78, FireVolume = 1, RollOffMax = 2500 },
	},

	Attachments = {
		Allowed = { Optic = {}, Muzzle = {}, Underbarrel = {}, Side = {} },
	},
}
