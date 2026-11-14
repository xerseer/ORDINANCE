--!strict
--[[
	Animator
	Decides, every frame, where one weapon and the two hands holding it are.

	It blends the two animation systems according to Animation.Mode:
	  - an encoded animation, if the weapon defines one for what is happening
	  - otherwise procedural motion built from the weapon's attachments

	The result is a Pose in the weapon handle's own space. It does not know or
	care whether it will be drawn as a first-person viewmodel or on a
	character's real arms; those both read the same Pose.

	Animation names the framework looks for:
		Equip, Reload, ReloadEmpty, Cycle   played for the matching action
		Fire                                played from the start on every shot
		Idle                                looped whenever the weapon is held
]]

local Encoded = require(script.Parent.Encoded)
local Procedural = require(script.Parent.Procedural)
local Registry = require(script.Parent.Parent.Weapons.Registry)
local Rig = require(script.Parent.Parent.Weapons.Rig)

export type Pose = {
	weapon: CFrame, -- offset of the weapon from where it is held
	right: CFrame, -- trigger-hand grip, in handle space
	left: CFrame, -- support-hand grip, in handle space
	parts: { [string]: CFrame }, -- offsets of named weapon parts
}

-- A weapon's attachments, measured once, in handle space.
export type Attachments = {
	main: CFrame,
	grip: CFrame,
	barrel: CFrame,
	mag: CFrame?,
	side: CFrame?,
	aim: CFrame?,
}

export type Animator = {
	attachments: Attachments,
	onSound: ((id: string) -> ())?,
	setAction: (self: Animator, action: string, start: number, duration: number, empty: boolean?) -> (),
	fire: (self: Animator, now: number) -> (),
	update: (self: Animator, now: number) -> Pose,
}

-- With no Grip attachment the support hand cups the trigger hand.
local CUPPED = CFrame.new(-0.1, -0.14, -0.06)

local Animator = {}

local function measureOne(model: Model, handle: BasePart, name: string): CFrame?
	local attachment = Rig.attachment(model, name)
	if attachment == nil then
		return nil
	end
	return handle.CFrame:ToObjectSpace(attachment.WorldCFrame)
end

-- Reads a prepared weapon model's attachments.
function Animator.measure(model: Model): Attachments
	local handle = model.PrimaryPart :: BasePart
	local main = measureOne(model, handle, "MainHandle") or CFrame.identity
	return {
		main = main,
		grip = measureOne(model, handle, "Grip") or main * CUPPED,
		barrel = measureOne(model, handle, "Barrel") or CFrame.new(0, 0, -1),
		mag = measureOne(model, handle, "Mag"),
		side = measureOne(model, handle, "Side"),
		aim = measureOne(model, handle, "Aim"),
	}
end

--[[
	Where a weapon part goes for a given channel offset. The offset's position
	moves the part along the handle's axes; its rotation turns the part about
	its own centre. `rest` is the part's resting frame in handle space.
]]
function Animator.partFrame(rest: CFrame, offset: CFrame): CFrame
	return CFrame.new(rest.Position + offset.Position) * offset.Rotation * rest.Rotation
end

function Animator.new(entry: Registry.Entry): Animator
	local config = entry.config
	local attachments = Animator.measure(entry.template)
	local compiled = Encoded.compileAll(entry.id, config.Animations)
	local context: Procedural.Context = {
		config = config,
		right = attachments.main,
		left = attachments.grip,
		mag = attachments.mag,
		side = attachments.side,
	}

	local action = "Idle"
	local actionStart = 0
	local actionDuration = 0
	local actionEmpty = false
	local soundCursor = -1
	local lastFire = -math.huge
	local created = os.clock()

	local channels: { [string]: CFrame } = {}
	local overlay: { [string]: CFrame } = {}
	local pose: Pose = {
		weapon = CFrame.identity,
		right = attachments.main,
		left = attachments.grip,
		parts = {},
	}

	local self = { attachments = attachments, onSound = nil } :: any

	function self.setAction(_: Animator, name: string, start: number, duration: number, empty: boolean?)
		action = name
		actionStart = start
		actionDuration = duration
		actionEmpty = empty == true
		soundCursor = -1
	end

	function self.fire(_: Animator, now: number)
		lastFire = now
	end

	function self.update(_: Animator, now: number): Pose
		local mode = config.Animation.Mode
		local useEncoded = mode ~= "Procedural"
		local useProcedural = mode ~= "Encoded"
		table.clear(channels)

		if useEncoded and compiled.Idle then
			Encoded.sample(compiled.Idle, now - created, channels)
		end

		if action ~= "Idle" then
			local elapsed = now - actionStart
			local alpha = if actionDuration > 0 then math.clamp(elapsed / actionDuration, 0, 1) else 1
			local track = if useEncoded
				then (if action == "Reload" and actionEmpty then compiled.ReloadEmpty else nil) or compiled[action]
				else nil
			if track then
				local time = if track.fit then alpha * track.length else elapsed
				Encoded.sample(track, time, channels)
				local onSound = self.onSound
				if onSound then
					for _, sound in track.sounds do
						if sound.time > soundCursor and sound.time <= time then
							onSound(sound.id)
						end
					end
				end
				soundCursor = time
			elseif useProcedural then
				Procedural.sample(action, alpha, elapsed, context, channels)
			end
			if alpha >= 1 then
				action = "Idle"
			end
		end

		-- A shot lays its own short motion over whatever else is playing.
		local sinceFire = now - lastFire
		table.clear(overlay)
		if useEncoded and compiled.Fire then
			if sinceFire < compiled.Fire.length then
				Encoded.sample(compiled.Fire, sinceFire, overlay)
			end
		elseif useProcedural then
			Procedural.fire(sinceFire, context, overlay)
		end
		for channel, frame in overlay do
			local existing = channels[channel]
			channels[channel] = if existing then existing * frame else frame
		end

		pose.weapon = channels.Weapon or CFrame.identity
		pose.right = attachments.main * (channels.Right or CFrame.identity)
		pose.left = attachments.grip * (channels.Left or CFrame.identity)
		table.clear(pose.parts)
		for channel, frame in channels do
			if channel ~= "Weapon" and channel ~= "Right" and channel ~= "Left" then
				pose.parts[channel] = frame
			end
		end
		return pose
	end

	return self :: Animator
end

return Animator
