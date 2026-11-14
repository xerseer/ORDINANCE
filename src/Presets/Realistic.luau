--[[
	Realistic
	Everything on. The chamber is tracked, bolts and pumps are worked by hand,
	a dropped magazine takes its rounds with it, weapons can jam, and there is
	no crosshair or hitmarker to lean on. Hits are lethal.
]]

return {
	Tuning = {
		Damage = 1.6,
		Recoil = 1.5,
		Spread = 1.2,
		ReloadTime = 1.2,
	},

	Ammo = {
		AutoReload = false,
	},

	Damage = {
		Multipliers = { Head = 4, Torso = 1.2, Limb = 0.6 },
		FriendlyFire = true,
	},

	Spread = {
		Moving = 2.4,
		Airborne = 6,
		Recovery = 5,
	},

	Recoil = {
		Recovery = 0.25,
		Damping = 0.65,
	},

	Handling = {
		EquipTime = 0.65,
		AimTime = 0.3,
		WalkSpeedScale = 0.9,
		AimWalkSpeedScale = 0.45,
	},

	Realism = {
		Chambering = true,
		ManualCycle = true,
		DropMagazine = true,
		Malfunctions = { Enabled = true, Chance = 0.002 },
	},

	HUD = {
		Crosshair = false,
		Hitmarker = false,
	},
}
