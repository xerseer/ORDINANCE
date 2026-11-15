--[[
	Ak-47
	A select-fire rifle. The fire mode key switches between automatic and
	semi-automatic.

	The model is from the MeshPart gun kit in Workspace.Models, stored here as
	Parts with SpecialMeshes so Rojo can sync it. It was built about 1.6 times
	the size of the other rifles, so Scale brings it down.
]]

return {
	Name = "Ak-47",
	Description = "7.62mm assault rifle with automatic and semi-automatic fire.",
	Scale = 0.62,

	Fire = {
		Mode = "Auto",
		Modes = { "Auto", "Semi" },
		RPM = 750,
	},

	Ammo = {
		Magazine = 37,
		Reserve = 150,
		ReloadTime = 2.3,
		ReloadEmptyTime = 2.8,
	},

	Ballistics = {
		Penetration = 0.6,
	},

	Damage = {
		Base = 38,
		Falloff = { Start = 150, End = 500 },
	},

	Spread = {
		Hip = 2.6,
		Aim = 0.3,
		PerShot = 0.3,
	},

	Recoil = {
		Vertical = 0.75,
		Horizontal = 0.55,
	},
}
