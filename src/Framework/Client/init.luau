--!strict
--[[
	Client
	The local player's side of the framework: reads input, predicts the weapon
	so it responds instantly, draws the effects, and tells the server what was
	attempted. The server decides what actually happened.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Framework = script.Parent

local Animator = require(Framework.Animation.Animator)
local Characters = require(script.Characters)
local Config = require(Framework.Config)
local Damage = require(Framework.Ballistics.Damage)
local DebugOverlay = require(script.DebugOverlay)
local AttachmentMenu = require(script.AttachmentMenu)
local Effects = require(script.Effects)
local Gadgets = require(script.Gadgets)
local Events = require(Framework.Core.Events)
local Hitscan = require(Framework.Ballistics.Hitscan)
local HUD = require(script.HUD)
local Input = require(script.Input)
local Logger = require(Framework.Core.Logger)
local Net = require(Framework.Core.Net)
local Projectile = require(Framework.Ballistics.Projectile)
local Recoil = require(script.Recoil)
local Registry = require(Framework.Weapons.Registry)
local Rig = require(Framework.Weapons.Rig)
local Spread = require(Framework.Ballistics.Spread)
local State = require(Framework.Weapons.State)
local Version = require(Framework.Version)
local View = require(script.View)
local Viewmodel = require(script.Viewmodel)
local Visualizer = require(Framework.Core.Visualizer)

type Entry = Registry.Entry

-- The weapon currently in the local player's hands.
type Held = {
	entry: Entry,
	instance: Instance, -- the Tool, or the model in Custom mode
	state: State.State?, -- nil until the server's first Sync arrives
	seed: number,
	triggerHeld: boolean,
	pressedAt: number, -- when the trigger was last pulled; -1 once used
	burstLeft: number,
	aiming: boolean,
	aim: number, -- 0 (hip) to 1 (aimed)
	bloom: number, -- degrees of spread built up by recent shots
	baseFov: number,
	baseSpeed: number,
	lastSpeed: number,
	clickedEmpty: boolean,
	animator: Animator.Animator,
	seenAction: number, -- actionStart of the last action handed to the animators
	reloadEmpty: boolean,
	aimDirection: Vector3, -- unit vector from the head to what is aimed at
	poseSentAt: number,
}

type ProjectileData = {
	entry: Entry,
	part: Part,
	params: RaycastParams,
	visualOffset: Vector3,
}

local WEAPON_ATTRIBUTE = "OrdnanceWeapon"
local MAX_SHOTS_PER_FRAME = 4
local POSE_INTERVAL = 0.1
local UPDATE_STEP = "OrdnanceUpdate"
local VISUAL_BLEND_TIME = 0.18

local log = Logger.scope("Client")
local player = Players.LocalPlayer

local Client = {}

local started = false
local ready = false
local held: Held? = nil
local nextShotId = 1
local pendingSync: { [string]: { snapshot: State.Snapshot, seed: number } } = {}
local connections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local simulator: Projectile.Simulator

local function clock(): number
	return os.clock()
end

local function humanoidOf(character: Model?): Humanoid?
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

-- Where rounds visibly leave a weapon held by `character`.
local function muzzleOf(instance: Instance?, fallback: Vector3): Vector3
	if instance then
		local barrel = Rig.attachment(instance, "Barrel")
		if barrel then
			return barrel.WorldPosition
		end
	end
	return fallback
end

local function visualize(from: Vector3, to: Vector3)
	local visualizeSettings = Config.global().Debug.Visualize
	if visualizeSettings.Rays then
		Visualizer.line(from, to, Color3.fromRGB(147, 180, 209), visualizeSettings.Lifetime)
	end
end

--[[
	Draws one shot: muzzle flash, sound, and a tracer or projectile per pellet.
	Used for the local player's shots (predicted) and for everyone else's
	(replicated). The pellets come from the same seed the server uses, so what
	is drawn is what the server resolved.
]]
local function drawShot(
	entry: Entry,
	character: Model?,
	weapon: Instance?,
	userId: number,
	origin: Vector3,
	aim: Vector3,
	angle: number,
	seed: number,
	shotId: number
)
	local config = entry.config
	-- The local player's own shots leave from the first-person weapon when it is showing.
	local muzzle = (if userId == player.UserId then Viewmodel.muzzle() else nil) or muzzleOf(weapon, origin)
	local sounds = config.Effects.Sounds

	Effects.muzzleFlash(muzzle, config)
	Effects.sound(sounds.Fire, muzzle, sounds.FireVolume, sounds.FirePitch, sounds.RollOffMax)

	local pellets = Spread.pellets(config, aim, angle, seed, shotId)
	local drawTracer = shotId % config.Effects.Tracer.Every == 0

	for index, direction in pellets do
		if config.Ballistics.Type == "Projectile" then
			local data: ProjectileData = {
				entry = entry,
				part = Effects.projectile(config),
				params = Hitscan.params({ character :: Instance }),
				visualOffset = muzzle - origin,
			}
			data.part.Position = muzzle
			simulator:launch({
				key = `{userId}:{shotId}:{index}`,
				origin = origin,
				velocity = Projectile.velocity(config.Ballistics, direction),
				ballistics = config.Ballistics,
				data = data,
			})
		else
			local params = Hitscan.params({ character :: Instance })
			local trace = Hitscan.trace(
				origin,
				direction,
				config.Ballistics.Range,
				params,
				config.Ballistics.Penetration
			)
			if drawTracer then
				Effects.tracer(muzzle, trace.position, config)
			end
			for _, wall in trace.walls do
				Effects.impact(wall.result, config)
			end
			if trace.final then
				Effects.impact(trace.final, config)
			end
			visualize(origin, trace.position)
		end
	end
end

local function onProjectileEvent(
	projectile: Projectile.Projectile,
	event: Projectile.Event,
	result: RaycastResult?
)
	local data = projectile.data :: ProjectileData
	if event == "Bounce" or event == "Rest" then
		return
	end
	-- Explosions are drawn when the server says so; a projectile that only
	-- hits something leaves its mark straight away.
	if event == "Impact" and result then
		Effects.impact(result, data.entry.config)
	end
	if event == "Detonate" then
		-- Keep the body where it stopped until the server's Explode arrives.
		task.delay(0.5, function()
			data.part:Destroy()
		end)
	else
		data.part:Destroy()
	end
end

local function projectileRaycast(
	projectile: Projectile.Projectile,
	origin: Vector3,
	displacement: Vector3
): RaycastResult?
	return Hitscan.raycast(origin, displacement, (projectile.data :: ProjectileData).params)
end

local function stepProjectiles(deltaTime: number)
	simulator:step(deltaTime)
	local visualizeSettings = Config.global().Debug.Visualize
	simulator:each(function(projectile)
		local data = projectile.data :: ProjectileData
		-- The simulation starts at the eye (to match the server); the body
		-- starts at the muzzle and blends onto the true path.
		local blend = math.max(0, 1 - projectile.age / VISUAL_BLEND_TIME)
		local position = projectile.position + data.visualOffset * blend
		if visualizeSettings.Projectiles then
			Visualizer.line(
				data.part.Position,
				position,
				Color3.fromRGB(217, 162, 122),
				visualizeSettings.Lifetime
			)
		end
		data.part.Position = position
	end)
end

------------------------------------------------------------------------------
-- Firing
------------------------------------------------------------------------------

-- The unit direction from the character's head to whatever is under the
-- crosshair. Recomputed every frame: it aims the shots, the arms and the body.
local function computeAim(character: Model, range: number): Vector3
	local rayOrigin, rayDirection = View.ray()
	local head = character:FindFirstChild("Head") or character.PrimaryPart
	if head == nil or not head:IsA("BasePart") then
		return rayDirection
	end
	local sight = Hitscan.raycast(rayOrigin, rayDirection * range, Hitscan.params({ character }))
	local target = if sight then sight.Position else rayOrigin + rayDirection * range
	local aim = target - head.Position
	if aim.Magnitude < 3 or aim.Unit:Dot(rayDirection) < 0.2 then
		return rayDirection -- the target is on top of us; do not aim backwards
	end
	return aim.Unit
end

local function sendAction(current: Held, kind: string)
	Net.fire("Action", current.entry.id, kind)
end

local function tryReload(current: Held): boolean
	local state = current.state
	if state == nil then
		return false
	end
	local config = current.entry.config
	local empty = not State.hasRound(state, config)
	if not State.startReload(state, config, clock()) then
		return false
	end
	current.reloadEmpty = empty
	current.burstLeft = 0
	sendAction(current, "Reload")
	local sounds = config.Effects.Sounds
	local character = player.Character
	local root = if character then character.PrimaryPart else nil
	if root then
		Effects.sound(sounds.Reload, root.Position, 0.5, 1.4, 80)
	end
	Events.Reloaded:Fire(current.entry.id)
	return true
end

local function fire(current: Held, state: State.State, character: Model, humanoid: Humanoid)
	local config = current.entry.config
	local head = character:FindFirstChild("Head") or character.PrimaryPart
	if head == nil or not head:IsA("BasePart") then
		return
	end

	-- Aim through the crosshair, but shoot from the character's head, so the
	-- server can check the origin tightly in third person too.
	local origin = head.Position
	local aim = current.aimDirection

	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
	local angle = Spread.angle(config, current.aim, moving, airborne, current.bloom)

	local shotId = nextShotId
	nextShotId += 1

	State.fire(state, config, clock())
	current.bloom = math.min(current.bloom + config.Spread.PerShot, config.Spread.Max)

	Net.fire("Shoot", current.entry.id, shotId, workspace:GetServerTimeNow(), origin, aim, angle)
	drawShot(
		current.entry,
		character,
		current.instance,
		player.UserId,
		origin,
		aim,
		angle,
		current.seed,
		shotId
	)
	Recoil.kick(config.Recoil, current.aim)
	current.animator:fire(clock())
	Viewmodel.kick(config, current.aim)
	Characters.fire(player)
	Events.Fired:Fire(current.entry.id, origin, aim)
end

local function emptyClick(current: Held, character: Model)
	if current.clickedEmpty then
		return
	end
	current.clickedEmpty = true
	local sounds = current.entry.config.Effects.Sounds
	local root = character.PrimaryPart
	if root then
		Effects.sound(sounds.Empty, root.Position, 0.6, 1, 60)
	end
end

local function updateTrigger(current: Held, state: State.State, character: Model, humanoid: Humanoid)
	local config = current.entry.config
	local now = clock()

	for _ = 1, MAX_SHOTS_PER_FRAME do
		local buffered = current.pressedAt >= 0 and now - current.pressedAt <= config.Fire.InputBuffer
		local wants = current.burstLeft > 0 or (state.mode == "Auto" and current.triggerHeld) or buffered
		if not wants then
			return
		end

		local canFire, reason = State.canFire(state, config, now)
		if not canFire then
			if reason == "Rate" or reason == "Busy" then
				return -- wait; the buffered press may still land
			end
			current.burstLeft = 0
			if buffered or current.triggerHeld then
				if reason == "Empty" then
					emptyClick(current, character)
					if config.Ammo.AutoReload then
						tryReload(current)
					end
				elseif reason == "Jammed" or reason == "NeedsCycle" then
					emptyClick(current, character)
				end
			end
			current.pressedAt = -1
			return
		end

		if buffered then
			current.pressedAt = -1
			if state.mode == "Burst" then
				current.burstLeft = config.Fire.BurstCount
			end
		end
		if current.burstLeft > 0 then
			current.burstLeft -= 1
		end
		fire(current, state, character, humanoid)
	end
end

------------------------------------------------------------------------------
-- Equipping
------------------------------------------------------------------------------

local function unequip()
	local current = held
	if current == nil then
		return
	end
	held = nil
	Input.unbind()
	HUD.hide()
	Viewmodel.hide()
	AttachmentMenu.closeSoon()
	Gadgets.setHeld(nil, nil)
	HUD.scope(nil)
	Viewmodel.setHidden(false)

	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = current.baseFov
	end
	local humanoid = humanoidOf(player.Character)
	View.finish(humanoid)
	if humanoid and humanoid.WalkSpeed == current.lastSpeed then
		humanoid.WalkSpeed = current.baseSpeed
	end
	Events.Unequipped:Fire(current.entry.id)
end

local function applySync(current: Held, snapshot: State.Snapshot, seed: number)
	local state = current.state
	if state == nil then
		state = State.new(current.entry.config, clock())
		current.state = state
	end
	State.apply(state, snapshot, clock())
	current.seed = seed
end

local function equip(entry: Entry, instance: Instance)
	unequip()
	local camera = workspace.CurrentCamera
	local humanoid = humanoidOf(player.Character)
	local speed = if humanoid then humanoid.WalkSpeed else 16

	local current: Held = {
		entry = entry,
		instance = instance,
		state = nil,
		seed = 0,
		triggerHeld = false,
		pressedAt = -1,
		burstLeft = 0,
		aiming = false,
		aim = 0,
		bloom = 0,
		baseFov = if camera then camera.FieldOfView else 70,
		baseSpeed = speed,
		lastSpeed = speed,
		clickedEmpty = false,
		animator = Animator.new(entry),
		seenAction = -1,
		reloadEmpty = false,
		aimDirection = if camera then camera.CFrame.LookVector else -Vector3.zAxis,
		poseSentAt = 0,
	}
	held = current

	-- Sounds named in encoded animations play from the character.
	current.animator.onSound = function(id: string)
		local soundRoot = if player.Character then player.Character.PrimaryPart else nil
		if soundRoot then
			Effects.sound(id, soundRoot.Position, 0.6, 1, 80)
		end
	end
	local body = player.Character
	if body and humanoid then
		Viewmodel.show(entry, current.animator.attachments, body)
		View.begin(entry.config, humanoid)
	end

	local waiting = pendingSync[entry.id]
	if waiting then
		pendingSync[entry.id] = nil
		applySync(current, waiting.snapshot, waiting.seed)
	end

	local config = entry.config
	local handlers: { [string]: Input.Handler } = {
		Fire = function(pressed)
			if pressed and AttachmentMenu.isOpen() then
				return
			end
			current.triggerHeld = pressed
			if pressed then
				current.pressedAt = clock()
				current.clickedEmpty = false
			end
		end,
		Aim = function(pressed)
			if config.Controls.AimToggle then
				if pressed then
					current.aiming = not current.aiming
				end
			else
				current.aiming = pressed
			end
		end,
		Reload = function(pressed)
			if pressed then
				tryReload(current)
			end
		end,
	}
	if #config.Fire.Modes > 1 then
		handlers.FireMode = function(pressed)
			local state = current.state
			if pressed and state and State.nextMode(state, config) then
				current.burstLeft = 0
				sendAction(current, "Mode")
			end
		end
	end
	local gadgets = entry.gadgets
	if gadgets.light or gadgets.laser then
		handlers.Light = function(pressed)
			if pressed then
				Net.fire("Light")
			end
		end
	end
	if config.Attachments.Menu then
		handlers.Attachments = function(pressed)
			if pressed then
				AttachmentMenu.toggle(entry, function(slot: string, attachmentId: string?)
					Net.fire("Attach", entry.id, slot, attachmentId)
				end)
			end
		end
	end
	if config.Realism.ManualCycle or config.Realism.Malfunctions.Enabled then
		handlers.Cycle = function(pressed)
			local state = current.state
			if pressed and state and State.cycle(state, config, clock()) then
				sendAction(current, "Cycle")
			end
		end
	end

	Input.bind(config.Keybinds :: any, config.Controls.TouchButtons, handlers)
	HUD.show(config)
	AttachmentMenu.refresh(entry)
	Gadgets.setHeld(instance, entry)
	Events.Equipped:Fire(entry.id)
end

local function onChildAdded(child: Instance)
	local id = child:GetAttribute(WEAPON_ATTRIBUTE)
	if type(id) ~= "string" then
		return
	end
	local entry = Registry.entryFor(child)
	if entry == nil then
		log:WarnOnce(`missing:{id}`, `the server gave a weapon "{id}" that this client does not have`)
		return
	end
	equip(entry, child)
end

local function onChildRemoved(child: Instance)
	if held and held.instance == child then
		unequip()
	end
end

local function onCharacter(character: Model)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	unequip()

	table.insert(characterConnections, character.ChildAdded:Connect(log:Wrap(onChildAdded)))
	table.insert(characterConnections, character.ChildRemoved:Connect(log:Wrap(onChildRemoved)))
	for _, child in character:GetChildren() do
		log:Try(onChildAdded, child)
	end
end

------------------------------------------------------------------------------
-- Per-frame update
------------------------------------------------------------------------------

local function update(deltaTime: number)
	Effects.step(deltaTime)
	stepProjectiles(deltaTime)

	local current = held
	if current == nil then
		return
	end
	local character = player.Character
	local humanoid = humanoidOf(character)
	if character == nil or humanoid == nil or humanoid.Health <= 0 then
		unequip()
		return
	end

	local config = current.entry.config
	local now = clock()

	-- Aim blend, field of view and walk speed.
	local aimTarget = if current.aiming then 1 else 0
	local aimStep = if config.Handling.AimTime > 0 then deltaTime / config.Handling.AimTime else 1
	if current.aim < aimTarget then
		current.aim = math.min(aimTarget, current.aim + aimStep)
	elseif current.aim > aimTarget then
		current.aim = math.max(aimTarget, current.aim - aimStep)
	end

	local camera = workspace.CurrentCamera
	if camera then
		local eased = current.aim * current.aim * (3 - 2 * current.aim)
		camera.FieldOfView = current.baseFov + (config.Handling.AimFOV - current.baseFov) * eased
	end

	-- Respect speed changes made by the game (sprinting and so on): if the
	-- value is no longer what we last wrote, treat it as the new base.
	if humanoid.WalkSpeed ~= current.lastSpeed then
		current.baseSpeed = humanoid.WalkSpeed
	end
	local handling = config.Handling
	local scale = handling.WalkSpeedScale
		+ (handling.AimWalkSpeedScale - handling.WalkSpeedScale) * current.aim
	humanoid.WalkSpeed = current.baseSpeed * scale
	-- Read it back: the property is a 32-bit float, so the value we wrote and
	-- the value stored can differ, which would look like an outside change.
	current.lastSpeed = humanoid.WalkSpeed

	current.bloom = math.max(0, current.bloom - config.Spread.Recovery * deltaTime)

	-- Where the crosshair points. This aims the shots, the arms and the body.
	local root = character.PrimaryPart
	current.aimDirection = computeAim(character, config.Ballistics.Range)
	local firstPerson = false
	if root then
		firstPerson = View.update(deltaTime, config, humanoid, root, current.aimDirection)
	end
	Viewmodel.setVisible(firstPerson)
	Characters.setLocalFirstPerson(firstPerson and Viewmodel.isVisible())

	local state = current.state
	if state then
		State.advance(state, config, now)
		updateTrigger(current, state, character, humanoid)

		-- Hand any action that has just begun to the animators.
		if state.action ~= "Idle" and state.actionStart ~= current.seenAction then
			current.seenAction = state.actionStart
			local duration = state.actionEnd - state.actionStart
			local empty = state.action == "Reload" and current.reloadEmpty
			current.animator:setAction(state.action, state.actionStart, duration, empty)
			Characters.setAction(player, state.action, duration, empty)
		end
	end

	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local airborne = humanoid.FloorMaterial == Enum.Material.Air

	local pose = current.animator:update(now)
	local velocity = if root then root.AssemblyLinearVelocity else Vector3.zero
	-- A scope with a full-screen picture takes over once it is up to the eye.
	local scope = current.entry.gadgets.scope
	local scoped = scope ~= nil and firstPerson and current.aim >= 0.9
	Viewmodel.setHidden(scoped)
	HUD.scope(if scoped then scope else nil)
	Viewmodel.update(deltaTime, pose, current.aim, velocity, not airborne)

	-- Tell this client's third-person view, and ten times a second everyone
	-- else's, where we are aiming.
	local pitch = math.asin(math.clamp(current.aimDirection.Y, -1, 1))
	Characters.setPose(player, pitch, current.aiming)
	if now - current.poseSentAt >= POSE_INTERVAL then
		current.poseSentAt = now
		Net.fire("Pose", pitch, current.aiming)
	end

	HUD.update(
		state,
		config,
		now,
		Spread.angle(config, current.aim, moving, airborne, current.bloom),
		current.aim,
		View.screenPoint(),
		-- Looking through a sight: first person, on a weapon that has one.
		firstPerson
			and Viewmodel.isVisible()
			and current.animator.attachments.aim ~= nil
	)
end

------------------------------------------------------------------------------
-- Messages from the server
------------------------------------------------------------------------------

local function onSync(id: string, snapshot: State.Snapshot, seed: number)
	if held and held.entry.id == id then
		applySync(held, snapshot, seed)
	else
		pendingSync[id] = { snapshot = snapshot, seed = seed }
	end
end

local function onHit(_position: Vector3, group: string, _damage: number, killed: boolean)
	if held then
		HUD.hitmarker(held.entry.config, clock(), group == "Head", killed)
	end
end

local function onReplicate(
	userId: number,
	weaponId: string,
	origin: Vector3,
	aim: Vector3,
	angle: number,
	seed: number,
	shotId: number
)
	local entry = Registry.get(weaponId)
	local shooter = Players:GetPlayerByUserId(userId)
	if entry == nil or shooter == nil or shooter == player then
		return
	end
	local character = shooter.Character
	local weapon: Instance? = nil
	if character then
		for _, child in character:GetChildren() do
			if child:GetAttribute(WEAPON_ATTRIBUTE) == weaponId then
				weapon = child
				break
			end
		end
	end
	-- Their attachments change how the shot looks and sounds (a suppressor).
	local fitted = if weapon then Registry.entryFor(weapon) else nil
	drawShot(fitted or entry, character, weapon, userId, origin, aim, angle, seed, shotId)
	Characters.fire(shooter, true)
end

-- Another player's aim, relayed by the server.
local function onPoseOf(userId: number, pitch: number, aiming: boolean)
	local other = Players:GetPlayerByUserId(userId)
	if other and other ~= player then
		Characters.setPose(other, pitch, aiming)
	end
end

-- Another player started a reload or cycled their weapon.
local function onAct(userId: number, _weaponId: string, action: string, duration: number, empty: boolean)
	local other = Players:GetPlayerByUserId(userId)
	if other and other ~= player then
		Characters.setAction(other, action, duration, empty)
	end
end

local function onExplode(position: Vector3, weaponId: string, key: string)
	local entry = Registry.get(weaponId)
	if entry == nil then
		return
	end
	local config = entry.config

	local projectile = simulator:get(key)
	if projectile then
		(projectile.data :: ProjectileData).part:Destroy()
		simulator:remove(key)
	end
	Effects.explosion(position, config)
	Events.Exploded:Fire(position, weaponId)

	local visualizeSettings = Config.global().Debug.Visualize
	if visualizeSettings.Projectiles then
		Visualizer.sphere(
			position,
			config.Ballistics.Explosive.Radius,
			Color3.fromRGB(217, 162, 122),
			visualizeSettings.Lifetime
		)
	end

	-- The player owns their own character's physics, so the push is applied here.
	local character = player.Character
	local root = if character then character.PrimaryPart else nil
	if root and config.Ballistics.Explosive.Knockback > 0 then
		local offset = root.Position - position
		local scale = Damage.blast(config, offset.Magnitude)
		if scale > 0 then
			local direction = if offset.Magnitude > 0.1 then offset.Unit else Vector3.yAxis
			local push = (direction + Vector3.new(0, 0.35, 0)).Unit
			root:ApplyImpulse(push * config.Ballistics.Explosive.Knockback * scale * root.AssemblyMass)
		end
	end
end

-- Custom inventory mode: the server says which weapon model is in hand.
local function onEquipMessage(id: string?)
	if id == nil then
		unequip()
		return
	end
	local entry = Registry.get(id)
	local character = player.Character
	if entry == nil or character == nil then
		return
	end
	task.spawn(function()
		-- The model may replicate a moment after the message.
		for _ = 1, 40 do
			for _, child in character:GetChildren() do
				if child:IsA("Model") and child:GetAttribute(WEAPON_ATTRIBUTE) == id then
					equip(Registry.entryFor(child) or entry, child)
					return
				end
			end
			task.wait(0.05)
		end
	end)
end

------------------------------------------------------------------------------
-- Lifecycle and local API
------------------------------------------------------------------------------

function Client.isReady(): boolean
	return ready
end

-- The id of the weapon in hand, if any.
function Client.getEquipped(): string?
	return if held then held.entry.id else nil
end

-- A read-only view of the held weapon for custom HUDs. Nil when unarmed or
-- before the server's first Sync.
function Client.getAmmo(): (number?, number?)
	local state = if held then held.state else nil
	if state == nil then
		return nil, nil
	end
	return State.loaded(state), state.reserve
end

function Client.isAiming(): boolean
	return held ~= nil and held.aiming
end

-- The local player's own crosshair settings, checked against the config
-- rules. Unknown or invalid fields are reported and left out.
function Client.setCrosshair(settings: { [string]: any }?)
	if settings == nil then
		HUD.setPlayerCrosshair(nil)
		return
	end
	local clean, problems = Config.Schema.validate({ Crosshair = settings }, "Weapon")
	for _, problem in problems do
		log:Warn(`SetCrosshair: {problem.path} {problem.message}`)
	end
	HUD.setPlayerCrosshair(clean.Crosshair or {})
end

function Client.start(root: Instance)
	if started then
		return
	end
	started = true

	task.spawn(function()
		log:Try(function()
			Config.load(root)
			Registry.load(root)

			simulator = Projectile.newSimulator(projectileRaycast, function(projectile, event, result)
				log:Try(onProjectileEvent, projectile, event, result)
			end)

			Net.on("Sync", onSync)
			Net.on("Hit", onHit)
			Net.on("Replicate", onReplicate)
			Net.on("Explode", onExplode)
			Net.on("Equip", onEquipMessage)
			Net.on("PoseOf", onPoseOf)
			Net.on("Act", onAct)
			if not Net.start(Framework) then
				return
			end

			Recoil.start()
			Characters.start()
			Gadgets.start()
			if Config.global().Debug.Overlay then
				DebugOverlay.start()
			end
			-- After the camera and the recoil have moved it, so the viewmodel
			-- is placed against this frame's final camera.
			RunService:BindToRenderStep(UPDATE_STEP, Enum.RenderPriority.Camera.Value + 2, log:Wrap(update))
			table.insert(connections, player.CharacterAdded:Connect(log:Wrap(onCharacter)))
			if player.Character then
				onCharacter(player.Character)
			end

			table.insert(
				connections,
				root.AncestryChanged:Connect(function()
					if not root:IsDescendantOf(game) then
						Client.stop()
					end
				end)
			)

			ready = true
			log:Info(`v{Version} started`)
		end)
	end)
end

function Client.stop()
	if not started then
		return
	end
	started = false
	ready = false
	unequip()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	pcall(function()
		RunService:UnbindFromRenderStep(UPDATE_STEP)
	end)
	Recoil.stop()
	Characters.stop()
	Gadgets.stop()
	AttachmentMenu.close()
	DebugOverlay.stop()
	Viewmodel.hide()
	Input.unbind()
	HUD.destroy()
	Effects.clear()
	Visualizer.clear()
	if simulator then
		simulator:clear()
	end
	Net.stop()
	Logger.shutdown()
end

return Client
