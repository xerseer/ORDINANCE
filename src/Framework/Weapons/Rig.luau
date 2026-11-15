--!strict
--[[
	Rig
	Turns whatever model a weapon ships with into something the framework can
	hold, weld and fire from.

	A weapon model needs very little:
	  - a part named "Handle" (or a PrimaryPart). Its front face (-Z) points
	    down the barrel and its top face (+Y) points up.
	  - optionally, attachments on the handle:
	        MainHandle   where the trigger hand holds
	        Barrel       the muzzle
	        Grip         where the support hand holds
	        Side         a second support-hand spot (bolt, charging handle)
	        Mag          the magazine
	Anything missing is worked out from the geometry, and every other part is
	welded to the handle here, so models do not need welds of their own.
]]

local Logger = require(script.Parent.Parent.Core.Logger)

local log = Logger.scope("Rig")

local Rig = {}

Rig.Attachments = table.freeze({ "MainHandle", "Barrel", "Grip", "Side", "Mag" })

local HANDLE_NAMES = { "Handle", "MainHandle" }

local function findHandle(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	for _, name in HANDLE_NAMES do
		local found = model:FindFirstChild(name, true)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	local largest: BasePart? = nil
	local largestVolume = -1
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local volume = descendant.Size.X * descendant.Size.Y * descendant.Size.Z
			if volume > largestVolume then
				largest = descendant
				largestVolume = volume
			end
		end
	end
	return largest
end

-- How far a part reaches along `axis` from its centre.
local function reach(part: BasePart, axis: Vector3): number
	local frame = part.CFrame
	local half = part.Size / 2
	return math.abs(frame.RightVector:Dot(axis)) * half.X
		+ math.abs(frame.UpVector:Dot(axis)) * half.Y
		+ math.abs(frame.LookVector:Dot(axis)) * half.Z
end

-- The point furthest forward on the model, in the handle's space.
local function estimateMuzzle(model: Model, handle: BasePart): Vector3
	local forward = handle.CFrame.LookVector
	local bestTip = -math.huge
	local bestPoint = handle.Position
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local extent = reach(descendant, forward)
			local tip = (descendant.Position - handle.Position):Dot(forward) + extent
			if tip > bestTip then
				bestTip = tip
				bestPoint = descendant.Position + forward * extent
			end
		end
	end
	return handle.CFrame:PointToObjectSpace(bestPoint)
end

-- A plain block gun, used when a weapon module has no model at all.
function Rig.placeholder(): Model
	local model = Instance.new("Model")
	model.Name = "Placeholder"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.28, 0.8, 0.34)
	handle.Color = Color3.fromRGB(42, 43, 40)
	handle.Material = Enum.Material.SmoothPlastic
	handle.Parent = model

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(0.3, 0.36, 1.9)
	body.Color = Color3.fromRGB(58, 60, 55)
	body.Material = Enum.Material.SmoothPlastic
	body.CFrame = handle.CFrame * CFrame.new(0, 0.5, -0.6)
	body.Parent = model

	model.PrimaryPart = handle
	return model
end

-- Finds an attachment on the weapon by name, wherever it was put.
function Rig.attachment(model: Instance, name: string): Attachment?
	-- A part and the joint that holds it often share an attachment's name
	-- ("Mag", "Barrel"), so match on class as well as name.
	local alias = if name == "Barrel" then "Muzzle" else nil
	local aliased: Attachment? = nil
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Attachment") then
			if descendant.Name == name then
				return descendant
			elseif descendant.Name == alias then
				aliased = descendant
			end
		end
	end
	return aliased
end

