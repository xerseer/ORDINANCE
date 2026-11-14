--[[
	G36C
	A select-fire rifle. The fire mode key switches between automatic, burst
	and semi-automatic.
]]

return {
	Name = "G36C",
	Description = "5.56mm compact assault rifle with automatic, burst and semi-automatic fire.",

	Fire = {
		Mode = "Auto",
		Modes = { "Auto", "Burst", "Semi" },
		RPM = 750,
		BurstCount = 2,
		BurstRPM = 900,
	},

	Ammo = {
		Magazine = 30,
		Reserve = 150,
		ReloadTime = 2.3,
		ReloadEmptyTime = 2.8,
	},

	Ballistics = {
		Penetration = 0.6,
	},

	Damage = {
		Base = 22,
		Falloff = { Start = 150, End = 500 },
	},

	Spread = {
		Hip = 2.6,
		Aim = 0.3,
		PerShot = 0.3,
	},

	Recoil = {
		Vertical = 0.95,
		Horizontal = 0.55,
	},
}
