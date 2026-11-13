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
	local found = model:FindFirstChild(name, true)
	if found and found:IsA("Attachment") then
		return found
	end
	if name == "Barrel" then
		local muzzle = model:FindFirstChild("Muzzle", true)
		if muzzle and muzzle:IsA("Attachment") then
			return muzzle
		end
	end
	return nil
end

--[[
	Returns a prepared copy of `source`: unanchored, non-colliding, welded to
	its handle, with MainHandle and Barrel attachments guaranteed. The source
	is not modified. Never fails; a hopeless model becomes the placeholder.
]]
function Rig.prepare(source: Instance?, weaponName: string): Model
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
				local weld = Instance.new("WeldConstraint")
				weld.Name = "OrdnanceWeld"
				weld.Part0 = handle
				weld.Part1 = descendant
				weld.Parent = descendant
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
