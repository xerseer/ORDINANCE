--[[
	Glock 17
	The simplest kind of weapon: a model and a handful of numbers. Everything
	not written here comes from the global config and the framework defaults.
]]

return {
	Name = "Glock 17",
	Description = "9mm semi-automatic pistol.",

	Fire = {
		Modes = { "Semi" },
		RPM = 420,
	},

	Ammo = {
		Magazine = 17,
		Reserve = 68,
		ReloadTime = 1.6,
	},

	Damage = {
		Base = 26,
		Falloff = { Start = 60, End = 220 },
	},

	Recoil = {
		Vertical = 1.4,
		Horizontal = 0.5,
	},
}
