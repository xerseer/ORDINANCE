--[[
	Rigs the example weapons from the gun kit in Workspace.GunModels and prints
	each one as a Rojo JSON model, for tools/import-models.mjs to pick up from
	the Studio log.

	The kit is geometry only: every part is called "Part", anchored and
	unwelded, lying flat with the barrel along world +Z and the top of the gun
	toward world -X. For each example this script:
	  - adds an invisible Handle at the pistol grip, facing down the barrel
	  - names the parts that matter (magazine, bolt, pump, ...)
	  - adds the MainHandle, Barrel, Grip, Side, Mag and Aim attachments
	  - re-expresses every part relative to the Handle

	Offsets are in studs from the centre of the model's bounding box, in world
	axes (x: +down/-up, y: thickness, z: +muzzle/-stock).

	Run from the command bar while `rojo serve` is connected:
		require(game.ServerStorage.OrdnanceDev.RigExamples)()
]]

local HttpService = game:GetService("HttpService")

local V = Vector3.new
local CHUNK = 700 -- Studio truncates long log lines

local function specs()
	local kit = workspace.GunModels.WEAPONS
	return {
		Glock17 = {
			model = kit.SIDEARMS["GLOCK 17"],
			handle = V(0.34, 0, -0.37), -- low on the grip, so the hand leaves the slide in view
			muzzle = V(-0.31, 0, 0.60),
			mag = V(0.08, 0, -0.37),
			aim = V(-0.45, 0, -0.50),
			names = {
				[1] = "Rail",
				[2] = "Mag",
				[3] = "Frame",
				[4] = "Slide",
				[5] = "Barrel",
				[6] = "Trigger",
				[7] = "Light",
			},
		},
		G36C = {
			model = kit["ASSAULT RIFLES"]["G36 VARIANTS"]["H&K G36C"],
			handle = V(0.28, 0, -0.38),
			muzzle = V(-0.31, 0, 1.85),
			grip = V(0.05, 0, 1.05),
			side = V(-0.34, 0.16, 0.31),
			mag = V(0.24, 0, 0.29),
			aim = V(-0.74, 0, -0.30),
			names = {
				[5] = "CarryHandle",
				[6] = "Handguard",
				[7] = "Stock",
				[8] = "Buttpad",
				[10] = "PistolGrip",
				[11] = "Bolt",
				[12] = "Barrel",
				[14] = "Receiver",
				[18] = "Mag",
			},
		},
		Remington700 = {
			model = kit["SNIPER RIFLES"]["REMINGTON 700"],
			handle = V(0.10, 0.07, -1.45),
			muzzle = V(-0.36, 0.07, 3.485),
			grip = V(0.12, 0.07, 1.0),
			side = V(-0.26, -0.25, -0.64),
			mag = V(0.0, 0.07, -0.64),
			aim = V(-0.60, 0.07, -0.90),
			names = {
				[1] = "Barrel",
				[2] = "Receiver",
				[3] = "Stock",
				[4] = "Rail",
				[5] = "Bolt",
				[7] = "Butt",
				[8] = "TriggerGuard",
				[9] = "MuzzleBrake",
			},
		},
		Remington870 = {
			model = kit.SHOTGUNS["REMINGTON 870, PICATINNY RAIL"],
			handle = V(0.3, 0, -0.80),
			muzzle = V(-0.36, 0, 2.10),
			grip = V(-0.05, 0, 0.97),
			mag = V(-0.05, 0, -0.45),
			aim = V(-0.40, 0, -0.90),
			names = {
				[1] = "Stock",
				[2] = "Pump",
				[3] = "PistolGrip",
				[4] = "Receiver",
				[5] = "Barrel",
			},
		},
		M203 = {
			model = kit["ASSAULT RIFLES"]["AR-15 VARIANTS"].CLASSICS["COLT M4A1, M203"],
			handle = V(0.33, 0, -0.97),
			muzzle = V(0.03, 0, 1.92), -- the launcher tube, not the rifle barrel
			grip = V(0.22, 0, 1.0),
			mag = V(0.03, 0, 0.75),
			aim = V(-0.78, 0, -0.60),
			names = {
				[3] = "Launcher",
				[4] = "RifleMag",
				[7] = "Stock",
				[10] = "PistolGrip",
				[11] = "Barrel",
			},
		},
	}
end

local function round(value: number, places: number?): number
	local scale = 10 ^ (places or 3)
	local rounded = math.round(value * scale) / scale
	return if rounded == 0 then 0 else rounded
end

local function vector(v: Vector3): { number }
	return { round(v.X), round(v.Y), round(v.Z) }
end

-- Rojo reads an implicit CFrame as twelve numbers: position, then the rotation
-- matrix row by row, which is the order GetComponents returns.
local function frame(cf: CFrame): { number }
	local components = { cf:GetComponents() }
	for index, value in components do
		components[index] = round(value, if index <= 3 then 3 else 4)
	end
	return components
end

local function serialize(spec)
	local centre = spec.model:GetBoundingBox().Position
	local grip = centre + spec.handle
	local handle = CFrame.lookAt(grip, grip + Vector3.zAxis, -Vector3.xAxis)

	local function attachment(name: string, offset: Vector3)
		return {
			Name = name,
			ClassName = "Attachment",
			Properties = {
				CFrame = frame(CFrame.new(handle:PointToObjectSpace(centre + offset))),
			},
		}
	end

	local attachments =
		{ { Name = "MainHandle", ClassName = "Attachment" }, attachment("Barrel", spec.muzzle) }
	for _, name in { "Grip", "Side", "Mag", "Aim" } do
		local offset = spec[string.lower(name)]
		if offset then
			table.insert(attachments, attachment(name, offset))
		end
	end

	local children = {
		{
			Name = "Handle",
			ClassName = "Part",
			Properties = { Size = { 0.2, 0.2, 0.2 }, Transparency = 1, CanCollide = false },
			Children = attachments,
		},
	}

	local index, unnamed = 0, 0
	for _, part in spec.model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		index += 1
		local name = spec.names[index]
		if name == nil then
			unnamed += 1
			name = "Part" .. unnamed
		end

		local properties = {
			CFrame = frame(handle:ToObjectSpace(part.CFrame)),
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

		local node = { Name = name, ClassName = "Part", Properties = properties, Children = nil :: any }
		local mesh = part:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			local meshProperties = { MeshType = mesh.MeshType.Name, Scale = vector(mesh.Scale) }
			if mesh.MeshId ~= "" then
				meshProperties.MeshId = mesh.MeshId
			end
			if mesh.TextureId ~= "" then
				meshProperties.TextureId = mesh.TextureId
			end
			if mesh.Offset.Magnitude > 0 then
				meshProperties.Offset = vector(mesh.Offset)
			end
			if mesh.VertexColor ~= Vector3.one then
				meshProperties.VertexColor = vector(mesh.VertexColor)
			end
			node.Children = { { Name = "Mesh", ClassName = "SpecialMesh", Properties = meshProperties } }
		end
		table.insert(children, node)
	end

	return HttpService:JSONEncode({ ClassName = "Model", Children = children }), index
end

return function()
	local summary = {}
	for name, spec in specs() do
		local json, parts = serialize(spec)
		local count = 0
		for start = 1, #json, CHUNK do
			count += 1
			print(`@@ORD|{name}|{count}|{string.sub(json, start, start + CHUNK - 1)}`)
		end
		print(`@@ORDEND|{name}|{count}|{#json}`)
		table.insert(summary, `{name}: {parts} parts, {#json} bytes, {count} chunks`)
	end
	return table.concat(summary, "\n")
end
