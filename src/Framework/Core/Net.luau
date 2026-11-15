--!strict
--[[
	Net
	The framework's only network surface: two remotes, created by the server
	inside the Ordnance object at runtime, carrying a fixed set of messages.

	Client messages are rate limited per player on the server before any
	handler runs, and every handler is wrapped so a bad message cannot throw.

		Net.on("Shoot", function(player, ...) end)   -- server
		Net.start(frameworkFolder)
		Net.fire("Shoot", ...)                       -- client
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Logger = require(script.Parent.Logger)

local log = Logger.scope("Net")
local IS_SERVER = RunService:IsServer()

type Message = {
	from: "Client" | "Server",
	reliable: boolean,
	rate: number?, -- client messages: most allowed per second, per player
}

local MESSAGES: { [string]: Message } = {
	-- client -> server
	Shoot = { from = "Client", reliable = true, rate = 60 },
	Action = { from = "Client", reliable = true, rate = 20 },
	Pose = { from = "Client", reliable = false, rate = 20 },
	Attach = { from = "Client", reliable = true, rate = 8 },
	Light = { from = "Client", reliable = true, rate = 8 },
	-- server -> client
	Sync = { from = "Server", reliable = true },
	Hit = { from = "Server", reliable = true },
	Replicate = { from = "Server", reliable = false },
	Explode = { from = "Server", reliable = true },
	Equip = { from = "Server", reliable = true },
	PoseOf = { from = "Server", reliable = false },
	Act = { from = "Server", reliable = true },
}

-- Names travel as small integers. Sorted so both sides derive the same ids.
local NAMES: { string } = {}
for name in MESSAGES do
	table.insert(NAMES, name)
end
table.sort(NAMES)
local IDS: { [string]: number } = {}
for id, name in NAMES do
	IDS[name] = id
end

type Bucket = { tokens: number, time: number }

local Net = {}

local reliable: RemoteEvent? = nil
local unreliable: UnreliableRemoteEvent? = nil
local handlers: { [string]: (...any) -> () } = {}
local buckets: { [Player]: { [number]: Bucket } } = {}
local connections: { RBXScriptConnection } = {}
local folder: Folder? = nil

local function allow(player: Player, id: number, rate: number): boolean
	local perPlayer = buckets[player]
	if perPlayer == nil then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local bucket = perPlayer[id]
	if bucket == nil then
		bucket = { tokens = rate, time = now }
		perPlayer[id] = bucket
	end
	bucket.tokens = math.min(rate, bucket.tokens + (now - bucket.time) * rate)
	bucket.time = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

local function dispatchFromClient(player: Player, id: any, ...: any)
	if type(id) ~= "number" then
		return
	end
	local name = NAMES[id]
	local message = if name then MESSAGES[name] else nil
	if message == nil or message.from ~= "Client" then
		return
	end
	if message.rate and not allow(player, id, message.rate) then
		log:WarnOnce(
			`rate:{player.UserId}:{name}`,
			`{player.Name} is sending "{name}" too fast; extra messages are dropped`
		)
		return
	end
	local handler = handlers[name]
	if handler then
		log:Try(handler, player, ...)
	end
end

local function dispatchFromServer(id: any, ...: any)
	local name = if type(id) == "number" then NAMES[id] else nil
	local handler = if name then handlers[name] else nil
	if handler then
		log:Try(handler, ...)
	end
end

-- Registers the handler for a message. One handler per message.
function Net.on(name: string, handler: (...any) -> ())
	if MESSAGES[name] == nil then
		log:Error(`"{name}" is not a known message`)
		return
	end
	handlers[name] = handler
end

-- Server: creates the remotes under `parent`. Client: waits for them.
function Net.start(parent: Instance): boolean
	if IS_SERVER then
		local created = Instance.new("Folder")
		created.Name = "Remotes"
		local reliableRemote = Instance.new("RemoteEvent")
		reliableRemote.Name = "Reliable"
		reliableRemote.Parent = created
		local unreliableRemote = Instance.new("UnreliableRemoteEvent")
		unreliableRemote.Name = "Unreliable"
		unreliableRemote.Parent = created
		created.Parent = parent

		folder = created
		reliable = reliableRemote
		unreliable = unreliableRemote
		table.insert(connections, reliableRemote.OnServerEvent:Connect(dispatchFromClient))
		table.insert(connections, unreliableRemote.OnServerEvent:Connect(dispatchFromClient))
		table.insert(
			connections,
			Players.PlayerRemoving:Connect(function(player)
				buckets[player] = nil
			end)
		)
		return true
	end

	local found = parent:WaitForChild("Remotes", 30)
	if found == nil then
		log:Error("the server never created the remotes; is the server script running?")
		return false
	end
	local reliableRemote = found:WaitForChild("Reliable", 10) :: RemoteEvent?
	local unreliableRemote = found:WaitForChild("Unreliable", 10) :: UnreliableRemoteEvent?
	if reliableRemote == nil or unreliableRemote == nil then
		log:Error("the remotes folder is incomplete")
		return false
	end
	reliable = reliableRemote
	unreliable = unreliableRemote
	table.insert(connections, reliableRemote.OnClientEvent:Connect(dispatchFromServer))
	table.insert(connections, unreliableRemote.OnClientEvent:Connect(dispatchFromServer))
	return true
end

local function remoteFor(name: string): (any, number?)
	local message = MESSAGES[name]
	if message == nil then
		log:Error(`"{name}" is not a known message`)
		return nil, nil
	end
	return if message.reliable then reliable else unreliable, IDS[name]
end

-- Client -> server.
function Net.fire(name: string, ...: any)
	local remote, id = remoteFor(name)
	if remote then
		remote:FireServer(id, ...)
	end
end

-- Server -> one client.
function Net.fireClient(player: Player, name: string, ...: any)
	local remote, id = remoteFor(name)
	if remote then
		remote:FireClient(player, id, ...)
	end
end

-- Server -> every client.
function Net.fireAll(name: string, ...: any)
	local remote, id = remoteFor(name)
	if remote then
		remote:FireAllClients(id, ...)
	end
end

-- Server -> every client but one. Used to show a shot to everyone except the
-- player who fired it, who already predicted it.
function Net.fireExcept(excluded: Player, name: string, ...: any)
	local remote, id = remoteFor(name)
	if remote == nil then
		return
	end
	for _, player in Players:GetPlayers() do
		if player ~= excluded then
			remote:FireClient(player, id, ...)
		end
	end
end

function Net.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(handlers)
	table.clear(buckets)
	if folder then
		folder:Destroy()
		folder = nil
	end
	reliable = nil
	unreliable = nil
end

return Net
