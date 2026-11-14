--!strict
--[[
	Presets tab
	A preset is a module in Ordnance.Presets containing a partial config.
	Here you can pick one as the starting point, export it as text, import one
	someone sent you, or save your current Config as a new one.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local ConfigTab = require(script.Parent.Config)
local Installer = require(script.Parent.Parent.Installer)
local Source = require(script.Parent.Parent.Source)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local Presets = { name = "Presets" }

local BUILT_IN = { Arcade = true, Standard = true, Tactical = true, Realistic = true }

local refresh: () -> () = function() end

-- The first sentence of a preset's header comment, as its description.
local function describe(source: string): string
	local block = string.match(source, "^%-%-%[%[(.-)%]%]")
	if block == nil then
		return ""
	end
	local lines = string.split(block, "\n")
	local text = {}
	for index = 3, #lines do
		local line = string.match(lines[index], "^%s*(.-)%s*$") :: string
		if line == "" then
			break
		end
		table.insert(text, line)
	end
	return table.concat(text, " ")
end

local function presetsFolder(): Instance?
	local root = Installer.installed()
	return if root then root:FindFirstChild("Presets") else nil
end

function Presets.build(parent: Frame)
	local _, content = UI.scroll(parent)
	UI.heading(content, "Presets", 1)
	UI.caption(
		content,
		"Ready-made configs, from Arcade to Realistic. A preset is the starting point; your Config is laid over it.",
		2
	)
	local _, setStatus = UI.status(content, 3)
	local list = UI.column(content, Theme.space.sm, 4)

	local exportBox: TextBox
	local importName: TextBox
	local importBox: TextBox
	local saveName: TextBox

	local function uniqueName(folder: Instance, base: string): string
		local name, count = base, 1
		while folder:FindFirstChild(name) do
			count += 1
			name = `{base}{count}`
		end
		return name
	end

	local function addPreset(name: string, source: string)
		local folder = presetsFolder()
		if folder == nil then
			setStatus("Install Ordnance first.", "bad")
			return
		end
		local safe = string.gsub(name, "[^%w_]", "")
		if safe == "" then
			setStatus("Give the preset a name (letters, numbers, underscores).", "bad")
			return
		end
		local module = Instance.new("ModuleScript")
		module.Name = uniqueName(folder, safe)
		module.Source = source

		-- Check it loads and returns a table before it goes in.
		local ok, value = pcall(require, module:Clone())
		if not ok or type(value) ~= "table" then
			module:Destroy()
			setStatus(
				"That is not a valid preset: " .. tostring(if ok then "it must return a table" else value),
				"bad"
			)
			return
		end
		local recording = ChangeHistoryService:TryBeginRecording("Add Ordnance preset")
		module.Parent = folder
		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		end
		setStatus(`Added preset "{module.Name}".`, "good")
		refresh()
	end

	local function rebuild()
		list:ClearAllChildren()
		UI.stack(list, Theme.space.sm)
		local folder = presetsFolder()
		if folder == nil then
			UI.label(list, "Install Ordnance first (Install tab).", { color = "danger", size = 12 })
			return
		end

		local active = ""
		local root = Installer.installed()
		local configModule = if root then root:FindFirstChild("Config") else nil
		if configModule and configModule:IsA("ModuleScript") then
			local ok, value = pcall(require, configModule:Clone())
			if ok and type(value) == "table" and type(value.Preset) == "string" then
				active = value.Preset
			end
		end

		local names = {}
		for _, child in folder:GetChildren() do
			if child:IsA("ModuleScript") then
				table.insert(names, child.Name)
			end
		end
		table.sort(names)

		for index, name in names do
			local module = folder:FindFirstChild(name) :: ModuleScript
			local card = UI.card(list, index)
			local head = UI.row(card, 20, Theme.space.sm, 1)
			local title = UI.label(head, name, { font = Theme.fontBold, wrap = false })
			title.AutomaticSize = Enum.AutomaticSize.XY
			title.Size = UDim2.fromOffset(0, 18)
			if name == active then
				local tag = UI.label(
					head,
					"ACTIVE",
					{ color = "accent", size = 11, font = Theme.fontMedium, wrap = false }
				)
				tag.AutomaticSize = Enum.AutomaticSize.XY
				tag.Size = UDim2.fromOffset(0, 18)
			elseif not BUILT_IN[name] then
				local tag = UI.label(head, "YOURS", { color = "muted", size = 11, wrap = false })
				tag.AutomaticSize = Enum.AutomaticSize.XY
				tag.Size = UDim2.fromOffset(0, 18)
			end
			local description = describe(module.Source)
			if description ~= "" then
				UI.caption(card, description, 2)
			end
			local buttons = UI.row(card, Theme.rowHeight, Theme.space.sm, 3)
			UI.button(
				buttons,
				if name == active then "Stop using" else "Use",
				if name == active then "default" else "primary",
				function()
					local _, message = ConfigTab.applyPreset(if name == active then nil else name)
					setStatus(message, "good")
					rebuild()
				end
			)
			UI.button(buttons, "Export", "default", function()
				exportBox.Text = module.Source
				exportBox.Visible = true
				setStatus(`{name} is below. Select it and copy.`, "info")
			end)
			if not BUILT_IN[name] then
				UI.button(buttons, "Delete", "ghost", function()
					local recording = ChangeHistoryService:TryBeginRecording("Delete Ordnance preset")
					module:Destroy()
					if recording then
						ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
					end
					rebuild()
				end)
			end
		end
	end

	UI.section(content, "Export", 5)
	exportBox = UI.code(content, "", 6)
	exportBox.Visible = false

	UI.section(content, "Import", 7)
	UI.caption(content, "Paste a preset's source. It is checked before it is added.", 8)
	importName = UI.input(content, "", function() end, { placeholder = "Name", order = 9 })
	importBox = UI.input(
		content,
		"",
		function() end,
		{ placeholder = "Paste source here", mono = true, order = 10 }
	)
	importBox.MultiLine = true
	importBox.TextYAlignment = Enum.TextYAlignment.Top
	importBox.Size = UDim2.new(1, 0, 0, 110)
	UI.button(content, "Add preset", "default", function()
		addPreset(importName.Text, importBox.Text)
		importBox.Text = ""
	end, 11)

	UI.section(content, "Save your Config as a preset", 12)
	UI.caption(
		content,
		"Copies the settings you changed in Ordnance.Config into a new preset you can share.",
		13
	)
	saveName = UI.input(content, "", function() end, { placeholder = "Name", order = 14 })
	UI.button(content, "Save as preset", "default", function()
		local root = Installer.installed()
		local module = if root then root:FindFirstChild("Config") else nil
		if module == nil or not module:IsA("ModuleScript") then
			setStatus("Install Ordnance first.", "bad")
			return
		end
		local ok, value = pcall(require, module:Clone())
		if not ok or type(value) ~= "table" then
			setStatus("Ordnance.Config could not be read.", "bad")
			return
		end
		local data = table.clone(value)
		data.Preset = nil
		addPreset(saveName.Text, Source.module(data, `{saveName.Text}\nSaved from Ordnance.Config.`))
	end, 15)

	refresh = rebuild
	rebuild()
end

function Presets.onShow()
	refresh()
end

return Presets
