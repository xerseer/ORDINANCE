--[[
	KitSpecs
	Where each example weapon built by RigKit holds, fires from and aims,
	in the gun's own frame (x right, y up, z back, from the centre of its box,
	before Scale). Positions were read off RigKit.profile.

	Rebuild one:
		local RigKit = require(game.ServerStorage.OrdnanceDev.RigKit)
		local Specs = require(game.ServerStorage.OrdnanceDev.KitSpecs)
		print(RigKit.build(Specs.source("MP5"), Specs.MP5))
]]

local V = Vector3.new

local PART_KIT = { forward = Vector3.zAxis, up = -Vector3.xAxis }

local Specs = {
	-- Sniper and anti-materiel
	Anzio20mm = {
		path = { "Model", "Anzio 20mm" },
		handle = V(0, -0.45, 4.55),
		barrel = V(0, 0.11, -7.09),
		grip = V(0, -0.35, 1.6),
		mag = V(0, -0.45, 3.55),
		aim = V(0, 0.72, 4.7),
	},
	SVD = {
		path = { "Model", "SVD" },
		handle = V(0, -0.55, 2.6),
		barrel = V(0, 0.1, -4.91),
		grip = V(0, -0.27, -0.9),
		mag = V(0, -0.45, 1.16),
		aim = V(0, 0.62, 2.9),
		names = { [6] = "Mag" },
	},
	BarrettM99 = {
		path = { "Model", "Barrett M99" },
		handle = V(0, -0.4, 1.95),
		barrel = V(0, 0.16, -4.09),
		grip = V(0, -0.35, -0.5),
		mag = V(0, -0.3, 1.0),
		aim = V(0, 0.62, 2.3),
	},
	SnipexTRex = {
		path = { "Model", "Snipex T-rex" },
		handle = V(0, -0.45, 2.95),
		barrel = V(0, 0.15, -4.96),
		grip = V(0, -0.45, 0.4),
		mag = V(0, -0.2, 1.0),
		aim = V(0, 0.7, 3.3),
	},

	-- Launchers and the unknown
	Panzerfaust3 = {
		path = { "Model", "Panzerfaust 3" },
		handle = V(0, -0.6, 0.4),
		barrel = V(0, 0.56, -4.0),
		grip = V(0, -0.7, -1.1),
		mag = V(0, 0.2, -2.0),
		aim = V(0, 1.05, 1.0),
	},
	Prototype = {
		path = { "Model", "I have no idea what this is" },
		handle = V(0, -0.55, 0.8),
		barrel = V(0, 0.23, -3.1),
		grip = V(0, -0.35, -0.9),
		mag = V(0, -0.3, 1.6),
		aim = V(0, 0.95, 0.6),
	},

	-- Rifles
	Honeybadger = {
		path = { "Model", "Honeybadger" },
		handle = V(0, -0.5, 1.3),
		barrel = V(0, 0.46, -3.1),
		grip = V(0, 0.0, -0.8),
		mag = V(0, -0.45, 0.2),
		aim = V(0, 0.95, 1.0),
		names = { [4] = "Mag" },
	},
	SCARL = {
		path = { "Model", "Scar L" },
		handle = V(0, -0.35, 1.15),
		barrel = V(0, 0.3, -2.9),
		grip = V(0, -0.1, -0.8),
		mag = V(0, -0.2, 0.07),
		aim = V(0, 0.72, 1.0),
		names = { [3] = "Mag" },
	},
	AUGA3 = {
		path = { "Model", "AUG A-3" },
		handle = V(0, -0.3, 0.4),
		barrel = V(0, 0.41, -3.1),
		grip = V(0, -0.35, -1.2),
		mag = V(0, -0.3, 1.35),
		aim = V(0, 1.15, 0.7),
		names = { [3] = "Mag" },
	},
	FNFAL = {
		path = { "Model", "FN FAL" },
		handle = V(0, -0.3, 1.75),
		barrel = V(0, 0.33, -3.53),
		grip = V(0, 0.02, -0.8),
		mag = V(0, -0.2, 0.72),
		aim = V(0, 0.66, 1.6),
		names = { [9] = "Mag" },
	},
	HK416A5 = {
		path = { "GunModels", "WEAPONS", "ASSAULT RIFLES", "AR-15 VARIANTS", "VARIANTS #1", "H&K HK416A5" },
		frame = PART_KIT,
		handle = V(0, -0.25, 0.65),
		barrel = V(0, 0.285, -1.9),
		grip = V(0, -0.08, -0.9),
		mag = V(0, -0.15, -0.07),
		aim = V(0, 0.6, 0.4),
		names = { [1] = "Mag" },
	},
	LVOA = {
		path = { "GunModels", "WEAPONS", "ASSAULT RIFLES", "AR-15 VARIANTS", "VARIANTS #2", 'WARSPORT LVOA, 14.7"' },
		frame = PART_KIT,
		handle = V(0, -0.2, 0.62),
		barrel = V(0, 0.44, -2.13),
		grip = V(0, 0.12, -1.1),
		mag = V(0, -0.05, -0.03),
		aim = V(0, 0.68, 0.6),
		names = { [17] = "Mag" },
	},
	PKM = {
		path = { "Model", "PKM" },
		handle = V(0, -0.3, 1.5),
		barrel = V(0, 0.36, -3.31),
		grip = V(0, -0.05, -0.6),
		mag = V(0, -0.3, 0.27),
		aim = V(0, 0.75, 1.2),
		names = { [2] = "Mag" },
	},

	-- Submachine guns
	MP5 = {
		path = { "Model", "MP5" },
		handle = V(0, -0.35, 0.55),
		barrel = V(0, 0.55, -2.66),
		grip = V(0, 0.22, -1.75),
		mag = V(0, -0.2, -0.86),
		aim = V(0, 0.95, 0.4),
		names = { [4] = "Mag" },
	},
	KrissVector = {
		path = { "Model", "Kriss Vector" },
		handle = V(0, -0.35, 0.25),
		barrel = V(0, 0.36, -2.49),
		grip = V(0, -0.6, -1.65),
		mag = V(0, -0.4, -0.8),
		aim = V(0, 0.86, 0.3),
		names = { [2] = "Mag" },
	},
	P90 = {
		path = { "Model", "FN P-90" },
		handle = V(0, -0.55, -0.7),
		barrel = V(0, -0.05, -2.23),
		grip = V(0, -0.6, -1.5),
		mag = V(0, 0.2, 0.3),
		aim = V(0, 0.78, -0.6),
	},
	MP7 = {
		path = { "Model", "MP7" },
		handle = V(0, -0.25, -0.45),
		barrel = V(0, 0.44, -2.26),
		grip = V(0, -0.15, -1.62),
		mag = V(0, -0.6, -0.48),
		aim = V(0, 0.88, -0.2),
	},
	Uzi = {
		path = { "Model", "IMI UZI" },
		handle = V(0, -0.15, -0.25),
		barrel = V(0, 0.62, -2.81),
		grip = V(0, 0.15, -1.4),
		mag = V(0, -0.6, -0.35),
		aim = V(0, 1.0, 0.6),
		names = { [2] = "Mag" },
	},

	-- Pistols and revolver
	DesertEagle = {
		path = { "Model", "Deagle" },
		handle = V(0, -0.35, 0.6),
		barrel = V(0, 0.38, -0.99),
		mag = V(0, -0.2, 0.55),
		aim = V(0, 0.58, 0.75),
		names = { [2] = "Slide" },
	},
	M1911 = {
		path = { "Model", "M1911" },
		handle = V(0, -0.3, 0.65),
		barrel = V(0, 0.42, -0.94),
		mag = V(0, -0.2, 0.6),
		aim = V(0, 0.62, 0.75),
	},
	ChiappaRhino = {
		path = { "Model", "Chiappa Rhino" },
		handle = V(0, -0.25, 0.78),
		barrel = V(0, 0.24, -1.14),
		mag = V(0, 0.3, 0.3),
		aim = V(0, 0.65, 0.6),
	},

	-- Shotguns
	ArmselStriker = {
		path = { "Model", "Armsel Striker" },
		handle = V(0, -0.5, 0.62),
		barrel = V(0, 0.26, -3.11),
		grip = V(0, -0.3, -1.97),
		mag = V(0, -0.2, -0.5),
		aim = V(0, 0.6, 0.5),
	},
	SPAS12 = {
		path = { "Model", "Spas 12" },
		handle = V(0, -0.35, 1.4),
		barrel = V(0, 0.33, -3.57),
		grip = V(0, -0.2, -1.9),
		mag = V(0, -0.1, 0.3),
		aim = V(0, 0.62, 1.1),
	},
	AA12 = {
		path = { "Model", "AA-12" },
		handle = V(0, -0.45, 0.85),
		barrel = V(0, 0.31, -2.89),
		grip = V(0, -0.1, -1.4),
		mag = V(0, -0.4, -0.2),
		aim = V(0, 1.05, 0.75),
		names = { [2] = "Mag" },
	},
}

-- The kit model a spec is built from.
function Specs.source(id: string): Instance
	local node: Instance = workspace.Models
	for _, name in (Specs :: any)[id].path do
		node = (node :: any)[name]
	end
	return node
end

-- RigKit's frame options for a spec.
function Specs.options(id: string): any
	local spec = (Specs :: any)[id]
	local options = table.clone(spec)
	if spec.frame then
		options.forward = spec.frame.forward
		options.up = spec.frame.up
	end
	return options
end

return Specs
