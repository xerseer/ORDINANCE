--!strict
--[[
	Trove
	Collects things that need cleaning up and cleans them all at once.

		local trove = Trove.new()
		trove:Add(part)                       -- Destroy()
		trove:Add(signal:Connect(handler))    -- Disconnect()
		trove:Add(function() ... end)         -- called
		trove:Clean()
]]

export type Trove = {
	Add: <T>(self: Trove, item: T) -> T,
	Clean: (self: Trove) -> (),
}

local Trove = {}
Trove.__index = Trove

function Trove.new(): Trove
	return (setmetatable({ _items = {} }, Trove) :: any) :: Trove
end

function Trove:Add(item: any): any
	table.insert(self._items, item)
	return item
end

function Trove:Clean()
	local items: { any } = self._items
	self._items = {}
	-- Last in, first out, like a stack of defers.
	for index = #items, 1, -1 do
		local item = items[index]
		local kind = typeof(item)
		if kind == "function" then
			task.spawn(item)
		elseif kind == "RBXScriptConnection" then
			item:Disconnect()
		elseif kind == "Instance" then
			item:Destroy()
		elseif kind == "thread" then
			pcall(task.cancel, item)
		elseif kind == "table" then
			if type(item.Disconnect) == "function" then
				item:Disconnect()
			elseif type(item.Clean) == "function" then
				item:Clean()
			elseif type(item.Destroy) == "function" then
				item:Destroy()
			end
		end
	end
end

return Trove
