--[[
	AAC M4-2000
	A suppressor. Quieter and higher pitched, no muzzle flash, a little less
	kick. The sound only carries a short way.
]]

return {
	Name = "AAC M4-2000 Suppressor",
	Slot = "Muzzle",
	Config = {
		Effects = {
			MuzzleFlash = { Enabled = false },
			Sounds = { FireVolume = 0.3, FirePitch = 1.4, RollOffMax = 160 },
		},
	},
	Tuning = { Recoil = 0.92 },
}
