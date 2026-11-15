--!strict
--[[
	Arms
	Inverse kinematics for a character's arms, for R15 and R6 alike.

	Everything in the animation system ends here: given where a hand should
	grip, work out where each part of the arm goes. The same solve is used two
	ways:

	  - first person: the parts are anchored copies, moved directly (`place`)
	  - third person: the parts are a real character's, moved by writing each
	    joint's Motor6D.Transform after the Animator has run (`drive`)

	R15 arms are a two-bone chain (upper arm, lower arm) with the hand fixed to
	the grip. R6 arms are a single block: the right arm lines up with the
	weapon exactly as a Roblox Tool grip does, and the left arm reaches from
	the shoulder to its grip point. An R6 arm may slide out of its socket to
	reach; that is the accepted look for R6 weapons.
]]

-- A character joint. R6 rigs and older R15 rigs use Motor6D; R15 rigs spawned
-- with the Avatar Joint Upgrade use AnimationConstraint, which has the same
-- C0, C1, Part0 and Transform.
export type Joint = {
	C0: CFrame,
	C1: CFrame,
	Part0: BasePart?,
	Transform: CFrame,
}

export type Arm = {
	rig: "R15" | "R6",
	side: "Right" | "Left",
	parts: { BasePart }, -- R15: upper, lower, hand. R6: the arm.
	motors: { Joint }, -- R15: shoulder, elbow, wrist. R6: shoulder.
	root: BasePart, -- the part the shoulder hangs from
	shoulder: Vector3, -- shoulder position in root space
	grip: CFrame, -- the hand's grip frame in hand (R15) or arm (R6) space
	upperTop: Vector3,
	upperBottom: Vector3,
	lowerTop: Vector3,
	lowerBottom: Vector3,
	handTop: Vector3,
	upperLength: number,
	lowerLength: number,
	pivot: Vector3, -- R6: the shoulder joint in arm space
}

export type Rig = {
	rig: "R15" | "R6",
	character: Model,
	root: BasePart, -- HumanoidRootPart
	right: Arm,
	left: Arm,
}

local DEFAULT_GRIP = CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0)

local Arms = {}

-- Finds a character joint by name under `parent`, whichever class it is.
function Arms.joint(parent: Instance, name: string): Joint?
	local found = parent:FindFirstChild(name)
	if found and (found:IsA("AnimationConstraint") or found:IsA("Motor6D")) then
		return found :: any
	end
	for _, child in parent:GetChildren() do
		if child.Name == name and (child:IsA("AnimationConstraint") or child:IsA("Motor6D")) then
			return child :: any
		end
	end
	return nil
end

local function findJoint(parent: Instance, name: string): Joint?
	local found = parent:FindFirstChild(name)
	if found and (found:IsA("AnimationConstraint") or found:IsA("Motor6D")) then
		return found :: any
	end
	-- Something else may share the name; look at every child.
	for _, child in parent:GetChildren() do
		if child.Name == name and (child:IsA("AnimationConstraint") or child:IsA("Motor6D")) then
			return child :: any
		end
	end
	return nil
end

-- A rotation whose Y axis is `y`, with Z as close to `zHint` as it can be.
local function basis(y: Vector3, zHint: Vector3): CFrame
	local x = y:Cross(zHint)
	if x.Magnitude < 1e-4 then
		x = y:Cross(if math.abs(y.X) < 0.9 then Vector3.xAxis else Vector3.zAxis)
	end
	x = x.Unit
	return CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
end

-- Places a bone so its local point `aLocal` sits at `aWorld` and it points at `bWorld`.
local function bone(
	aWorld: Vector3,
	bWorld: Vector3,
	aLocal: Vector3,
	bLocal: Vector3,
	zHint: Vector3
): CFrame
	local fromLocal = basis(-(bLocal - aLocal).Unit, Vector3.zAxis)
	local toWorld = basis(-(bWorld - aWorld).Unit, zHint)
	return CFrame.new(aWorld) * (toWorld * fromLocal:Inverse()) * CFrame.new(-aLocal)
end

--[[
	Two-bone IK. Returns the elbow position, the wrist position the chain can
	actually reach, and the direction the elbow sticks out in.
	`pole` is a hint for which way the elbow should point.
]]
function Arms.twoBone(
	shoulder: Vector3,
	wrist: Vector3,
	upper: number,
	lower: number,
	pole: Vector3
): (Vector3, Vector3, Vector3)
	local offset = wrist - shoulder
	local distance = offset.Magnitude
	local direction = if distance > 1e-4 then offset / distance else -Vector3.yAxis
	distance = math.clamp(distance, math.abs(upper - lower) + 1e-3, upper + lower - 1e-3)

	local side = pole - direction * pole:Dot(direction)
	if side.Magnitude < 1e-4 then
		side = direction:Cross(Vector3.xAxis)
	end
	side = side.Unit

	local cosine = (upper * upper + distance * distance - lower * lower) / (2 * upper * distance)
	local angle = math.acos(math.clamp(cosine, -1, 1))
	local elbow = shoulder + direction * (math.cos(angle) * upper) + side * (math.sin(angle) * upper)
	return elbow, shoulder + direction * distance, side
