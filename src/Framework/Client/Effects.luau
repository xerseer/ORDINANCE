--!strict
--[[
	Effects
	Everything a shot looks and sounds like: tracers, muzzle flash, impact
	marks, projectile bodies, explosions and sounds.

	All of it is local to this client and lives in one folder in Workspace,
	created on first use and removed by Effects.clear(). Nothing here affects
	gameplay, and none of the parts can be hit by raycasts.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Defaults = require(script.Parent.Parent.Config.Defaults)
local Hitscan = require(script.Parent.Parent.Ballistics.Hitscan)

type Config = Defaults.Config

type Tracer = {
	part: Part,
	from: Vector3,
	direction: Vector3,
	distance: number,
	travelled: number,
	speed: number,
	length: number,
}

local FOLDER_NAME = "OrdnanceEffects"

local Effects = {}

local folder: Folder? = nil
local tracers: { Tracer } = {}

local function container(): Folder
	if folder == nil or folder.Parent == nil then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = workspace
		folder = created
	end
	return folder :: Folder
end

local function ghost(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- Plays a sound at a point in the world.
function Effects.sound(id: string, position: Vector3, volume: number, pitch: number, rollOffMax: number)
	if id == "" then
		return
	end
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain

	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = rollOffMax
	sound.Parent = anchor
	sound:Play()

	-- Long enough for any reasonable sound; the anchor takes the sound with it.
	Debris:AddItem(anchor, 6)
end

function Effects.muzzleFlash(position: Vector3, config: Config)
	local flash = config.Effects.MuzzleFlash
	if not flash.Enabled then
		return
	end
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain

	local light = Instance.new("PointLight")
	light.Color = flash.Color
	light.Brightness = flash.Brightness
	light.Range = flash.Range
	light.Shadows = false
	light.Parent = anchor

	local spark = Instance.new("Part")
	ghost(spark)
	spark.Shape = Enum.PartType.Ball
	spark.Material = Enum.Material.Neon
	spark.Color = flash.Color
	spark.Size = Vector3.one * 0.45
	spark.Transparency = 0.25
	spark.Position = position
	spark.Parent = container()

	Debris:AddItem(anchor, flash.Duration)
	Debris:AddItem(spark, flash.Duration)
end

-- Draws a tracer that flies from one point to another.
function Effects.tracer(from: Vector3, to: Vector3, config: Config)
	local settings = config.Effects.Tracer
	if not settings.Enabled then
		return
	end
	local offset = to - from
	local distance = offset.Magnitude
	if distance < settings.Length * 0.5 then
		return
	end

	local part = Instance.new("Part")
	ghost(part)
	part.Material = Enum.Material.Neon
	part.Color = settings.Color
	part.Size = Vector3.new(settings.Width, settings.Width, settings.Length)
	part.Parent = container()

	table.insert(tracers, {
		part = part,
		from = from,
		direction = offset.Unit,
		distance = distance,
		travelled = 0,
		speed = settings.Speed,
		length = settings.Length,
	})
end

-- Leaves a mark where a round landed on the level.
function Effects.impact(result: RaycastResult, config: Config)
	local settings = config.Effects.Impact
	if not settings.Enabled or settings.Lifetime <= 0 then
		return
	end
	if Hitscan.humanoidOf(result.Instance) ~= nil then
		return -- no bullet holes floating where a character used to be
	end

	local mark = Instance.new("Part")
	ghost(mark)
	mark.Shape = Enum.PartType.Cylinder
	mark.Material = Enum.Material.SmoothPlastic
	mark.Color = Color3.fromRGB(22, 22, 21)
	mark.Size = Vector3.new(0.03, settings.Size, settings.Size)
	-- A cylinder's axis is X; point it along the surface normal.
	mark.CFrame = CFrame.lookAlong(result.Position + result.Normal * 0.012, result.Normal)
		* CFrame.Angles(0, math.rad(90), 0)
	mark.Parent = container()

	local puff = Instance.new("Part")
	ghost(puff)
	puff.Shape = Enum.PartType.Ball
	puff.Material = Enum.Material.SmoothPlastic
	local surface = result.Instance
	puff.Color = if surface:IsA("BasePart") and not surface:IsA("Terrain")
		then surface.Color
		else Color3.fromRGB(120, 112, 98)
	puff.Transparency = 0.35
	puff.Size = Vector3.one * settings.Size
	puff.Position = result.Position + result.Normal * 0.1
	puff.Parent = container()
	TweenService:Create(puff, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * settings.Size * 3.5,
		Transparency = 1,
		Position = result.Position + result.Normal * 0.45,
	}):Play()

	Debris:AddItem(puff, 0.25)
	Debris:AddItem(mark, settings.Lifetime)
end

-- The visible body of a physical projectile. The caller moves and destroys it.
function Effects.projectile(config: Config): Part
	local settings = config.Effects.Projectile
	local part = Instance.new("Part")
	ghost(part)
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Metal
	part.Color = settings.Color
	part.Size = Vector3.one * settings.Size

	if settings.Trail then
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, settings.Size * 0.4, 0)
		top.Parent = part
		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(0, -settings.Size * 0.4, 0)
		bottom.Parent = part

		local trail = Instance.new("Trail")
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Lifetime = 0.35
		trail.MinLength = 0.05
		trail.LightEmission = 0.2
		trail.Color = ColorSequence.new(Color3.fromRGB(232, 231, 226))
		trail.Transparency = NumberSequence.new(0.55, 1)
		trail.Parent = part
	end

	part.Parent = container()
	return part
end

function Effects.explosion(position: Vector3, config: Config)
	local explosive = config.Ballistics.Explosive
	local sounds = config.Effects.Sounds

	-- Roblox's own explosion effect, with everything that affects gameplay off.
	local visual = Instance.new("Explosion")
	visual.BlastPressure = 0
	visual.BlastRadius = 0
	visual.DestroyJointRadiusPercent = 0
	visual.ExplosionType = Enum.ExplosionType.NoCraters
	visual.Position = position
	visual.Parent = container()
	Debris:AddItem(visual, 3)

	local shock = Instance.new("Part")
	ghost(shock)
	shock.Shape = Enum.PartType.Ball
	shock.Material = Enum.Material.Neon
	shock.Color = Color3.fromRGB(255, 214, 140)
	shock.Transparency = 0.35
	shock.Size = Vector3.one
	shock.Position = position
	shock.Parent = container()
	TweenService:Create(shock, TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * explosive.Radius * 1.2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(shock, 0.3)

	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 110)
	light.Brightness = 8
	light.Range = explosive.Radius * 2.5
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(0.35), { Brightness = 0 }):Play()
	Debris:AddItem(anchor, 0.4)

	Effects.sound(sounds.Explosion, position, 1.4, 1, sounds.RollOffMax * 1.5)
end

-- Moves tracers. Call once per frame.
function Effects.step(deltaTime: number)
	for index = #tracers, 1, -1 do
		local tracer = tracers[index]
		tracer.travelled += tracer.speed * deltaTime
		local head = math.min(tracer.travelled, tracer.distance)
		local tail = math.max(0, tracer.travelled - tracer.length)
		if tail >= tracer.distance then
			tracer.part:Destroy()
			table.remove(tracers, index)
			continue
		end
		local length = math.max(head - tail, 0.05)
		local centre = tracer.from + tracer.direction * ((head + tail) / 2)
		tracer.part.Size = Vector3.new(tracer.part.Size.X, tracer.part.Size.Y, length)
		tracer.part.CFrame = CFrame.lookAlong(centre, tracer.direction)
	end
end

function Effects.clear()
	table.clear(tracers)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return Effects
