--[[
	Unknown Prototype
	The kit called it "I have no idea what this is", so it got to be something
	nobody expects: it fires slow glowing rounds that bounce off walls three
	times before they give up.
]]

return {
	Name = "Unknown Prototype",
	Description = "Nobody knows what it is. It fires something that bounces.",
	Scale = 0.62,

	Fire = { Mode = "Auto", Modes = { "Auto", "Semi" }, RPM = 520 },
	Ammo = { Magazine = 24, Reserve = 96, ReloadTime = 2.4 },
	Ballistics = {
		Type = "Projectile",
		Velocity = 260,
		Gravity = 0,
		Lifetime = 3,
		Bounce = { Count = 3, Elasticity = 0.95, MinSpeed = 5 },
	},
	Damage = { Base = 28, Falloff = { Start = 80, End = 260 } },
	Spread = { Hip = 2.4, Aim = 0.4, PerShot = 0.2 },
	Recoil = { Vertical = 0.7, Horizontal = 0.6 },

	Effects = {
		Projectile = { Size = 0.3, Color = Color3.fromRGB(110, 230, 255), Trail = true },
		MuzzleFlash = { Color = Color3.fromRGB(110, 230, 255) },
		Sounds = { Fire = "rbxassetid://9114727096", FirePitch = 1.8, FireVolume = 0.55 },
	},

	Attachments = {
		Allowed = { Optic = {}, Muzzle = {}, Underbarrel = {}, Side = {} },
	},
}
