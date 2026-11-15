--!strict
--[[
	Viewmodel
	The first-person view: a copy of the weapon and of the player's own arms,
	drawn at the camera.

	Nothing here is uploaded or pre-built. The arms are cloned from the
	player's character when a weapon is drawn, so they match its rig (R15 or
	R6), skin and, optionally, its shirt. They are drawn slimmer than the real
	ones (Viewmodel.ArmWidth, Viewmodel.HandScale): a character's arms are
	built to be seen from a distance and fill the screen when held at the
	camera. Every frame the weapon is placed relative to the camera and the
	arms are solved to reach it.

	Only the local player sees this. Everyone else, and the player too in
	third person, sees the character holding the world weapon.

	The viewmodel is local, anchored and cannot be hit by raycasts.
]]

local Arms = require(script.Parent.Parent.Animation.Arms)
local Animator = require(script.Parent.Parent.Animation.Animator)
local Defaults = require(script.Parent.Parent.Config.Defaults)
local Encoded = require(script.Parent.Parent.Animation.Encoded)
local Registry = require(script.Parent.Parent.Weapons.Registry)
local Sway = require(script.Parent.Parent.Animation.Sway)
local Visualizer = require(script.Parent.Parent.Core.Visualizer)

type Config = Defaults.Config

type View = {
	entry: Registry.Entry,
	attachments: Animator.Attachments,
	model: Model,
	weaponParts: { BasePart },
	weaponNames: { string },
	weaponRests: { CFrame },
	weaponFrames: { CFrame },
	right: Arms.Arm?,
	left: Arms.Arm?,
	rightParts: { BasePart },
	leftParts: { BasePart },
	hip: CFrame,
	aimed: CFrame,
	handle: CFrame,
}

-- Which way each shoulder lies from its wrist, in camera space. The
-- shoulders are not fixed points: they are placed so the arms always reach.
-- They point down and out more than back, so the arms leave the bottom of the
-- screen instead of passing close to the camera, where they would fill it.
local RIGHT_SHOULDER = Vector3.new(0.42, -0.8, 0.42).Unit
-- The support arm comes in from the left, across under the weapon.
local LEFT_SHOULDER = Vector3.new(-0.62, -0.62, 0.48).Unit
local RIGHT_POLE = Vector3.new(0.75, -0.65, 0.1)
local LEFT_POLE = Vector3.new(-0.75, -0.65, 0.1)
local REACH = 0.93

local Viewmodel = {}

local view: View? = nil
local visible = false
local sway = Sway.new()
local lastCamera: CFrame? = nil
local swayInput: Sway.Input = { look = Vector2.zero, velocity = Vector3.zero, grounded = true, aim = 0 }

