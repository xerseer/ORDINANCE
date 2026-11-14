--!strict
--[[
	View
	The local player's camera while a weapon is held: first or third person,
	where the aim point is on screen, and which way the character faces.

	The framework does not own the camera. It nudges a few settings while a
	weapon is out and puts every one of them back when it is put away.

	Aim follows the cursor when the mouse is free (third person without mouse
	lock) and the centre of the screen otherwise, so both the classic Roblox
	"click where you want to shoot" and a shooter-style locked view work
	without configuration.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Defaults = require(script.Parent.Parent.Config.Defaults)

type Config = Defaults.Config

type Saved = {
	cameraMode: Enum.CameraMode,
	minZoom: number,
	cameraOffset: Vector3,
	autoRotate: boolean,
	mouseIcon: boolean,
}

local FIRST_PERSON_DISTANCE = 1.1
local THIRD_PERSON_MIN_ZOOM = 6
local TURN_SPEED = 16

local TURNABLE: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Landed] = true,
}

local player = Players.LocalPlayer

local View = {}

local saved: Saved? = nil
local shoulder = Vector3.zero

-- True when the camera is zoomed all the way in.
function View.isFirstPerson(): boolean
	local camera = workspace.CurrentCamera
	if camera == nil then
		return false
	end
	return (camera.CFrame.Position - camera.Focus.Position).Magnitude < FIRST_PERSON_DISTANCE
end

-- The point on screen the weapon is aimed through, in viewport pixels.
function View.screenPoint(): Vector2
	local camera = workspace.CurrentCamera
	local centre = if camera then camera.ViewportSize / 2 else Vector2.zero
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
		return centre
	end
	local last = UserInputService:GetLastInputType()
	local usingMouse = last == Enum.UserInputType.MouseMovement
		or last == Enum.UserInputType.MouseButton1
		or last == Enum.UserInputType.MouseButton2
		or last == Enum.UserInputType.MouseWheel
		or last == Enum.UserInputType.Keyboard
	if not usingMouse or not UserInputService.MouseEnabled then
		return centre
	end
	return UserInputService:GetMouseLocation()
end

-- The world ray through the aim point.
function View.ray(): (Vector3, Vector3)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return Vector3.zero, -Vector3.zAxis
	end
	local point = View.screenPoint()
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	return ray.Origin, ray.Direction
end

-- Call when a weapon is drawn.
function View.begin(config: Config, humanoid: Humanoid)
	if saved == nil then
		saved = {
			cameraMode = player.CameraMode,
			minZoom = player.CameraMinZoomDistance,
			cameraOffset = humanoid.CameraOffset,
			autoRotate = humanoid.AutoRotate,
			mouseIcon = UserInputService.MouseIconEnabled,
		}
		shoulder = Vector3.zero
	end
	local current = saved :: Saved

	local mode = config.Camera.Mode
	if mode == "FirstPerson" then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	elseif mode == "ThirdPerson" then
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMinZoomDistance = math.max(current.minZoom, THIRD_PERSON_MIN_ZOOM)
	else
		player.CameraMode = current.cameraMode
		player.CameraMinZoomDistance = current.minZoom
	end

	-- The built-in crosshair stands in for the cursor.
	UserInputService.MouseIconEnabled = not (config.HUD.Enabled and config.HUD.Crosshair)
end

-- Call when the weapon is put away. Restores everything `begin` changed.
function View.finish(humanoid: Humanoid?)
	local current = saved
	if current == nil then
		return
	end
	saved = nil
	player.CameraMode = current.cameraMode
	player.CameraMinZoomDistance = current.minZoom
	UserInputService.MouseIconEnabled = current.mouseIcon
	if humanoid then
		humanoid.CameraOffset = current.cameraOffset
		humanoid.AutoRotate = current.autoRotate
	end
end

--[[
	Per-frame camera upkeep. `aim` is the unit direction from the character's
	head to what it is aiming at. Returns true while in first person.
]]
function View.update(
	deltaTime: number,
	config: Config,
	humanoid: Humanoid,
	root: BasePart,
	aim: Vector3
): boolean
	local current = saved
	local firstPerson = View.isFirstPerson()
	if current == nil then
		return firstPerson
	end

	-- Over-the-shoulder camera in third person, straight through the head in first.
	local target = if firstPerson then Vector3.zero else config.Camera.ShoulderOffset
	shoulder = shoulder:Lerp(target, math.min(1, deltaTime * 10))
	humanoid.CameraOffset = current.cameraOffset + shoulder

	local turn = config.Camera.FaceAim and not firstPerson and TURNABLE[humanoid:GetState()] == true
	if turn then
		humanoid.AutoRotate = false
		local flat = Vector3.new(aim.X, 0, aim.Z)
		if flat.Magnitude > 0.05 then
			local facing = CFrame.lookAlong(root.Position, flat.Unit)
			root.CFrame = root.CFrame:Lerp(facing, 1 - math.exp(-TURN_SPEED * deltaTime))
		end
	else
		humanoid.AutoRotate = current.autoRotate
	end

	return firstPerson
end

return View
