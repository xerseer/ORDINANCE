--[[
	Remington 870
	A pump-action shotgun: several pellets per shell, a pump between shots, and
	shells loaded one at a time. Firing interrupts the reload.
]]

return {
	Name = "Remington 870",
	Description = "12 gauge pump-action shotgun.",

	Fire = {
		Modes = { "Semi" },
		RPM = 240,
		Pellets = 9,
		Action = "Pump",
		CycleTime = 0.55,
	},

	Ammo = {
		Magazine = 6,
		Reserve = 30,
		ReloadType = "Single",
		ShellTime = 0.5,
	},

	Ballistics = {
		Range = 260,
	},

	Damage = {
		Base = 13,
		Multipliers = { Head = 1.4, Torso = 1, Limb = 0.85 },
		Falloff = { Start = 25, End = 110, MinScale = 0.2 },
	},

	Spread = {
		Hip = 4.2,
		Aim = 3.2,
		Moving = 0.6,
		PerShot = 0,
		Max = 6,
	},

	Recoil = {
		Vertical = 3.8,
		Horizontal = 1.2,
		Recovery = 0.7,
	},

	Effects = {
		Tracer = { Width = 0.04, Length = 5 },
		-- A rifle shot slowed down: heavier and boomier, close to a 12 gauge.
		Sounds = { Fire = "rbxassetid://9114726684", FirePitch = 0.72, FireVolume = 1 },
	},
}
