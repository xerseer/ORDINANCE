--!strict
--[[
	Attachments
	Finds the attachment modules in Ordnance.Attachments and gets each one
	ready: checks its settings and prepares its model.

	An attachment is a ModuleScript with its model inside it, like a weapon:

		return {
			Name = "Aimpoint CompM4",
			Slot = "Optic",                          -- Optic, Muzzle, Underbarrel or Side
			Config = { Handling = { AimFOV = 55 } }, -- weapon settings it changes
			Tuning = { Recoil = 0.9 },               -- multiplied onto the weapon's
		}

	Optional behaviour: Light (a flashlight), Laser (a laser sight) and Scope
	(a full-screen scope picture when aimed). See the docs for their fields.

	The model faces the same way as a weapon (front -Z, top +Y) and may mark:
		Mount     where it meets the weapon
		Aim       the sight line through an optic
		Barrel    the new muzzle, on a muzzle device
		Grip      where the support hand holds, on a grip
		Emitter   where a light or laser shines from, facing forward
	Anything missing is worked out from the model's shape.
]]

local Config = require(script.Parent.Parent.Config)
local Logger = require(script.Parent.Parent.Core.Logger)

local log = Logger.scope("Attachments")

export type Slot = "Optic" | "Muzzle" | "Underbarrel" | "Side"

export type Light = {
	Brightness: number,
	Range: number,
	Angle: number,
	Color: Color3,
}

export type Laser = {
	Color: Color3,
	Width: number,
	Range: number,
}

export type Scope = {
	Reticle: Color3,
	Overlay: Color3,
}

export type Definition = {
	id: string,
	name: string,
	slot: Slot,
	module: ModuleScript,
	template: Model, -- prepared: a Handle, and every marker attachment present
	config: { [string]: any }?, -- checked partial weapon config
	tuning: { [string]: number }?,
	scale: number,
	light: Light?,
	laser: Laser?,
	scope: Scope?,
}

local Attachments = {}

Attachments.Slots = table.freeze({ "Optic", "Muzzle", "Underbarrel", "Side" } :: { Slot })

local definitions: { [string]: Definition } = {}
local order: { string } = {}

local LIGHT_DEFAULTS: Light = {
	Brightness = 4,
	Range = 45,
	Angle = 50,
	Color = Color3.fromRGB(255, 247, 230),
}
local LASER_DEFAULTS: Laser = {
	Color = Color3.fromRGB(255, 40, 40),
	Width = 0.03,
	Range = 300,
}
local SCOPE_DEFAULTS: Scope = {
	Reticle = Color3.fromRGB(10, 10, 10),
	Overlay = Color3.fromRGB(0, 0, 0),
}

-- Fills in a behaviour table from its defaults, keeping only known fields of the right type.
local function behaviour<T>(id: string, field: string, value: any, defaults: T): T?
	if value == nil or value == false then
		return nil
	end
	local result = table.clone(defaults :: any)
	if type(value) == "table" then
		for key, item in value do
			local default = (defaults :: any)[key]
			if default == nil then
				log:Warn(`attachment "{id}": {field}.{tostring(key)} is not a setting`)
			elseif typeof(item) ~= typeof(default) then
				log:Warn(`attachment "{id}": {field}.{key} should be a {typeof(default)}`)
			else
				result[key] = item
			end
		end
	end
	return result :: any
end

-- The box around every part of `model`, in `frame`'s space.
function Attachments.bounds(model: Instance, frame: CFrame): (Vector3, Vector3)
	local low = Vector3.one * math.huge
	local high = -low
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local local_ = frame:ToObjectSpace(part.CFrame)
			local half = part.Size / 2
			for _, corner in
				{
					Vector3.new(1, 1, 1),
					Vector3.new(1, 1, -1),
					Vector3.new(1, -1, 1),
					Vector3.new(1, -1, -1),
					Vector3.new(-1, 1, 1),
					Vector3.new(-1, 1, -1),
					Vector3.new(-1, -1, 1),
					Vector3.new(-1, -1, -1),
				}
			do
				local point = local_ * (half * corner)
				low = low:Min(point)
				high = high:Max(point)
			end
		end
	end
	if low.X == math.huge then
		return Vector3.zero, Vector3.zero
	end
	return low, high
