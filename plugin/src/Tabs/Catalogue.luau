--!strict
--[[
	Catalogue tab
	Browse and insert weapons and presets published on GitHub.

	The index is catalogue.json on the repository's release branch. Each entry
	points at a JSON description of the instances to build, the same format the
	updater uses, so a weapon arrives with its module, model and attachments.

	Limits worth knowing: a plugin can only build instances from data (no
	binary models over HTTP), so weapons whose meshes are Unions need a Creator
	Store asset id instead, and thumbnails are not shown (a plugin cannot
	display arbitrary web images).
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Installer = require(script.Parent.Parent.Installer)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local Catalogue = { name = "Catalogue" }

type Entry = {
	id: string,
	kind: string, -- "weapon" or "preset"
	name: string,
	description: string?,
	author: string?,
	version: string?,
	path: string, -- relative to the release branch
}

local function parse(index: any): { Entry }
	local entries = {}
	if type(index) ~= "table" or type(index.entries) ~= "table" then
		return entries
	end
	for _, raw in index.entries do
		if
			type(raw) == "table"
			and type(raw.name) == "string"
			and type(raw.path) == "string"
			and (raw.kind == "weapon" or raw.kind == "preset")
		then
			table.insert(entries, {
				id = tostring(raw.id or raw.name),
				kind = raw.kind,
				name = raw.name,
				description = raw.description,
				author = raw.author,
				version = raw.version,
				path = raw.path,
			})
		end
	end
	table.sort(entries, function(a, b)
		if a.kind ~= b.kind then
			return a.kind < b.kind
		end
		return a.name < b.name
	end)
	return entries
end

-- Inserts an entry into the installed framework. Returns a message.
function Catalogue.insert(entry: Entry): (boolean, string)
	local root = Installer.installed()
	if root == nil then
		return false, "Install Ordnance first (Install tab)."
	end
	local data, problem = Installer.fetchJson(entry.path)
	if data == nil then
		return false, problem or "Download failed."
	end
	local ok, instance = pcall(Installer.instantiate, data)
	if not ok then
		return false, "The entry is not valid: " .. tostring(instance)
	end

	local folder = root:FindFirstChild(if entry.kind == "weapon" then "Weapons" else "Presets")
	if folder == nil then
		return false, "The installed Ordnance is missing that folder."
	end
	local recording = ChangeHistoryService:TryBeginRecording("Insert from Ordnance catalogue")
	local built = instance :: Instance
	local base, count = built.Name, 1
	while folder:FindFirstChild(built.Name) do
		count += 1
		built.Name = `{base}{count}`
	end
	built.Parent = folder
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	return true, `Added {built.Name} to Ordnance.{folder.Name}.`
end

function Catalogue.build(parent: Frame)
	local _, content = UI.scroll(parent)
	UI.heading(content, "Catalogue", 1)
	UI.caption(
		content,
		"Weapons and presets from the Ordnance repository. Insert one and it works: it lands in your Weapons or Presets folder.",
		2
	)

	local top = UI.row(content, Theme.rowHeight, Theme.space.sm, 3)
	local searchBox = UI.input(top, "", function() end, { placeholder = "Search", width = 180 })
	local filter = "all"
	local render: () -> () = function() end
	UI.segmented(top, { "all", "weapon", "preset" }, filter, function(choice)
		filter = choice
		render()
	end)
	local _, setStatus = UI.status(content, 4)
	local list = UI.column(content, Theme.space.sm, 5)

	local entries: { Entry } = {}
	local loaded = false

	render = function()
		list:ClearAllChildren()
		UI.stack(list, Theme.space.sm)
		local query = string.lower(searchBox.Text)
		local shown = 0
		for index, entry in entries do
			local haystack =
				string.lower(entry.name .. " " .. (entry.description or "") .. " " .. (entry.author or ""))
			if
				(filter == "all" or entry.kind == filter)
				and (query == "" or string.find(haystack, query, 1, true))
			then
				shown += 1
				local card = UI.card(list, index)
				local head = UI.row(card, 20, Theme.space.sm, 1)
				local title = UI.label(head, entry.name, { font = Theme.fontBold, wrap = false })
				title.AutomaticSize = Enum.AutomaticSize.XY
				title.Size = UDim2.fromOffset(0, 18)
				local tag =
					UI.label(head, string.upper(entry.kind), { color = "muted", size = 11, wrap = false })
				tag.AutomaticSize = Enum.AutomaticSize.XY
				tag.Size = UDim2.fromOffset(0, 18)
				if entry.description then
					UI.caption(card, entry.description, 2)
				end
				local byline = {}
				if entry.author then
					table.insert(byline, `by {entry.author}`)
				end
				if entry.version then
					table.insert(byline, `v{entry.version}`)
				end
				if #byline > 0 then
					UI.caption(card, table.concat(byline, "  "), 3)
				end
				UI.button(card, "Insert", "primary", function()
					setStatus("Downloading...", "info")
					task.spawn(function()
						local ok, message = Catalogue.insert(entry)
						setStatus(message, if ok then "good" else "bad")
					end)
				end, 4)
			end
		end
		if shown == 0 and loaded then
			UI.label(list, "Nothing matches.", { color = "muted", size = 12 })
		end
	end

	local function load()
		setStatus("Loading the catalogue...", "info")
		task.spawn(function()
			local index, problem = Installer.fetchJson("catalogue.json")
			if index == nil then
				setStatus(problem or "Could not load the catalogue.", "warn")
				return
			end
			entries = parse(index)
			loaded = true
			setStatus(`{#entries} entries.`, "info")
			render()
		end)
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(render)
	UI.button(content, "Refresh", "ghost", load, 6)
	load()
end

return Catalogue
