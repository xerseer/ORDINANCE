--[[
	Tactical
	Slower and more deliberate. Hip fire is loose, aimed fire is rewarded,
	recoil has to be controlled, and an early reload keeps the round in the
	chamber.
]]

return {
	Tuning = {
		Recoil = 1.25,
		Spread = 1.15,
		ReloadTime = 1.1,
	},

	Damage = {
		Multipliers = { Head = 2.5, Torso = 1, Limb = 0.7 },
	},

	Spread = {
		Moving = 1.8,
		Airborne = 4.5,
		Recovery = 7,
	},

	Recoil = {
		Recovery = 0.4,
	},

	Handling = {
		EquipTime = 0.5,
		AimTime = 0.24,
		WalkSpeedScale = 0.95,
		AimWalkSpeedScale = 0.6,
	},

	Realism = {
		Chambering = true,
	},
}
