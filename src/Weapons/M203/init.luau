--[[
	M203
	A grenade launcher. The round is a physical projectile: it leaves slowly,
	arcs under gravity and explodes on the first thing it touches.

	For a bouncing, timed grenade instead, set:
		Explosive = { DetonateOnImpact = false, Fuse = 3 }
		Bounce = { Count = 4 }
]]

return {
	Name = "M203",
	Description = "40mm grenade launcher. Rounds arc and explode on impact.",

	Fire = {
		Modes = { "Semi" },
		RPM = 60,
	},

	Ammo = {
		Magazine = 1,
		Reserve = 8,
		ReloadTime = 2.6,
	},

	Ballistics = {
		Type = "Projectile",
		Velocity = 190,
		Gravity = 1,
		Drag = 0.05,
		Lifetime = 10,
		Range = 2500,
		Explosive = {
			Enabled = true,
			Damage = 140,
			Radius = 20,
			Falloff = "Linear",
			DetonateOnImpact = true,
			SelfDamageScale = 0.6,
			Knockback = 70,
		},
	},

	Damage = {
		Base = 60,
	},

	Spread = {
		Hip = 1.2,
		Aim = 0.4,
		PerShot = 0,
	},

	Recoil = {
		Vertical = 2.6,
		Horizontal = 0.4,
		Recovery = 0.8,
	},

	Effects = {
		Sounds = { FirePitch = 1.2, FireVolume = 0.7 },
		Tracer = { Enabled = false },
	},
}
