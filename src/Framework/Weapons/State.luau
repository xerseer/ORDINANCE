--!strict
--[[
	State
	The mechanical state of one weapon: rounds, chamber, fire mode and whatever
	action it is in the middle of. Pure data and pure functions, no instances
	and no timers.

	The client runs it to predict; the server runs the same code to decide.
	Time-based actions (equip, reload, cycle) are stored as a start and an end
	and resolved by `advance`, so neither side needs a timer and the server can
	forgive a little network delay by passing a tolerance.
]]

local Defaults = require(script.Parent.Parent.Config.Defaults)

type Config = Defaults.Config

export type Action = "Idle" | "Equip" | "Reload" | "Cycle"

export type State = {
	mag: number,
	reserve: number,
	chambered: boolean,
	mode: string,
	action: Action,
	actionStart: number,
	actionEnd: number,
	shellsToLoad: number,
	shellsLoaded: number,
	needsCycle: boolean,
	jammed: boolean,
	nextFire: number,
	shots: number,
}

-- What travels in a Sync message.
export type Snapshot = { any }

local State = {}

local function isManual(config: Config): boolean
	return config.Fire.Action ~= "SelfLoading"
end

local function spend(state: State, config: Config, amount: number): number
	if config.Ammo.Infinite or state.reserve == math.huge then
		return amount
	end
	local taken = math.min(amount, state.reserve)
	state.reserve -= taken
	return taken
end

local function chamberFromMagazine(state: State, config: Config)
	if config.Realism.Chambering and not state.chambered and state.mag > 0 then
		state.mag -= 1
		state.chambered = true
	end
end

function State.new(config: Config, now: number): State
	local state: State = {
		mag = config.Ammo.Magazine,
		reserve = config.Ammo.Reserve,
		chambered = config.Realism.Chambering,
		mode = config.Fire.Mode,
		action = "Equip",
		actionStart = now,
		actionEnd = now + config.Handling.EquipTime,
		shellsToLoad = 0,
		shellsLoaded = 0,
		needsCycle = false,
		jammed = false,
		nextFire = 0,
		shots = 0,
	}
	return state
end

-- Rounds ready to fire without reloading.
function State.loaded(state: State): number
	return state.mag + (if state.chambered then 1 else 0)
end

function State.hasRound(state: State, config: Config): boolean
	if config.Realism.Chambering then
		return state.chambered
	end
	return state.mag > 0
end

-- Restarts the equip delay. Called every time the weapon is drawn.
function State.equip(state: State, config: Config, now: number)
	state.action = "Equip"
	state.actionStart = now
	state.actionEnd = now + config.Handling.EquipTime
	state.shellsToLoad = 0
	state.shellsLoaded = 0
end

local function finishMagazineReload(state: State, config: Config)
	if config.Realism.DropMagazine then
		state.mag = 0
	end
	state.mag += spend(state, config, config.Ammo.Magazine - state.mag)
	chamberFromMagazine(state, config)
	state.needsCycle = false
	state.jammed = false
end

--[[
	Brings the state up to `now`, completing any action that has finished.
	`tolerance` is the fraction of an action's length to forgive (0 to 1); the
	server passes Security.ReloadTolerance, the client passes 0.
]]
function State.advance(state: State, config: Config, now: number, tolerance: number?)
	local action = state.action
	if action == "Idle" then
		return
	end
	local scale = 1 - (tolerance or 0)
	local elapsed = now - state.actionStart

	if action == "Reload" and config.Ammo.ReloadType == "Single" then
		local shellTime = config.Ammo.ShellTime * scale
		local due = math.min(state.shellsToLoad, math.floor(elapsed / shellTime + 1e-4))
		while state.shellsLoaded < due do
			if spend(state, config, 1) < 1 then
				state.shellsToLoad = state.shellsLoaded
				break
			end
			state.mag += 1
			state.shellsLoaded += 1
		end
		if state.shellsLoaded >= state.shellsToLoad then
			chamberFromMagazine(state, config)
			state.needsCycle = false
			state.jammed = false
			state.action = "Idle"
		end
		return
	end

	if elapsed < (state.actionEnd - state.actionStart) * scale then
		return
	end

	if action == "Reload" then
		finishMagazineReload(state, config)
	elseif action == "Cycle" then
		state.needsCycle = false
		state.jammed = false
		chamberFromMagazine(state, config)
	end
	state.action = "Idle"
end

