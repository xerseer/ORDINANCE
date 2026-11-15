--[[
	RigKit
	Turns kit models in the dev place into weapon models for src/Weapons, as
	Rojo JSON (Parts with SpecialMeshes, since a plugin cannot set a MeshPart's
	mesh, so Rojo cannot sync MeshParts).

	Every position is given in the gun's own frame: x right, y up, z back
	(the muzzle is toward -z), in studs from the centre of its bounding box,
	before any Scale. profile() prints the gun's outline in that frame so the
	grip, magazine and sights can be found.

	Run from the command bar while `rojo serve` is connected:
		local RigKit = require(game.ServerStorage.OrdnanceDev.RigKit)
		print(RigKit.profile(workspace.Models.Model.MP5))
		print(RigKit.build(workspace.Models.Model.MP5, { handle = Vector3.new(0, -0.3, 0.6), ... }))
]]

local HttpService = game:GetService("HttpService")

local RigKit = {}

export type Spec = {
	forward: Vector3?, -- world direction of the muzzle; default: the parts' -RightVector
	up: Vector3?, -- world direction of the top; default: the parts' UpVector
	flip: boolean?, -- turn the default frame around (muzzle the other way)
	handle: Vector3, -- the trigger hand, in the gun's frame
	barrel: Vector3?, -- the muzzle; worked out from the front of the outline when left out
	grip: Vector3?, -- the support hand
	mag: Vector3?,
	side: Vector3?,
	aim: Vector3?,
	names: { [number]: string }?, -- part index -> name, for moving parts
}

local function parts(model: Instance): { BasePart }
	local result = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(result, descendant)
		end
	end
	return result
end

-- The gun's frame: centred on its box, -Z toward the muzzle, +Y toward the top.
function RigKit.frame(model: Instance, spec: { forward: Vector3?, up: Vector3?, flip: boolean? }?): CFrame
	local list = parts(model)
	local first = list[1]
	local forward = (spec and spec.forward) or -first.CFrame.RightVector
	local up = (spec and spec.up) or first.CFrame.UpVector
	if spec and spec.flip then
		forward = -forward
	end
	local right = forward:Cross(up)
	local rough = CFrame.fromMatrix(Vector3.zero, right, up, -forward)
	-- Centre on the box measured in this frame.
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in list do
		local local_ = rough:ToObjectSpace(part.CFrame)
		local half = part.Size / 2
		local extent = Vector3.new(
			math.abs(local_.XVector.X) * half.X + math.abs(local_.YVector.X) * half.Y + math.abs(local_.ZVector.X) * half.Z,
			math.abs(local_.XVector.Y) * half.X + math.abs(local_.YVector.Y) * half.Y + math.abs(local_.ZVector.Y) * half.Z,
			math.abs(local_.XVector.Z) * half.X + math.abs(local_.YVector.Z) * half.Y + math.abs(local_.ZVector.Z) * half.Z
		)
		low = low:Min(local_.Position - extent)
		high = high:Max(local_.Position + extent)
	end
	return rough * CFrame.new((low + high) / 2), (high - low)
end

-- The gun's outline from the stock (+z) to the muzzle (-z): bottom and top at each slice.
function RigKit.profile(model: Instance, spec: { forward: Vector3?, up: Vector3?, flip: boolean? }?, slices: number?): string
	local count = slices or 40
	local frame, size = RigKit.frame(model, spec)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts(model)
	local rows = { string.format("length %.2f height %.2f width %.2f", size.Z, size.Y, size.X) }
	for index = 0, count do
		local z = size.Z / 2 - size.Z * index / count
		local bottom, top = math.huge, -math.huge
		for step = -3, 3 do
			local x = size.X * 0.45 * step / 3
			local below = workspace:Raycast(frame * Vector3.new(x, -size.Y, z), frame.UpVector * size.Y * 2, params)
			if below then
				bottom = math.min(bottom, frame:PointToObjectSpace(below.Position).Y)
			end
			local above = workspace:Raycast(frame * Vector3.new(x, size.Y, z), -frame.UpVector * size.Y * 2, params)
			if above then
				top = math.max(top, frame:PointToObjectSpace(above.Position).Y)
			end
		end
		if bottom == math.huge then
			table.insert(rows, string.format("%6.2f    .      .", z))
		else
			table.insert(rows, string.format("%6.2f %6.2f %6.2f", z, bottom, top))
		end
	end
	return table.concat(rows, "\n")
end

local function round(value: number, places: number?): number
	local scale = 10 ^ (places or 3)
	local rounded = math.round(value * scale) / scale
	return if rounded == 0 then 0 else rounded
end

local function vector(v: Vector3, places: number?): { number }
	return { round(v.X, places), round(v.Y, places), round(v.Z, places) }
end

