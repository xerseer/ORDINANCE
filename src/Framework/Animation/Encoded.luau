--!strict
--[[
	Encoded
	Animations stored as plain numbers in the weapon module, so a weapon needs
	no uploaded animation assets.

		Animations = {
			Reload = {
				Keyframes = {
					{ Time = 0.0, Weapon = { 0, 0, 0, 0, 0, 0 } },
					{ Time = 0.3, Weapon = { 0, -0.1, 0, 12, 0, 18 }, Easing = "SineOut" },
					{ Time = 0.5, Mag = { 0, -1.2, 0, 0, 0, 0 }, Left = { 0, -1.2, 0, 0, 0, 0 } },
					{ Time = 1.0, Weapon = { 0, 0, 0, 0, 0, 0 }, Mag = { 0, 0, 0, 0, 0, 0 } },
				},
			},
		}

	A value is six numbers: position x, y, z in studs, then rotation x, y, z in
	degrees (the same order as a part's Orientation). Every value is an offset
	from rest, so six zeros always means "where it normally is".

	Channels:
		Weapon        the whole weapon, relative to its hold position
		Right, Left   each hand, relative to its grip attachment
		anything else a part of the weapon model with that name (Mag, Bolt, ...)

	A keyframe only needs the channels that change at that time. `Easing` is
	how the keyframe is approached: a style name, optionally followed by In,
	Out or InOut. `Sound` plays an asset id when the keyframe is reached.

	Animation options: Length (defaults to the last keyframe), Loop, and Fit
	(stretch to the length of the action it plays for; on by default).
]]

local TweenService = game:GetService("TweenService")

local Logger = require(script.Parent.Parent.Core.Logger)

type Key = {
	time: number,
	frame: CFrame,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
}

export type Compiled = {
	length: number,
	loop: boolean,
	fit: boolean,
	channels: { [string]: { Key } },
	sounds: { { time: number, id: string } },
}

local RESERVED = { Time = true, Easing = true, Sound = true }

local log = Logger.scope("Animation")

local Encoded = {}

-- Six numbers (or a CFrame) to a CFrame.
function Encoded.frame(value: any): CFrame?
	if typeof(value) == "CFrame" then
		return value
	end
	if type(value) ~= "table" or #value ~= 6 then
		return nil
	end
	for index = 1, 6 do
		if type(value[index]) ~= "number" then
			return nil
		end
	end
	return CFrame.new(value[1], value[2], value[3])
		* CFrame.fromOrientation(math.rad(value[4]), math.rad(value[5]), math.rad(value[6]))
end

-- A CFrame back to six numbers, rounded. Used by the plugin's converter.
function Encoded.numbers(frame: CFrame): { number }
	local rx, ry, rz = frame:ToOrientation()
	local function round(value: number, places: number): number
		local scale = 10 ^ places
		local rounded = math.round(value * scale) / scale
		return if rounded == 0 then 0 else rounded
	end
	return {
		round(frame.X, 3),
		round(frame.Y, 3),
		round(frame.Z, 3),
		round(math.deg(rx), 2),
		round(math.deg(ry), 2),
		round(math.deg(rz), 2),
	}
end

local function parseEasing(name: any): (Enum.EasingStyle, Enum.EasingDirection)
	if type(name) ~= "string" then
		return Enum.EasingStyle.Sine, Enum.EasingDirection.InOut
	end
	local direction = Enum.EasingDirection.InOut
	local styleName = name
	for _, suffix in { "InOut", "Out", "In" } do
		if #name > #suffix and string.sub(name, -#suffix) == suffix then
			styleName = string.sub(name, 1, -#suffix - 1)
			direction = (Enum.EasingDirection :: any)[suffix]
			break
		end
	end
	local ok, style = pcall(function()
		return (Enum.EasingStyle :: any)[styleName]
	end)
	if ok and style then
		return style, direction
	end
	return Enum.EasingStyle.Sine, Enum.EasingDirection.InOut
end

-- Checks and prepares one animation. Problems are reported; the usable part
-- is kept. Returns nil only when nothing can be played.
function Encoded.compile(weaponName: string, name: string, animation: any): Compiled?
	local where = `{weaponName}: animation "{name}"`
	if type(animation) ~= "table" or type(animation.Keyframes) ~= "table" then
		log:Warn(`{where} needs a Keyframes list`)
		return nil
	end

	local channels: { [string]: { Key } } = {}
	local sounds = {}
	local last = 0
	for index, keyframe in animation.Keyframes do
		if type(keyframe) ~= "table" or type(keyframe.Time) ~= "number" then
			log:Warn(`{where} keyframe {index} has no Time; skipped`)
			continue
		end
		local time = math.max(0, keyframe.Time)
		last = math.max(last, time)
		local style, direction = parseEasing(keyframe.Easing)
		if type(keyframe.Sound) == "string" then
			table.insert(sounds, { time = time, id = keyframe.Sound })
		end
		for channel, value in keyframe do
			if RESERVED[channel] or type(channel) ~= "string" then
				continue
			end
			local frame = Encoded.frame(value)
			if frame == nil then
				log:Warn(`{where} keyframe {index}: "{channel}" must be six numbers; skipped`)
				continue
			end
			local keys = channels[channel]
			if keys == nil then
				keys = {}
				channels[channel] = keys
			end
			table.insert(keys, { time = time, frame = frame, style = style, direction = direction })
		end
	end

	if next(channels) == nil then
		log:Warn(`{where} has no usable keyframes`)
		return nil
	end
	for _, keys in channels do
		table.sort(keys, function(a, b)
			return a.time < b.time
		end)
	end
	table.sort(sounds, function(a, b)
		return a.time < b.time
	end)

	local length = if type(animation.Length) == "number" and animation.Length > 0
		then animation.Length
		else last
	return {
		length = math.max(length, 1e-3),
		loop = animation.Loop == true,
		fit = animation.Fit ~= false,
		channels = channels,
		sounds = sounds,
	}
end

-- Compiles every animation in a weapon's Animations table.
function Encoded.compileAll(weaponName: string, animations: any): { [string]: Compiled }
	local result: { [string]: Compiled } = {}
	if type(animations) ~= "table" then
		return result
	end
	for name, animation in animations do
		if type(name) == "string" then
			local compiled = Encoded.compile(weaponName, name, animation)
			if compiled then
				result[name] = compiled
			end
		end
	end
	return result
end

-- Writes each channel's value at `time` (seconds into the animation) into `out`.
function Encoded.sample(compiled: Compiled, time: number, out: { [string]: CFrame })
	if compiled.loop then
		time %= compiled.length
	else
		time = math.clamp(time, 0, compiled.length)
	end
	for channel, keys in compiled.channels do
		local first = keys[1]
		if time <= first.time then
			out[channel] = first.frame
			continue
		end
		local value = keys[#keys].frame
		for index = 2, #keys do
			local key = keys[index]
			if time <= key.time then
				local previous = keys[index - 1]
				local span = key.time - previous.time
				local alpha = if span > 0 then (time - previous.time) / span else 1
				value = previous.frame:Lerp(key.frame, TweenService:GetValue(alpha, key.style, key.direction))
				break
			end
		end
		out[channel] = value
	end
end

return Encoded
