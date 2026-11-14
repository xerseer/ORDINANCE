--!strict
--[[
	Source
	Turns Lua values into readable source code, for writing the config module,
	presets and converted animations back into the place.

	Output is stable (keys sorted, lists inline when short) so regenerating a
	file produces a small diff.
]]

local Source = {}

local function isIdentifier(key: string): boolean
	return string.match(key, "^[%a_][%w_]*$") ~= nil
end

local function number(value: number): string
	if value == math.huge then
		return "math.huge"
	end
	local text = string.format("%.6g", value)
	return text
end

local function isList(value: { [any]: any }): boolean
	return #value > 0 or next(value) == nil
end

local function scalar(value: any): string?
	local kind = typeof(value)
	if kind == "number" then
		return number(value)
	elseif kind == "string" then
		return string.format("%q", value)
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "Color3" then
		return `Color3.fromHex("#{(value :: Color3):ToHex()}")`
	elseif kind == "Vector3" then
		local v = value :: Vector3
		return `Vector3.new({number(v.X)}, {number(v.Y)}, {number(v.Z)})`
	elseif kind == "Vector2" then
		local v = value :: Vector2
		return `Vector2.new({number(v.X)}, {number(v.Y)})`
	end
	return nil
end

local function write(value: any, indent: string, lines: { string }, trail: string)
	local text = scalar(value)
	if text then
		table.insert(lines, text .. trail)
		return
	end
	if type(value) ~= "table" then
		table.insert(lines, "nil" .. trail)
		return
	end

	if isList(value) then
		local simple = true
		local parts = {}
		for _, item in value do
			local s = scalar(item)
			if s == nil or #s > 40 then
				simple = false
				break
			end
			table.insert(parts, s)
		end
		if simple and #table.concat(parts, ", ") <= 72 then
			table.insert(
				lines,
				(if #parts == 0 then "{}" else "{ " .. table.concat(parts, ", ") .. " }") .. trail
			)
			return
		end
		table.insert(lines, "{")
		for _, item in value do
			local nested: { string } = {}
			write(item, indent .. "\t", nested, ",")
			table.insert(lines, indent .. "\t" .. nested[1])
			for index = 2, #nested do
				table.insert(lines, nested[index])
			end
		end
		table.insert(lines, indent .. "}" .. trail)
		return
	end

	local keys = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	-- A table of only scalars stays on one line when it is short.
	local inline = {}
	local flat = #keys <= 4
	for _, key in keys do
		local s = scalar(value[key])
		if s == nil or type(key) ~= "string" or not isIdentifier(key) then
			flat = false
			break
		end
		table.insert(inline, `{key} = {s}`)
	end
	if flat and #table.concat(inline, ", ") <= 64 then
		table.insert(lines, "{ " .. table.concat(inline, ", ") .. " }" .. trail)
		return
	end

	table.insert(lines, "{")
	for _, key in keys do
		local label = if type(key) == "string" and isIdentifier(key)
			then key
			else `[{scalar(key) or tostring(key)}]`
		local nested: { string } = {}
		write(value[key], indent .. "\t", nested, ",")
		table.insert(lines, `{indent}\t{label} = {nested[1]}`)
		for index = 2, #nested do
			table.insert(lines, nested[index])
		end
	end
	table.insert(lines, indent .. "}" .. trail)
end

-- Source for a value, ending without a trailing newline.
function Source.value(value: any, indent: string?): string
	local lines: { string } = {}
	write(value, indent or "", lines, "")
	return table.concat(lines, "\n")
end

-- A module that returns `value`, with an optional comment block on top.
function Source.module(value: any, header: string?): string
	local top = if header then `--[[\n{header}\n]]\n\n` else ""
	return `{top}return {Source.value(value)}\n`
end

return Source
