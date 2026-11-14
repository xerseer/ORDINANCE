--!strict
--[[
	Merge
	Deep-merges config tables.

	  - Maps (string keys) are merged key by key, recursively.
	  - Lists (numeric keys) and every other value replace what was there.
	  - Nothing is mutated; the result shares no tables with its inputs.
]]

local Merge = {}

type Map = { [any]: any }

function Merge.isList(value: any): boolean
	return type(value) == "table" and #value > 0
end

function Merge.copy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, inner in value :: any do
		result[key] = Merge.copy(inner)
	end
	return (result :: any) :: T
end

-- Returns a new table: `base` with `override` laid on top.
function Merge.deep(base: Map, override: Map?): Map
	local result = Merge.copy(base)
	if override == nil then
		return result
	end
	for key, value in override do
		local existing = result[key]
		if type(value) == "table" and type(existing) == "table" and #value == 0 and #existing == 0 then
			result[key] = Merge.deep(existing, value)
		else
			result[key] = Merge.copy(value)
		end
	end
	return result
end

-- Lays any number of layers over `base`, lowest priority first.
function Merge.layers(base: Map, ...: Map?): Map
	local result = Merge.copy(base)
	for index = 1, select("#", ...) do
		local layer = select(index, ...)
		if layer ~= nil then
			result = Merge.deep(result, layer)
		end
	end
	return result
end

function Merge.freeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		for _, inner in value :: any do
			Merge.freeze(inner)
		end
		table.freeze(value :: any)
	end
	return value
end

return Merge
