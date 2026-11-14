--!strict
--[[
	Projectile
	Simulates physical rounds: gravity, drag, bounces, fuses.

	A Simulator owns a set of projectiles and steps them with a fixed timestep,
	so the server (which decides damage) and every client (which only draws)
	trace the same arc from the same launch values. Nothing here creates
	instances; the owner supplies a raycast function and reacts to events.

		local simulator = Projectile.newSimulator(raycast, onEvent)
		simulator:launch({ key = "12:5:1", origin = o, velocity = v, ballistics = config.Ballistics })
		RunService.Heartbeat:Connect(function(dt) simulator:step(dt) end)

	Events:
		"Bounce"    hit something and kept going
		"Rest"      a fused round came to a stop and is waiting for its fuse
		"Impact"    hit something and is done                (terminal)
		"Detonate"  exploded, by impact or by fuse           (terminal)
		"Expire"    ran out of lifetime or range             (terminal)
]]

-- selene: allow(unused_variable)
local Defaults = require(script.Parent.Parent.Config.Defaults)

type Ballistics = typeof(Defaults.Ballistics)

export type Event = "Bounce" | "Rest" | "Impact" | "Detonate" | "Expire"

export type Projectile = {
	key: string,
	origin: Vector3,
	position: Vector3,
	velocity: Vector3,
	ballistics: Ballistics,
	age: number,
	travelled: number,
	bounces: number,
	resting: boolean,
	data: any,
}

export type Launch = {
	key: string,
	origin: Vector3,
	velocity: Vector3,
	ballistics: Ballistics,
	data: any?,
	-- Seconds to simulate immediately, to catch up with a launch that
	-- happened earlier on another machine.
	headStart: number?,
}

export type Raycast = (projectile: Projectile, origin: Vector3, displacement: Vector3) -> RaycastResult?
export type OnEvent = (projectile: Projectile, event: Event, result: RaycastResult?) -> ()

export type Simulator = {
	launch: (self: Simulator, launch: Launch) -> Projectile,
	step: (self: Simulator, deltaTime: number) -> (),
	remove: (self: Simulator, key: string) -> (),
	get: (self: Simulator, key: string) -> Projectile?,
	each: (self: Simulator, visit: (Projectile) -> ()) -> (),
	clear: (self: Simulator) -> (),
}

local STEP = 1 / 60
local MAX_STEPS_PER_FRAME = 8
local SKIN = 0.02

local Projectile = {}

-- Advances one projectile by one fixed step. Returns true if it is finished.
local function advance(projectile: Projectile, dt: number, raycast: Raycast, onEvent: OnEvent): boolean
	local ballistics = projectile.ballistics
	local explosive = ballistics.Explosive
	projectile.age += dt

	if explosive.Enabled and explosive.Fuse > 0 and projectile.age >= explosive.Fuse then
		onEvent(projectile, "Detonate", nil)
		return true
	end
	if projectile.age >= ballistics.Lifetime or projectile.travelled >= ballistics.Range then
		onEvent(projectile, "Expire", nil)
		return true
	end
	if projectile.resting then
		return false
	end

	local velocity = projectile.velocity + Vector3.new(0, -workspace.Gravity * ballistics.Gravity * dt, 0)
	velocity *= math.max(0, 1 - ballistics.Drag * dt)
	local displacement = velocity * dt
	projectile.velocity = velocity

	local result = raycast(projectile, projectile.position, displacement)
	if result == nil then
		projectile.position += displacement
		projectile.travelled += displacement.Magnitude
		return false
	end

	projectile.travelled += result.Distance
	projectile.position = result.Position + result.Normal * SKIN

	local detonates = explosive.Enabled and explosive.DetonateOnImpact
	if detonates then
		onEvent(projectile, "Detonate", result)
		return true
	end

	local speed = velocity.Magnitude
	if projectile.bounces < ballistics.Bounce.Count and speed >= ballistics.Bounce.MinSpeed then
		local normal = result.Normal
		projectile.velocity = (velocity - 2 * velocity:Dot(normal) * normal) * ballistics.Bounce.Elasticity
		projectile.bounces += 1
		onEvent(projectile, "Bounce", result)
		return false
	end

	-- A fused round that can no longer bounce lies where it landed.
	if explosive.Enabled and explosive.Fuse > 0 then
		projectile.velocity = Vector3.zero
		projectile.resting = true
		onEvent(projectile, "Rest", result)
		return false
	end

	onEvent(projectile, "Impact", result)
	return true
end

function Projectile.newSimulator(raycast: Raycast, onEvent: OnEvent): Simulator
	local active: { [string]: Projectile } = {}
	local leftover = 0

	local self = {} :: any

	function self.launch(_: Simulator, launch: Launch): Projectile
		local projectile: Projectile = {
			key = launch.key,
			origin = launch.origin,
			position = launch.origin,
			velocity = launch.velocity,
			ballistics = launch.ballistics,
			age = 0,
			travelled = 0,
			bounces = 0,
			resting = false,
			data = launch.data,
		}
		active[launch.key] = projectile

		local headStart = math.min(launch.headStart or 0, 0.5)
		while headStart >= STEP do
			headStart -= STEP
			if advance(projectile, STEP, raycast, onEvent) then
				active[launch.key] = nil
				break
			end
		end
		return projectile
	end

	function self.step(_: Simulator, deltaTime: number)
		leftover += deltaTime
		local steps = math.min(math.floor(leftover / STEP), MAX_STEPS_PER_FRAME)
		leftover = math.min(leftover - steps * STEP, STEP)
		if steps == 0 or next(active) == nil then
			return
		end
		for _ = 1, steps do
			for key, projectile in active do
				if advance(projectile, STEP, raycast, onEvent) then
					active[key] = nil
				end
			end
		end
	end

	function self.remove(_: Simulator, key: string)
		active[key] = nil
	end

	function self.get(_: Simulator, key: string): Projectile?
		return active[key]
	end

	function self.each(_: Simulator, visit: (Projectile) -> ())
		for _, projectile in active do
			visit(projectile)
		end
	end

	function self.clear(_: Simulator)
		table.clear(active)
	end

	return self :: Simulator
end

-- The launch velocity for a config and a unit direction.
function Projectile.velocity(ballistics: Ballistics, direction: Vector3): Vector3
	return direction.Unit * ballistics.Velocity
end

return Projectile
