--!strict
--[[
	Visualizer
	Short-lived debug drawings: lines, boxes and spheres. Used by the
	Debug.Visualize settings. Drawings live in one folder in Workspace that is
	created on first use and removed by Visualizer.clear().

	Drawn on the client they are local; drawn on the server everyone sees them.
]]

local Debris = game:GetService("Debris")

local Visualizer = {}

local FOLDER_NAME = "OrdnanceDebug"

local folder: Folder? = nil

local function container(): Folder
	if folder == nil or folder.Parent == nil then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = workspace
		folder = created
	end
	return folder :: Folder
end

local function shape(color: Color3, lifetime: number): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.45
	Debris:AddItem(part, lifetime)
	return part
end

function Visualizer.line(from: Vector3, to: Vector3, color: Color3, lifetime: number)
	local length = (to - from).Magnitude
	if length < 1e-3 then
		return
	end
	local part = shape(color, lifetime)
	part.Size = Vector3.new(0.04, 0.04, length)
	part.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	part.Parent = container()
end

function Visualizer.box(frame: CFrame, size: Vector3, color: Color3, lifetime: number)
	local part = shape(color, lifetime)
	part.Transparency = 0.7
	part.Size = size
	part.CFrame = frame
	part.Parent = container()
end

function Visualizer.sphere(position: Vector3, radius: number, color: Color3, lifetime: number)
	local part = shape(color, lifetime)
	part.Shape = Enum.PartType.Ball
	part.Transparency = 0.75
	part.Size = Vector3.one * radius * 2
	part.Position = position
	part.Parent = container()
end

function Visualizer.clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return Visualizer
