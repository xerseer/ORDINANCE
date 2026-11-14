--!strict
--[[
	Helper tab
	Checks a weapon model for the attachments the animation system uses, and
	places any that are missing from the model's geometry.

	  MainHandle   where the trigger hand holds         (required)
	  Barrel       the muzzle                           (required)
	  Grip         where the support hand rests         (recommended)
	  Mag          the magazine; the hand goes here      (for reloads)
	  Side         the bolt or charging handle          (for cycling)
	  Aim          the sight line, centred behind the sight (for aiming)

	The handle's front (-Z) must point down the barrel and its top (+Y) up.
	Everything else is a position on the handle, in the handle's own space.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local Helper = { name = "IK Helper" }

local ATTACHMENTS = {
	{ name = "MainHandle", need = "required", note = "trigger hand" },
	{ name = "Barrel", need = "required", note = "muzzle; shots and flashes start here" },
	{ name = "Grip", need = "recommended", note = "support hand" },
	{ name = "Mag", need = "optional", note = "reload hand target" },
	{ name = "Side", need = "optional", note = "bolt or charging handle" },
	{ name = "Aim", need = "optional", note = "sight line when aiming" },
}

export type Report = { lines: { { text: string, kind: string } }, missing: { string }, handle: BasePart? }

local function findHandle(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local named = model:FindFirstChild("Handle", true)
	if named and named:IsA("BasePart") then
		return named
	end
	local best: BasePart? = nil
	local volume = -1
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Size.X * part.Size.Y * part.Size.Z > volume then
			best = part
			volume = part.Size.X * part.Size.Y * part.Size.Z
		end
	end
	return best
end

local function attachmentOf(model: Model, name: string): Attachment?
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == name then
			return descendant
		end
	end
	return nil
end

-- How far a part reaches along a world direction from its centre.
local function reach(part: BasePart, axis: Vector3): number
	local frame, half = part.CFrame, part.Size / 2
	return math.abs(frame.RightVector:Dot(axis)) * half.X
		+ math.abs(frame.UpVector:Dot(axis)) * half.Y
		+ math.abs(frame.LookVector:Dot(axis)) * half.Z
end

-- Extents of the whole model along the handle's axes: (min, max) per axis.
local function extents(model: Model, handle: BasePart): (Vector3, Vector3)
	local low, high = Vector3.one * math.huge, Vector3.one * -math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local centre = handle.CFrame:PointToObjectSpace(part.Position)
			local rx, ry, rz =
				reach(part, handle.CFrame.RightVector),
				reach(part, handle.CFrame.UpVector),
				reach(part, handle.CFrame.LookVector)
			low = Vector3.new(
				math.min(low.X, centre.X - rx),
				math.min(low.Y, centre.Y - ry),
				math.min(low.Z, centre.Z - rz)
			)
			high = Vector3.new(
				math.max(high.X, centre.X + rx),
				math.max(high.Y, centre.Y + ry),
				math.max(high.Z, centre.Z + rz)
			)
		end
	end
	return low, high
end

-- Where each missing attachment would go, in handle space.
local function guess(model: Model, handle: BasePart, name: string): CFrame?
	local low, high = extents(model, handle)
	local main = attachmentOf(model, "MainHandle")
	local mainPosition = if main then handle.CFrame:PointToObjectSpace(main.WorldPosition) else Vector3.zero
	local length = high.Z - low.Z
	local height = high.Y - low.Y
	if name == "MainHandle" then
		return CFrame.new(0, 0, 0)
	elseif name == "Barrel" then
		-- The forward-most point, level with the top of the receiver.
		return CFrame.new(0, math.clamp(mainPosition.Y + height * 0.35, low.Y, high.Y), low.Z)
	elseif name == "Grip" then
		return CFrame.new(mainPosition.X, mainPosition.Y + height * 0.2, mainPosition.Z - length * 0.3)
	elseif name == "Mag" then
		return CFrame.new(mainPosition.X, mainPosition.Y, mainPosition.Z - length * 0.1)
	elseif name == "Side" then
		return CFrame.new(
			mainPosition.X + (high.X - low.X) / 2,
			mainPosition.Y + height * 0.3,
			mainPosition.Z - length * 0.1
		)
	elseif name == "Aim" then
		return CFrame.new(mainPosition.X, high.Y, mainPosition.Z - length * 0.1)
	end
	return nil
end

function Helper.check(model: Model): Report
	local report: Report = { lines = {}, missing = {}, handle = nil }
	local function add(text: string, kind: string)
		table.insert(report.lines, { text = text, kind = kind })
	end

	local handle = findHandle(model)
	if handle == nil then
		add("The model has no parts.", "bad")
		return report
	end
	report.handle = handle
	if model.PrimaryPart == handle or handle.Name == "Handle" then
		add(`Handle: {handle.Name}`, "good")
	else
		add(
			`No part named Handle; the largest part, {handle.Name}, will be used. Name or set the PrimaryPart to the grip.`,
			"warn"
		)
	end

	for _, spec in ATTACHMENTS do
		local attachment = attachmentOf(model, spec.name)
		if attachment then
			add(`{spec.name}: found on {attachment.Parent and attachment.Parent.Name}`, "good")
		else
			table.insert(report.missing, spec.name)
			add(
				`{spec.name} ({spec.need}): missing, {spec.note}`,
				if spec.need == "required" then "bad" elseif spec.need == "recommended" then "warn" else "info"
			)
		end
	end

	local barrel = attachmentOf(model, "Barrel")
	local main = attachmentOf(model, "MainHandle")
	if barrel then
		local local_ = handle.CFrame:PointToObjectSpace(barrel.WorldPosition)
		if local_.Z > 0.05 then
			add(
				"Barrel is behind the Handle. The Handle's front (-Z) must point down the barrel; rotate the Handle.",
				"bad"
			)
		end
		if main and (barrel.WorldPosition - main.WorldPosition).Magnitude < 0.2 then
			add("Barrel and MainHandle are in the same place.", "warn")
		end
	end
	local anchored = 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Anchored then
			anchored += 1
		end
	end
	if anchored > 0 then
		add(
			`{anchored} parts are anchored. That is fine: Ordnance unanchors and joins them when the weapon loads.`,
			"info"
		)
	end
	return report
end

function Helper.addMissing(model: Model, names: { string }): number
	local handle = findHandle(model)
	if handle == nil then
		return 0
	end
	local added = 0
	-- MainHandle first: the others are placed relative to it.
	table.sort(names, function(a, b)
		return a == "MainHandle" and b ~= "MainHandle"
	end)
	for _, name in names do
		local frame = guess(model, handle, name)
		if frame and attachmentOf(model, name) == nil then
			local attachment = Instance.new("Attachment")
			attachment.Name = name
			attachment.CFrame = frame
			attachment.Visible = true
			attachment.Parent = handle
			added += 1
		end
	end
	return added
end

function Helper.build(parent: Frame)
	local _, content = UI.scroll(parent)
	UI.heading(content, "IK Helper", 1)
	UI.caption(
		content,
		"Select a weapon model. This lists the attachments the animation system uses and places the missing ones for you to adjust.",
		2
	)
	local selectedLabel = UI.label(content, "Nothing selected.", { color = "muted", size = 12, order = 3 })
	local actions = UI.row(content, Theme.rowHeight, Theme.space.sm, 4)
	local _, setStatus = UI.status(content, 5)
	local results = UI.column(content, 4, 6)

	local function currentModel(): Model?
		for _, item in Selection:Get() do
			if item:IsA("Model") then
				return item
			end
			local model = item:FindFirstAncestorOfClass("Model")
			if model then
				return model
			end
		end
		return nil
	end

	local function run(fix: boolean)
		local model = currentModel()
		if model == nil then
			setStatus("Select a weapon model in the Explorer.", "warn")
			return
		end
		if fix then
			local report = Helper.check(model)
			local recording = ChangeHistoryService:TryBeginRecording("Add weapon attachments")
			local count = Helper.addMissing(model, report.missing)
			if recording then
				ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
			end
			setStatus(
				`Added {count} attachments. They are shown in the viewport: drag each to the right spot.`,
				"good"
			)
		else
			setStatus("", "info")
		end

		results:ClearAllChildren()
		UI.stack(results, 4)
		for index, line in Helper.check(model).lines do
			local label = UI.label(results, line.text, { size = 12, order = index })
			UI.paint(label, {
				TextColor3 = if line.kind == "good"
					then "accent"
					elseif line.kind == "bad" then "danger"
					elseif line.kind == "warn" then "warn"
					else "muted",
			})
		end
	end

	UI.button(actions, "Check", "primary", function()
		run(false)
	end)
	UI.button(actions, "Add missing attachments", "default", function()
		run(true)
	end)
	UI.button(actions, "Show all", "ghost", function()
		local model = currentModel()
		if model then
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("Attachment") then
					descendant.Visible = true
				end
			end
		end
	end)

	Selection.SelectionChanged:Connect(function()
		local model = currentModel()
		selectedLabel.Text = if model then `Selected: {model.Name}` else "Nothing selected."
	end)
end

return Helper
