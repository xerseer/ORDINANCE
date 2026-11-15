--!strict
--[[
	Setup tab
	A step-by-step way to turn any gun model into an Ordnance weapon.

	  1. Select the model and press Start setup.
	  2. Name it. Every part is gathered directly under one model.
	  3. Click parts in the viewport and press Select for each: the grip, the
	     muzzle and the sight (needed), then the magazine, the support hand and
	     a slide or bolt (each can be skipped).
	  4. Pick what kind of weapon it is and press Finish.

	The grip, muzzle and sight say which way the gun faces, so the model can be
	lying in any direction. Where you click on each part is used, not its
	centre, because kit models often put a whole gun in one mesh.

	Finish adds an invisible Handle with the attachments the animation system
	reads, names the moving parts, renames the rest Part1, Part2..., and puts
	the model in a new weapon module in Ordnance.Weapons. Every step is one
	undo.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CoreGui = game:GetService("CoreGui")
local Selection = game:GetService("Selection")

local Installer = require(script.Parent.Parent.Installer)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local Setup = { name = "Setup" }

type Pick = { part: BasePart, point: Vector3 }

type Step = {
	key: string,
	title: string,
	prompt: string,
	required: boolean,
}

local STEPS: { Step } = {
	{
		key = "grip",
		title = "Grip",
		prompt = "Click where the trigger hand holds: the pistol grip, or the grip of a pistol.",
		required = true,
	},
	{
		key = "muzzle",
		title = "Muzzle",
		prompt = "Click the very front of the barrel, or the muzzle device on it.",
		required = true,
	},
	{
		key = "sight",
		title = "Sight",
		prompt = "Click the rear sight, or the top of the receiver if there is no sight. This is where the eye goes when aiming, and it tells the setup which way is up.",
		required = true,
	},
	{
		key = "mag",
		title = "Magazine",
		prompt = "Click the magazine. If it is its own part it drops out on reloads. Skip it if the weapon has none.",
		required = false,
	},
	{
		key = "support",
		title = "Support hand",
		prompt = "Click where the other hand holds: the handguard, the pump or a foregrip. Skip it for a pistol.",
		required = false,
	},
	{
		key = "moving",
		title = "Slide or bolt",
		prompt = "Click the slide, bolt or pump if it is its own part. It moves when firing.",
		required = false,
	},
}

local KINDS = { "Rifle", "SMG", "Pistol", "Shotgun", "Sniper" }

local TEMPLATES: { [string]: string } = {
	Rifle = [[
	Fire = {
		Mode = "Auto",
		Modes = { "Auto", "Semi" },
		RPM = 700,
	},

	Ammo = {
		Magazine = 30,
		Reserve = 150,
		ReloadTime = 2.2,
	},

	Damage = {
		Base = 24,
		Falloff = { Start = 150, End = 500 },
	},
]],
	SMG = [[
	Fire = {
		Mode = "Auto",
		Modes = { "Auto", "Semi" },
		RPM = 850,
	},

	Ammo = {
		Magazine = 30,
		Reserve = 150,
		ReloadTime = 2.0,
	},

	Damage = {
		Base = 18,
		Falloff = { Start = 60, End = 200 },
	},

	Recoil = {
		Vertical = 0.6,
		Horizontal = 0.4,
	},
]],
	Pistol = [[
	Fire = {
		Modes = { "Semi" },
		RPM = 400,
	},

	Ammo = {
		Magazine = 15,
		Reserve = 60,
		ReloadTime = 1.6,
	},

	Damage = {
		Base = 26,
		Falloff = { Start = 60, End = 220 },
	},

	Recoil = {
		Vertical = 1.4,
		Horizontal = 0.5,
	},

	Viewmodel = {
		Offset = { 0.42, -0.58, -1.6, 0, 0, 0 },
		AimDistance = 1.5,
	},

	ThirdPerson = {
		Offset = { 0.28, -0.5, -1.0, 0, 5, 0 },
		AimOffset = { 0.06, -0.36, -1.15, 0, 0, 0 },
		BodyTurn = 12,
	},
]],
	Shotgun = [[
	Fire = {
		Modes = { "Semi" },
		RPM = 240,
		Pellets = 8,
		Action = "Pump",
		CycleTime = 0.55,
	},

	Ammo = {
		Magazine = 6,
		Reserve = 30,
		ReloadType = "Single",
		ShellTime = 0.5,
	},

	Ballistics = {
		Range = 260,
	},

	Damage = {
		Base = 13,
		Falloff = { Start = 25, End = 110, MinScale = 0.2 },
	},

	Spread = {
		Hip = 4.2,
		Aim = 3.2,
		PerShot = 0,
	},

	Recoil = {
		Vertical = 3.6,
		Horizontal = 1.1,
	},
]],
	Sniper = [[
	Fire = {
		Modes = { "Semi" },
		RPM = 50,
		Action = "Bolt",
		CycleTime = 1.1,
	},

	Ammo = {
		Magazine = 5,
		Reserve = 25,
		ReloadTime = 3,
	},

	Ballistics = {
		Range = 2500,
		Penetration = 2,
	},

	Damage = {
		Base = 85,
		Multipliers = { Head = 2.5, Torso = 1, Limb = 0.8 },
		Falloff = { Start = 400, End = 1500, MinScale = 0.7 },
	},

	Spread = {
		Hip = 5,
		Aim = 0.05,
	},

	Recoil = {
		Vertical = 3.5,
		Horizontal = 1,
	},

	Handling = {
		AimFOV = 20,
	},
]],
}

-- A tidy module name from whatever the user typed.
local function identifier(name: string): string
	local id = string.gsub(name, "[^%w]", "")
	if id == "" or string.match(id, "^%d") then
		id = "Weapon" .. id
	end
	return id
end

-- Of a part's three axes, the one closest to `direction`, pointing the same way.
local function snap(part: BasePart, direction: Vector3, exclude: Vector3?): Vector3
	local best, bestDot = direction, 0
	for _, axis in { part.CFrame.RightVector, part.CFrame.UpVector, part.CFrame.LookVector } do
		if exclude == nil or math.abs(axis:Dot(exclude)) < 0.5 then
			local dot = axis:Dot(direction)
			if math.abs(dot) > math.abs(bestDot) then
				best = if dot >= 0 then axis else -axis
				bestDot = dot
			end
		end
	end
	-- Only snap when the part is close to lined up; otherwise trust the clicks.
	return if math.abs(bestDot) > 0.9 then best else direction
end

-- How far a part reaches from its centre along `axis`.
local function reach(part: BasePart, axis: Vector3): number
	local frame, half = part.CFrame, part.Size / 2
	return math.abs(frame.RightVector:Dot(axis)) * half.X
		+ math.abs(frame.UpVector:Dot(axis)) * half.Y
		+ math.abs(frame.LookVector:Dot(axis)) * half.Z
end

local function parts(model: Model): { BasePart }
	local result = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(result, descendant)
		end
	end
	return result
end

--[[
	Puts every part directly under `model`, keeping what is inside each part
	(meshes, textures, attachments), and removes the empty folders and models
	left behind. Joints are removed: Ordnance joins the parts itself.
]]
function Setup.gather(model: Model): number
	local moved = 0
	for _, part in parts(model) do
		if part.Parent ~= model then
			part.Parent = model
			moved += 1
		end
	end
	for _, child in model:GetChildren() do
		if not child:IsA("BasePart") then
			child:Destroy()
		end
	end
	for _, part in parts(model) do
		for _, joint in part:GetChildren() do
			if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
				joint:Destroy()
			end
		end
	end
	return moved
end

--[[
	Builds the Handle and attachments from the picks and names the parts.
	Returns the weapon frame (for tests) or nil and a reason.
]]
function Setup.rig(model: Model, picks: { [string]: Pick }, movingName: string): (CFrame?, string?)
	local grip, muzzle, sight = picks.grip, picks.muzzle, picks.sight
	if grip == nil or muzzle == nil or sight == nil then
		return nil, "The grip, muzzle and sight are needed."
	end

	-- Which way the gun faces, from the grip to the muzzle, lined up with the
	-- muzzle part where it is close; then up, toward the sight.
	local towardMuzzle = muzzle.point - grip.point
	if towardMuzzle.Magnitude < 0.1 then
		return nil, "The grip and the muzzle are in the same place."
	end
	local forward = snap(muzzle.part, towardMuzzle.Unit)
	local towardSight = sight.point - grip.point
	local upward = towardSight - forward * towardSight:Dot(forward)
	if upward.Magnitude < 0.05 then
		return nil, "The sight is level with the grip; pick the top of the weapon for the sight."
	end
	local up = snap(sight.part, upward.Unit, forward)
	up = (up - forward * up:Dot(forward)).Unit
	local right = forward:Cross(up)
	local rotation = CFrame.fromMatrix(Vector3.zero, right, up, -forward)

	-- Centre the handle across the gun's width; keep the click's height and depth.
	local low, high = math.huge, -math.huge
	for _, part in parts(model) do
		local across = part.Position:Dot(right)
		local extent = reach(part, right)
		low = math.min(low, across - extent)
		high = math.max(high, across + extent)
	end
	local centreAcross = (low + high) / 2
	local function centred(point: Vector3): Vector3
		return point + right * (centreAcross - point:Dot(right))
	end
	local handleFrame = rotation + centred(grip.point)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.one * 0.2
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Anchored = true
	handle.CFrame = handleFrame
	handle.Parent = model
	model.PrimaryPart = handle

	local function attach(name: string, point: Vector3)
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.CFrame = CFrame.new(handleFrame:PointToObjectSpace(point))
		attachment.Visible = true
		attachment.Parent = handle
	end
	attach("MainHandle", handleFrame.Position)
	-- The muzzle is the front of the muzzle part, level with where it was clicked.
	local clicked = centred(muzzle.point)
	local tip =
		math.max(muzzle.part.Position:Dot(forward) + reach(muzzle.part, forward), clicked:Dot(forward))
	attach("Barrel", clicked + forward * (tip - clicked:Dot(forward)))
	attach("Aim", centred(sight.point) + up * 0.04)
	if picks.mag then
		attach("Mag", centred(picks.mag.point))
	end
	if picks.support then
		attach("Grip", centred(picks.support.point))
	end

	-- Names: the moving parts get theirs, everything else is numbered.
	local named: { [BasePart]: string } = {}
	local roles: { [BasePart]: number } = {}
	for _, pick in picks do
		roles[pick.part] = (roles[pick.part] or 0) + 1
	end
	-- A part only gets a moving-part name if it was picked for nothing else.
	if picks.mag and roles[picks.mag.part] == 1 then
		named[picks.mag.part] = "Mag"
	end
	if picks.moving and roles[picks.moving.part] == 1 then
		named[picks.moving.part] = movingName
	end
	local count = 0
	for _, part in parts(model) do
		if part ~= handle then
			local name = named[part]
			if name then
				part.Name = name
			else
				count += 1
				part.Name = `Part{count}`
			end
		end
	end
	return handleFrame, nil
end

-- The new weapon module's source.
function Setup.source(name: string, kind: string, scale: number): string
	local lines = {
		"--[[",
		`\t{name}`,
		"\tMade with the Ordnance Setup tab. Anything not written here comes from",
		"\tOrdnance.Config and the framework defaults; the docs list every setting.",
		"]]",
		"",
		"return {",
		`\tName = "{string.gsub(name, '"', '\\"')}",`,
		`\tDescription = "",`,
	}
	if math.abs(scale - 1) > 1e-3 then
		table.insert(lines, `\tScale = {string.format("%g", scale)},`)
	end
	table.insert(lines, "")
	table.insert(lines, (string.gsub(TEMPLATES[kind] or TEMPLATES.Rifle, "\n$", "")))
	table.insert(lines, "}")
	return table.concat(lines, "\n") .. "\n"
end

------------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------------

local pluginRef: Plugin? = nil

function Setup.setPlugin(value: Plugin)
	pluginRef = value
end

function Setup.build(parent: Frame)
	local _, content = UI.scroll(parent)
	UI.heading(content, "Set up a weapon", 1)
	UI.caption(
		content,
		"Turns any gun model into an Ordnance weapon, a step at a time. The model can be lying in any direction.",
		2
	)
	local body = UI.column(content, Theme.space.sm, 3)
	local _, setStatus = UI.status(content, 4)

	-- State of the run in progress.
	local model: Model? = nil
	local weaponName = ""
	local picks: { [string]: Pick } = {}
	local stepIndex = 0
	local kind = "Rifle"
	local movingName = "Slide"
	local scale = 1
	local lastClick: Pick? = nil
	local marks: Folder? = nil
	local mouseConnection: RBXScriptConnection? = nil

	local function clearMarks()
		if marks then
			marks:Destroy()
			marks = nil
		end
	end

	local function mark(part: BasePart, point: Vector3)
		if marks == nil then
			local folder = Instance.new("Folder")
			folder.Name = "OrdnanceSetupMarks"
			folder.Parent = CoreGui
			marks = folder
		end
		local box = Instance.new("SelectionBox")
		box.Adornee = part
		box.LineThickness = 0.02
		box.Color3 = Theme.palette().accent
		box.Parent = marks
		local dot = Instance.new("Part")
		dot.Shape = Enum.PartType.Ball
		dot.Size = Vector3.one * 0.12
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.Material = Enum.Material.Neon
		dot.Color = Theme.palette().accent
		dot.Position = point
		dot.Archivable = false
		dot.Parent = workspace.CurrentCamera
		local holder = Instance.new("ObjectValue")
		holder.Value = dot
		holder.Parent = marks
		holder.Destroying:Connect(function()
			dot:Destroy()
		end)
	end

	-- While picking, clicks in the viewport choose a part of the model and
	-- remember the point clicked.
	local function startPicking()
		local active = pluginRef
		if active == nil or mouseConnection then
			return
		end
		active:Activate(true)
		local mouse = active:GetMouse()
		mouseConnection = mouse.Button1Down:Connect(function()
			local target = mouse.Target
			local current = model
			if target and current and target:IsDescendantOf(current) and target:IsA("BasePart") then
				lastClick = { part = target, point = mouse.Hit.Position }
				Selection:Set({ target })
			end
		end)
	end

	local function stopPicking()
		if mouseConnection then
			mouseConnection:Disconnect()
			mouseConnection = nil
		end
		if pluginRef then
			pluginRef:Deactivate()
		end
	end

	local render: () -> ()

	local function reset(message: string?, kindOfMessage: string?)
		stopPicking()
		clearMarks()
		model = nil
		picks = {}
		stepIndex = 0
		lastClick = nil
		render()
		setStatus(message or "", kindOfMessage or "info")
	end

	local function selectedModel(): Model?
		for _, item in Selection:Get() do
			if item:IsA("Model") then
				return item
			end
			local ancestor = item:FindFirstAncestorOfClass("Model")
			if ancestor and ancestor ~= workspace then
				return ancestor
			end
		end
		return nil
	end

	local function startSetup()
		local chosen = selectedModel()
		if chosen == nil then
			setStatus("Select the gun model in the Explorer or the viewport first.", "warn")
			return
		end
		if #parts(chosen) == 0 then
			setStatus("That model has no parts.", "warn")
			return
		end
		model = chosen
		weaponName = chosen.Name
		picks = {}
		stepIndex = 0
		render()
		setStatus("", "info")
	end

	local function confirmName()
		local current = model
		if current == nil then
			return
		end
		if string.gsub(weaponName, "%s", "") == "" then
			setStatus("Give the weapon a name.", "warn")
			return
		end
		local root = Installer.installed()
		local folder = if root then root:FindFirstChild("Weapons") else nil
		if folder and folder:FindFirstChild(identifier(weaponName)) then
			setStatus(`A weapon called {identifier(weaponName)} already exists. Pick another name.`, "warn")
			return
		end
		local recording = ChangeHistoryService:TryBeginRecording("Ordnance setup: gather parts")
		local moved = Setup.gather(current)
		current.Name = weaponName
		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		end
		stepIndex = 1
		lastClick = nil
		startPicking()
		render()
		setStatus(if moved > 0 then `Gathered {moved} parts into one model.` else "", "good")
	end

	local function choose()
		local step = STEPS[stepIndex]
		local current = model
		if step == nil or current == nil then
			return
		end
		local selected = Selection:Get()[1]
		if selected == nil or not selected:IsA("BasePart") or not selected:IsDescendantOf(current) then
			setStatus("Click a part of the weapon in the viewport first.", "warn")
			return
		end
		local point = if lastClick and lastClick.part == selected then lastClick.point else selected.Position
		picks[step.key] = { part = selected, point = point }
		mark(selected, point)
		stepIndex += 1
		lastClick = nil
		Selection:Set({})
		if stepIndex > #STEPS then
			stopPicking()
		end
		render()
		setStatus(`{step.title}: {selected.Name}`, "good")
	end

	local function skip()
		local step = STEPS[stepIndex]
		if step == nil or step.required then
			return
		end
		picks[step.key] = nil
		stepIndex += 1
		if stepIndex > #STEPS then
			stopPicking()
		end
		render()
		setStatus(`{step.title}: skipped`, "info")
	end

	local function back()
		if stepIndex <= 1 then
			stepIndex = 0
			stopPicking()
		else
			stepIndex -= 1
			local step = STEPS[stepIndex]
			picks[step.key] = nil
			startPicking()
		end
		render()
	end

	local function finish()
		local current = model
		if current == nil then
			return
		end
		local root = Installer.installed()
		local recording = ChangeHistoryService:TryBeginRecording("Ordnance setup: make weapon")
		local ok, result, reason = pcall(Setup.rig, current, picks, movingName)
		if not ok or result == nil then
			if recording then
				ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
			end
			setStatus(
				if ok then reason or "Could not set the weapon up." else `Setup failed: {result}`,
				"danger"
			)
			return
		end

		local module = Instance.new("ModuleScript")
		module.Name = identifier(weaponName)
		module.Source = Setup.source(weaponName, kind, scale)
		current.Name = "Model"
		current.Parent = module
		local folder = if root then root:FindFirstChild("Weapons") else nil
		module.Parent = folder or game:GetService("ServerStorage")
		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		end
		Selection:Set({ module })
		local where = if folder
			then "It is in Ordnance.Weapons and loads at the next Play."
			else "Ordnance is not installed, so it was put in ServerStorage; move it into Ordnance.Weapons."
		reset(
			`{module.Name} is ready. {where} The attachments are shown on the model: drag any that are off. The IK Helper tab can check it.`,
			"good"
		)
	end

	function render()
		body:ClearAllChildren()
		UI.stack(body, Theme.space.sm)
		local current = model

		if current == nil then
			UI.label(
				body,
				"Select the gun model in the Explorer or the viewport, then start. Its parts can be anything: MeshParts, Parts with meshes, unions, nested models.",
				{ color = "muted", size = 12, order = 1 }
			)
			local row = UI.row(body, Theme.rowHeight, Theme.space.sm, 2)
			UI.button(row, "Start setup", "primary", startSetup)
			return
		end

		local progress = if stepIndex == 0
			then "Step 1: name"
			elseif stepIndex <= #STEPS then `Step {stepIndex + 1} of {#STEPS + 2}: {STEPS[stepIndex].title}`
			else `Step {#STEPS + 2}: finish`
		UI.section(body, progress, 1)

		if stepIndex == 0 then
			UI.label(
				body,
				"What is the weapon called? This is the name players see; the module is named from it.",
				{ color = "muted", size = 12, order = 2 }
			)
			UI.input(body, weaponName, function(text)
				weaponName = text
			end, { order = 3, placeholder = "AK-47" })
			local row = UI.row(body, Theme.rowHeight, Theme.space.sm, 4)
			UI.button(row, "Next", "primary", confirmName)
			UI.button(row, "Cancel", "ghost", function()
				reset()
			end)
			return
		end

		if stepIndex <= #STEPS then
			local step = STEPS[stepIndex]
			UI.label(body, step.prompt, { size = 12, order = 2 })
			UI.label(
				body,
				"Click the part in the viewport, then press Select. Where you click is used, so click the right spot on it.",
				{ color = "muted", size = 12, order = 3 }
			)
			if step.key == "moving" then
				UI.segmented(body, { "Slide", "Bolt", "Pump" }, movingName, function(choice)
					movingName = choice
				end, 4)
			end
			local row = UI.row(body, Theme.rowHeight, Theme.space.sm, 5)
			UI.button(row, "Select", "primary", choose)
			if not step.required then
				UI.button(row, "Skip", "default", skip)
			end
			UI.button(row, "Back", "ghost", back)
			UI.button(row, "Cancel", "ghost", function()
				reset("Setup cancelled. Ctrl+Z undoes the gathering of parts.", "info")
			end)
			return
		end

		-- Finish: kind, size, and a summary.
		UI.label(body, "What kind of weapon is it? This picks starting numbers you can change later.", {
			color = "muted",
			size = 12,
			order = 2,
		})
		UI.segmented(body, KINDS, kind, function(choice)
			kind = choice
		end, 3)

		local length = 0
		local grip, muzzle = picks.grip, picks.muzzle
		if grip and muzzle then
			length = (muzzle.point - grip.point).Magnitude
		end
		UI.label(
			body,
			string.format(
				"Grip to muzzle: %.1f studs. A rifle is about 2.2 at the scale of a Roblox character, a pistol about 0.9. Scale resizes the whole model.",
				length
			),
			{ color = "muted", size = 12, order = 4 }
		)
		local scaleRow = UI.row(body, Theme.rowHeight, Theme.space.sm, 5)
		UI.label(scaleRow, "Scale", { width = 60 })
		UI.number(scaleRow, scale, 0.1, 10, function(value)
			scale = value
		end)

		local summary = {}
		for _, step in STEPS do
			local pick = picks[step.key]
			table.insert(summary, `{step.title}: {if pick then pick.part.Name else "skipped"}`)
		end
		UI.label(body, table.concat(summary, "\n"), { size = 12, order = 6 })

		local row = UI.row(body, Theme.rowHeight, Theme.space.sm, 7)
		UI.button(row, "Finish", "primary", finish)
		UI.button(row, "Back", "ghost", back)
		UI.button(row, "Cancel", "ghost", function()
			reset("Setup cancelled. Ctrl+Z undoes the gathering of parts.", "info")
		end)
	end

	render()
end

function Setup.onHide()
	-- Leave the viewport's own tools working when the tab is not showing.
	if pluginRef then
		pluginRef:Deactivate()
	end
end

return Setup
