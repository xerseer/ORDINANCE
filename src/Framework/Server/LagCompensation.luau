--!strict
--[[
	LagCompensation
	Remembers where every player's body parts were for the last second, so a
	shot can be tested against the world the shooter actually saw.

	Player characters are never raycast against directly. The server casts
	against the level, then tests the shot against boxes placed where each
	character's parts were at the shot's (rewound) time.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

export type Hit = {
	character: Model,
	humanoid: Humanoid,
	player: Player,
	part: string,
	distance: number,
	position: Vector3,
}

type Frame = {
	time: number,
	parts: { [string]: CFrame },
}

type Track = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	frames: { Frame },
	sizes: { [string]: Vector3 },
}

local HISTORY = 1 -- seconds kept
local BROAD_RADIUS = 9 -- studs around the root that could contain a limb

local LagCompensation = {}

local tracks: { [Player]: Track } = {}
local connection: RBXScriptConnection? = nil
local interval = 1 / 30
local accumulated = 0

local function record(now: number)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if character == nil or humanoid == nil or humanoid.Health <= 0 then
			tracks[player] = nil
			continue
		end

		local track = tracks[player]
		if track == nil or track.character ~= character then
			track = { player = player, character = character, humanoid = humanoid, frames = {}, sizes = {} }
			tracks[player] = track
		end

		local parts: { [string]: CFrame } = {}
		for _, child in character:GetChildren() do
			if child:IsA("BasePart") then
				parts[child.Name] = child.CFrame
				track.sizes[child.Name] = child.Size
			end
		end

		local frames = track.frames
		table.insert(frames, { time = now, parts = parts })
		while #frames > 2 and frames[1].time < now - HISTORY do
			table.remove(frames, 1)
		end
	end

	for player in tracks do
		if player.Parent == nil then
			tracks[player] = nil
		end
	end
end

-- The two frames around `time` and how far between them it falls.
local function bracket(frames: { Frame }, time: number): (Frame, Frame, number)
	local last = frames[#frames]
	if time >= last.time then
		return last, last, 0
	end
	for index = #frames - 1, 1, -1 do
		local earlier = frames[index]
		if earlier.time <= time then
			local later = frames[index + 1]
			local span = later.time - earlier.time
			return earlier, later, if span > 0 then (time - earlier.time) / span else 0
		end
	end
	return frames[1], frames[1], 0
end

-- Distance along the ray to an oriented box, or nil if it misses.
local function rayBox(
	origin: Vector3,
	direction: Vector3,
	frame: CFrame,
	size: Vector3,
	limit: number
): number?
	local o = frame:PointToObjectSpace(origin)
	local d = frame:VectorToObjectSpace(direction)
	local half = size / 2
	local near, far = 0, limit

	local function slab(position: number, slope: number, extent: number): boolean
		if math.abs(slope) < 1e-8 then
			return position >= -extent and position <= extent
		end
		local a = (-extent - position) / slope
		local b = (extent - position) / slope
		if a > b then
			a, b = b, a
		end
		near = math.max(near, a)
		far = math.min(far, b)
		return near <= far
	end

	if slab(o.X, d.X, half.X) and slab(o.Y, d.Y, half.Y) and slab(o.Z, d.Z, half.Z) then
		return near
	end
	return nil
end

function LagCompensation.start(snapshotRate: number)
	LagCompensation.stop()
	interval = 1 / snapshotRate
	accumulated = 0
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		accumulated += deltaTime
		if accumulated >= interval then
			accumulated %= interval
			record(workspace:GetServerTimeNow())
		end
	end)
end

function LagCompensation.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	table.clear(tracks)
end

-- Every tracked character, for raycast exclude lists.
function LagCompensation.characters(): { Instance }
	local list: { Instance } = {}
	for _, track in tracks do
		table.insert(list, track.character)
	end
	return list
end

--[[
	Tests a ray against every tracked character as they were at `time`
	(server time). `direction` must be a unit vector. Returns the closest hit
	within `limit` studs, ignoring `exclude` (the shooter).
]]
function LagCompensation.raycast(
	origin: Vector3,
	direction: Vector3,
	limit: number,
	time: number,
	exclude: Model?
): Hit?
	local best: Hit? = nil
	local bestDistance = limit

	for _, track in tracks do
		if track.character == exclude or track.humanoid.Health <= 0 or #track.frames == 0 then
			continue
		end
		local earlier, later, alpha = bracket(track.frames, time)

		-- Broad phase: skip characters whose root is nowhere near the ray.
		local rootFrame = earlier.parts.HumanoidRootPart
		if rootFrame then
			local toRoot = rootFrame.Position - origin
			local along = toRoot:Dot(direction)
			if along < -BROAD_RADIUS or along > bestDistance + BROAD_RADIUS then
				continue
			end
			local offset = toRoot - direction * along
			if offset:Dot(offset) > BROAD_RADIUS * BROAD_RADIUS then
				continue
			end
		end

		for name, earlierFrame in earlier.parts do
			if name == "HumanoidRootPart" then
				continue -- overlaps the torso; counting it would double the hitbox
			end
			local laterFrame = later.parts[name]
			local size = track.sizes[name]
			if laterFrame == nil or size == nil then
				continue
			end
			local frame = if alpha > 0 then earlierFrame:Lerp(laterFrame, alpha) else earlierFrame
			local distance = rayBox(origin, direction, frame, size, bestDistance)
			if distance and distance < bestDistance then
				bestDistance = distance
				best = {
					character = track.character,
					humanoid = track.humanoid,
					player = track.player,
					part = name,
					distance = distance,
					position = origin + direction * distance,
				}
			end
		end
	end

	return best
end

-- The rewound boxes of one character, for the debug visualiser.
function LagCompensation.boxes(player: Player, time: number): { { cframe: CFrame, size: Vector3 } }
	local track = tracks[player]
	local boxes = {}
	if track == nil or #track.frames == 0 then
		return boxes
	end
	local earlier, later, alpha = bracket(track.frames, time)
	for name, earlierFrame in earlier.parts do
		local laterFrame = later.parts[name]
		local size = track.sizes[name]
		if laterFrame and size and name ~= "HumanoidRootPart" then
			table.insert(boxes, { cframe = earlierFrame:Lerp(laterFrame, alpha), size = size })
		end
	end
	return boxes
end

return LagCompensation
