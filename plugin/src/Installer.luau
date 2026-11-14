--!strict
--[[
	Installer
	Puts Ordnance into the place and keeps it up to date.

	What a plugin can and cannot do:
	  - It can make HTTP requests, but Studio asks the user to allow each
	    domain the first time. We only ever talk to raw.githubusercontent.com
	    and api.github.com is never used.
	  - It cannot download a binary model file and insert it. So releases
	    publish the framework as a JSON tree (see tools/bundle.mjs), and this
	    module rebuilds the instances from it.

	Updates replace the `Framework` folder and the root module and nothing
	else, so the user's Config, weapons and presets are never touched. New
	shipped presets are added if missing. Everything happens inside one undo
	step.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REPO = "xerseer/ORDINANCE"
local BRANCH = "dist"
local BASE = `https://raw.githubusercontent.com/{REPO}/{BRANCH}/`
local ROOT_NAME = "Ordnance"

export type Node = {
	n: string,
	c: string,
	s: string?,
	p: { [string]: any }?,
	a: { [string]: any }?,
	k: { Node }?,
}

export type Bundle = { format: number, name: string, version: string, root: Node }

export type Result = { ok: boolean, message: string, version: string? }

local ENUM_PROPERTIES: { [string]: any } = {
	RunContext = Enum.RunContext,
	Material = Enum.Material,
	MeshType = Enum.MeshType,
	Shape = Enum.PartType,
}

local Installer = {}

Installer.repository = REPO

------------------------------------------------------------------------------
-- Versions
------------------------------------------------------------------------------

local function parseVersion(text: string): { number }
	local parts = {}
	for number in string.gmatch(string.gsub(text, "^v", ""), "%d+") do
		table.insert(parts, tonumber(number) :: number)
	end
	while #parts < 3 do
		table.insert(parts, 0)
	end
	return parts
end

-- True if version `a` is newer than version `b`.
function Installer.isNewer(a: string, b: string): boolean
	local x, y = parseVersion(a), parseVersion(b)
	for index = 1, 3 do
		if x[index] ~= y[index] then
			return x[index] > y[index]
		end
	end
	return false
end

------------------------------------------------------------------------------
-- Network
------------------------------------------------------------------------------

local function explain(message: string): string
	local lowered = string.lower(message)
	if string.find(lowered, "not enabled", 1, true) or string.find(lowered, "not allowed", 1, true) then
		return "Studio blocked the request. Allow HTTP requests for this plugin when Studio asks, or turn them on in Plugin Management."
	elseif string.find(lowered, "404", 1, true) then
		return "Nothing has been released yet. The first tagged version publishes it."
	elseif string.find(lowered, "timed out", 1, true) or string.find(lowered, "resolve", 1, true) then
		return "Could not reach GitHub. Check your connection; the bundled copy can still be installed."
	end
	return message
end

local function get(path: string): (boolean, string)
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = BASE .. path,
			Method = "GET",
			Headers = { ["Cache-Control"] = "no-cache" },
		})
	end)
	if not ok then
		return false, explain(tostring(response))
	end
	if not response.Success then
		return false, explain(`GitHub answered {response.StatusCode} {response.StatusMessage}`)
	end
	return true, response.Body
end

-- The newest released version, or an explanation of why it is not known.
function Installer.latest(): (string?, string?)
	local ok, body = get("latest.json")
	if not ok then
		return nil, body
	end
	local parsed, data = pcall(HttpService.JSONDecode, HttpService, body)
	if not parsed or type(data) ~= "table" or type(data.version) ~= "string" then
		return nil, "The release index could not be read."
	end
	return data.version, nil
end

function Installer.download(): (Bundle?, string?)
	local ok, body = get("ordnance.bundle.json")
	if not ok then
		return nil, body
	end
	local parsed, data = pcall(HttpService.JSONDecode, HttpService, body)
	if not parsed or type(data) ~= "table" or type(data.root) ~= "table" then
		return nil, "The downloaded bundle is not valid."
	end
	return data :: any, nil
end

-- The copy shipped inside the plugin, for installing without a connection.
function Installer.embedded(): Bundle?
	local module = script.Parent:FindFirstChild("Embedded")
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, data = pcall(require, module)
	if ok and type(data) == "table" and type(data.root) == "table" then
		return data :: any
	end
	return nil
end

------------------------------------------------------------------------------
-- Building instances from a bundle
------------------------------------------------------------------------------

local function decode(property: string, value: any): any
	local enum = ENUM_PROPERTIES[property]
	if enum and type(value) == "string" then
		return (enum :: any)[value]
	end
	if type(value) == "table" then
		if #value == 12 then
			return CFrame.new(table.unpack(value))
		elseif #value == 3 then
			return Vector3.new(value[1], value[2], value[3])
		end
	end
	return value
end

