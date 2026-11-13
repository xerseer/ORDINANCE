--!strict
--[[
	Damage
	The arithmetic of how much a hit hurts. No instances are touched here; the
	server's Combat module applies the result.
]]

local Defaults = require(script.Parent.Parent.Config.Defaults)

type Config = Defaults.Config

export type Group = "Head" | "Torso" | "Limb"

local Damage = {}

local TORSO: { [string]: boolean } = {
	Torso = true,
	UpperTorso = true,
	LowerTorso = true,
	HumanoidRootPart = true,
}

-- Which multiplier a body part uses. Works for R6 and R15 part names;
-- anything unrecognised (accessories, custom rigs) counts as a limb.
function Damage.group(partName: string): Group
	if partName == "Head" then
		return "Head"
	elseif TORSO[partName] then
		return "Torso"
	end
	return "Limb"
end

-- Damage multiplier for distance: 1 up to Falloff.Start, MinScale from Falloff.End.
function Damage.falloff(config: Config, distance: number): number
	local falloff = config.Damage.Falloff
	if distance <= falloff.Start or falloff.End <= falloff.Start then
		return 1
	end
	local alpha = math.clamp((distance - falloff.Start) / (falloff.End - falloff.Start), 0, 1)
	return 1 + (falloff.MinScale - 1) * alpha
end

-- Damage of one round that hit `partName` after travelling `distance` studs.
function Damage.bullet(config: Config, partName: string, distance: number): (number, Group)
	local group = Damage.group(partName)
	local multiplier = config.Damage.Multipliers[group]
	return config.Damage.Base * multiplier * Damage.falloff(config, distance), group
end

-- Damage multiplier at `distance` from the centre of a blast. 0 outside it.
function Damage.blast(config: Config, distance: number): number
	local explosive = config.Ballistics.Explosive
	if distance >= explosive.Radius then
		return 0
	end
	local alpha = distance / explosive.Radius
	local falloff = explosive.Falloff
	if falloff == "None" then
		return 1
	elseif falloff == "Quadratic" then
		alpha *= alpha
	end
	return 1 + (explosive.MinScale - 1) * alpha
end

return Damage
