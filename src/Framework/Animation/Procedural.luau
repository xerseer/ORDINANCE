--!strict
--[[
	Procedural
	Motion made from the weapon's attachments instead of keyframes. A weapon
	with nothing but a model and a few attachments still equips, reloads and
	cycles believably.

	What each attachment enables:
		Grip   the support hand rests here (otherwise it cups the trigger hand)
		Mag    the support hand travels here to swap the magazine or feed shells
		Side   a hand travels here to work the bolt or charging handle

	Parts of the model with these names move by themselves:
		Mag            drops out and comes back during a magazine reload
		Bolt, Slide    snap back on every shot, and move with the hand on a cycle
		Pump           slides back and forward with the support hand

	Output uses the same channels as an encoded animation (see Encoded.luau),
	so the two can stand in for each other.
]]

local Defaults = require(script.Parent.Parent.Config.Defaults)

type Config = Defaults.Config

export type Context = {
	config: Config,
	right: CFrame, -- trigger-hand grip, in handle space
	left: CFrame, -- support-hand grip, in handle space
	mag: CFrame?,
	side: CFrame?,
}

local Procedural = {}

-- 0 before `from`, 1 after `to`, smooth in between.
local function ramp(from: number, to: number, alpha: number): number
	local t = math.clamp((alpha - from) / (to - from), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Rises through `from..peak` and falls through `back..to`.
local function hump(from: number, peak: number, back: number, to: number, alpha: number): number
	return ramp(from, peak, alpha) - ramp(back, to, alpha)
end

local function tilt(pitch: number, yaw: number, roll: number): CFrame
	return CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
end

-- A hand offset that takes a hand from its grip to a point in handle space,
-- keeping the hand's own rotation.
local function reach(grip: CFrame, target: Vector3, amount: number): CFrame
	return CFrame.new(grip:VectorToObjectSpace(target - grip.Position) * amount)
end

-- A hand offset equal to sliding the hand by a handle-space vector.
local function slide(grip: CFrame, offset: Vector3): CFrame
	return CFrame.new(grip:VectorToObjectSpace(offset))
end

local function equip(alpha: number, out: { [string]: CFrame })
	local k = 1 - ramp(0, 1, alpha)
	out.Weapon = CFrame.new(0, -0.9 * k, 0.3 * k) * tilt(38 * k, 0, -12 * k)
end

local function reloadMagazine(alpha: number, context: Context, out: { [string]: CFrame })
	local settle = hump(0, 0.14, 0.86, 1, alpha)
	out.Weapon = CFrame.new(0.04 * settle, -0.06 * settle, 0.05 * settle) * tilt(9 * settle, 0, -16 * settle)

	local mag = context.mag
	if mag == nil then
		-- No Mag attachment: the weapon dips and comes back.
		local dip = hump(0.15, 0.4, 0.6, 0.85, alpha)
		out.Weapon *= CFrame.new(0, -0.25 * dip, 0) * tilt(14 * dip, 0, 0)
		return
	end

	-- Hand goes to the magazine, pulls it out and down, brings a fresh one
	-- up, seats it, and returns to the grip.
	local toMag = hump(0.05, 0.22, 0.8, 0.96, alpha)
	local out1 = hump(0.24, 0.4, 0.56, 0.76, alpha)
	local drop = Vector3.new(-0.15 * out1, -1.35 * out1, 0.2 * out1)

	out.Mag = CFrame.new(drop)
	out.Left = slide(context.left, drop) * reach(context.left, mag.Position + Vector3.new(0, -0.18, 0), toMag)
end

local function reloadShells(elapsed: number, alpha: number, context: Context, out: { [string]: CFrame })
	local settle = hump(0, 0.12, 0.9, 1, alpha)
	out.Weapon = CFrame.new(0, -0.05 * settle, 0) * tilt(12 * settle, 0, 14 * settle)

	local shellTime = context.config.Ammo.ShellTime
	local cycle = (elapsed % shellTime) / shellTime
	local feed = hump(0.1, 0.5, 0.6, 0.95, cycle) * settle
	local port = if context.mag
		then context.mag.Position
		else context.right.Position + Vector3.new(0, 0.1, -0.5)
	local pouch = port + Vector3.new(-0.2, -1.1, 0.5)
	local hand = pouch:Lerp(port, feed)
	out.Left = reach(context.left, hand, settle)
end

local function cycle(alpha: number, context: Context, out: { [string]: CFrame })
	local action = context.config.Fire.Action
	local pull = hump(0.25, 0.45, 0.55, 0.78, alpha)

	if action == "Pump" then
		local travel = Vector3.new(0, 0, 0.38 * pull)
		out.Pump = CFrame.new(travel)
		out.Left = slide(context.left, travel)
		out.Weapon = CFrame.new(0, 0, 0.05 * pull) * tilt(-2 * pull, 0, 0)
		return
	end

	local handOn = hump(0, 0.2, 0.8, 1, alpha)
	local travel = Vector3.new(0, 0, 0.42 * pull)
	out.Bolt = CFrame.new(travel)
	out.Slide = CFrame.new(travel)

	local side = context.side
	if action == "Bolt" then
		out.Weapon = CFrame.new(0, -0.03 * handOn, 0) * tilt(3 * handOn, 0, 10 * handOn)
		if side then
			out.Right = slide(context.right, travel) * reach(context.right, side.Position, handOn)
		end
	else
		-- Self-loading: the support hand racks the charging handle.
		out.Weapon = CFrame.new(0, -0.04 * handOn, 0) * tilt(6 * handOn, 0, -12 * handOn)
		if side then
			out.Left = slide(context.left, travel) * reach(context.left, side.Position, handOn)
		end
	end
end

--[[
	Writes the channels for `action` into `out`.
	`alpha` is 0 to 1 through the action; `elapsed` is seconds since it began.
]]
function Procedural.sample(
	action: string,
	alpha: number,
	elapsed: number,
	context: Context,
	out: { [string]: CFrame }
)
	if action == "Equip" then
		equip(alpha, out)
	elseif action == "Reload" then
		if context.config.Ammo.ReloadType == "Single" then
			reloadShells(elapsed, alpha, context, out)
		else
			reloadMagazine(alpha, context, out)
		end
	elseif action == "Cycle" then
		cycle(alpha, context, out)
	end
end

-- The moving parts' offsets `age` seconds after a shot. Self-loading only:
-- the slide or bolt snaps back and returns.
function Procedural.fire(age: number, context: Context, out: { [string]: CFrame })
	if context.config.Fire.Action ~= "SelfLoading" then
		return
	end
	local duration = math.min(0.09, 60 / context.config.Fire.RPM * 0.8)
	if age >= duration then
		return
	end
	local k = math.sin(math.pi * age / duration)
	local travel = CFrame.new(0, 0, 0.16 * k)
	out.Slide = travel
	out.Bolt = travel
end

return Procedural