--[[
	Returns a prepared copy of `source`: unanchored, non-colliding, welded to
	its handle, with MainHandle and Barrel attachments guaranteed. The source
	is not modified. Never fails; a hopeless model becomes the placeholder.
]]
function Rig.prepare(source: Instance?, weaponName: string, scale: number?): Model
	local model: Model
	if source == nil then
		model = Rig.placeholder()
	elseif source:IsA("Model") then
		model = source:Clone()
	elseif source:IsA("BasePart") then
		model = Instance.new("Model")
		local part = source:Clone()
		part.Parent = model
		model.PrimaryPart = part
	elseif source:IsA("Tool") or source:IsA("Folder") then
		model = Instance.new("Model")
		for _, child in source:GetChildren() do
			child:Clone().Parent = model
		end
	else
		log:Warn(`{weaponName}: the model is a {source.ClassName}, which cannot be held; using a placeholder`)
		model = Rig.placeholder()
	end

	local handle = findHandle(model)
	if handle == nil then
		log:Warn(`{weaponName}: the model has no parts; using a placeholder`)
		model:Destroy()
		model = Rig.placeholder()
		handle = model.PrimaryPart :: BasePart
	elseif model.PrimaryPart == nil and not table.find(HANDLE_NAMES, handle.Name) then
		log:Warn(
			`{weaponName}: no part named "Handle"; using the largest part, "{handle.Name}". The grip may look off.`
		)
	end
	model.Name = weaponName
	model.PrimaryPart = handle
	if scale and scale ~= 1 then
		-- Scales parts, meshes, attachments and joint offsets together.
		model:ScaleTo(model:GetScale() * scale)
	end

	-- Parts already held by a joint keep it (moving parts rigged by hand).
	local jointed: { [Instance]: boolean } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			local joint = descendant :: any
			if joint.Part0 and joint.Part1 then
				jointed[joint.Part0] = true
				jointed[joint.Part1] = true
			end
		end
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			if descendant ~= handle and not jointed[descendant] then
				-- A Motor6D rather than a weld, so the part can be animated
				-- through its Transform. It is named after the part it holds.
				local joint = Instance.new("Motor6D")
				joint.Name = descendant.Name
				joint.Part0 = handle
				joint.Part1 = descendant
				joint.C0 = handle.CFrame:ToObjectSpace(descendant.CFrame)
				joint.Parent = handle
			end
		end
	end

	if Rig.attachment(model, "MainHandle") == nil then
		local grip = Instance.new("Attachment")
		grip.Name = "MainHandle"
		grip.Parent = handle
	end
	if Rig.attachment(model, "Barrel") == nil then
		local barrel = Instance.new("Attachment")
		barrel.Name = "Barrel"
		barrel.Position = estimateMuzzle(model, handle)
		barrel.Parent = handle
	end

	return model
end

--[[
	Attachment mounts. A weapon can mark where each slot sits with an
	attachment named OpticMount, MuzzleMount, UnderMount or SideMount (front
	-Z, top +Y, like the handle). Without one, the place is worked out from
	the model's shape:
	  Optic        on top of the receiver, a little ahead of the grip
	  Muzzle       at the Barrel attachment
	  Underbarrel  under the handguard
	  Side         on the right of the handguard
]]
Rig.Mounts = table.freeze({
	Optic = "OpticMount",
	Muzzle = "MuzzleMount",
	Underbarrel = "UnderMount",
	Side = "SideMount",
})

type Box = { low: Vector3, high: Vector3, name: string }

local function partBoxes(model: Model, frame: CFrame): { Box }
	local boxes = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local local_ = frame:ToObjectSpace(part.CFrame)
			local half = part.Size / 2
			local extent = Vector3.new(
				math.abs(local_.XVector.X) * half.X
					+ math.abs(local_.YVector.X) * half.Y
					+ math.abs(local_.ZVector.X) * half.Z,
				math.abs(local_.XVector.Y) * half.X
					+ math.abs(local_.YVector.Y) * half.Y
					+ math.abs(local_.ZVector.Y) * half.Z,
				math.abs(local_.XVector.Z) * half.X
					+ math.abs(local_.YVector.Z) * half.Y
					+ math.abs(local_.ZVector.Z) * half.Z
			)
			table.insert(
				boxes,
				{ low = local_.Position - extent, high = local_.Position + extent, name = part.Name }
			)
		end
	end
	return boxes
end

