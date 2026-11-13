--!strict
--[[
	Recoil
	Kicks the camera when a shot is fired.

	Each kick has two parts. The recoverable part goes through a spring: the
	camera jumps and settles back by itself. The rest is a permanent climb the
	player has to pull down against. Recoil.Recovery sets the split.

	The camera is turned by a small delta each frame, after the camera scripts
	have run. Roblox's camera carries on from wherever the camera is facing, so
	the deltas add up to the kick without the framework owning the camera.
]]

local RunService = game:GetService("RunService")

-- selene: allow(unused_variable)
local Defaults = require(script.Parent.Parent.Config.Defaults)
local Spring = require(script.Parent.Parent.Core.Spring)

type RecoilConfig = typeof(Defaults.Recoil)

local STEP_NAME = "OrdnanceRecoil"

local Recoil = {}

-- X is pitch (up), Y is yaw, both in radians.
local spring = Spring.new(Vector2.zero, 22, 0.8)
local lastSpring = Vector2.zero
local pending = Vector2.zero
local climbSpeed = 22
local random = Random.new()
local running = false

local function step(deltaTime: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end

	local position = spring:Step(deltaTime)
	local delta = position - lastSpring
	lastSpring = position

	if pending.Magnitude > 1e-5 then
		local portion = pending * math.min(1, climbSpeed * deltaTime)
		pending -= portion
		delta += portion
	end

	if delta.Magnitude > 1e-6 then
		camera.CFrame *= CFrame.Angles(delta.X, delta.Y, 0)
	end
end

function Recoil.start()
	if running then
		return
	end
	running = true
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, step)
end

function Recoil.stop()
	if not running then
		return
	end
	running = false
	RunService:UnbindFromRenderStep(STEP_NAME)
	spring:Reset(Vector2.zero)
	lastSpring = Vector2.zero
	pending = Vector2.zero
end

-- Applies one shot's worth of recoil. `aim` is 0 (hip) to 1 (aimed).
function Recoil.kick(config: RecoilConfig, aim: number)
	local scale = 1 + (config.AimScale - 1) * math.clamp(aim, 0, 1)
	local pitch = math.rad(config.Vertical) * scale
	local yaw = math.rad(config.Horizontal) * scale * random:NextNumber(-1, 1)
	local kick = Vector2.new(pitch, yaw)

	spring.Speed = config.Speed
	spring.Damping = config.Damping
	climbSpeed = config.Speed

	-- An impulse of v peaks near v / (e * speed) on a well-damped spring, so
	-- scale it to make the peak equal the recoverable part of the kick.
	spring:Impulse(kick * config.Recovery * config.Speed * math.exp(1))
	pending += kick * (1 - config.Recovery)
end

return Recoil