local function frameNumbers(cf: CFrame): { number }
	local components = { cf:GetComponents() }
	for index, value in components do
		components[index] = round(value, if index <= 3 then 3 else 4)
	end
	return components
end

-- A part as Rojo JSON: MeshParts become Parts with a SpecialMesh.
local function node(part: BasePart, handle: CFrame, name: string)
	local properties: { [string]: any } = {
		CFrame = frameNumbers(handle:ToObjectSpace(part.CFrame)),
		Size = vector(part.Size),
		Color = { round(part.Color.R), round(part.Color.G), round(part.Color.B) },
		Material = part.Material.Name,
	}
	if part.Transparency ~= 0 then
		properties.Transparency = round(part.Transparency)
	end
	if part.Reflectance ~= 0 then
		properties.Reflectance = round(part.Reflectance)
	end
	local result: { [string]: any } = { Name = name, ClassName = "Part", Properties = properties }
	if part:IsA("MeshPart") then
		local mesh: { [string]: any } = {
			MeshType = "FileMesh",
			MeshId = part.MeshId,
			Scale = vector(part.Size / part.MeshSize, 6),
		}
		if part.TextureID ~= "" then
			mesh.TextureId = part.TextureID
		end
		result.Children = { { Name = "Mesh", ClassName = "SpecialMesh", Properties = mesh } }
	else
		local special = part:FindFirstChildOfClass("SpecialMesh")
		if special then
			local mesh: { [string]: any } = { MeshType = special.MeshType.Name, Scale = vector(special.Scale, 6) }
			if special.MeshId ~= "" then
				mesh.MeshId = special.MeshId
			end
			if special.TextureId ~= "" then
				mesh.TextureId = special.TextureId
			end
			if special.Offset.Magnitude > 0 then
				mesh.Offset = vector(special.Offset)
			end
			if special.VertexColor ~= Vector3.one then
				mesh.VertexColor = vector(special.VertexColor)
			end
			result.Children = { { Name = "Mesh", ClassName = "SpecialMesh", Properties = mesh } }
		elseif part:IsA("Part") and part.Shape ~= Enum.PartType.Block then
			properties.Shape = part.Shape.Name
		end
	end
	return result
end

-- The model as Rojo JSON, with an invisible Handle and the attachments in `spec`.
function RigKit.build(model: Instance, spec: Spec): string
	local frame = RigKit.frame(model, spec)
	local handle = frame * CFrame.new(spec.handle)

	local attachments = { { Name = "MainHandle", ClassName = "Attachment" } }
	local function add(name: string, at: Vector3?)
		if at then
			local offset = at - spec.handle
			table.insert(attachments, {
				Name = name,
				ClassName = "Attachment",
				Properties = { CFrame = { round(offset.X), round(offset.Y), round(offset.Z), 1, 0, 0, 0, 1, 0, 0, 0, 1 } },
			})
		end
	end
	add("Barrel", spec.barrel)
	add("Grip", spec.grip)
	add("Side", spec.side)
	add("Mag", spec.mag)
	add("Aim", spec.aim)

	local children = {
		{
			Name = "Handle",
			ClassName = "Part",
			Properties = { Size = { 0.2, 0.2, 0.2 }, Transparency = 1, CanCollide = false },
			Children = attachments,
		},
	}
	local unnamed = 0
	for index, part in parts(model) do
		local name = spec.names and spec.names[index]
		if name == nil then
			unnamed += 1
			name = "Part" .. unnamed
		end
		table.insert(children, node(part, handle, name))
	end
	return HttpService:JSONEncode({ ClassName = "Model", Children = children })
end

-- One line per part: index, colour and box in the gun's frame, to tell the pieces apart.
function RigKit.parts(model: Instance, spec: { forward: Vector3?, up: Vector3?, flip: boolean? }?): string
	local frame = RigKit.frame(model, spec)
	local rows = {}
	for index, part in parts(model) do
		local local_ = frame:ToObjectSpace(part.CFrame)
		local half = part.Size / 2
		local extent = Vector3.new(
			math.abs(local_.XVector.X) * half.X + math.abs(local_.YVector.X) * half.Y + math.abs(local_.ZVector.X) * half.Z,
			math.abs(local_.XVector.Y) * half.X + math.abs(local_.YVector.Y) * half.Y + math.abs(local_.ZVector.Y) * half.Z,
			math.abs(local_.XVector.Z) * half.X + math.abs(local_.YVector.Z) * half.Y + math.abs(local_.ZVector.Z) * half.Z
		)
		local low, high = local_.Position - extent, local_.Position + extent
		table.insert(
			rows,
			string.format(
				"%2d %-10s y %5.2f..%5.2f z %5.2f..%5.2f",
				index,
				part.BrickColor.Name:sub(1, 10),
				low.Y,
				high.Y,
				low.Z,
				high.Z
			)
		)
	end
	return table.concat(rows, "\n")
end

return RigKit