-- Where `slot` sits on a prepared weapon model, in the handle's space.
function Rig.mountPoint(model: Model, slot: string): CFrame
	local handle = model.PrimaryPart :: BasePart
	local named = Rig.attachment(model, (Rig.Mounts :: any)[slot] or "")
	if named then
		return handle.CFrame:ToObjectSpace(named.WorldCFrame)
	end
	local barrelAttachment = Rig.attachment(model, "Barrel")
	local barrel = if barrelAttachment
		then handle.CFrame:ToObjectSpace(barrelAttachment.WorldCFrame).Position
		else Vector3.new(0, 0.5, -2)
	if slot == "Muzzle" then
		return CFrame.new(barrel)
	end

	local main = Rig.gripCFrame(model).Position
	local length = barrel.Z - main.Z -- negative: the barrel is forward
	local boxes = partBoxes(model, handle.CFrame)
	local function covering(z: number, needX: boolean): { Box }
		local found = {}
		for _, box in boxes do
			if
				box.low.Z <= z
				and box.high.Z >= z
				and (not needX or (box.low.X <= 0.02 and box.high.X >= -0.02))
			then
				if box.name ~= "Mag" then
					table.insert(found, box)
				end
			end
		end
		return found
	end

	if slot == "Optic" then
		local z = main.Z + length * 0.18
		local top = barrel.Y + 0.15
		for _, box in covering(z, true) do
			top = math.max(top, box.high.Y)
		end
		return CFrame.new(0, top, z)
	elseif slot == "Underbarrel" then
		local z = main.Z + length * 0.62
		local bottom = barrel.Y - 0.1
		for _, box in covering(z, true) do
			if box.high.Y > barrel.Y - 0.6 then -- the handguard, not something hanging far below
				bottom = math.min(bottom, box.low.Y)
			end
		end
		return CFrame.new(0, bottom, z)
	end
	-- Side
	local z = main.Z + length * 0.58
	local right = 0.05
	for _, box in covering(z, false) do
		if box.low.Y <= barrel.Y and box.high.Y >= barrel.Y - 0.2 then
			right = math.max(right, box.high.X)
		end
	end
	return CFrame.new(right, barrel.Y - 0.08, z)
end

-- Names a fitted attachment can take over from the weapon: the optic's sight
-- line, the muzzle device's muzzle, the grip's hand position.
local TAKES_OVER = { Aim = "IronAim", Barrel = "BaseBarrel", Muzzle = "BaseMuzzle", Grip = "BaseGrip" }

--[[
	Fits an attachment model to a prepared weapon model (changing it) and
	returns the folder its parts went into. `template` is the attachment's
	prepared model; its Mount marker is placed on the weapon's mount point.
]]
function Rig.mount(model: Model, slot: string, template: Model): Model
	local handle = model.PrimaryPart :: BasePart
	local copy = template:Clone()
	local own = copy.PrimaryPart :: BasePart
	local mount: Attachment? = nil
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == "Mount" then
			mount = descendant
			break
		end
	end
	local mountLocal = if mount then own.CFrame:ToObjectSpace(mount.WorldCFrame) else CFrame.identity
	local target = handle.CFrame * Rig.mountPoint(model, slot) * mountLocal:Inverse()

	-- The attachment's own markers replace the weapon's.
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("Attachment") then
			local replaced = TAKES_OVER[descendant.Name]
			if replaced then
				for _, existing in model:GetDescendants() do
					if existing:IsA("Attachment") and existing.Name == descendant.Name then
						existing.Name = replaced
					end
				end
				if descendant.Name == "Barrel" then
					-- "Muzzle" is also read as the muzzle; retire it too.
					for _, existing in model:GetDescendants() do
						if existing:IsA("Attachment") and existing.Name == "Muzzle" then
							existing.Name = "BaseMuzzle"
						end
					end
				end
			end
		end
	end

	local folder = Instance.new("Model")
	folder.Name = `Attachment{slot}`
	local origin = own.CFrame -- read once: the handle moves with the rest
	for _, part in copy:GetDescendants() do
		if part:IsA("BasePart") then
			local frame = target * origin:ToObjectSpace(part.CFrame)
			part.Parent = folder
			part.CFrame = frame
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			for _, joint in part:GetChildren() do
				if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
					joint:Destroy()
				end
			end
			local motor = Instance.new("Motor6D")
			motor.Name = `{slot}{part.Name}`
			motor.Part0 = handle
			motor.Part1 = part
			motor.C0 = handle.CFrame:ToObjectSpace(frame)
			motor.Parent = handle
		end
	end
	copy:Destroy()
	folder.Parent = model
	return folder
end

-- Where the trigger hand holds, relative to the handle part.
function Rig.gripCFrame(model: Model): CFrame
	local handle = model.PrimaryPart
	local grip = Rig.attachment(model, "MainHandle")
	if handle == nil or grip == nil then
		return CFrame.identity
	end
	return handle.CFrame:ToObjectSpace(grip.WorldCFrame)
end

return Rig
