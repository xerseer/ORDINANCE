--!strict
--[[
	Characters
	The third-person view: makes every character that holds a weapon actually
	hold it, with the trigger hand on the grip, the support hand on the
	handguard, the arms following where the player aims, and the weapon's
	moving parts moving.

	This runs on each client for every character it can see, including the
	local player's own. Nothing is replicated but a little state per player
	(aim pitch, whether they are aiming, and what action they started); each
	client turns that into arm poses locally, by writing joint Transforms after
	the Animator has run.

	In third person the weapon is still welded to the trigger hand, as any
	Roblox Tool is. So the trigger hand is solved to where the weapon should
	be, the weapon follows it, and the support hand is solved onto the weapon.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Framework = script.Parent.Parent

local Animator = require(Framework.Animation.Animator)
local Arms = require(Framework.Animation.Arms)
local Encoded = require(Framework.Animation.Encoded)
local Logger = require(Framework.Core.Logger)
local Registry = require(Framework.Weapons.Registry)

-- A joint the Animator also writes to. We lay our own rotation over
-- whatever animation is playing instead of replacing it.
type Layered = {
	joint: Arms.Joint,
	base: CFrame, -- the Animator's most recent value
	written: CFrame?, -- what we last wrote on top of it
}

type Tracked = {
	player: Player,
	character: Model,
	weapon: Instance,
	entry: Registry.Entry,
	animator: Animator.Animator,
	rig: Arms.Rig?,
	waist: Layered?,
	neck: Layered?,
	joints: { [string]: Arms.Joint },
	hip: CFrame,
	aimed: CFrame,
	pitch: number,
	pitchTarget: number,
	aim: number,
	aiming: boolean,
	driven: boolean,
	hidden: boolean,
}

local WEAPON_ATTRIBUTE = "OrdnanceWeapon"
local EYE_HEIGHT = 1.5 -- studs above the root part, for both rig types
local RIGHT_POLE = Vector3.new(0.55, -1, 0.45)
local LEFT_POLE = Vector3.new(-0.65, -0.8, 0.3)

local log = Logger.scope("Characters")
local localPlayer = Players.LocalPlayer

local Characters = {}

local tracked: { [Player]: Tracked } = {}
local connections: { RBXScriptConnection } = {}
local perPlayer: { [Player]: { RBXScriptConnection } } = {}
local localFirstPerson = false

-- Roblox hides the character in first person but not the Tool it holds, so
-- the world weapon is hidden here while the viewmodel stands in for it.
local function setWeaponHidden(entry: Tracked, hidden: boolean)
	if entry.hidden == hidden then
		return
	end
	entry.hidden = hidden
	for _, descendant in entry.weapon:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

-- Multiplies `extra` onto a joint the Animator is also driving. If the
-- joint still holds what we wrote, the Animator did not run this frame, and
-- the remembered base is used again so the rotation cannot pile up.
local function layer(slot: Layered, extra: CFrame)
	local current = slot.joint.Transform
	if slot.written == nil or current ~= slot.written then
		slot.base = current
	end
	local value = extra * slot.base
	slot.joint.Transform = value
	slot.written = value
end

local function unlayer(slot: Layered?)
	if slot and slot.written then
		slot.joint.Transform = slot.base
		slot.written = nil
	end
end

local function findLayered(character: Model, partName: string, jointName: string): Layered?
	local part = character:FindFirstChild(partName)
	local joint = if part then Arms.joint(part, jointName) else nil
	if joint == nil then
		return nil
	end
	return { joint = joint, base = joint.Transform, written = nil }
end

local function release(entry: Tracked)
	unlayer(entry.waist)
	unlayer(entry.neck)
	local rig = entry.rig
	if rig and entry.driven then
		Arms.release(rig.right)
		Arms.release(rig.left)
	end
	for _, joint in entry.joints do
		joint.Transform = CFrame.identity
	end
	entry.driven = false
end

local function untrack(player: Player)
	local entry = tracked[player]
	if entry then
		tracked[player] = nil
		release(entry)
		setWeaponHidden(entry, false)
	end
end

-- The joints holding each weapon part to the handle, by part name.
local function findPartJoints(weapon: Instance): { [string]: Arms.Joint }
	local joints: { [string]: Arms.Joint } = {}
	local handle = weapon:FindFirstChild("Handle")
		or (if weapon:IsA("Model") then weapon.PrimaryPart else nil)
	if handle then
		for _, child in handle:GetChildren() do
			if child:IsA("Motor6D") and child.Part0 == handle then
				joints[child.Name] = child :: any
			end
		end
	end
	return joints
end

local function track(player: Player, character: Model, weapon: Instance)
	local id = weapon:GetAttribute(WEAPON_ATTRIBUTE)
	local entry = if type(id) == "string" then Registry.get(id) else nil
	if entry == nil then
		return
	end
	untrack(player)

	local config = entry.config
	local animator = Animator.new(entry)
	animator:setAction("Equip", os.clock(), config.Handling.EquipTime)
	tracked[player] = {
		player = player,
		character = character,
		weapon = weapon,
		entry = entry,
		animator = animator,
		rig = nil,
		waist = nil,
		neck = nil,
		joints = findPartJoints(weapon),
		hip = Encoded.frame(config.ThirdPerson.Offset) or CFrame.new(0.42, -0.74, -0.3),
		aimed = Encoded.frame(config.ThirdPerson.AimOffset) or CFrame.new(0.22, -0.5, -0.42),
		pitch = 0,
		pitchTarget = 0,
		aim = 0,
		aiming = false,
		driven = false,
		hidden = false,
	}
end

local function onChildAdded(player: Player, character: Model, child: Instance)
	if child:GetAttribute(WEAPON_ATTRIBUTE) ~= nil and (child:IsA("Tool") or child:IsA("Model")) then
		track(player, character, child)
	end
end

local function onCharacter(player: Player, character: Model)
	untrack(player)
	local list = perPlayer[player]
	if list == nil then
		return
	end
	-- Index 1 is the CharacterAdded connection; the rest belong to the old character.
	for index = #list, 2, -1 do
		list[index]:Disconnect()
		list[index] = nil
	end
	table.insert(
		list,
		character.ChildAdded:Connect(log:Wrap(function(child)
			onChildAdded(player, character, child)
		end))
	)
	table.insert(
		list,
		character.ChildRemoved:Connect(log:Wrap(function(child)
			local entry = tracked[player]
			if entry and entry.weapon == child then
				untrack(player)
			end
		end))
	)
	for _, child in character:GetChildren() do
		onChildAdded(player, character, child)
	end
end

local function onPlayer(player: Player)
	perPlayer[player] = {
		player.CharacterAdded:Connect(log:Wrap(function(character)
			onCharacter(player, character)
		end)),
	}
	if player.Character then
		onCharacter(player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	untrack(player)
	local list = perPlayer[player]
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
		perPlayer[player] = nil
	end
end

local function step(entry: Tracked, now: number, deltaTime: number)
	local character = entry.character
	if character.Parent == nil then
		return
	end
	if entry.player == localPlayer and localFirstPerson then
		-- The body is invisible; leave it to the Animator.
		if entry.driven then
			release(entry)
		end
		setWeaponHidden(entry, true)
		return
	end
	setWeaponHidden(entry, false)

	local rig = entry.rig
	if rig == nil then
		-- The character may still be assembling; try again next frame.
		rig = Arms.describe(character)
		entry.rig = rig
		if rig == nil then
			return
		end
	end

	local blend = math.min(1, deltaTime * 14)
	entry.pitch += (entry.pitchTarget - entry.pitch) * blend
	entry.aim += ((if entry.aiming then 1 else 0) - entry.aim) * blend

	-- Stance: turn the upper body side-on so the support arm can reach, lean
	-- it with the aim, and keep the head on the target. R15 only; an R6 torso
	-- is one piece and its arms slide to reach instead.
	if rig.rig == "R15" then
		if entry.waist == nil then
			entry.waist = findLayered(character, "UpperTorso", "Waist")
			entry.neck = findLayered(character, "Head", "Neck")
		end
		local settings = entry.entry.config.ThirdPerson
		local turn = math.rad(settings.BodyTurn)
		local lean = entry.pitch * settings.BodyPitch
		if entry.waist then
			layer(entry.waist, CFrame.Angles(lean, 0, 0) * CFrame.Angles(0, -turn, 0))
		end
		if entry.neck then
			layer(entry.neck, CFrame.Angles(0, turn, 0) * CFrame.Angles(entry.pitch * 0.9 - lean, 0, 0))
		end
	end

	local pose = entry.animator:update(now)
	local attachments = entry.animator.attachments
	local root = rig.root.CFrame
	local eye = root * CFrame.new(0, EYE_HEIGHT, 0) * CFrame.Angles(entry.pitch, 0, 0)
	local eased = entry.aim * entry.aim * (3 - 2 * entry.aim)
	local desired = eye * entry.hip:Lerp(entry.aimed, eased) * pose.weapon

	local rightFrames = Arms.solve(
		rig.right,
		Arms.shoulderOf(rig.right),
		desired * attachments.main,
		root:VectorToWorldSpace(RIGHT_POLE)
	)
	Arms.drive(rig.right, rightFrames)

	-- The weapon rides the trigger hand, so the support hand is solved onto
	-- where the weapon will really be, not where it was asked to be.
	local actual = rightFrames[#rightFrames] * rig.right.grip * attachments.main:Inverse()
	local leftShoulder = Arms.shoulderOf(rig.left)
	local leftGrip =
		Arms.withinReach(rig.left, leftShoulder, actual * pose.left, (actual * attachments.main).Position)
	Arms.drive(rig.left, Arms.solve(rig.left, leftShoulder, leftGrip, root:VectorToWorldSpace(LEFT_POLE)))
	entry.driven = true

	for name, joint in entry.joints do
		local offset = pose.parts[name]
		joint.Transform = if offset
			then joint.C0:Inverse() * Animator.partFrame(joint.C0, offset)
			else CFrame.identity
	end
end

-- Sets where a player is aiming: pitch in radians (up is positive) and
-- whether they are aiming down sights.
function Characters.setPose(player: Player, pitch: number, aiming: boolean)
	local entry = tracked[player]
	if entry then
		entry.pitchTarget = math.clamp(pitch, -1.4, 1.4)
		entry.aiming = aiming
	end
end

-- Starts an action's animation on a player's weapon.
function Characters.setAction(player: Player, action: string, duration: number, empty: boolean?)
	local entry = tracked[player]
	if entry then
		entry.animator:setAction(action, os.clock(), duration, empty)
	end
end

--[[
	Plays a shot on a player's weapon. For other players, `replicated` also
	starts the bolt or pump cycle that follows, which the local player's own
	weapon state does for itself.
]]
function Characters.fire(player: Player, replicated: boolean?)
	local entry = tracked[player]
	if entry == nil then
		return
	end
	local now = os.clock()
	entry.animator:fire(now)
	local config = entry.entry.config
	if replicated and config.Fire.Action ~= "SelfLoading" and not config.Realism.ManualCycle then
		entry.animator:setAction("Cycle", now, config.Fire.CycleTime)
	end
end

-- The weapon instance a player is holding, if any.
function Characters.weaponOf(player: Player): Instance?
	local entry = tracked[player]
	return if entry then entry.weapon else nil
end

-- While the local player is in first person their own body is left alone.
function Characters.setLocalFirstPerson(firstPerson: boolean)
	localFirstPerson = firstPerson
end

function Characters.start()
	table.insert(connections, Players.PlayerAdded:Connect(log:Wrap(onPlayer)))
	table.insert(connections, Players.PlayerRemoving:Connect(log:Wrap(onPlayerRemoving)))
	for _, player in Players:GetPlayers() do
		log:Try(onPlayer, player)
	end
	-- PreSimulation: after the Animator has written this frame's Transforms,
	-- before the joints are evaluated.
	table.insert(
		connections,
		RunService.PreSimulation:Connect(function(deltaTime)
			local now = os.clock()
			for player, entry in tracked do
				-- A character that cannot be posed is dropped rather than
				-- reported again every frame.
				if not log:Try(step, entry, now, deltaTime) then
					untrack(player)
				end
			end
		end)
	)
end

function Characters.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for player in perPlayer do
		onPlayerRemoving(player)
	end
	for player in tracked do
		untrack(player)
	end
end

return Characters
