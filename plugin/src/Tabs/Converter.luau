--!strict
--[[
	Converter tab
	Turns a Roblox animation into an encoded animation table.

	Select a KeyframeSequence (or an Animation instance whose id you own) in
	the Explorer. Each pose's CFrame is already an offset from rest, which is
	exactly what an encoded channel is, so conversion is a rename and a
	rounding: pose names become channels (Weapon, Left, Right, or a part of the
	weapon), times and easing carry over.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Selection = game:GetService("Selection")

local Source = require(script.Parent.Parent.Source)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local Converter = { name = "Converter" }

local SLOTS = { "Reload", "Equip", "Fire", "Cycle", "Idle" }

local STYLE: { [string]: string } = {
	Linear = "Linear",
	Constant = "Linear",
	Elastic = "Elastic",
	Cubic = "Sine",
	Bounce = "Bounce",
	CubicV2 = "Sine",
}

local function round(value: number, places: number): number
	local scale = 10 ^ places
	local rounded = math.round(value * scale) / scale
	return if rounded == 0 then 0 else rounded
end

local function numbers(frame: CFrame): { number }
	local rx, ry, rz = frame:ToOrientation()
	return {
		round(frame.X, 3),
		round(frame.Y, 3),
		round(frame.Z, 3),
		round(math.deg(rx), 2),
		round(math.deg(ry), 2),
		round(math.deg(rz), 2),
	}
end

local function isZero(values: { number }): boolean
	for _, value in values do
		if value ~= 0 then
			return false
		end
	end
	return true
end

-- Default channel for a pose name: the hands and the weapon get their own
-- channels; anything else is assumed to be a part of the weapon.
local function channelFor(pose: string, mapping: { [string]: string }): string
	local mapped = mapping[pose]
	if mapped then
		return mapped
	end
	local lowered = string.lower(pose)
	if string.find(lowered, "right") and (string.find(lowered, "hand") or string.find(lowered, "arm")) then
		return "Right"
	elseif string.find(lowered, "left") and (string.find(lowered, "hand") or string.find(lowered, "arm")) then
		return "Left"
	elseif
		lowered == "weapon"
		or lowered == "gun"
		or lowered == "handle"
		or lowered == "humanoidrootpart"
		or lowered == "torso"
	then
		return "Weapon"
	end
	return pose
end

local function collect(pose: Instance, into: { Pose }, mapping: { [string]: string })
	for _, child in pose:GetChildren() do
		if child:IsA("Pose") then
			table.insert(into, child)
			collect(child, into, mapping)
		end
	end
end

export type Options = { slot: string, mapping: { [string]: string }, skipRest: boolean }

--[[
	Converts a KeyframeSequence into the text of one Animations entry.
	Returns the text, or nil and a reason.
]]
function Converter.convert(sequence: KeyframeSequence, options: Options): (string?, string?)
	local keyframes = sequence:GetKeyframes()
	if #keyframes == 0 then
		return nil, "The animation has no keyframes."
	end
	table.sort(keyframes, function(a, b)
		return a.Time < b.Time
	end)

	local out = {}
	local channelsSeen: { [string]: boolean } = {}
	for _, keyframe in keyframes do
		local poses: { Pose } = {}
		collect(keyframe, poses, options.mapping)
		local entry: { [string]: any } = { Time = round(keyframe.Time, 3) }
		local easing: string? = nil
		for _, pose in poses do
			if pose.Weight <= 0 then
				continue
			end
			local values = numbers(pose.CFrame)
			if options.skipRest and isZero(values) and keyframe.Time > 0 and #out > 0 then
				-- A pose at rest is the default; leave it out, except at the
				-- start where it anchors the channel.
				continue
			end
			local channel = channelFor(pose.Name, options.mapping)
			-- Two poses mapped to one channel: the later one wins.
			entry[channel] = values
			channelsSeen[channel] = true
			if easing == nil and pose.EasingStyle ~= Enum.PoseEasingStyle.Linear then
				local style = STYLE[pose.EasingStyle.Name] or "Sine"
				easing = style
					.. (
						if pose.EasingDirection == Enum.PoseEasingDirection.In
							then "In"
							elseif pose.EasingDirection == Enum.PoseEasingDirection.Out then "Out"
							else ""
					)
			end
		end
		entry.Easing = easing
		table.insert(out, entry)
	end

	local data: { [string]: any } = { Keyframes = out }
	if sequence.Loop then
		data.Loop = true
	end
	local names = {}
	for name in channelsSeen do
		table.insert(names, name)
	end
	table.sort(names)

	local lines = {
		`{options.slot} = \{`,
		"\tKeyframes = {",
	}
	for _, entry in out do
		local keys = {}
		for key in entry do
			if key ~= "Time" and key ~= "Easing" then
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		local parts = { `Time = {entry.Time}` }
		for _, key in keys do
			table.insert(parts, `{key} = {Source.value(entry[key])}`)
		end
		if entry.Easing then
			table.insert(parts, `Easing = "{entry.Easing}"`)
		end
		table.insert(lines, `\t\t\{ {table.concat(parts, ", ")} },`)
	end
	table.insert(lines, "\t},")
	if data.Loop then
		table.insert(lines, "\tLoop = true,")
	end
	table.insert(lines, "},")
	return table.concat(lines, "\n"), `{#out} keyframes, channels: {table.concat(names, ", ")}.`
end

-- Adds an entry to the Animations table of a weapon module's source.
function Converter.insert(source: string, entry: string): string?
	local indented = "\t\t" .. string.gsub(entry, "\n", "\n\t\t")
	local opening = string.find(source, "Animations%s*=%s*{")
	if opening then
		local _, close = string.find(source, "Animations%s*=%s*{[^\n]*\n", opening)
		if close then
			return string.sub(source, 1, close) .. indented .. "\n" .. string.sub(source, close + 1)
		end
		return nil
	end
	local last = string.find(source, "\n}%s*$")
	if last == nil then
		return nil
	end
	return string.sub(source, 1, last) .. `\n\tAnimations = \{\n{indented}\n\t},` .. string.sub(source, last)
end

local function sequenceFrom(selected: Instance): (KeyframeSequence?, string?)
	if selected:IsA("KeyframeSequence") then
		return selected, nil
	end
	if selected:IsA("Animation") then
		local ok, result = pcall(function()
			return KeyframeSequenceProvider:GetKeyframeSequenceAsync(selected.AnimationId)
		end)
		if ok and result then
			return result :: KeyframeSequence, nil
		end
		return nil,
			"That animation could not be downloaded. Studio only gives plugins animations you own; paste its keyframes in as a KeyframeSequence instead."
	end
	for _, child in selected:GetChildren() do
		if child:IsA("KeyframeSequence") then
			return child, nil
		end
	end
	return nil, "Select a KeyframeSequence, or an Animation, in the Explorer."
end

function Converter.build(parent: Frame)
	local _, content = UI.scroll(parent)
	UI.heading(content, "Converter", 1)
	UI.caption(
		content,
		"Select a KeyframeSequence in the Explorer and turn it into an encoded animation: numbers in the weapon module, no uploaded asset.",
		2
	)

	local picked = UI.label(content, "Nothing selected.", { color = "muted", size = 12, order = 3 })
	local slot = "Reload"
	UI.section(content, "Plays for", 4)
	UI.segmented(content, SLOTS, slot, function(choice)
		slot = choice
	end, 5)

	UI.section(content, "Pose names", 6)
	UI.caption(
		content,
		"Poses named like a hand become Left or Right; Weapon, Gun and Handle move the whole weapon; any other name is taken to be a part of the weapon. Rename with one line each, Pose = Channel.",
		7
	)
	local mapBox = UI.input(
		content,
		"",
		function() end,
		{ placeholder = "Rig_R_Hand = Right", mono = true, order = 8 }
	)
	mapBox.MultiLine = true
	mapBox.TextYAlignment = Enum.TextYAlignment.Top
	mapBox.Size = UDim2.new(1, 0, 0, 64)

	local skipRest = true
	local skipRow = UI.row(content, Theme.rowHeight, Theme.space.sm, 9)
	UI.toggle(skipRow, true, function(value)
		skipRest = value
	end)
	UI.label(skipRow, "Leave out poses that are at rest", { size = 12, wrap = false }).Size =
		UDim2.new(1, -44, 0, 18)

	local actions = UI.row(content, Theme.rowHeight, Theme.space.sm, 10)
	local output = UI.code(content, "", 12)
	output.Visible = false
	local _, setStatus = UI.status(content, 11)
	local lastEntry: string? = nil

	local function currentSequence(): (KeyframeSequence?, string?)
		local selection = Selection:Get()
		if #selection == 0 then
			return nil, "Select a KeyframeSequence in the Explorer first."
		end
		return sequenceFrom(selection[1])
	end

	Selection.SelectionChanged:Connect(function()
		local selection = Selection:Get()
		picked.Text = if #selection == 0
			then "Nothing selected."
			else `Selected: {selection[1].Name} ({selection[1].ClassName})`
	end)

	UI.button(actions, "Convert", "primary", function()
		local sequence, problem = currentSequence()
		if sequence == nil then
			setStatus(problem or "Nothing to convert.", "bad")
			return
		end
		local mapping: { [string]: string } = {}
		for line in string.gmatch(mapBox.Text, "[^\n]+") do
			local from, to = string.match(line, "^%s*(.-)%s*=%s*(.-)%s*$")
			if from and to and from ~= "" and to ~= "" then
				mapping[from] = to
			end
		end
		local text, summary =
			Converter.convert(sequence, { slot = slot, mapping = mapping, skipRest = skipRest })
		if text == nil then
			setStatus(summary or "Conversion failed.", "bad")
			return
		end
		lastEntry = text
		output.Text = text
		output.Visible = true
		setStatus(summary or "", "good")
	end)

	UI.button(actions, "Add to selected weapon", "default", function()
		if lastEntry == nil then
			setStatus("Convert something first.", "warn")
			return
		end
		local target: ModuleScript? = nil
		for _, item in Selection:Get() do
			if item:IsA("ModuleScript") then
				target = item
				break
			end
		end
		if target == nil then
			setStatus("Select the weapon's module in the Explorer, then press this.", "warn")
			return
		end
		local updated = Converter.insert(target.Source, lastEntry)
		if updated == nil then
			setStatus(
				"That module's layout could not be edited automatically. Copy the text above into its Animations table.",
				"bad"
			)
			return
		end
		local recording = ChangeHistoryService:TryBeginRecording("Add encoded animation")
		target.Source = updated
		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		end
		setStatus(`Added to {target.Name}.`, "good")
	end)
end

return Converter