end

local function describeR15(character: Model, side: "Right" | "Left"): Arm?
	local upper = character:FindFirstChild(side .. "UpperArm")
	local lower = character:FindFirstChild(side .. "LowerArm")
	local hand = character:FindFirstChild(side .. "Hand")
	if
		not (
			upper
			and lower
			and hand
			and upper:IsA("BasePart")
			and lower:IsA("BasePart")
			and hand:IsA("BasePart")
		)
	then
		return nil
	end
	local shoulder = findJoint(upper, side .. "Shoulder")
	local elbow = findJoint(lower, side .. "Elbow")
	local wrist = findJoint(hand, side .. "Wrist")
	if shoulder == nil or elbow == nil or wrist == nil then
		return nil
	end
	local root = shoulder.Part0
	if root == nil then
		return nil
	end

	local gripAttachment = hand:FindFirstChild(side .. "GripAttachment")
	local arm: Arm = {
		rig = "R15",
		side = side,
		parts = { upper, lower, hand },
		motors = { shoulder, elbow, wrist },
		root = root,
		shoulder = shoulder.C0.Position,
		grip = if gripAttachment and gripAttachment:IsA("Attachment")
			then gripAttachment.CFrame
			else CFrame.Angles(-math.pi / 2, 0, 0),
		upperTop = shoulder.C1.Position,
		upperBottom = elbow.C0.Position,
		lowerTop = elbow.C1.Position,
		lowerBottom = wrist.C0.Position,
		handTop = wrist.C1.Position,
		upperLength = (elbow.C0.Position - shoulder.C1.Position).Magnitude,
		lowerLength = (wrist.C0.Position - elbow.C1.Position).Magnitude,
		pivot = Vector3.zero,
	}
	return arm
end

local function describeR6(character: Model, side: "Right" | "Left"): Arm?
	local torso = character:FindFirstChild("Torso")
	local part = character:FindFirstChild(side .. " Arm")
	if not (torso and part and torso:IsA("BasePart") and part:IsA("BasePart")) then
		return nil
	end
	local shoulder = findJoint(torso, side .. " Shoulder")
	if shoulder == nil then
		return nil
	end

	local gripAttachment = part:FindFirstChild(side .. "GripAttachment")
	local arm: Arm = {
		rig = "R6",
		side = side,
		parts = { part },
		motors = { shoulder },
		root = torso,
		shoulder = shoulder.C0.Position,
		-- R6 grip attachments carry no rotation; a Tool is welded to an R6 arm
		-- with a fixed quarter turn, so the same turn is applied here.
		grip = if gripAttachment and gripAttachment:IsA("Attachment")
			then CFrame.new(gripAttachment.Position) * DEFAULT_GRIP.Rotation
			else DEFAULT_GRIP,
		upperTop = Vector3.zero,
		upperBottom = Vector3.zero,
		lowerTop = Vector3.zero,
		lowerBottom = Vector3.zero,
		handTop = Vector3.zero,
		upperLength = 0,
		lowerLength = 0,
		pivot = shoulder.C1.Position,
	}
	return arm
end

-- Measures a character's arms. Returns nil for rigs that are neither R15 nor R6.
function Arms.describe(character: Model): Rig?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	local isR15 = character:FindFirstChild("RightUpperArm") ~= nil
	local describeArm = if isR15 then describeR15 else describeR6
	local right = describeArm(character, "Right")
	local left = describeArm(character, "Left")
	if right == nil or left == nil then
		return nil
	end
	return {
		rig = if isR15 then "R15" else "R6",
		character = character,
		root = root,
		right = right,
		left = left,
	}
end