end

local function findHandle(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local named = model:FindFirstChild("Handle", true)
	if named and named:IsA("BasePart") then
		return named
	end
	local largest: BasePart? = nil
	local volume = -1
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local size = part.Size.X * part.Size.Y * part.Size.Z
			if size > volume then
				largest = part
				volume = size
			end
		end
	end
	return largest
end

local function marker(model: Instance, name: string): Attachment?
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == name then
			return descendant
		end
	end
	return nil
end

local function addMarker(handle: BasePart, name: string, frame: CFrame)
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = frame
	attachment.Parent = handle
end

-- Copies the model and adds any markers it is missing.
local function prepare(source: Instance, id: string, slot: Slot, scale: number): Model?
	local model: Model
	if source:IsA("Model") then
		model = source:Clone()
	elseif source:IsA("BasePart") then
		model = Instance.new("Model")
		source:Clone().Parent = model
	else
		log:Warn(`attachment "{id}": the model is a {source.ClassName}; use a Model or a part`)
		return nil
	end
	local handle = findHandle(model)
	if handle == nil then
		log:Warn(`attachment "{id}": the model has no parts`)
		model:Destroy()
		return nil
	end
	model.PrimaryPart = handle
	model.Name = id
	if scale ~= 1 then
		model:ScaleTo(model:GetScale() * scale)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
		end
	end

	local low, high = Attachments.bounds(model, handle.CFrame)
	local centre = (low + high) / 2
	local size = high - low

	-- Where it meets the weapon: the face that sits against it.
	if marker(model, "Mount") == nil then
		local mount = if slot == "Optic"
			then Vector3.new(centre.X, low.Y, centre.Z)
			elseif slot == "Muzzle" then Vector3.new(centre.X, centre.Y, high.Z)
			elseif slot == "Underbarrel" then Vector3.new(centre.X, high.Y, centre.Z)
			else Vector3.new(low.X, centre.Y, centre.Z)
		addMarker(handle, "Mount", CFrame.new(mount))
	end
	if slot == "Optic" and marker(model, "Aim") == nil then
		-- The window of a sight is a little above the middle, at the back.
		addMarker(handle, "Aim", CFrame.new(centre.X, low.Y + size.Y * 0.62, high.Z))
	end
	if slot == "Muzzle" and marker(model, "Barrel") == nil then
		addMarker(handle, "Barrel", CFrame.new(centre.X, centre.Y, low.Z))
	end
	if slot == "Underbarrel" and marker(model, "Grip") == nil then
		addMarker(handle, "Grip", CFrame.new(centre.X, low.Y + size.Y * 0.45, centre.Z))
	end
	if slot == "Side" and marker(model, "Emitter") == nil then
		addMarker(handle, "Emitter", CFrame.new(centre.X, centre.Y, low.Z))
	end
	return model
end

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
		if child:IsA("Model") or child:IsA("BasePart") then
			return child
		end
	end
	return nil
end

local function load(module: ModuleScript)
	local id = module.Name
	if definitions[id] then
		log:Warn(`two attachments are named "{id}"; keeping the first`)
		return
	end
	local ok, definition = pcall(require, module)
	if not ok or type(definition) ~= "table" then
		log:Error(
			`attachment "{id}" failed to load: {if ok then "it must return a table" else tostring(definition)}`
		)
		return
	end

	local slot = definition.Slot
	if not table.find(Attachments.Slots, slot) then
		log:Warn(`attachment "{id}": Slot must be one of {table.concat(Attachments.Slots, ", ")}; skipped`)
		return
	end

	local config: { [string]: any }? = nil
	if definition.Config ~= nil then
		local clean, problems = Config.Schema.validate(definition.Config, "Weapon")
		for _, problem in problems do
			log:Warn(`attachment "{id}": Config.{problem.path} {problem.message}`)
		end
		for _, key in { "Name", "Description", "Model", "Scale", "Custom", "Animations", "Attachments" } do
			if clean[key] ~= nil then
				clean[key] = nil
				log:Warn(`attachment "{id}": Config.{key} cannot be changed by an attachment`)
			end
		end
		config = clean
	end

	local tuning: { [string]: number }? = nil
	if definition.Tuning ~= nil then
		local clean, problems = Config.Schema.validate({ Tuning = definition.Tuning }, "Weapon")
		for _, problem in problems do
			log:Warn(`attachment "{id}": {problem.path} {problem.message}`)
		end
		tuning = clean.Tuning
	end

	local scale = if type(definition.Scale) == "number" and definition.Scale > 0 then definition.Scale else 1
	local source = findModel(module, definition.Model or "Model")
	if source == nil then
		log:Warn(`attachment "{id}" has no model; skipped. Put a Model inside the module.`)
		return
	end
	local template = prepare(source, id, slot, scale)
	if template == nil then
		return
	end

	local light = behaviour(id, "Light", definition.Light, LIGHT_DEFAULTS)
	if light then
		-- One SpotLight per Emitter, off until the player switches it on.
		for _, emitter in template:GetDescendants() do
			if emitter:IsA("Attachment") and emitter.Name == "Emitter" then
				local spot = Instance.new("SpotLight")
				spot.Brightness = light.Brightness
				spot.Range = light.Range
				spot.Angle = light.Angle
				spot.Color = light.Color
				spot.Face = Enum.NormalId.Front
				spot.Shadows = true
				spot.Enabled = false
				spot.Parent = emitter
			end
		end
	end

	definitions[id] = {
		id = id,
		name = if type(definition.Name) == "string" and definition.Name ~= "" then definition.Name else id,
		slot = slot,
		module = module,
		template = template,
		config = config,
		tuning = tuning,
		scale = scale,
		light = light,
		laser = behaviour(id, "Laser", definition.Laser, LASER_DEFAULTS),
		scope = behaviour(id, "Scope", definition.Scope, SCOPE_DEFAULTS),
	}
	table.insert(order, id)
end

local function scan(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("ModuleScript") then
			log:Try(load, child)
		elseif child:IsA("Folder") then
			scan(child)
		end
	end
end

-- Loads every attachment under `root.Attachments`. Calling it again reloads.
function Attachments.load(root: Instance)
	for _, definition in definitions do
		definition.template:Destroy()
	end
	table.clear(definitions)
	table.clear(order)
	local folder = root:FindFirstChild("Attachments")
	if folder == nil then
		return
	end
	scan(folder)
	table.sort(order)
	if #order > 0 then
		log:Info(`{#order} attachment{if #order == 1 then "" else "s"} ready`)
	end
end

function Attachments.get(id: string): Definition?
	return definitions[id]
end

-- Attachment ids in alphabetical order, optionally only those for one slot.
function Attachments.ids(slot: Slot?): { string }
	local result = {}
	for _, id in order do
		if slot == nil or definitions[id].slot == slot then
			table.insert(result, id)
		end
	end
	return result
end

-- "Muzzle=Suppressor;Optic=RedDot": a stable text form of what is fitted.
function Attachments.encode(fitted: { [string]: string }): string
	local parts = {}
	for _, slot in Attachments.Slots do
		local id = fitted[slot]
		if id then
			table.insert(parts, `{slot}={id}`)
		end
	end
	return table.concat(parts, ";")
end

function Attachments.decode(text: any): { [string]: string }
	local fitted = {}
	if type(text) ~= "string" then
		return fitted
	end
	for slot, id in string.gmatch(text, "(%w+)=([^;]+)") do
		if table.find(Attachments.Slots, slot :: any) then
			fitted[slot] = id
		end
	end
	return fitted
end

return Attachments
