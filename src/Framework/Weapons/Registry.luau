--!strict
--[[
	Registry
	Finds the weapon modules in Ordnance.Weapons and gets each one ready:
	loads it, resolves its config and prepares its model.

	A weapon is a ModuleScript that returns a table. Folders inside Weapons are
	only for organising; ModuleScripts inside a weapon module belong to that
	weapon and are not weapons themselves.

	A weapon that fails to load is reported and skipped. It never stops the
	others from loading.
]]

local Config = require(script.Parent.Parent.Config)
local Logger = require(script.Parent.Parent.Core.Logger)
local Rig = require(script.Parent.Rig)

export type Entry = {
	id: string,
	module: ModuleScript,
	config: Config.Config,
	template: Model,
}

local log = Logger.scope("Registry")

local Registry = {}

local entries: { [string]: Entry } = {}
local order: { string } = {}

local function findModel(module: ModuleScript, setting: any): Instance?
	if typeof(setting) == "Instance" then
		return setting
	end
	if type(setting) == "string" then
		local named = module:FindFirstChild(setting)
		if named then
			return named
		end
	end
	for _, child in module:GetChildren() do
		if child:IsA("Model") or child:IsA("Tool") or child:IsA("BasePart") then
			return child
		end
	end
	return nil
end

local function loadWeapon(module: ModuleScript)
	local id = module.Name
	if entries[id] then
		log:Warn(`two weapons are named "{id}"; keeping the first, skipping {module:GetFullName()}`)
		return
	end

	local ok, definition = pcall(require, module)
	if not ok then
		log:Error(`weapon "{id}" failed to load: {tostring(definition)}`)
		return
	end
	if type(definition) ~= "table" then
		log:Error(`weapon "{id}" must return a table, got {typeof(definition)}`)
		return
	end

	local config = Config.weapon(id, definition)
	local source = findModel(module, config.Model)
	if source == nil then
		log:Warn(`weapon "{id}" has no model; using a placeholder. Put a Model inside the module.`)
	end

	entries[id] = {
		id = id,
		module = module,
		config = config,
		template = Rig.prepare(source, id, config.Scale),
	}
	table.insert(order, id)
end

local function scan(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("ModuleScript") then
			log:Try(loadWeapon, child)
		elseif child:IsA("Folder") then
			scan(child)
		end
	end
end

-- Loads every weapon under `root.Weapons`. Calling it again reloads.
function Registry.load(root: Instance)
	for _, entry in entries do
		entry.template:Destroy()
	end
	table.clear(entries)
	table.clear(order)

	local folder = root:FindFirstChild("Weapons")
	if folder == nil then
		log:Warn("Ordnance.Weapons is missing; no weapons loaded")
		return
	end
	scan(folder)
	table.sort(order)
	log:Info(`{#order} weapon{if #order == 1 then "" else "s"} ready`)
end

function Registry.get(id: string): Entry?
	return entries[id]
end

-- Weapon ids in alphabetical order.
function Registry.ids(): { string }
	return table.clone(order)
end

return Registry