local function ghost(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
end

local function cloneArm(arm: Arms.Arm, scales: { Vector3 }, parent: Instance): { BasePart }
	local clones = {}
	for index, part in arm.parts do
		local clone = part:Clone()
		clone.Size *= scales[index] or Vector3.one
		for _, descendant in clone:GetDescendants() do
			if
				descendant:IsA("JointInstance")
				or descendant:IsA("Constraint")
				or descendant:IsA("BaseScript")
			then
				descendant:Destroy()
			end
		end
		ghost(clone)
		-- Plastic's grain is meant to be seen from a distance; up close it
		-- reads as noise.
		if clone.Material == Enum.Material.Plastic then
			clone.Material = Enum.Material.SmoothPlastic
		end
		clone.Parent = parent
		table.insert(clones, clone)
	end
	return clones
end

local function build(entry: Registry.Entry, attachments: Animator.Attachments, character: Model): View
	local config = entry.config
	local model = Instance.new("Model")
	model.Name = "OrdnanceViewmodel"

	-- The weapon: an anchored copy whose parts are placed by hand each frame.
	local weapon = entry.template:Clone()
	local handle = weapon.PrimaryPart :: BasePart
	local parts, names, rests = {}, {}, {}
	for _, descendant in weapon:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
			table.insert(names, descendant.Name)
			table.insert(rests, handle.CFrame:ToObjectSpace(descendant.CFrame))
		end
	end
	for _, descendant in weapon:GetDescendants() do
		if descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		end
	end
	for _, part in parts do
		ghost(part)
	end
	weapon.Name = "Weapon"
	weapon.Parent = model

	-- The arms: copies of the character's own.
	local rig = Arms.describe(character)
	local rightParts: { BasePart } = {}
	local leftParts: { BasePart } = {}
	local right: Arms.Arm?, left: Arms.Arm? = nil, nil
	if rig then
		local settings = config.Viewmodel
		local rightScales, leftScales
		right, rightScales = Arms.scaled(rig.right, settings.ArmWidth, settings.HandScale)
		left, leftScales = Arms.scaled(rig.left, settings.ArmWidth, settings.HandScale)
		rightParts = cloneArm(rig.right, rightScales, model)
		leftParts = cloneArm(rig.left, leftScales, model)
		if config.Viewmodel.Sleeves then
			-- Clothing only renders inside a model that has a Humanoid.
			local shirt = character:FindFirstChildOfClass("Shirt")
			if shirt then
				local humanoid = Instance.new("Humanoid")
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
				humanoid.EvaluateStateMachine = false
				humanoid.RequiresNeck = false
				humanoid.BreakJointsOnDeath = false
				humanoid.Parent = model
				shirt:Clone().Parent = model
			end
		end
	end

	local hip = Encoded.frame(config.Viewmodel.Offset) or CFrame.new(0.6, -0.8, -1.2)
	local aimAttachment = attachments.aim
	local aimed = if aimAttachment
		then CFrame.new(0, 0, -config.Viewmodel.AimDistance) * aimAttachment:Inverse()
		else CFrame.new(0, hip.Y * 0.7, hip.Z)

	return {
		entry = entry,
		attachments = attachments,
		model = model,
		weaponParts = parts,
		weaponNames = names,
		weaponRests = rests,
		weaponFrames = table.create(#parts, CFrame.identity),
		right = right,
		left = left,
		rightParts = rightParts,
		leftParts = leftParts,
		hip = hip,
		aimed = aimed,
		handle = CFrame.identity,
	}
end

local function applyVisibility()
	local current = view
	if current == nil then
		return
	end
	local camera = workspace.CurrentCamera
	current.model.Parent = if visible and camera then camera else nil
end

-- Builds the viewmodel for a weapon the local player has drawn.
function Viewmodel.show(entry: Registry.Entry, attachments: Animator.Attachments, character: Model)
	Viewmodel.hide()
	if not entry.config.Viewmodel.Enabled then
		return
	end
	view = build(entry, attachments, character)
	sway:reset()
	lastCamera = nil
	applyVisibility()
end

function Viewmodel.hide()
	if view then
		view.model:Destroy()
		view = nil
	end
end

-- Shown only while the camera is in first person.
function Viewmodel.setVisible(shown: boolean)
	if visible ~= shown then
		visible = shown
		lastCamera = nil
		applyVisibility()
	end
end

function Viewmodel.isVisible(): boolean
	return visible and view ~= nil
end

-- Where the muzzle is on screen, for first-person muzzle flashes and tracers.
function Viewmodel.muzzle(): Vector3?
	local current = view
	if current == nil or not visible then
		return nil
	end
	return (current.handle * current.attachments.barrel).Position
end

function Viewmodel.kick(config: Config, aim: number)
	sway:kick(config, aim)
end

local function solveArm(
	arm: Arms.Arm,
	parts: { BasePart },
	base: CFrame,
	grip: CFrame,
	shoulderDirection: Vector3,
	pole: Vector3
)
	local reach: number
	local wrist: Vector3
	if arm.rig == "R15" then
		reach = (arm.upperLength + arm.lowerLength) * REACH
		wrist = (grip * arm.grip:Inverse()) * arm.handTop
	else
		reach = (arm.grip.Position - arm.pivot).Magnitude
		wrist = grip.Position
	end
	local shoulder = wrist + base:VectorToWorldSpace(shoulderDirection) * reach
	Arms.place(parts, Arms.solve(arm, shoulder, grip, base:VectorToWorldSpace(pole)))
end

--[[
	Places the viewmodel for this frame. Call after the camera has updated.
	`velocity` is the character's world velocity and `aim` is 0 to 1.
]]
function Viewmodel.update(
	deltaTime: number,
	pose: Animator.Pose,
	aim: number,
	velocity: Vector3,
	grounded: boolean
)
	local current = view
	local camera = workspace.CurrentCamera
	if current == nil or camera == nil or not visible then
		return
	end
	local config = current.entry.config
	local cameraFrame = camera.CFrame

	local previous = lastCamera
	if previous then
		local pitch, yaw = previous:ToObjectSpace(cameraFrame):ToOrientation()
		swayInput.look = Vector2.new(yaw, pitch)
	else
		swayInput.look = Vector2.zero
	end
	lastCamera = cameraFrame
	swayInput.velocity = cameraFrame:VectorToObjectSpace(velocity)
	swayInput.grounded = grounded
	swayInput.aim = aim

	local base = cameraFrame * sway:update(deltaTime, config, swayInput)
	local eased = aim * aim * (3 - 2 * aim)
	local handle = base * current.hip:Lerp(current.aimed, eased) * pose.weapon
	current.handle = handle

	local frames = current.weaponFrames
	for index, rest in current.weaponRests do
		local offset = pose.parts[current.weaponNames[index]]
		frames[index] = handle * (if offset then Animator.partFrame(rest, offset) else rest)
	end
	workspace:BulkMoveTo(current.weaponParts, frames, Enum.BulkMoveMode.FireCFrameChanged)

	local right, left = current.right, current.left
	if right and left then
		solveArm(right, current.rightParts, base, handle * pose.right, RIGHT_SHOULDER, RIGHT_POLE)
		solveArm(left, current.leftParts, base, handle * pose.left, LEFT_SHOULDER, LEFT_POLE)
	end

	-- Debug gizmos, redrawn every frame so they follow the weapon.
	local visualize = config.Debug.Visualize
	if visualize.IK then
		Visualizer.sphere((handle * pose.right).Position, 0.05, Color3.fromRGB(217, 162, 122), 0.04)
		Visualizer.sphere((handle * pose.left).Position, 0.05, Color3.fromRGB(147, 180, 209), 0.04)
	end
	if visualize.Attachments then
		local attachments = current.attachments
		local marks: { CFrame? } = { attachments.barrel, attachments.mag, attachments.side, attachments.aim }
		for index = 1, 4 do
			local mark = marks[index]
			if mark then
				Visualizer.sphere((handle * mark).Position, 0.035, Color3.fromRGB(179, 191, 125), 0.04)
			end
		end
	end
end

return Viewmodel
