--[[
	Development sync: rebuilds ReplicatedStorage.Ordnance from the bundle served
	by tools/serve.mjs. Paste into the Studio command bar (edit mode).

		node tools/bundle.mjs && node tools/serve.mjs

	This replaces the whole object, including Config and Weapons: the repo is
	the source of truth while developing. The plugin's updater is the one that
	preserves user files.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local URL = "http://127.0.0.1:34873/ordnance.bundle.json"

local function decode(value)
	if type(value) ~= "table" then
		return value
	end
	local kind, inner = next(value)
	if kind == "Vector3" then
		return Vector3.new(inner[1], inner[2], inner[3])
	elseif kind == "Vector2" then
		return Vector2.new(inner[1], inner[2])
	elseif kind == "Color3" then
		return Color3.new(inner[1], inner[2], inner[3])
	elseif kind == "Color3uint8" then
		return Color3.fromRGB(inner[1], inner[2], inner[3])
	elseif kind == "CFrame" then
		local p, o = inner.position, inner.orientation
		return CFrame.new(
			p[1], p[2], p[3],
			o[1][1], o[1][2], o[1][3],
			o[2][1], o[2][2], o[2][3],
			o[3][1], o[3][2], o[3][3]
		)
	elseif type(kind) == "string" then
		return inner -- Enum, Content, String, Bool, Float32, ...
	end
	return value
end

local problems = 0

local function build(node)
	local instance = Instance.new(node.c)
	instance.Name = node.n
	if node.s then
		instance.Source = node.s
	end
	for property, value in node.p or {} do
		local ok, message = pcall(function()
			-- Rojo's implicit forms: twelve numbers are a CFrame, three are a
			-- Vector3 or, where the property wants one, a Color3.
			if type(value) == "table" and #value == 12 then
				instance[property] = CFrame.new(table.unpack(value))
			elseif type(value) == "table" and #value == 3 then
				if not pcall(function()
					instance[property] = Vector3.new(value[1], value[2], value[3])
				end) then
					instance[property] = Color3.new(value[1], value[2], value[3])
				end
			else
				instance[property] = decode(value)
			end
		end)
		if not ok then
			problems += 1
			warn(`[Ordnance:Sync] {node.n}.{property}: {message}`)
		end
	end
	for attribute, value in node.a or {} do
		instance:SetAttribute(attribute, decode(value))
	end
	for _, child in node.k or {} do
		build(child).Parent = instance
	end
	return instance
end

local bundle = HttpService:JSONDecode(HttpService:GetAsync(URL, true))
local fresh = build(bundle.root)

local existing = ReplicatedStorage:FindFirstChild(bundle.name)
if existing then
	existing:Destroy()
end
fresh.Parent = ReplicatedStorage

return `[Ordnance:Sync] v{bundle.version} installed, {#fresh:GetDescendants() + 1} instances, {problems} problems`
