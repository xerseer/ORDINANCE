--!strict
--[[
	Spread
	Turns an aim direction into the directions rounds actually leave in.

	The offsets come from a seeded generator, so the client and the server
	derive identical pellets from (seed, shot number) and only the aim
	direction has to cross the network. A client cannot send hand-picked
	pellet directions.
]]

local Defaults = require(script.Parent.Parent.Config.Defaults)

type Config = Defaults.Config

local Spread = {}

-- The direction of pellet `index` of shot `shotId`, inside a cone of
-- half-angle `degrees` around `aim`.
function Spread.direction(aim: Vector3, degrees: number, seed: number, shotId: number, index: number): Vector3
	if degrees <= 0 then
		return aim.Unit
	end
	local random = Random.new(seed + shotId * 7919 + index * 104729)
	-- sqrt gives an even spread over the disc instead of bunching at the centre.
	local angle = math.rad(degrees) * math.sqrt(random:NextNumber())
	local roll = random:NextNumber() * math.pi * 2
	local frame = CFrame.lookAlong(Vector3.zero, aim.Unit)
	return (frame * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

-- Every pellet direction for one shot.
function Spread.pellets(
	config: Config,
	aim: Vector3,
	degrees: number,
	seed: number,
	shotId: number
): { Vector3 }
	local count = config.Fire.Pellets
	local directions = table.create(count)
	for index = 1, count do
		directions[index] = Spread.direction(aim, degrees, seed, shotId, index)
	end
	return directions
end

-- The narrowest and widest cone a client could honestly report.
function Spread.bounds(config: Config): (number, number)
	local spread = config.Spread
	local low = math.min(spread.Hip, spread.Aim)
	local high = math.max(spread.Hip, spread.Aim) + spread.Moving + spread.Airborne + spread.Max
	return low, high
end

--[[
	The cone half-angle for the shooter's current situation.
	`aim` is 0 (hip) to 1 (fully aimed); `bloom` is the degrees built up by
	recent shots.
]]
function Spread.angle(config: Config, aim: number, moving: boolean, airborne: boolean, bloom: number): number
	local spread = config.Spread
	local angle = spread.Hip + (spread.Aim - spread.Hip) * math.clamp(aim, 0, 1)
	if moving then
		angle += spread.Moving
	end
	if airborne then
		angle += spread.Airborne
	end
	return math.min(angle + bloom, math.max(spread.Max, angle))
end

return Spread
