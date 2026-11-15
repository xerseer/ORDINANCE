--[[
	Anzio 20mm
	The largest rifle here: a bolt-action 20mm with a three-round magazine.
	Heavy enough to slow you right down.
]]

return {
	Name = "Anzio 20mm",
	Description = "20mm bolt-action anti-materiel rifle.",
	Scale = 0.62,

	Fire = { Modes = { "Semi" }, RPM = 60, Action = "Bolt", CycleTime = 1.4 },
	Ammo = { Magazine = 3, Reserve = 15, ReloadTime = 3.6 },
	Ballistics = { Range = 3500, Penetration = 5 },
	Damage = {
		Base = 220,
		Multipliers = { Head = 2, Torso = 1, Limb = 0.9 },
		Falloff = { Start = 800, End = 2500, MinScale = 0.8 },
	},
	Spread = { Hip = 7, Aim = 0.03 },
	Recoil = { Vertical = 10, Horizontal = 2.5, Recovery = 0.6 },
	Handling = { EquipTime = 1.0, AimFOV = 9, AimTime = 0.45, WalkSpeedScale = 0.7, AimWalkSpeedScale = 0.35 },
	Scope = { Enabled = true },

	Effects = {
		Sounds = { Fire = "rbxassetid://9118173739", FirePitch = 0.6, FireVolume = 1, RollOffMax = 3500 },
	},

	Attachments = {
		Allowed = { Optic = {}, Muzzle = {}, Underbarrel = {}, Side = {} },
	},
}