local function build(node: Node, problems: { string }): Instance
	local instance = Instance.new(node.c)
	instance.Name = node.n
	if node.s then
		(instance :: any).Source = node.s
	end
	for property, value in node.p or {} do
		local ok, message = pcall(function()
			local decoded = decode(property, value)
			-- Rojo writes Colour as three numbers too; fall back to Color3.
			if
				typeof(decoded) == "Vector3"
				and not pcall(function()
					(instance :: any)[property] = decoded
				end)
			then
				(instance :: any)[property] = Color3.new(decoded.X, decoded.Y, decoded.Z)
			elseif typeof(decoded) ~= "Vector3" then
				(instance :: any)[property] = decoded
			end
		end)
		if not ok then
			table.insert(problems, `{node.n}.{property}: {message}`)
		end
	end
	for attribute, value in node.a or {} do
		instance:SetAttribute(attribute, value)
	end
	for _, child in node.k or {} do
		build(child, problems).Parent = instance
	end
	return instance
end

local function find(node: Node, name: string): Node?
	for _, child in node.k or {} do
		if child.n == name then
			return child
		end
	end
	return nil
end

------------------------------------------------------------------------------
-- State of the place
------------------------------------------------------------------------------

function Installer.installed(): Instance?
	local found = ReplicatedStorage:FindFirstChild(ROOT_NAME)
	if found and found:IsA("ModuleScript") then
		return found
	end
	return nil
end

-- The installed version, read from the source so no code has to run.
function Installer.installedVersion(): string?
	local root = Installer.installed()
	local version = if root then root:FindFirstChild("Framework") else nil
	local module = if version then version:FindFirstChild("Version") else nil
	if module and module:IsA("ModuleScript") then
		return string.match(module.Source, 'return%s+"([^"]+)"')
	end
	return nil
end

------------------------------------------------------------------------------
-- Install and update
------------------------------------------------------------------------------

local function replace(existing: Instance, fresh: Instance)
	fresh.Parent = existing.Parent
	existing:Destroy()
end

--[[
	Installs `bundle`. On a fresh place the whole tree is created. On an
	existing install only `Framework` and the root module are replaced, and
	missing shipped presets are added; Config and Weapons are left alone.
]]
function Installer.install(bundle: Bundle): Result
	local problems: { string } = {}
	local updated = false
	local recording = ChangeHistoryService:TryBeginRecording("Install Ordnance")
	local ok, err = pcall(function()
		local fresh = build(bundle.root, problems) :: ModuleScript
		fresh.Name = ROOT_NAME
		local existing = Installer.installed()
		if existing == nil then
			fresh.Parent = ReplicatedStorage
			return
		end

		updated = true;
		(existing :: any).Source = (fresh :: any).Source
		local old = existing:FindFirstChild("Framework")
		local new = fresh:FindFirstChild("Framework")
		if old and new then
			replace(old, new)
		elseif new then
			new.Parent = existing
		end

		local presets = existing:FindFirstChild("Presets")
		local shipped = fresh:FindFirstChild("Presets")
		if presets and shipped then
			for _, preset in shipped:GetChildren() do
				if presets:FindFirstChild(preset.Name) == nil then
					preset.Parent = presets
				end
			end
		end
		for _, name in { "Config", "Weapons", "Presets" } do
			if existing:FindFirstChild(name) == nil and fresh:FindFirstChild(name) then
				(fresh :: any)[name].Parent = existing
			end
		end
		fresh:Destroy()
	end)

	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end
	if not ok then
		return { ok = false, message = `Install failed: {err}` }
	end
	local suffix = if #problems > 0 then `, with {#problems} property warnings` else ""
	return {
		ok = true,
		message = `Ordnance {bundle.version} {if updated then "updated, your files kept" else "installed"}{suffix}.`,
		version = bundle.version,
	}
end

-- Removes the framework completely.
function Installer.uninstall(): Result
	local root = Installer.installed()
	if root == nil then
		return { ok = false, message = "Ordnance is not installed." }
	end
	local recording = ChangeHistoryService:TryBeginRecording("Remove Ordnance")
	root:Destroy()
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	return { ok = true, message = "Ordnance was removed. Nothing else was left in the place." }
end

-- Downloads the latest release and installs it.
function Installer.update(): Result
	local bundle, problem = Installer.download()
	if bundle == nil then
		return { ok = false, message = problem or "Download failed." }
	end
	return Installer.install(bundle)
end

-- Installs the copy shipped with the plugin.
function Installer.installEmbedded(): Result
	local bundle = Installer.embedded()
	if bundle == nil then
		return { ok = false, message = "This build of the plugin carries no bundled copy." }
	end
	return Installer.install(bundle)
end

-- Where the files that belong to the user are, for the Install tab to describe.
function Installer.userFiles(): { string }
	local root = Installer.installed()
	local names = {}
	if root then
		for _, name in { "Config", "Weapons", "Presets" } do
			if root:FindFirstChild(name) then
				table.insert(names, name)
			end
		end
	end
	return names
end

-- Bundle nodes, for the catalogue and tests.
Installer.find = find

-- Builds the instances for one node of a bundle or catalogue entry.
function Installer.instantiate(node: Node): (Instance, { string })
	local problems: { string } = {}
	return build(node, problems), problems
end

-- Downloads a file from the release branch and decodes it as JSON.
function Installer.fetchJson(path: string): (any, string?)
	local ok, body = get(path)
	if not ok then
		return nil, body
	end
	local parsed, data = pcall(HttpService.JSONDecode, HttpService, body)
	if not parsed then
		return nil, "The file could not be read."
	end
	return data, nil
end

return Installer
