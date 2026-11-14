--!strict
--[[
	Config
	Resolves the settings every other module reads.

	Precedence, lowest to highest:
		Defaults  <  Preset  <  Ordnance.Config  <  weapon module

	Both the server and each client run this against the same replicated
	modules, so they always agree on the result without sending it.

		Config.load(ordnanceRoot)
		local global = Config.global()
		local glock = Config.weapon("Glock17", require(module))
]]

local Logger = require(script.Parent.Core.Logger)

local Defaults = require(script.Defaults)
local Merge = require(script.Merge)
local Schema = require(script.Schema)

export type Config = Defaults.Config

local log = Logger.scope("Config")

local Config = {}

Config.Defaults = Defaults
Config.Schema = Schema
Config.Merge = Merge

local base: { [string]: any } = Merge.copy(Defaults :: any)
local frozenGlobal: Config = Merge.freeze(Merge.copy(Defaults))
local presetName = ""
local loaded = false

local function report(source: string, problems: { Schema.Problem })
	for _, problem in problems do
		local where = if problem.path == "" then source else `{source}: {problem.path}`
		log:Warn(`{where} {problem.message}`)
	end
end

local function requireTable(module: Instance?, label: string): any
	if module == nil then
		return nil
	end
	if not module:IsA("ModuleScript") then
		log:Warn(`{label} should be a ModuleScript, found a {module.ClassName}`)
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		log:Error(`{label} failed to load: {tostring(result)}`)
		return nil
	end
	if type(result) ~= "table" then
		log:Warn(`{label} must return a table, got {typeof(result)}`)
		return nil
	end
	return result
end

-- Reads Ordnance.Config and its preset. Safe to call more than once; later
-- calls reload, which the plugin uses for live previews.
function Config.load(root: Instance)
	local globalInput = requireTable(root:FindFirstChild("Config"), "Ordnance.Config") or {}
	local globalClean, globalProblems = Schema.validate(globalInput, "Global")

	local presetClean: { [string]: any }? = nil
	local presetProblems: { Schema.Problem } = {}
	presetName = if type(globalClean.Preset) == "string" then globalClean.Preset else ""
	if presetName ~= "" then
		local presets = root:FindFirstChild("Presets")
		local module = if presets then presets:FindFirstChild(presetName) else nil
		if module == nil then
			table.insert(
				presetProblems,
				{ path = "", message = "was not found in Ordnance.Presets; using defaults" }
			)
		else
			local presetInput = requireTable(module, `Preset "{presetName}"`)
			if presetInput then
				presetClean, presetProblems = Schema.validate(presetInput, "Preset")
			end
		end
	end

	base = Merge.layers(Defaults :: any, presetClean, globalClean)
	base.Preset = presetName
	frozenGlobal = Merge.freeze(Merge.copy(base)) :: any
	loaded = true

	-- Configure the logger first so the reports below follow the user's settings.
	Logger.configure(base.Debug.Logger)
	report(`Preset "{presetName}"`, presetProblems)
	report("Ordnance.Config", globalProblems)
end

function Config.isLoaded(): boolean
	return loaded
end

-- The resolved global config. Frozen.
function Config.global(): Config
	return frozenGlobal
end

function Config.presetName(): string
	return presetName
end

-- Resolves one weapon's config from its module table. Frozen.
function Config.weapon(name: string, definition: any): Config
	local clean, problems = Schema.validate(definition, "Weapon")
	report(`Weapon "{name}"`, problems)

	local resolved = Merge.deep(base, clean)
	if resolved.Name == "" then
		resolved.Name = name
	end

	-- Fold the tuning multipliers into the numbers, so nothing downstream has
	-- to know they exist.
	local tuning = resolved.Tuning
	resolved.Damage.Base *= tuning.Damage
	resolved.Ballistics.Explosive.Damage *= tuning.Damage
	resolved.Recoil.Vertical *= tuning.Recoil
	resolved.Recoil.Horizontal *= tuning.Recoil
	for _, key in { "Hip", "Aim", "Moving", "Airborne", "PerShot", "Max" } do
		resolved.Spread[key] *= tuning.Spread
	end
	resolved.Ammo.ReloadTime *= tuning.ReloadTime
	resolved.Ammo.ReloadEmptyTime *= tuning.ReloadTime
	resolved.Ammo.ShellTime *= tuning.ReloadTime
	resolved.Fire.RPM *= tuning.FireRate
	resolved.Fire.BurstRPM *= tuning.FireRate

	-- A starting mode that is not selectable would strand the player in it.
	if not table.find(resolved.Fire.Modes, resolved.Fire.Mode) then
		local fire = clean.Fire
		if fire and fire.Modes and #fire.Modes > 0 and fire.Mode == nil then
			resolved.Fire.Mode = resolved.Fire.Modes[1]
		else
			table.insert(resolved.Fire.Modes, 1, resolved.Fire.Mode)
		end
	end

	return Merge.freeze(resolved) :: any
end

return Config
