--[[
	Glock 17
	The simplest kind of weapon: a model and a handful of numbers. Everything
	not written here comes from the global config and the framework defaults.

	It also shows encoded animation. The Animations table at the bottom is the
	whole reload and the slide's kick, as plain numbers; delete it and the
	pistol falls back to the framework's procedural motion.
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

	Effects = {
		Sounds = { Fire = "rbxassetid://9117396996", FireVolume = 0.7 }, -- Pistol Single Shots 1 (Pro Sound Effects)
	},

	-- A pistol is held further out and nearer the middle than a rifle.
	Viewmodel = {
		Offset = { 0.42, -0.58, -1.6, 0, 0, 0 },
		AimDistance = 1.5,
	},

	ThirdPerson = {
		Offset = { 0.28, -0.5, -1.0, 0, 5, 0 },
		AimOffset = { 0.06, -0.36, -1.15, 0, 0, 0 },
		BodyTurn = 12,
	},

	--[[
		Each value is six numbers: x, y, z in studs (right, up, back), then
		rotation x, y, z in degrees. All are offsets from rest.
		Weapon moves the whole pistol; Left is the support hand; Mag and Slide
		are parts of the model with those names.
	]]
	Animations = {
		-- Played from the start on every shot. Times are in seconds.
		Fire = {
			Keyframes = {
				{ Time = 0, Slide = { 0, 0, 0, 0, 0, 0 }, Weapon = { 0, 0, 0, 0, 0, 0 } },
				{
					Time = 0.03,
					Slide = { 0, 0, 0.2, 0, 0, 0 },
					Weapon = { 0, 0.01, 0.05, 5, 0, 0 },
					Easing = "QuadOut",
				},
				{
					Time = 0.12,
					Slide = { 0, 0, 0, 0, 0, 0 },
					Weapon = { 0, 0, 0, 0, 0, 0 },
					Easing = "QuadIn",
				},
			},
		},

		-- Stretched to the weapon's ReloadTime, so only the proportions matter.
		Reload = {
			Keyframes = {
				{
					Time = 0,
					Weapon = { 0, 0, 0, 0, 0, 0 },
					Left = { 0, 0, 0, 0, 0, 0 },
					Mag = { 0, 0, 0, 0, 0, 0 },
				},
				-- Tip the pistol to bring the magazine well toward the support hand.
				{ Time = 0.18, Weapon = { 0.05, 0.05, 0.06, 20, 0, -24 }, Easing = "SineOut" },
				{
					Time = 0.3,
					Left = { 0, -0.3, 0.04, 0, 0, 0 },
					Mag = { 0, 0, 0, 0, 0, 0 },
					Easing = "Sine",
				},
				-- The magazine drops; the hand goes for a fresh one.
				{
					Time = 0.46,
					Left = { -0.2, -1.3, 0.25, 0, 0, 0 },
					Mag = { 0, -1.5, 0.15, 0, 0, 0 },
					Easing = "QuadIn",
				},
				-- The fresh magazine comes up and seats.
				{
					Time = 0.68,
					Left = { 0, -0.75, 0.08, 0, 0, 0 },
					Mag = { 0, -0.45, 0.04, 0, 0, 0 },
					Easing = "SineOut",
				},
				{
					Time = 0.78,
					Left = { 0, -0.3, 0.02, 0, 0, 0 },
					Mag = { 0, 0, 0, 0, 0, 0 },
					Easing = "BackOut",
				},
				{ Time = 0.84, Weapon = { 0.05, 0.05, 0.06, 20, 0, -24 } },
				{ Time = 1, Weapon = { 0, 0, 0, 0, 0, 0 }, Left = { 0, 0, 0, 0, 0, 0 }, Easing = "Sine" },
			},
		},
	},
}