--[[
	Whether a shot may be fired right now, and if not, why:
	"Safe", "Busy", "Jammed", "NeedsCycle", "Empty" or "Rate".
	The server passes ignoreRate and checks cadence with its own allowance.
]]
function State.canFire(state: State, config: Config, now: number, ignoreRate: boolean?): (boolean, string?)
	if state.mode == "Safe" then
		return false, "Safe"
	end
	if state.action ~= "Idle" then
		-- A round-by-round reload can be cut short by firing.
		local interruptible = state.action == "Reload"
			and config.Ammo.ReloadType == "Single"
			and State.hasRound(state, config)
		if not interruptible then
			return false, "Busy"
		end
	end
	if state.jammed then
		return false, "Jammed"
	end
	if state.needsCycle then
		return false, "NeedsCycle"
	end
	if not State.hasRound(state, config) then
		return false, "Empty"
	end
	if not ignoreRate and now < state.nextFire - 1e-3 then
		return false, "Rate"
	end
	return true, nil
end

-- Seconds between shots in the current mode. Bursts may run faster inside the burst.
function State.interval(state: State, config: Config): number
	local rpm = config.Fire.RPM
	if state.mode == "Burst" and config.Fire.BurstRPM > 0 then
		rpm = config.Fire.BurstRPM
	end
	return 60 / rpm
end

-- Fires one round. Call canFire first.
function State.fire(state: State, config: Config, now: number)
	if state.action == "Reload" then
		state.action = "Idle"
	end

	if config.Realism.Chambering then
		state.chambered = false
		if not isManual(config) then
			chamberFromMagazine(state, config)
		end
	else
		state.mag -= 1
	end
	state.shots += 1

	-- Keep an exact cadence when the trigger is held: schedule from the last
	-- slot rather than from "now" when we are only a frame late.
	local interval = State.interval(state, config)
	local late = now - state.nextFire
	state.nextFire = (if late >= 0 and late < interval then state.nextFire else now) + interval

	if isManual(config) and state.mag > 0 then
		if config.Realism.ManualCycle then
			state.needsCycle = true
		else
			state.action = "Cycle"
			state.actionStart = now
			state.actionEnd = now + config.Fire.CycleTime
		end
	end
end

-- Starts a reload. Returns false when there is nothing to do.
function State.startReload(state: State, config: Config, now: number): boolean
	if state.action ~= "Idle" then
		return false
	end
	local missing = config.Ammo.Magazine - state.mag
	local hasReserve = config.Ammo.Infinite or state.reserve > 0
	if missing <= 0 or not hasReserve then
		return false
	end

	local duration: number
	if config.Ammo.ReloadType == "Single" then
		local available = if config.Ammo.Infinite then missing else math.min(missing, state.reserve)
		state.shellsToLoad = available
		state.shellsLoaded = 0
		duration = available * config.Ammo.ShellTime
	else
		local empty = not State.hasRound(state, config)
		duration = if empty and config.Ammo.ReloadEmptyTime > 0
			then config.Ammo.ReloadEmptyTime
			else config.Ammo.ReloadTime
	end

	state.action = "Reload"
	state.actionStart = now
	state.actionEnd = now + duration
	return true
end

-- Works the action by hand: clears a jam, or chambers the next round on a
-- bolt or pump weapon with Realism.ManualCycle.
function State.cycle(state: State, config: Config, now: number): boolean
	if state.action ~= "Idle" then
		return false
	end
	if not state.jammed and not state.needsCycle then
		return false
	end
	state.action = "Cycle"
	state.actionStart = now
	state.actionEnd = now + config.Fire.CycleTime
	return true
end

-- Switches to the next selectable fire mode. Returns false if there is only one.
function State.nextMode(state: State, config: Config): boolean
	local modes = config.Fire.Modes
	if #modes <= 1 then
		return false
	end
	local index = table.find(modes, state.mode) or 0
	state.mode = modes[index % #modes + 1]
	return true
end

-- 0 to 1 through the current action, for progress bars and animation.
function State.progress(state: State, now: number): number
	if state.action == "Idle" then
		return 1
	end
	local length = state.actionEnd - state.actionStart
	if length <= 0 then
		return 1
	end
	return math.clamp((now - state.actionStart) / length, 0, 1)
end

function State.snapshot(state: State, now: number): Snapshot
	return {
		state.mag,
		state.reserve,
		state.chambered,
		state.mode,
		state.action,
		now - state.actionStart,
		state.actionEnd - state.actionStart,
		state.shellsToLoad,
		state.shellsLoaded,
		state.needsCycle,
		state.jammed,
	}
end

-- Overwrites the predicted state with the server's. `now` is the local clock.
function State.apply(state: State, snapshot: Snapshot, now: number)
	state.mag = snapshot[1]
	state.reserve = snapshot[2]
	state.chambered = snapshot[3]
	state.mode = snapshot[4]
	state.action = snapshot[5]
	state.actionStart = now - snapshot[6]
	state.actionEnd = state.actionStart + snapshot[7]
	state.shellsToLoad = snapshot[8]
	state.shellsLoaded = snapshot[9]
	state.needsCycle = snapshot[10]
	state.jammed = snapshot[11]
end

return State
