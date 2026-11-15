--!strict
--[[
	Registry
	Finds the weapon modules in Ordnance.Weapons and gets each one ready:
	loads it, resolves its config and prepares its model.

	A weapon is a ModuleScript that returns a table. Folders inside Weapons are
	only for organising; ModuleScripts inside a weapon module belong to that
	weapon and are not weapons themselves.

	A weapon with attachments fitted is a variant: its own config (the
	attachments' settings laid over the weapon's) and its own model (the
	attachment models mounted on it). Variants are built when first asked for
	and kept. The server and every client build the same variant from the
	same short key, so only the key is ever sent.

	A weapon that fails to load is reported and skipped. It never stops the
	others from loading.
]]

local Attachments = require(script.Parent.Attachments)
local Config = require(script.Parent.Parent.Config)
local Logger = require(script.Parent.Parent.Core.Logger)
local Rig = require(script.Parent.Rig)

export type Gadgets = {
	light: Attachments.Light?,
	laser: Attachments.Laser?,
	scope: Attachments.Scope?,
}

export type Entry = {
	id: string,
	module: ModuleScript,
	config: Config.Config,
	template: Model,
	definition: { [string]: any }, -- the module's table
	fitted: { [string]: string }, -- slot -> attachment id
	key: string, -- Attachments.encode(fitted); "" for the bare weapon
	gadgets: Gadgets,
}

local WEAPON_ATTRIBUTE = "OrdnanceWeapon"
local FITTED_ATTRIBUTE = "OrdnanceAttachments"

local log = Logger.scope("Registry")

local Registry = {}

Registry.WeaponAttribute = WEAPON_ATTRIBUTE
Registry.FittedAttribute = FITTED_ATTRIBUTE

local entries: { [string]: Entry } = {}
local variants: { [string]: Entry } = {}
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
		definition = definition,
		fitted = {},
		key = "",
		gadgets = { scope = if config.Scope.Enabled then config.Scope :: any else nil },
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

-- Loads every weapon under `root.Weapons` and every attachment under
-- `root.Attachments`. Calling it again reloads.
function Registry.load(root: Instance)
	for _, entry in entries do
		entry.template:Destroy()
	end
	for _, entry in variants do
		entry.template:Destroy()
	end
	table.clear(entries)
	table.clear(variants)
	table.clear(order)

	Attachments.load(root)
	local folder = root:FindFirstChild("Weapons")
	if folder == nil then
		log:Warn("Ordnance.Weapons is missing; no weapons loaded")
		return
	end
	scan(folder)
	table.sort(order)
	log:Info(`{#order} weapon{if #order == 1 then "" else "s"} ready`)
end

-- The bare weapon, with nothing fitted.
function Registry.get(id: string): Entry?
	return entries[id]
end

-- Weapon ids in alphabetical order.
function Registry.ids(): { string }
	return table.clone(order)
end

-- Whether `attachmentId` may be fitted to a weapon in `slot`.
function Registry.accepts(entry: Entry, slot: string, attachmentId: string): boolean
	local attachment = Attachments.get(attachmentId)
	if attachment == nil or attachment.slot ~= slot then
		return false
	end
	local allowed = (entry.config.Attachments.Allowed :: any)[slot]
	if type(allowed) ~= "table" then
		return true
	end
	return table.find(allowed, attachmentId) ~= nil or table.find(allowed, "*") ~= nil
end

-- Every attachment id a weapon accepts in `slot`.
function Registry.options(entry: Entry, slot: string): { string }
	local result = {}
	for _, id in Attachments.ids(slot :: any) do
		if Registry.accepts(entry, slot, id) then
			table.insert(result, id)
		end
	end
	return result
end

-- What a weapon comes with: its Attachments.Default, minus anything it cannot take.
function Registry.defaults(entry: Entry): { [string]: string }
	local fitted = {}
	for slot, id in entry.config.Attachments.Default :: any do
		if type(slot) == "string" and type(id) == "string" then
			if Registry.accepts(entry, slot, id) then
				fitted[slot] = id
			else
				log:WarnOnce(
					`default:{entry.id}:{slot}`,
					`weapon "{entry.id}": the default {slot} "{id}" does not exist or does not fit`
				)
			end
		end
	end
	return fitted
end

-- A weapon with attachments fitted. Attachments that do not fit are left off.
function Registry.variant(id: string, fitted: { [string]: string }?): Entry?
	local base = entries[id]
	if base == nil then
		return nil
	end
	local clean = {}
	for slot, attachmentId in fitted or {} do
		if Registry.accepts(base, slot, attachmentId) then
			clean[slot] = attachmentId
		end
	end
	local key = Attachments.encode(clean)
	if key == "" then
		return base
	end
	local cacheKey = `{id}|{key}`
	local cached = variants[cacheKey]
	if cached then
		return cached
	end

	local layers: { Config.Layer } = {}
	local gadgets: Gadgets = {}
	local template = base.template:Clone()
	local ownScope = base.gadgets.scope
	for _, slot in Attachments.Slots do
		local attachmentId = clean[slot]
		local attachment = if attachmentId then Attachments.get(attachmentId) else nil
		if attachment then
			table.insert(layers, { config = attachment.config, tuning = attachment.tuning })
			Rig.mount(template, slot, attachment.template)
			gadgets.light = gadgets.light or attachment.light
			gadgets.laser = gadgets.laser or attachment.laser
			gadgets.scope = gadgets.scope or attachment.scope
		end
	end

	if gadgets.scope == nil and clean.Optic == nil then
		gadgets.scope = ownScope -- a built-in scope, unless an optic replaced it
	end

	local entry: Entry = {
		id = id,
		module = base.module,
		config = Config.weapon(id, base.definition, layers, true),
		template = template,
		definition = base.definition,
		fitted = clean,
		key = key,
		gadgets = gadgets,
	}
	variants[cacheKey] = entry
	return entry
end

-- The weapon a Tool or held model is, with whatever is fitted to it.
function Registry.entryFor(instance: Instance): Entry?
	local id = instance:GetAttribute(WEAPON_ATTRIBUTE)
	if type(id) ~= "string" then
		return nil
	end
	return Registry.variant(id, Attachments.decode(instance:GetAttribute(FITTED_ATTRIBUTE)))
end

return Registry
