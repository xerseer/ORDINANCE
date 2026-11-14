--!strict
--[[
	Combat
	The server's side of every shot: check it, resolve it, apply the damage.

	The client is trusted for exactly two things, both bounded: where the shot
	started (must be close to the shooter's head and not behind a wall) and
	which way it pointed. Everything else is decided here:

	  - whether the weapon could fire at all (ammo, reload, cadence)
	  - the pellet pattern (derived from a per-player seed, not sent)
	  - what was hit (the level, plus characters rewound to the shot's time)
	  - how much it hurt

	A rejected shot costs the client nothing but a Sync that corrects its ammo.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Framework = script.Parent.Parent

local Config = require(Framework.Config)
local Damage = require(Framework.Ballistics.Damage)
local Events = require(Framework.Core.Events)
local Hitscan = require(Framework.Ballistics.Hitscan)
local LagCompensation = require(script.Parent.LagCompensation)
local Logger = require(Framework.Core.Logger)
local Net = require(Framework.Core.Net)
local Projectile = require(Framework.Ballistics.Projectile)
local Registry = require(Framework.Weapons.Registry)
local Sessions = require(script.Parent.Sessions)
local Spread = require(Framework.Ballistics.Spread)
local State = require(Framework.Weapons.State)
local Visualizer = require(Framework.Core.Visualizer)

type Session = Sessions.Session
type Entry = Registry.Entry

-- Damage gathered for one victim across the pellets of a single shot.
type Tally = {
	humanoid: Humanoid,
	player: Player?,
	damage: number,
	part: string,
	group: string,
	distance: number,
	position: Vector3,
}

type ProjectileData = {
	player: Player,
	entry: Entry,
	params: RaycastParams,
}

export type DamageHandler = (info: Events.DamageInfo) -> (number | boolean)?

local MAX_SHOT_ID_JUMP = 500
local FIRE_BURST_ALLOWANCE = 3

local log = Logger.scope("Combat")

local Combat = {}

local damageHandler: DamageHandler? = nil
local simulator: Projectile.Simulator
local heartbeat: RBXScriptConnection? = nil
local random = Random.new()

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function isFinite(vector: Vector3): boolean
	return vector.X == vector.X
		and vector.Y == vector.Y
		and vector.Z == vector.Z
		and math.abs(vector.X) < 1e7
		and math.abs(vector.Y) < 1e7
		and math.abs(vector.Z) < 1e7
end

local function sameTeam(a: Player, b: Player): boolean
	return a ~= b and not a.Neutral and not b.Neutral and a.Team ~= nil and a.Team == b.Team
end

-- Applies damage through the game's handler, if any. Returns (dealt, killed).
local function applyDamage(info: Events.DamageInfo, friendlyFire: boolean): (number, boolean)
	local humanoid = info.victim
	if humanoid.Health <= 0 or humanoid.Parent == nil then
		return 0, false
	end
	if
		info.attacker
		and info.victimPlayer
		and not friendlyFire
		and sameTeam(info.attacker, info.victimPlayer)
	then
		return 0, false
	end

	if damageHandler then
		local ok, result = pcall(damageHandler, info)
		if not ok then
			log:Error(`the damage handler errored: {tostring(result)}`)
		elseif result == false then
			return 0, false
		elseif type(result) == "number" then
			info.damage = result
		end
	end
	if info.damage <= 0 then
		return 0, false
	end

	local before = humanoid.Health
	humanoid:TakeDamage(info.damage)
	local dealt = before - humanoid.Health
	Events.Damaged:Fire(info)
	local killed = before > 0 and humanoid.Health <= 0
	if killed then
		Events.Killed:Fire(info)
	end
	return dealt, killed
end

local function tallyHit(
	tallies: { [Humanoid]: Tally },
	config: Config.Config,
	humanoid: Humanoid,
	player: Player?,
	part: string,
	distance: number,
	position: Vector3,
	scale: number
)
	local damage, group = Damage.bullet(config, part, distance)
	damage *= scale
	local tally = tallies[humanoid]
	if tally == nil then
		tallies[humanoid] = {
			humanoid = humanoid,
			player = player,
			damage = damage,
			part = part,
			group = group,
			distance = distance,
			position = position,
		}
		return
	end
	tally.damage += damage
	-- Report the most valuable part a shotgun blast touched.
	if group == "Head" or (group == "Torso" and tally.group == "Limb") then
		tally.part = part
		tally.group = group
		tally.position = position
	end
end

local function settle(player: Player, entry: Entry, tallies: { [Humanoid]: Tally }, explosive: boolean)
	for _, tally in tallies do
		local info: Events.DamageInfo = {
			attacker = player,
			victim = tally.humanoid,
			victimPlayer = tally.player,
			weapon = entry.id,
			damage = tally.damage,
			part = tally.part,
			group = tally.group,
			distance = tally.distance,
			position = tally.position,
			explosive = explosive,
		}
		local dealt, killed = applyDamage(info, entry.config.Damage.FriendlyFire)
		if dealt > 0 and player.Parent ~= nil then
			Net.fireClient(player, "Hit", tally.position, tally.group, dealt, killed)
		end
	end
end

local function resolveHitscan(
	entry: Entry,
	character: Model,
	origin: Vector3,
	direction: Vector3,
	rewindTo: number,
	tallies: { [Humanoid]: Tally }
)
	local config = entry.config
	local security = Config.global().Security
	local penetration = config.Ballistics.Penetration

	local exclude: { Instance } = if security.LagCompensation then LagCompensation.characters() else {}
	table.insert(exclude, character)
	local trace =
		Hitscan.trace(origin, direction, config.Ballistics.Range, Hitscan.params(exclude), penetration)

	if security.LagCompensation then
		local hit = LagCompensation.raycast(origin, direction, trace.distance, rewindTo, character)
		if hit then
			local scale = Hitscan.penetrationScale(trace, hit.distance, penetration)
			tallyHit(tallies, config, hit.humanoid, hit.player, hit.part, hit.distance, hit.position, scale)
			return
		end
	end

	-- NPCs (and players, when lag compensation is off) are hit by the level trace.
	local final = trace.final
	if final then
		local humanoid, model = Hitscan.humanoidOf(final.Instance)
		if humanoid and model then
			local scale = Hitscan.penetrationScale(trace, trace.distance, penetration)
			local victim = Players:GetPlayerFromCharacter(model)
			tallyHit(
				tallies,
				config,
				humanoid,
				victim,
				final.Instance.Name,
				trace.distance,
				trace.position,
				scale
			)
		end
	end
end

-- True if something solid that is not a character stands between two points.
local function isBlocked(from: Vector3, to: Vector3, exclude: { Instance }): boolean
	local params = Hitscan.params(exclude)
	for _ = 1, 8 do
		local result = Hitscan.raycast(from, to - from, params)
		if result == nil then
			return false
		end
		local _, model = Hitscan.humanoidOf(result.Instance)
		if model == nil then
			return true
		end
		params:AddToFilter(model)
	end
	return false
end

local function explode(data: ProjectileData, position: Vector3, key: string)
	local entry = data.entry
	local config = entry.config
	local explosive = config.Ballistics.Explosive
	local seen: { [Humanoid]: boolean } = {}

	for _, part in workspace:GetPartBoundsInRadius(position, explosive.Radius) do
		local humanoid, model = Hitscan.humanoidOf(part)
		if humanoid == nil or model == nil or seen[humanoid] then
			continue
		end
		seen[humanoid] = true

		local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		local centre = if root and root:IsA("BasePart") then root.Position else part.Position
		local distance = (centre - position).Magnitude
		local scale = Damage.blast(config, distance)
		if scale <= 0 then
			continue
		end
		if explosive.RequireLineOfSight and isBlocked(position, centre, { model }) then
			continue
		end

		local victim = Players:GetPlayerFromCharacter(model)
		if victim == data.player then
			scale *= explosive.SelfDamageScale
		end
		local info: Events.DamageInfo = {
			attacker = data.player,
			victim = humanoid,
			victimPlayer = victim,
			weapon = entry.id,
			damage = explosive.Damage * scale,
			part = if root then root.Name else part.Name,
			group = "Torso",
			distance = distance,
			position = centre,
			explosive = true,
		}
		-- Your own grenade always hurts you; team rules apply to everyone else.
		local dealt, killed = applyDamage(info, config.Damage.FriendlyFire or victim == data.player)
		if dealt > 0 and data.player.Parent ~= nil and victim ~= data.player then
			Net.fireClient(data.player, "Hit", centre, "Torso", dealt, killed)
		end
	end

	Net.fireAll("Explode", position, entry.id, key)
	Events.Exploded:Fire(position, entry.id)
end

local function onProjectileEvent(
	projectile: Projectile.Projectile,
	event: Projectile.Event,
	result: RaycastResult?
)
	local data = projectile.data :: ProjectileData
	if event == "Detonate" then
		explode(data, projectile.position, projectile.key)
	elseif event == "Impact" and result then
		local humanoid, model = Hitscan.humanoidOf(result.Instance)
		if humanoid and model then
			local tallies: { [Humanoid]: Tally } = {}
			local victim = Players:GetPlayerFromCharacter(model)
			tallyHit(
				tallies,
				data.entry.config,
				humanoid,
				victim,
				result.Instance.Name,
				projectile.travelled,
				result.Position,
				1
			)
			settle(data.player, data.entry, tallies, false)
		end
	end
end

local function projectileRaycast(
	projectile: Projectile.Projectile,
	origin: Vector3,
	displacement: Vector3
): RaycastResult?
	return Hitscan.raycast(origin, displacement, (projectile.data :: ProjectileData).params)
end

local function reject(session: Session, id: string, reason: string)
	log:Debug(`rejected a shot from {session.player.Name} with "{id}": {reason}`)
	Sessions.sync(session, id)
end

-- Handles the "Shoot" message.
function Combat.onShoot(
	player: Player,
	weaponId: any,
	shotId: any,
	clientTime: any,
	origin: any,
	aim: any,
	spreadAngle: any
)
	if
		type(weaponId) ~= "string"
		or type(shotId) ~= "number"
		or type(clientTime) ~= "number"
		or type(spreadAngle) ~= "number"
		or typeof(origin) ~= "Vector3"
		or typeof(aim) ~= "Vector3"
	then
		return
	end
	if shotId ~= shotId or shotId % 1 ~= 0 or clientTime ~= clientTime or spreadAngle ~= spreadAngle then
		return
	end
	if not isFinite(origin) or not isFinite(aim) or math.abs(aim.Magnitude - 1) > 0.01 then
		return
	end

	local session = Sessions.get(player)
	local entry = Registry.get(weaponId)
	if session == nil or entry == nil then
		return
	end
	if session.equipped ~= weaponId then
		return reject(session, weaponId, "not equipped")
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if character == nil or humanoid == nil or humanoid.Health <= 0 then
		return
	end
	if shotId <= session.lastShotId or shotId > session.lastShotId + MAX_SHOT_ID_JUMP then
		return
	end

	local config = entry.config
	local security = Config.global().Security
	local now = serverNow()
	local state = Sessions.state(session, entry)

	State.advance(state, config, now, security.ReloadTolerance)
	local canFire, reason = State.canFire(state, config, now, true)
	if not canFire then
		return reject(session, weaponId, reason or "cannot fire")
	end

	-- Cadence: an allowance that refills at the weapon's rate of fire. It
	-- absorbs network jitter without letting a client fire faster on average.
	local rpm = math.max(config.Fire.RPM, config.Fire.BurstRPM)
	local clock = os.clock()
	session.fireTokens = math.min(
		FIRE_BURST_ALLOWANCE,
		session.fireTokens + (clock - session.fireTime) * rpm / 60 * security.FireRateTolerance
	)
	session.fireTime = clock
	if session.fireTokens < 1 then
		return reject(session, weaponId, "firing too fast")
	end

	local head = character:FindFirstChild("Head") or character.PrimaryPart
	if head == nil or not head:IsA("BasePart") then
		return
	end
	if (origin - head.Position).Magnitude > security.MaxOriginError then
		return reject(session, weaponId, "origin too far from the character")
	end
	if security.ValidateLineOfSight then
		local exclude = LagCompensation.characters()
		table.insert(exclude, character)
		if isBlocked(head.Position, origin, exclude) then
			return reject(session, weaponId, "origin behind cover")
		end
	end

	-- Accepted.
	session.fireTokens -= 1
	session.lastShotId = shotId
	State.fire(state, config, now)

	local malfunctions = config.Realism.Malfunctions
	if malfunctions.Enabled and random:NextNumber() < malfunctions.Chance then
		state.jammed = true
		Sessions.sync(session, weaponId)
	end

	local low, high = Spread.bounds(config)
	local angle = math.clamp(spreadAngle, low, high)
	local pellets = Spread.pellets(config, aim, angle, session.seed, shotId)

	if config.Ballistics.Type == "Projectile" then
		local headStart = math.min(player:GetNetworkPing() / 2, 0.2)
		for index, direction in pellets do
			local data: ProjectileData = {
				player = player,
				entry = entry,
				params = Hitscan.params({ character }),
			}
			simulator:launch({
				key = `{player.UserId}:{shotId}:{index}`,
				origin = origin,
				velocity = Projectile.velocity(config.Ballistics, direction),
				ballistics = config.Ballistics,
				data = data,
				headStart = headStart,
			})
		end
	else
		-- The shooter saw everyone else roughly half a round trip plus the
		-- interpolation delay in the past.
		local shotTime = math.min(clientTime, now)
		local rewindTo = math.max(
			now - security.MaxRewind,
			shotTime - player:GetNetworkPing() / 2 - security.InterpolationDelay
		)

		local tallies: { [Humanoid]: Tally } = {}
		for _, direction in pellets do
			resolveHitscan(entry, character, origin, direction, rewindTo, tallies)
		end

		if Config.global().Debug.Visualize.Hitboxes then
			local lifetime = Config.global().Debug.Visualize.Lifetime
			for _, other in Players:GetPlayers() do
				if other ~= player then
					for _, box in LagCompensation.boxes(other, rewindTo) do
						Visualizer.box(box.cframe, box.size, Color3.fromRGB(217, 162, 122), lifetime)
					end
				end
			end
		end

		settle(player, entry, tallies, false)
	end

	Net.fireExcept(player, "Replicate", player.UserId, weaponId, origin, aim, angle, session.seed, shotId)
	Events.Fired:Fire(player, weaponId, origin, aim)
end

-- Handles the "Action" message: Reload, Cycle and Mode.
function Combat.onAction(player: Player, weaponId: any, kind: any)
	if type(weaponId) ~= "string" or type(kind) ~= "string" then
		return
	end
	local session = Sessions.get(player)
	local entry = Registry.get(weaponId)
	if session == nil or entry == nil or session.equipped ~= weaponId then
		return
	end

	local config = entry.config
	local now = serverNow()
	local state = Sessions.state(session, entry)
	State.advance(state, config, now, Config.global().Security.ReloadTolerance)

	local ok = false
	local empty = false
	if kind == "Reload" then
		empty = not State.hasRound(state, config)
		ok = State.startReload(state, config, now)
		if ok then
			Events.Reloaded:Fire(player, weaponId)
		end
	elseif kind == "Cycle" then
		ok = State.cycle(state, config, now)
	elseif kind == "Mode" then
		ok = State.nextMode(state, config)
	end

	if not ok then
		-- The client predicted something the server did not allow; put it right.
		Sessions.sync(session, weaponId)
	elseif kind ~= "Mode" then
		-- Everyone else plays the same animation on this player's weapon.
		local duration = state.actionEnd - state.actionStart
		Net.fireExcept(player, "Act", player.UserId, weaponId, state.action, duration, empty)
	end
end

-- Handles the "Pose" message: where a player is aiming, relayed to everyone
-- else so their copy of the character points its weapon the same way.
function Combat.onPose(player: Player, pitch: any, aiming: any)
	if type(pitch) ~= "number" or pitch ~= pitch or type(aiming) ~= "boolean" then
		return
	end
	local session = Sessions.get(player)
	if session == nil or session.equipped == nil then
		return
	end
	Net.fireExcept(player, "PoseOf", player.UserId, math.clamp(pitch, -1.5, 1.5), aiming)
end

-- Sets a function that sees every hit before damage is applied. Return a
-- number to change the damage, false to cancel it, nothing to leave it alone.
function Combat.setDamageHandler(handler: DamageHandler?)
	damageHandler = handler
end

function Combat.start()
	simulator = Projectile.newSimulator(projectileRaycast, function(projectile, event, result)
		log:Try(onProjectileEvent, projectile, event, result)
	end)
	heartbeat = RunService.Heartbeat:Connect(function(deltaTime)
		simulator:step(deltaTime)
	end)
	Net.on("Shoot", Combat.onShoot)
	Net.on("Action", Combat.onAction)
	Net.on("Pose", Combat.onPose)
end

function Combat.stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	if simulator then
		simulator:clear()
	end
	damageHandler = nil
end

return Combat
