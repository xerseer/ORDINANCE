--[[
	Arcade
	Point and click. No reserve to manage, generous accuracy, gentle recoil,
	quick reloads and nothing to learn beyond aim, shoot and reload.
]]

return {
	Ammo = {
		Infinite = true,
		AutoReload = true,
	},

	Tuning = {
		Recoil = 0.5,
		Spread = 0.6,
		ReloadTime = 0.7,
	},

	Damage = {
		Falloff = { MinScale = 0.8 },
	},

	Handling = {
		EquipTime = 0.2,
		AimTime = 0.12,
		AimWalkSpeedScale = 0.9,
	},

	Recoil = {
		Recovery = 0.9,
	},

	Realism = {
		Chambering = false,
		ManualCycle = false,
		DropMagazine = false,
		Malfunctions = { Enabled = false },
	},
}
