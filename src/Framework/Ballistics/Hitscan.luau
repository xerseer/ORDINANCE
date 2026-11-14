--!strict
--[[
	Hitscan
	World raycasts for bullets.

	Bullets ignore things that are not solid (decorations with CanCollide off,
	invisible triggers) but still hit characters, whose limbs are non-colliding
	by design. With penetration, a bullet passes through thin walls and the
	walls it crossed are returned so damage can be scaled.
]]

local Hitscan = {}

export type Wall = {
	enter: number, -- distance along the ray where the wall starts
	thickness: number,
	result: RaycastResult,
}

export type Trace = {
	walls: { Wall }, -- solid things the bullet passed through
	final: RaycastResult?, -- where it stopped; nil if it ran out of range
	distance: number, -- how far it travelled
	position: Vector3,
}

local MAX_PASSES = 12

-- The model a part belongs to if that model is a character or NPC.
function Hitscan.humanoidOf(instance: Instance): (Humanoid?, Model?)
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid, model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

local function isSolid(instance: Instance): boolean
	if instance:IsA("Terrain") then
		return true
	end
	-- Hats and hair are not body parts. A bullet passes through them to the
	-- body behind, as it does against the rewound hitboxes of players, so a
	-- tall hat is not a bigger head.
	if instance:FindFirstAncestorOfClass("Accessory") then
		return false
	end
	if instance:IsA("BasePart") then
		if instance.CanCollide then
			return true
		end
		return Hitscan.humanoidOf(instance) ~= nil
	end
	return false
end

function Hitscan.params(exclude: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	params.RespectCanCollide = false
	return params
end

-- One raycast that skips non-solid parts. `params` gains the skipped parts.
function Hitscan.raycast(origin: Vector3, displacement: Vector3, params: RaycastParams): RaycastResult?
	for _ = 1, MAX_PASSES do
		local result = workspace:Raycast(origin, displacement, params)
		if result == nil then
			return nil
		end
		if isSolid(result.Instance) then
			return result
		end
		params:AddToFilter(result.Instance)
	end
	return nil
end

-- How thick `instance` is along the ray from `enter`, or nil if it is thicker than `limit`.
local function thicknessOf(instance: Instance, enter: Vector3, direction: Vector3, limit: number): number?
	local only = RaycastParams.new()
	only.FilterType = Enum.RaycastFilterType.Include
	only.FilterDescendantsInstances = { instance }
	only.IgnoreWater = true
	local start = enter + direction * (limit + 0.05)
	local back = workspace:Raycast(start, -direction * (limit + 0.05), only)
	if back == nil then
		return nil
	end
	return (back.Position - enter).Magnitude
end

--[[
	Traces a bullet from `origin` along the unit vector `direction`.
	`penetration` is the total studs of solid material it may cross.
	Characters and NPCs always stop the bullet.
]]
function Hitscan.trace(
	origin: Vector3,
	direction: Vector3,
	range: number,
	params: RaycastParams,
	penetration: number
): Trace
	local walls: { Wall } = {}
	local budget = penetration
	local travelled = 0
	local position = origin

	for _ = 1, MAX_PASSES do
		local remaining = range - travelled
		if remaining <= 0 then
			break
		end
		local result = Hitscan.raycast(position, direction * remaining, params)
		if result == nil then
			break
		end

		local hitDistance = travelled + result.Distance
		local stops = budget <= 0
			or result.Instance:IsA("Terrain")
			or Hitscan.humanoidOf(result.Instance) ~= nil
		local thickness = if stops
			then nil
			else thicknessOf(result.Instance, result.Position, direction, budget)
		if thickness == nil then
			return { walls = walls, final = result, distance = hitDistance, position = result.Position }
		end

		table.insert(walls, { enter = hitDistance, thickness = thickness, result = result })
		budget -= thickness
		travelled = hitDistance + thickness + 0.01
		position = origin + direction * travelled
		params:AddToFilter(result.Instance)
	end

	return { walls = walls, final = nil, distance = range, position = origin + direction * range }
end

-- Fraction of damage left after crossing the walls in front of `distance`.
function Hitscan.penetrationScale(trace: Trace, distance: number, penetration: number): number
	if penetration <= 0 then
		return 1
	end
	local crossed = 0
	for _, wall in trace.walls do
		if wall.enter < distance then
			crossed += wall.thickness
		end
	end
	return math.clamp(1 - 0.6 * crossed / penetration, 0.1, 1)
end

return Hitscan
