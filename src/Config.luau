--[[
	Ordnance global config

	Everything here is optional. Anything you leave out uses the framework
	default, so an empty table is a complete, working config.

	Precedence, lowest to highest:
		framework defaults  <  Preset  <  this file  <  the weapon's own module

	The Studio plugin's Config tab edits this file for you.
]]

return {
	-- Name of a module in Ordnance.Presets to start from, or nil for defaults.
	Preset = nil,
}
