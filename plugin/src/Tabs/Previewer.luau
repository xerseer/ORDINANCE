--!strict
--[[
	Previewer tab
	Plays a weapon's animations in a viewport, in first person (the viewmodel)
	or third person (a character), on R15 or R6, with a scrubber, play and
	pause, speed and an aim toggle.

	It runs the installed framework's own Animator and arm solver, so what
	moves here is what moves in game: encoded keyframes, procedural motion, or
	the blend of both, whichever the weapon uses.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Installer = require(script.Parent.Parent.Installer)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local Previewer = { name = "Previewer", _start = function() end, _stop = function() end }

local ACTIONS = { "Idle", "Equip", "Reload", "Reload (empty)", "Cycle", "Fire" }
local SPEEDS = { "0.25x", "0.5x", "1x", "2x" }
local SPEED_VALUE: { [string]: number } = { ["0.25x"] = 0.25, ["0.5x"] = 0.5, ["1x"] = 1, ["2x"] = 2 }

-- Where each shoulder lies from its wrist in first person; matches the game's viewmodel.
local RIGHT_SHOULDER = Vector3.new(0.38, -0.62, 0.7).Unit
local LEFT_SHOULDER = Vector3.new(-0.5, -0.55, 0.68).Unit
local RIGHT_POLE = Vector3.new(0.75, -0.65, 0.1)
local LEFT_POLE = Vector3.new(-0.75, -0.65, 0.1)
local TP_RIGHT_POLE = Vector3.new(0.55, -1, 0.45)
local TP_LEFT_POLE = Vector3.new(-0.65, -0.8, 0.3)

type Framework = {
	Config: any,
	Registry: any,
	Animator: any,
	Arms: any,
	Encoded: any,
}

local function loadFramework(): (Framework?, string?)
	local root = Installer.installed()
	if root == nil then
		return nil, "Install Ordnance first (Install tab)."
	end
	local ok, result = pcall(function()
		local framework = root.Framework
		return {
			Config = require(framework.Config),
			Registry = require(framework.Weapons.Registry),
			Animator = require(framework.Animation.Animator),
			Arms = require(framework.Animation.Arms),
			Encoded = require(framework.Animation.Encoded),
		}
	end)
	if not ok then
		return nil, "The installed Ordnance has no animation system. Update it from the Install tab."
	end
	return result :: Framework, nil
end

function Previewer.build(parent: Frame)
	local _, content = UI.scroll(parent)
	UI.heading(content, "Previewer", 1)
	UI.caption(
		content,
		"Pick a weapon and scrub through what it does. This is the installed framework's own animation code.",
		2
	)

	local weaponList = UI.row(content, 32, Theme.space.xs, 3)
	weaponList.AutomaticSize = Enum.AutomaticSize.None
	local chips = UI.make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 32),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		LayoutOrder = 3,
	}, content)
	weaponList:Destroy()
	UI.stack(chips, Theme.space.xs, true)

	local viewport = UI.make("ViewportFrame", {
		Size = UDim2.new(1, 0, 0, 300),
		BackgroundTransparency = 0,
		LayoutOrder = 4,
		Ambient = Color3.fromRGB(150, 150, 146),
		LightColor = Color3.fromRGB(235, 232, 220),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
	}, content)
	UI.paint(viewport, { BackgroundColor3 = "code", ImageColor3 = "fg" })
	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local world = Instance.new("WorldModel")
	world.Parent = viewport

	local timeline = UI.column(content, Theme.space.sm, 5)
	local playRow = UI.row(timeline, Theme.rowHeight, Theme.space.sm, 1)
	local track = UI.make("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 0,
		LayoutOrder = 2,
	}, timeline)
	UI.paint(track, { BackgroundColor3 = "surface" })
	local fill = UI.make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundTransparency = 0 }, track)
	UI.paint(fill, { BackgroundColor3 = "accentSoft" })
	local thumb = UI.make("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundTransparency = 0 }, track)
	UI.paint(thumb, { BackgroundColor3 = "accent" })
	local timeLabel = UI.label(timeline, "", { color = "muted", size = 12, order = 3 })

	local controls = UI.column(content, Theme.space.sm, 6)
	local _, setStatus = UI.status(content, 7)

	local fw: Framework? = nil
	local entry: any = nil
	local animator: any = nil
	local character: Model? = nil
	local weaponModel: Model? = nil
	local weaponRests: { [BasePart]: CFrame } = {}
	local rigType = "R15"
	local view = "First person"
	local action = "Reload"
	local aiming = false
	local playing = true
	local speed = 1
	local alpha = 0
	local dragging = false
	local connection: RBXScriptConnection? = nil

	local function durationOf(): number
		if entry == nil then
			return 1
		end
		local config = entry.config
		if action == "Equip" then
			return math.max(config.Handling.EquipTime, 0.2)
		elseif action == "Reload" or action == "Reload (empty)" then
			if config.Ammo.ReloadType == "Single" then
				return config.Ammo.ShellTime * 3
			end
			return if action == "Reload (empty)" and config.Ammo.ReloadEmptyTime > 0
				then config.Ammo.ReloadEmptyTime
				else config.Ammo.ReloadTime
		elseif action == "Cycle" then
			return math.max(config.Fire.CycleTime, 0.2)
		elseif action == "Fire" then
			return 0.25
		end
		return 2
	end

	local function clearScene()
		if character then
			character:Destroy()
			character = nil
		end
		if weaponModel then
			weaponModel:Destroy()
			weaponModel = nil
		end
		table.clear(weaponRests)
	end

	local function frame(values: { number }): CFrame
		return (fw :: Framework).Encoded.frame(values) or CFrame.identity
	end

	-- Places the weapon and both arms for the current moment.
	local function pose()
		local framework = fw
		local char = character
		local weapon = weaponModel
		if framework == nil or entry == nil or animator == nil or char == nil or weapon == nil then
			return
		end
		local config = entry.config
		local now = os.clock()
		local duration = durationOf()
		if action == "Idle" then
			animator:setAction("Idle", now, 0)
		elseif action == "Fire" then
			animator:setAction("Idle", now, 0)
			animator:fire(now - alpha * duration)
		else
			animator:setAction(
				string.gsub(action, " %(empty%)", ""),
				now - alpha * duration,
				duration,
				action == "Reload (empty)"
			)
		end
		local current = animator:update(now - (if action == "Idle" then alpha * duration else 0))
		local attachments = animator.attachments

		local arms = framework.Arms.describe(char)
		if arms == nil then
			return
		end
		local firstPerson = view == "First person"
		local base = CFrame.identity
		local desired: CFrame
		local rightPole, leftPole = TP_RIGHT_POLE, TP_LEFT_POLE
		if firstPerson then
			local hip = frame(config.Viewmodel.Offset)
			local aimed = if attachments.aim
				then CFrame.new(0, 0, -config.Viewmodel.AimDistance) * attachments.aim:Inverse()
				else CFrame.new(0, hip.Y * 0.7, hip.Z)
			local eased = if aiming then 1 else 0
			desired = base * hip:Lerp(aimed, eased) * current.weapon
			rightPole, leftPole = RIGHT_POLE, LEFT_POLE
		else
			local rootFrame = arms.root.CFrame
			local eye = rootFrame * CFrame.new(0, 1.5, 0)
			local hip = frame(config.ThirdPerson.Offset)
			local aimed = frame(config.ThirdPerson.AimOffset)
			desired = eye * (if aiming then aimed else hip) * current.weapon
		end

		local function solve(arm: any, grip: CFrame, direction: Vector3?, polePole: Vector3): { CFrame }
			local shoulder: Vector3
			if direction then
				-- First person: the shoulder floats behind the wrist by the arm's reach.
				local reach: number
				local wrist: Vector3
				if arm.rig == "R15" then
					reach = (arm.upperLength + arm.lowerLength) * 0.93
					wrist = (grip * arm.grip:Inverse()) * arm.handTop
				else
					reach = (arm.grip.Position - arm.pivot).Magnitude
					wrist = grip.Position
				end
				shoulder = wrist + base:VectorToWorldSpace(direction) * reach
			else
				shoulder = framework.Arms.shoulderOf(arm)
			end
			return framework.Arms.solve(arm, shoulder, grip, base:VectorToWorldSpace(polePole))
		end

		local rightFrames = solve(
			arms.right,
			desired * attachments.main,
			if firstPerson then RIGHT_SHOULDER else nil,
			rightPole
		)
		framework.Arms.place(arms.right.parts, rightFrames)
		local actual = desired
		if not firstPerson then
			actual = rightFrames[#rightFrames] * arms.right.grip * attachments.main:Inverse()
		end
		local leftGrip = actual * current.left
		if not firstPerson then
			leftGrip = framework.Arms.withinReach(
				arms.left,
				framework.Arms.shoulderOf(arms.left),
				leftGrip,
				(actual * attachments.main).Position
			)
		end
		framework.Arms.place(
			arms.left.parts,
			solve(arms.left, leftGrip, if firstPerson then LEFT_SHOULDER else nil, leftPole)
		)

		for part, rest in weaponRests do
			local offset = current.parts[part.Name]
			part.CFrame = actual * (if offset then framework.Animator.partFrame(rest, offset) else rest)
		end

		timeLabel.Text = string.format(
			"%s   %.2fs of %.2fs   %s%s",
			action,
			alpha * duration,
			duration,
			view,
			if aiming then ", aiming" else ""
		)
		fill.Size = UDim2.fromScale(alpha, 1)
		thumb.Position = UDim2.new(alpha, -1, 0, 0)

		if firstPerson then
			camera.FieldOfView = 70
			camera.CFrame = CFrame.new(Vector3.zero, -Vector3.zAxis)
		else
			camera.FieldOfView = 40
			camera.CFrame = CFrame.lookAt(Vector3.new(5.5, 2.4, -3.5), Vector3.new(0, 0.6, -1.2))
		end
	end

	local function buildScene()
		clearScene()
		local framework = fw
		if framework == nil or entry == nil then
			return
		end
		task.spawn(function()
			local ok, rig = pcall(function()
				return Players:CreateHumanoidModelFromDescription(
					Instance.new("HumanoidDescription"),
					if rigType == "R6" then Enum.HumanoidRigType.R6 else Enum.HumanoidRigType.R15
				)
			end)
			if not ok then
				setStatus("The preview character could not be created: " .. tostring(rig), "bad")
				return
			end
			clearScene()
			local body = rig :: Model
			body.Name = "PreviewCharacter"
			for _, item in body:GetDescendants() do
				if item:IsA("BaseScript") then
					item:Destroy()
				elseif item:IsA("BasePart") then
					item.Anchored = true
				end
			end
			body:PivotTo(CFrame.new(0, 3, 0))
			-- First person shows arms only.
			local arms = framework.Arms.describe(body)
			if view == "First person" and arms then
				local visible: { [Instance]: boolean } = {}
				for _, arm in { arms.right, arms.left } do
					for _, part in arm.parts do
						visible[part] = true
					end
				end
				for _, item in body:GetDescendants() do
					if item:IsA("BasePart") and not visible[item] then
						item.Transparency = 1
					end
				end
			end
			body.Parent = world
			character = body

			local weapon = entry.template:Clone()
			local handle = weapon.PrimaryPart :: BasePart
			for _, item in weapon:GetDescendants() do
				if item:IsA("JointInstance") or item:IsA("WeldConstraint") then
					item:Destroy()
				end
			end
			for _, item in weapon:GetDescendants() do
				if item:IsA("BasePart") then
					item.Anchored = true
					weaponRests[item] = handle.CFrame:ToObjectSpace(item.CFrame)
				end
			end
			weapon.Parent = world
			weaponModel = weapon
			animator = framework.Animator.new(entry)
			pose()
		end)
	end

	local function chooseWeapon(id: string)
		local framework = fw
		if framework == nil then
			return
		end
		entry = framework.Registry.get(id)
		if entry == nil then
			return
		end
		local mode = entry.config.Animation.Mode
		setStatus(`{entry.config.Name}: {string.lower(mode)} animation.`, "info")
		buildScene()
	end

	local function tick(deltaTime: number)
		if playing and not dragging and animator then
			alpha += deltaTime * speed / math.max(durationOf(), 0.05)
			if alpha >= 1 then
				alpha = 0
			end
		end
		pose()
	end

	local function setScrub(positionX: number)
		local width = track.AbsoluteSize.X
		if width > 0 then
			alpha = math.clamp((positionX - track.AbsolutePosition.X) / width, 0, 1)
			pose()
		end
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setScrub(input.Position.X)
		end
	end)
	track.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			setScrub(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	local playButton = UI.button(playRow, "Pause", "default", function() end)
	playButton.Activated:Connect(function()
		playing = not playing
		playButton.Text = if playing then "Pause" else "Play"
	end)
	UI.segmented(playRow, SPEEDS, "1x", function(choice)
		speed = SPEED_VALUE[choice]
	end)

	local function labelled(text: string, order: number): Frame
		local row = UI.row(controls, Theme.rowHeight, Theme.space.sm, order)
		UI.label(row, text, { color = "muted", size = 12, wrap = false, width = 58 })
		return row
	end
	UI.segmented(labelled("Plays", 1), ACTIONS, action, function(choice)
		action = choice
		alpha = 0
	end)
	UI.segmented(labelled("View", 2), { "First person", "Third person" }, view, function(choice)
		view = choice
		buildScene()
	end)
	UI.segmented(labelled("Rig", 3), { "R15", "R6" }, rigType, function(choice)
		rigType = choice
		buildScene()
	end)
	local aimRow = labelled("Aim", 4)
	UI.toggle(aimRow, false, function(value)
		aiming = value
	end)

	local function reload()
		for _, child in chips:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		local framework, problem = loadFramework()
		fw = framework
		if framework == nil then
			setStatus(problem or "", "bad")
			return
		end
		local root = Installer.installed() :: Instance
		local ok, err = pcall(function()
			framework.Config.load(root)
			framework.Registry.load(root)
		end)
		if not ok then
			setStatus("The weapons could not be loaded: " .. tostring(err), "bad")
			return
		end
		local ids = framework.Registry.ids()
		if #ids == 0 then
			setStatus("No weapons in Ordnance.Weapons yet.", "warn")
			return
		end
		for index, id in ids do
			local chip = UI.button(chips, id, "default", function()
				chooseWeapon(id)
			end, index)
			chip.TextSize = 12
		end
		if entry == nil or framework.Registry.get(entry.id) == nil then
			chooseWeapon(ids[1])
		else
			chooseWeapon(entry.id)
		end
	end

	UI.button(content, "Reload weapons", "ghost", reload, 8)

	Previewer._start = function()
		if connection == nil then
			connection = RunService.Heartbeat:Connect(tick)
		end
		reload()
	end
	Previewer._stop = function()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end
end

function Previewer.onShow()
	Previewer._start()
end

function Previewer.onHide()
	Previewer._stop()
end

return Previewer
