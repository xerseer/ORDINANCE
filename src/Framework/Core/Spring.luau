--!strict
--[[
	Spring
	A damped spring for numbers and vectors. Used for recoil now and for sway
	and procedural animation later.

		local spring = Spring.new(Vector3.zero, 12, 0.7)
		spring.Target = Vector3.new(0, 1, 0)
		spring:Impulse(Vector3.new(0, 4, 0))
		local value = spring:Step(deltaTime)

	Speed is the natural frequency in radians per second (higher is snappier).
	Damping is the damping ratio: below 1 overshoots, 1 settles without
	overshoot, above 1 is sluggish.
]]

export type Spring<T> = {
	Position: T,
	Velocity: T,
	Target: T,
	Speed: number,
	Damping: number,
	Step: (self: Spring<T>, deltaTime: number) -> T,
	Impulse: (self: Spring<T>, velocity: T) -> (),
	Reset: (self: Spring<T>, position: T) -> (),
}

local MAX_STEP = 1 / 120

local Spring = {}
Spring.__index = Spring

function Spring.new<T>(initial: T, speed: number, damping: number): Spring<T>
	local self = setmetatable({
		Position = initial,
		Velocity = (initial :: any) * 0,
		Target = initial,
		Speed = speed,
		Damping = damping,
	}, Spring)
	return (self :: any) :: Spring<T>
end

function Spring:Step(deltaTime: number): any
	-- Clamp long frames so a hitch cannot make the spring explode.
	local remaining = math.min(deltaTime, 0.1)
	local speed: number = self.Speed
	local damping: number = self.Damping
	while remaining > 1e-6 do
		local step = math.min(remaining, MAX_STEP)
		remaining -= step
		local acceleration = (self.Target - self.Position) * (speed * speed)
			- self.Velocity * (2 * damping * speed)
		self.Velocity += acceleration * step
		self.Position += self.Velocity * step
	end
	return self.Position
end

function Spring:Impulse(velocity: any)
	self.Velocity += velocity
end

function Spring:Reset(position: any)
	self.Position = position
	self.Target = position
	self.Velocity = position * 0
end

return Spring