--[[
	A slimmer copy of an arm's measurements, for the first-person viewmodel.
	`width` scales how thick the arm is (its length is kept, so it still
	reaches from off screen) and `hand` scales the hand in every direction.
	Returns the new measurements and, per part, the factor to scale its Size by.
]]
function Arms.scaled(arm: Arm, width: number, hand: number): (Arm, { Vector3 })
	local limb = Vector3.new(width, 1, width)
	local copy = table.clone(arm)
	if arm.rig == "R6" then
		copy.grip = CFrame.new(arm.grip.Position * limb) * arm.grip.Rotation
		copy.pivot = arm.pivot * limb
		return copy, { limb }
	end
	local palm = Vector3.new(hand, hand, hand)
	copy.upperTop = arm.upperTop * limb
	copy.upperBottom = arm.upperBottom * limb
	copy.lowerTop = arm.lowerTop * limb
	copy.lowerBottom = arm.lowerBottom * limb
	copy.handTop = arm.handTop * palm
	copy.grip = CFrame.new(arm.grip.Position * palm) * arm.grip.Rotation
	copy.upperLength = (copy.upperBottom - copy.upperTop).Magnitude
	copy.lowerLength = (copy.lowerBottom - copy.lowerTop).Magnitude
	return copy, { limb, limb, palm }
end

--[[
	Works out where each part of an arm goes so the hand's grip frame lands on
	`grip` (world space). `shoulder` is the shoulder's world position and
	`pole` hints which way the elbow points. Returns one CFrame per part, in
	the order of `arm.parts`.
]]
function Arms.solve(arm: Arm, shoulder: Vector3, grip: CFrame, pole: Vector3): { CFrame }
	if arm.rig == "R6" then
		if arm.side == "Right" then
			-- The grip frame fixes the whole arm, exactly like a Tool weld.
			return { grip * arm.grip:Inverse() }
		end
		-- Reach from the shoulder to the grip point, hand end on the target.
		local handLocal = arm.grip.Position
		local direction = grip.Position - shoulder
		if direction.Magnitude < 1e-3 then
			direction = -Vector3.yAxis
		end
		local start = grip.Position - direction.Unit * (handLocal - arm.pivot).Magnitude
		return { bone(start, grip.Position, arm.pivot, handLocal, grip.UpVector) }
	end

	local hand = grip * arm.grip:Inverse()
	local wristTarget = hand * arm.handTop
	local elbow, wrist, side = Arms.twoBone(shoulder, wristTarget, arm.upperLength, arm.lowerLength, pole)
	if (wrist - wristTarget).Magnitude > 1e-3 then
		-- Out of reach: keep the hand's angle, bring it back onto the arm.
		hand += wrist - wristTarget
	end
	return {
		bone(shoulder, elbow, arm.upperTop, arm.upperBottom, side),
		bone(elbow, wrist, arm.lowerTop, arm.lowerBottom, side),
		hand,
	}
end

--[[
	Brings a grip target within the arm's reach. If the hand cannot get to
	`grip`, the target is slid toward `fallback` (a point the hand can always
	reach, such as the other hand) just far enough that it can. A support hand
	on a long rifle ends up holding the weapon as far forward as the arm goes,
	instead of hovering short of the handguard.
]]
function Arms.withinReach(arm: Arm, shoulder: Vector3, grip: CFrame, fallback: Vector3): CFrame
	if arm.rig ~= "R15" then
		return grip -- an R6 arm slides at the shoulder instead
	end
	local reach = (arm.upperLength + arm.lowerLength) * 0.985
	local wristOffset = (grip * arm.grip:Inverse()):VectorToWorldSpace(arm.handTop)
	local function tooFar(position: Vector3): boolean
		return (position + wristOffset - shoulder).Magnitude > reach
	end
	if not tooFar(grip.Position) then
		return grip
	end
	local low, high = 0, 1 -- fraction of the way from fallback to the target
	for _ = 1, 8 do
		local middle = (low + high) / 2
		if tooFar(fallback:Lerp(grip.Position, middle)) then
			high = middle
		else
			low = middle
		end
	end
	return grip.Rotation + fallback:Lerp(grip.Position, low)
end

-- First person: moves anchored copies of the arm parts straight to the solve.
function Arms.place(parts: { BasePart }, frames: { CFrame })
	for index, part in parts do
		part.CFrame = frames[index]
	end
end

--[[
	Third person: poses a real character's arm by writing Motor6D.Transform.
	Call from RunService.PreSimulation (Stepped) so it lands after the Animator
	and before the joints are evaluated.
]]
function Arms.drive(arm: Arm, frames: { CFrame })
	local parent = arm.root.CFrame
	for index, motor in arm.motors do
		local frame = frames[index]
		motor.Transform = motor.C0:Inverse() * parent:Inverse() * frame * motor.C1
		parent = frame
	end
end

-- Hands the joints back to the Animator.
function Arms.release(arm: Arm)
	for _, motor in arm.motors do
		motor.Transform = CFrame.identity
	end
end

-- The shoulder's current world position on a live character.
function Arms.shoulderOf(arm: Arm): Vector3
	return arm.root.CFrame * arm.shoulder
end

return Arms
