--[[
	Draws the first-person viewmodel as text, for checking poses when a
	screenshot is not available.

	It builds a temporary character of the requested rig type, shows the
	viewmodel for one weapon at the edit camera, and ray-traces the result
	into a grid of characters:

		#  weapon      R r  right arm, right hand      L l  left arm, left hand

	It also reports how far each hand's grip ended up from where it was asked
	to be, which should be zero.

	Run from the command bar while `rojo serve` is connected:
		print(require(game.ServerStorage.OrdnanceDev.PosePreview)("G36C", "R15", "Idle", 0, 0))

	Arguments: weapon name, "R15" or "R6", action ("Idle", "Equip", "Reload",
	"Cycle"), progress through the action 0 to 1, aim 0 to 1.
]]

local Players = game:GetService("Players")

local WIDTH, HEIGHT = 96, 40

return function(weaponName: string, rigType: string, action: string?, alpha: number?, aim: number?): string
	local clone = game:GetService("ReplicatedStorage").Ordnance:Clone()
	local Framework = clone.Framework
	local Config = require(Framework.Config)
	local Registry = require(Framework.Weapons.Registry)
	local Animator = require(Framework.Animation.Animator)
	local Arms = require(Framework.Animation.Arms)
	local Viewmodel = require(Framework.Client.Viewmodel)

	Config.load(clone)
	Registry.load(clone)
	local entry = Registry.get(weaponName)
	if entry == nil then
		clone:Destroy()
		return `no weapon named "{weaponName}"`
	end

	local character = Players:CreateHumanoidModelFromDescription(
		Instance.new("HumanoidDescription"),
		if rigType == "R6" then Enum.HumanoidRigType.R6 else Enum.HumanoidRigType.R15
	)
	character.Name = "OrdnancePreviewRig"
	character:PivotTo(CFrame.new(0, 500, 0))
	character.Parent = workspace

	local animator = Animator.new(entry)
	local now = os.clock()
	local duration = 2
	if action and action ~= "Idle" then
		animator:setAction(action, now - (alpha or 0) * duration, duration, false)
	end
	local pose = animator:update(now)

	Viewmodel.show(entry, animator.attachments, character)
	Viewmodel.setVisible(true)
	Viewmodel.update(1 / 60, pose, aim or 0, Vector3.zero, true)

	local camera = workspace.CurrentCamera
	local model = camera:FindFirstChild("OrdnanceViewmodel")
	local lines = {}
	if model == nil then
		table.insert(lines, "the viewmodel was not created")
	else
		-- What each part is, for the picture.
		local glyphs = {}
		local rig = Arms.describe(character)
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanQuery = true
				local name = part.Name
				local glyph = "#"
				if part.Parent == model then
					local right = string.find(name, "Right") ~= nil
					local hand = string.find(name, "Hand") ~= nil
					glyph = if right then (if hand then "r" else "R") else (if hand then "l" else "L")
				elseif part.Transparency >= 1 then
					glyph = ""
				end
				glyphs[part] = glyph
			end
		end

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { model }
		local size = camera.ViewportSize
		for row = 0, HEIGHT - 1 do
			local cells = table.create(WIDTH, " ")
			for column = 0, WIDTH - 1 do
				local ray =
					camera:ViewportPointToRay((column + 0.5) / WIDTH * size.X, (row + 0.5) / HEIGHT * size.Y)
				local origin = ray.Origin
				for _ = 1, 6 do
					local hit = workspace:Raycast(origin, ray.Direction * 12, params)
					if hit == nil then
						break
					end
					local glyph = glyphs[hit.Instance]
					if glyph ~= "" then
						cells[column + 1] = glyph or "?"
						break
					end
					origin = hit.Position + ray.Direction * 0.01
				end
			end
			table.insert(lines, (string.gsub(table.concat(cells), "%s+$", "")))
		end

		-- How well the hands landed on their targets.
		if rig then
			local handle = (model :: any).Weapon.PrimaryPart.CFrame
			for _, side in { "Right", "Left" } do
				local arm = (rig :: any)[string.lower(side)]
				local target = handle * (pose :: any)[string.lower(side)]
				local last = arm.parts[#arm.parts]
				local placed = model:FindFirstChild(last.Name)
				if placed and placed:IsA("BasePart") then
					local grip = placed.CFrame * arm.grip
					local offset = (grip.Position - target.Position).Magnitude
					local angle =
						math.deg(math.acos(math.clamp(grip.LookVector:Dot(target.LookVector), -1, 1)))
					table.insert(
						lines,
						string.format("%s grip: %.3f studs, %.1f degrees from target", side, offset, angle)
					)
				end
			end
			local cf = camera.CFrame
			for _, part in model:GetChildren() do
				if part:IsA("BasePart") then
					local p = cf:PointToObjectSpace(part.Position)
					table.insert(
						lines,
						string.format("  %-14s camera-space (%.2f, %.2f, %.2f)", part.Name, p.X, p.Y, p.Z)
					)
				end
			end
		end
	end

	Viewmodel.hide()
	character:Destroy()
	clone:Destroy()
	return table.concat(lines, "\n")
end
