--!strict
--[[
	Config tab
	A visual editor for Ordnance.Config.

	The form is generated from the installed framework's own Schema and
	Defaults, so a setting added to the framework shows up here without any
	plugin change, with its range, choices and description. Only values that
	differ from the default are written to the Config module.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Installer = require(script.Parent.Parent.Installer)
local Writer = require(script.Parent.Parent.Writer)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local Config = { name = "Config" }

local MARKER = "Written by the Ordnance plugin"
local HEADER =
	`Ordnance global config\n{MARKER}. Change it here or in the plugin's Config tab; both work.\nOnly settings that differ from the defaults are listed.`
local ORDER = {
	"Fire",
	"Ammo",
	"Ballistics",
	"Damage",
	"Spread",
	"Recoil",
	"Handling",
	"Realism",
	"Tuning",
	"Camera",
	"Viewmodel",
	"ThirdPerson",
	"Animation",
	"Sway",
	"Keybinds",
	"Controls",
	"Effects",
	"HUD",
	"Inventory",
	"Security",
	"Debug",
}

type Rule = { doc: string, min: number?, max: number?, integer: boolean?, choices: { string }?, kind: string? }

type Entry = { path: string, frame: Frame, haystack: string, refresh: () -> () }
type Group = { name: string, button: TextButton, body: Frame, entries: { Entry }, open: boolean }

local reload: () -> () = function() end

------------------------------------------------------------------------------
-- Table paths
------------------------------------------------------------------------------

local function split(path: string): { string }
	return string.split(path, ".")
end

local function getPath(tbl: any, path: string): any
	local value = tbl
	for _, key in split(path) do
		if type(value) ~= "table" then
			return nil
		end
		value = value[key]
	end
	return value
end

local function setPath(tbl: { [string]: any }, path: string, value: any)
	local keys = split(path)
	local node = tbl
	for index = 1, #keys - 1 do
		local child = node[keys[index]]
		if type(child) ~= "table" then
			child = {}
			node[keys[index]] = child
		end
		node = child
	end
	node[keys[#keys]] = value
end

local function clearPath(tbl: { [string]: any }, path: string)
	local keys = split(path)
	local chain = { tbl }
	for index = 1, #keys - 1 do
		local child = chain[#chain][keys[index]]
		if type(child) ~= "table" then
			return
		end
		table.insert(chain, child)
	end
	chain[#chain][keys[#keys]] = nil
	-- Drop sections left empty, so the file only lists what was changed.
	for index = #chain, 2, -1 do
		if next(chain[index]) == nil then
			chain[index - 1][keys[index - 1]] = nil
		end
	end
end

local function same(a: any, b: any): boolean
	if typeof(a) ~= typeof(b) then
		return false
	end
	if type(a) == "table" then
		for key, value in a do
			if not same(value, b[key]) then
				return false
			end
		end
		for key in b do
			if a[key] == nil then
				return false
			end
		end
		return true
	end
	if type(a) == "number" then
		return math.abs(a - b) < 1e-9
	end
	return a == b
end

------------------------------------------------------------------------------
-- Text <-> value
------------------------------------------------------------------------------

local function numbersOf(text: string, count: number?): { number }?
	local result = {}
	for piece in string.gmatch(text, "[^,%s]+") do
		local value = tonumber(piece)
		if value == nil then
			return nil
		end
		table.insert(result, value)
	end
	if count and #result ~= count then
		return nil
	end
	return result
end

local function show(value: any): string
	local kind = typeof(value)
	if kind == "Color3" then
		return "#" .. (value :: Color3):ToHex()
	elseif kind == "Vector3" then
		local v = value :: Vector3
		return string.format("%g, %g, %g", v.X, v.Y, v.Z)
	elseif kind == "table" then
		local parts = {}
		for _, item in value :: { any } do
			table.insert(parts, if type(item) == "number" then string.format("%g", item) else tostring(item))
		end
		return table.concat(parts, ", ")
	end
	return tostring(value)
end

local function parse(text: string, default: any, rule: Rule?): (any, string?)
	local kind = typeof(default)
	if kind == "Color3" then
		local ok, color = pcall(Color3.fromHex, text)
		if ok then
			return color, nil
		end
		return nil, "Use a hex colour like #b3bf7d."
	elseif kind == "Vector3" then
		local numbers = numbersOf(text, 3)
		if numbers then
			return Vector3.new(numbers[1], numbers[2], numbers[3]), nil
		end
		return nil, "Use three numbers: x, y, z."
	elseif kind == "table" then
		if rule and rule.kind == "frame" then
			local numbers = numbersOf(text, 6)
			if numbers then
				return numbers, nil
			end
			return nil, "Use six numbers: x, y, z, then rotation x, y, z in degrees."
		end
		local list = {}
		for piece in string.gmatch(text, "[^,]+") do
			local trimmed = string.match(piece, "^%s*(.-)%s*$") :: string
			if trimmed ~= "" then
				table.insert(list, trimmed)
			end
		end
		return list, nil
	end
	return text, nil
end

------------------------------------------------------------------------------
-- Tab
------------------------------------------------------------------------------

function Config.build(parent: Frame)
	local scroll, content = UI.scroll(parent)
	scroll.Name = "ConfigScroll"

	UI.heading(content, "Config", 1)
	UI.caption(
		content,
		"Everything here is optional. Only what you change is written to Ordnance.Config; the rest uses the defaults.",
		2
	)

	local message = UI.column(content, 6, 3)
	local presetRow = UI.column(content, 4, 4)
	local actions = UI.row(content, Theme.rowHeight, Theme.space.sm, 5)
	local saveButton, enableSave = UI.button(actions, "Save to Config", "primary", function() end)
	local discardButton = UI.button(actions, "Discard changes", "default", function() end)
	local _, setStatus = UI.status(content, 6)
	local searchBox = UI.input(content, "", function() end, { placeholder = "Search settings", order = 7 })
	local list = UI.column(content, Theme.space.sm, 8)

	local rules: { [string]: Rule } = {}
	local defaults: any = nil
	local overrides: { [string]: any } = {}
	local configModule: ModuleScript? = nil
	local groups: { Group } = {}
	local entryByPath: { [string]: Entry } = {}
	local dirty = false
	local built = false

	local function markDirty(value: boolean)
		dirty = value
		enableSave(value)
		setStatus(if value then "Unsaved changes." else "", if value then "warn" else "info")
	end

	local function filter()
		local query = string.lower(searchBox.Text)
		for _, group in groups do
			local shown = 0
			for _, entry in group.entries do
				local match = query == "" or string.find(entry.haystack, query, 1, true) ~= nil
				entry.frame.Visible = match
				if match then
					shown += 1
				end
			end
			group.button.Visible = shown > 0
			group.body.Visible = shown > 0 and (group.open or query ~= "")
		end
	end
	searchBox:GetPropertyChangedSignal("Text"):Connect(filter)

	local function makeEntry(group: Group, path: string, rule: Rule)
		local default = getPath(defaults, path)
		if default == nil then
			return
		end
		local frame = UI.column(group.body, 4)
		local leaf = split(path)
		local headline = UI.row(frame, 18, Theme.space.sm, 1)
		local name = UI.label(
			headline,
			table.concat(leaf, " / "),
			{ font = Theme.fontMedium, size = 12, wrap = false }
		)
		name.Size = UDim2.new(1, -34, 0, 16)
		name.AutomaticSize = Enum.AutomaticSize.None
		local resetButton = UI.button(headline, "reset", "ghost", function() end)
		resetButton.Size = UDim2.fromOffset(0, 18)
		resetButton.TextSize = 11
		local controlRow = UI.row(frame, Theme.rowHeight, Theme.space.sm, 2)
		UI.caption(frame, rule.doc, 3).TextSize = 11
		UI.line(frame, 4)

		local function current(): any
			local value = getPath(overrides, path)
			if value == nil then
				return default
			end
			return value
		end

		local function commit(value: any)
			if same(value, default) then
				clearPath(overrides, path)
			else
				setPath(overrides, path, value)
			end
			resetButton.Visible = getPath(overrides, path) ~= nil
			markDirty(true)
		end

		local setControl: (any) -> () = function() end
		local kind = typeof(default)
		if kind == "boolean" then
			local _, set = UI.toggle(controlRow, current(), commit)
			setControl = set
		elseif kind == "number" then
			setControl = UI.number(controlRow, current(), rule.min, rule.max, commit)
		elseif kind == "string" and rule.choices and #rule.choices <= 5 then
			setControl = UI.segmented(controlRow, rule.choices, current(), commit)
		else
			local setText
			_, setText = UI.input(controlRow, show(current()), function(text)
				local value, problem = parse(text, default, rule)
				if value == nil then
					setStatus(`{path}: {problem}`, "bad")
					setText(show(current()))
					return
				end
				commit(value)
				setText(show(value))
			end, { mono = true })
			setControl = function(value: any)
				setText(show(value))
			end
		end

		resetButton.Visible = getPath(overrides, path) ~= nil
		resetButton.Activated:Connect(function()
			clearPath(overrides, path)
			setControl(default)
			resetButton.Visible = false
			markDirty(true)
		end)

		table.insert(group.entries, {
			path = path,
			frame = frame,
			haystack = string.lower(path .. " " .. rule.doc),
			refresh = function()
				setControl(current())
				resetButton.Visible = getPath(overrides, path) ~= nil
			end,
		})
		entryByPath[path] = group.entries[#group.entries]
	end

	local function buildForm(schema: any, defaultTable: any, presets: { string })
		rules = schema.Rules
		defaults = defaultTable

		-- Preset chooser.
		presetRow:ClearAllChildren()
		UI.stack(presetRow, 4)
		UI.section(presetRow, "Preset", 0)
		local choices = { "None" }
		for _, name in presets do
			table.insert(choices, name)
		end
		local chosen = overrides.Preset
		UI.segmented(
			presetRow,
			choices,
			if type(chosen) == "string" and chosen ~= "" then chosen else "None",
			function(choice)
				overrides.Preset = if choice == "None" then nil else choice
				markDirty(true)
			end,
			1
		)
		UI.caption(presetRow, "A preset sets the starting point. Anything below is laid over it.", 2)

		-- Settings, grouped by section.
		local byGroup: { [string]: { string } } = {}
		for path in rules do
			local top = split(path)[1]
			local rule = rules[path]
			if
				not schema.WeaponOnly[top]
				and top ~= "Preset"
				and rule.kind ~= "free"
				and rule.kind ~= "model"
			then
				byGroup[top] = byGroup[top] or {}
				table.insert(byGroup[top], path)
			end
		end
		local names = {}
		for _, name in ORDER do
			if byGroup[name] then
				table.insert(names, name)
			end
		end
		local rest = {}
		for name in byGroup do
			if not table.find(ORDER, name) then
				table.insert(rest, name)
			end
		end
		table.sort(rest)
		for _, name in rest do
			table.insert(names, name)
		end

		list:ClearAllChildren()
		UI.stack(list, Theme.space.sm)
		table.clear(groups)
		table.clear(entryByPath)
		for index, name in names do
			local paths = byGroup[name]
			table.sort(paths)
			local wrapper = UI.column(list, 4, index)
			local header = UI.make("TextButton", {
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundTransparency = 0,
				LayoutOrder = 1,
			}, wrapper)
			UI.padding(header, 0, Theme.space.sm)
			UI.paint(header, { BackgroundColor3 = "surface" })
			local title = UI.make("TextLabel", {
				Text = "",
				Size = UDim2.fromScale(1, 1),
				FontFace = Theme.fontMedium,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, header)
			UI.paint(title, { TextColor3 = "fg" })
			local body = UI.column(wrapper, Theme.space.sm, 2)
			UI.padding(body, Theme.space.sm, 0, Theme.space.sm, Theme.space.sm)
			body.Visible = false

			local group: Group = { name = name, button = header, body = body, entries = {}, open = false }
			table.insert(groups, group)
			for _, path in paths do
				makeEntry(group, path, rules[path])
			end
			local function paintTitle()
				title.Text = `{if group.open then "v" else ">"}  {name}   ({#group.entries})`
			end
			paintTitle()
			header.Activated:Connect(function()
				group.open = not group.open
				paintTitle()
				body.Visible = group.open
			end)
			-- The wrapper holds the header; collapse the whole wrapper with it.
			group.button = wrapper :: any
		end
		built = true
		filter()
	end

	local function refreshMessage(text: string?, kind: string?)
		message:ClearAllChildren()
		UI.stack(message, 6)
		if text then
			local label =
				UI.label(message, text, { color = if kind == "bad" then "danger" else "muted", size = 12 })
			label.Name = "Note"
		end
	end

	reload = function()
		local root = Installer.installed()
		if root == nil then
			built = false
			list:ClearAllChildren()
			presetRow:ClearAllChildren()
			refreshMessage(
				"Install Ordnance first (Install tab). The editor is built from the installed version, so it always matches it.",
				"bad"
			)
			enableSave(false)
			return
		end
		local framework = root:FindFirstChild("Framework")
		local configFolder = if framework then framework:FindFirstChild("Config") else nil
		local schemaModule = if configFolder then configFolder:FindFirstChild("Schema") else nil
		local defaultsModule = if configFolder then configFolder:FindFirstChild("Defaults") else nil
		if schemaModule == nil or defaultsModule == nil then
			refreshMessage(
				"The installed Ordnance has no Config schema. Update it from the Install tab.",
				"bad"
			)
			return
		end

		configModule = root:FindFirstChild("Config") :: ModuleScript?
		overrides = {}
		if configModule then
			local ok, value = pcall(require, configModule:Clone())
			if ok and type(value) == "table" then
				overrides = value
			else
				refreshMessage(
					"Ordnance.Config could not be read, so the editor starts empty: " .. tostring(value),
					"bad"
				)
			end
		end

		local ok, schema = pcall(require, schemaModule)
		local okDefaults, defaultTable = pcall(require, defaultsModule)
		if not ok or not okDefaults then
			refreshMessage("The framework's schema could not be loaded: " .. tostring(schema), "bad")
			return
		end

		local presets = {}
		local presetFolder = root:FindFirstChild("Presets")
		if presetFolder then
			for _, child in presetFolder:GetChildren() do
				if child:IsA("ModuleScript") then
					table.insert(presets, child.Name)
				end
			end
			table.sort(presets)
		end

		local handWritten = configModule ~= nil
			and not string.find(configModule.Source, MARKER, 1, true)
			and not string.find(configModule.Source, "Ordnance global config", 1, true)
		refreshMessage(
			if handWritten
				then "Ordnance.Config was written by hand. Saving keeps every value but replaces the file, so comments are lost."
				else nil,
			nil
		)
		buildForm(schema, defaultTable, presets)
		markDirty(false)
	end

	saveButton.Activated:Connect(function()
		if configModule == nil then
			setStatus("There is no Config module to write to.", "bad")
			return
		end
		local recording = ChangeHistoryService:TryBeginRecording("Edit Ordnance config")
		configModule.Source = Writer.module(overrides, HEADER)
		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		end
		markDirty(false)
		setStatus("Saved.", "good")
	end)
	discardButton.Activated:Connect(function()
		reload()
	end)

	-- Keep the form honest if the module is edited by hand while it is open.
	local watching: RBXScriptConnection? = nil
	local function watch()
		if watching then
			watching:Disconnect()
			watching = nil
		end
		local module = configModule
		if module then
			watching = module:GetPropertyChangedSignal("Source"):Connect(function()
				if not dirty and built then
					reload()
				end
			end)
		end
	end
	local innerReload = reload
	reload = function()
		innerReload()
		watch()
	end
end

-- Sets (or clears, with nil) the Preset in the Config module, keeping every
-- other value. Used by the Presets tab.
function Config.applyPreset(name: string?): (boolean, string)
	local root = Installer.installed()
	local module = if root then root:FindFirstChild("Config") else nil
	if module == nil or not module:IsA("ModuleScript") then
		return false, "There is no Config module to write to."
	end
	local ok, value = pcall(require, module:Clone())
	local data: { [string]: any } = if ok and type(value) == "table" then value else {}
	data.Preset = name
	local recording = ChangeHistoryService:TryBeginRecording("Set Ordnance preset")
	module.Source = Writer.module(data, HEADER)
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	return true, if name then `Preset "{name}" is now the starting point.` else "Preset cleared."
end

function Config.onShow()
	reload()
end

return Config
