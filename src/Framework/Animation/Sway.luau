--!strict
--[[
	Sway
	Makes a first-person weapon feel held rather than bolted to the camera.

	Six small motions, each with its own multiplier in the Sway config:
		Mouse     the weapon lags behind when you look around
		Bob       it bobs in step while you walk
		Breath    it drifts gently when you stand still
		Landing   it dips when you land
		Tilt      it rolls into a strafe
		Kick      it jumps back and up with every shot

	All of them run on springs (Sway.Speed and Sway.Damping), and all but the
	kick shrink while aiming (Sway.AimScale).
]]

local Defaults = require(script.Parent.Parent.Config.Defaults)
local Spring = require(script.Parent.Parent.Core.Spring)

type Config = Defaults.Config

export type Input = {
	look: Vector2, -- change in camera yaw and pitch this frame, radians
	velocity: Vector3, -- character velocity in camera space
	grounded: boolean,
	aim: number, -- 0 (hip) to 1 (aimed)
}

export type Sway = {
	update: (self: Sway, deltaTime: number, config: Config, input: Input) -> CFrame,
	kick: (self: Sway, config: Config, aim: number) -> (),
	reset: (self: Sway) -> (),
}

local MAX_LOOK = math.rad(5)

local Sway = {}

function Sway.new(): Sway
	local look = Spring.new(Vector2.zero, 12, 0.7)
	local roll = Spring.new(0, 10, 0.8)
	local land = Spring.new(0, 14, 0.5)
	-- X: back (studs). Y: muzzle climb (radians). Z: twist (radians).
	local kick = Spring.new(Vector3.zero, 26, 0.55)
	local random = Random.new()

	local phase = 0
	local stride = 0
	local time = 0
	local wasGrounded = true
	local fallSpeed = 0

	local self = {} :: any

	function self.update(_: Sway, deltaTime: number, config: Config, input: Input): CFrame
		local settings = config.Sway
		if not settings.Enabled then
			return CFrame.identity
		end
		time += deltaTime
		local calm = 1 + (settings.AimScale - 1) * math.clamp(input.aim, 0, 1)

		-- Mouse: aim the weapon a little behind where the camera turned.
		look.Speed = settings.Speed
		look.Damping = settings.Damping
		local rate = if deltaTime > 0 then input.look / deltaTime else Vector2.zero
		local lag = rate * -0.012 * settings.Mouse
		look.Target =
			Vector2.new(math.clamp(lag.X, -MAX_LOOK, MAX_LOOK), math.clamp(lag.Y, -MAX_LOOK, MAX_LOOK))
		local lookOffset = look:Step(deltaTime) * calm

		-- Bob: a figure of eight in step with walking speed.
		local planar = Vector3.new(input.velocity.X, 0, input.velocity.Z).Magnitude
		local walking = if input.grounded then math.clamp(planar / 16, 0, 1.6) else 0
		stride += (walking - stride) * math.min(1, deltaTime * 8)
		phase += deltaTime * (5 + planar * 0.45) * (if walking > 0.05 then 1 else 0)
		local bob = stride * settings.Bob * calm
		local bobX = math.sin(phase) * 0.03 * bob
		local bobY = -math.abs(math.cos(phase)) * 0.028 * bob + 0.014 * bob

		-- Breath: slow, never quite repeating.
		local breath = settings.Breath * calm * (1 - math.min(stride, 1) * 0.6)
		local breathY = math.sin(time * 1.15) * 0.006 * breath
		local breathPitch = math.sin(time * 0.9 + 1.3) * 0.004 * breath
		local breathYaw = math.sin(time * 0.61) * 0.004 * breath

		-- Landing: a dip sized by how fast we were falling.
		if not input.grounded then
			fallSpeed = math.max(fallSpeed, -input.velocity.Y)
		elseif not wasGrounded then
			land:Impulse(-math.clamp(fallSpeed, 0, 80) * 0.035 * settings.Landing)
			fallSpeed = 0
		end
		wasGrounded = input.grounded
		local dip = land:Step(deltaTime)

		-- Tilt: lean into a strafe.
		roll.Target = -math.clamp(input.velocity.X / 16, -1, 1) * math.rad(3.5) * settings.Tilt * calm
		local rollOffset = roll:Step(deltaTime) + math.sin(phase) * 0.008 * bob

		local kicked = kick:Step(deltaTime)

		return CFrame.new(bobX, bobY + breathY + dip, kicked.X)
			* CFrame.Angles(
				lookOffset.Y + breathPitch + kicked.Y + dip * 0.25,
				lookOffset.X + breathYaw,
				rollOffset + kicked.Z
			)
	end

	-- One shot's worth of kick. Heavier-recoiling weapons kick harder.
	function self.kick(_: Sway, config: Config, aim: number)
		local settings = config.Sway
		if not settings.Enabled or settings.Kick <= 0 then
			return
		end
		local weight = settings.Kick * (0.45 + config.Recoil.Vertical * 0.5)
		local aimed = 1 - 0.45 * math.clamp(aim, 0, 1)
		kick:Impulse(
			Vector3.new(
				2.6 * weight * aimed,
				1.1 * weight * aimed,
				random:NextNumber(-0.5, 0.5) * weight * aimed
			)
		)
	end

	function self.reset(_: Sway)
		look:Reset(Vector2.zero)
		roll:Reset(0)
		land:Reset(0)
		kick:Reset(Vector3.zero)
		stride = 0
		fallSpeed = 0
	end

	return self :: Sway
end

return Sway
