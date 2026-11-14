--[[
	Remington 700
	A bolt-action rifle with the realism options on: the chambered round is
	tracked separately from the magazine, and every shot needs the bolt cycled
	before the next.
]]

return {
	Name = "Remington 700",
	Description = "Bolt-action .308 rifle. One shot, then work the bolt.",

	Fire = {
		Modes = { "Semi" },
		RPM = 300,
		Action = "Bolt",
		CycleTime = 1.15,
	},

	Ammo = {
		Magazine = 5,
		Reserve = 30,
		ReloadTime = 3.2,
	},

	Ballistics = {
		Range = 3000,
		Penetration = 1.5,
	},

	Damage = {
		Base = 85,
		Multipliers = { Head = 2.5, Torso = 1.1, Limb = 0.8 },
		Falloff = { Start = 600, End = 2000, MinScale = 0.75 },
	},

	Spread = {
		Hip = 4.5,
		Aim = 0.02,
		Moving = 2.5,
		PerShot = 0,
	},

	Recoil = {
		Vertical = 3.2,
		Horizontal = 0.7,
		Recovery = 0.75,
	},

	Handling = {
		AimFOV = 22,
		AimTime = 0.3,
		AimWalkSpeedScale = 0.5,
	},

	Realism = {
		Chambering = true,
	},

	Effects = {
		Sounds = { Fire = "rbxassetid://9118173739", FireVolume = 0.9, RollOffMax = 1500 }, -- Rifle Single Shots 1 (Pro Sound Effects)
	},
}
