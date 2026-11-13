--!strict
--[[
	Signal
	A small, allocation-light event. Handlers run in their own thread, so one
	handler erroring or yielding never blocks the rest or the caller.

		local fired = Signal.new()
		local connection = fired:Connect(function(weaponId) ... end)
		fired:Fire("Glock17")
		connection:Disconnect()
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Slot = {
	handler: (...any) -> (),
	connection: Connection,
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _slots = {} :: { Slot } }, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal:Connect(handler: (...any) -> ()): Connection
	local slots: { Slot } = self._slots
	local connection = { Connected = true } :: any
	local slot: Slot = { handler = handler, connection = connection }

	function connection.Disconnect(_: Connection)
		if not connection.Connected then
			return
		end
		connection.Connected = false
		local index = table.find(slots, slot)
		if index then
			table.remove(slots, index)
		end
	end

	table.insert(slots, slot)
	return connection
end

function Signal:Once(handler: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	local slots: { Slot } = self._slots
	if #slots == 0 then
		return
	end
	-- Copy so handlers may connect or disconnect while we iterate.
	for _, slot in table.clone(slots) do
		if slot.connection.Connected then
			task.spawn(slot.handler, ...)
		end
	end
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	local slots: { Slot } = self._slots
	for _, slot in slots do
		slot.connection.Connected = false
	end
	table.clear(slots)
end

return Signal
