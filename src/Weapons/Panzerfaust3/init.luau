--[[
	Panzerfaust 3
	A rocket launcher. One rocket that flies, drops a little and explodes on
	whatever it hits.
]]

return {
	Name = "Panzerfaust 3",
	Description = "Shoulder-fired anti-tank rocket launcher.",
	Scale = 0.62,

	Fire = { Modes = { "Semi" }, RPM = 30 },
	Ammo = { Magazine = 1, Reserve = 4, ReloadTime = 4.5 },
	Ballistics = {
		Type = "Projectile",
		Velocity = 160,
		Gravity = 0.3,
		Drag = 0.02,
		Lifetime = 8,
		Explosive = {
			Enabled = true,
			Damage = 200,
			Radius = 22,
			DetonateOnImpact = true,
			SelfDamageScale = 0.6,
			Knockback = 90,
		},
	},
	Damage = { Base = 60 },
	Spread = { Hip = 2, Aim = 0.2, PerShot = 0 },
	Recoil = { Vertical = 4, Horizontal = 1 },
	Handling = { EquipTime = 1.0, AimTime = 0.35, WalkSpeedScale = 0.8, AimWalkSpeedScale = 0.5 },

	Effects = {
		Projectile = { Size = 0.5, Trail = true },
		Sounds = { Fire = "rbxasset://sounds/impact_explosion_03.mp3", FirePitch = 1.2, FireVolume = 0.8 },
	},

	Attachments = {
		Allowed = { Optic = {}, Muzzle = {}, Underbarrel = {}, Side = {} },
	},
}
