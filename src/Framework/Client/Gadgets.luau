--!strict
--[[
	Gadgets
	Flashlights and laser sights, drawn on every client for every weapon that
	has them switched on, the local player's first-person weapon included.

	The server only keeps one attribute per weapon (OrdnanceLight); each
	client turns that into lights and beams. A light is a SpotLight inside
	the attachment's Emitter; a laser is a Beam from the Emitter to whatever
	it points at, with a dot where it lands.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Framework = script.Parent.Parent

local Characters = require(script.Parent.Characters)
local Hitscan = require(Framework.Ballistics.Hitscan)
local Logger = require(Framework.Core.Logger)
local Registry = require(Framework.Weapons.Registry)
local Viewmodel = require(script.Parent.Viewmodel)

type Beam = {
	beam: Beam,
	target: Attachment,
	dot: Part,
	used: boolean,
}

local LIGHT_ATTRIBUTE = "OrdnanceLight"
local STEP = "OrdnanceGadgets"

local log = Logger.scope("Gadgets")
local localPlayer = Players.LocalPlayer

local Gadgets = {}

local beams: { [Attachment]: Beam } = {}
local folder: Folder? = nil
local heldInstance: Instance? = nil
local heldEntry: Registry.Entry? = nil

local function container(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "OrdnanceLasers"
	made.Parent = workspace.CurrentCamera
	folder = made
	return made
end

local function emitters(model: Instance): { Attachment }
	local found = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == "Emitter" then
			table.insert(found, descendant)
		end
	end
	return found
end

local function setLights(model: Instance, on: boolean)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("SpotLight") and descendant.Parent and descendant.Parent.Name == "Emitter" then
			descendant.Enabled = on
		end
	end
end

local function beamFor(emitter: Attachment, laser: any): Beam
	local existing = beams[emitter]
	if existing and existing.beam.Parent then
		return existing
	end
	local target = Instance.new("Attachment")
	target.Name = "OrdnanceLaserEnd"
	target.Parent = workspace.Terrain

	local beam = Instance.new("Beam")
	beam.Attachment0 = emitter
	beam.Attachment1 = target
	beam.Width0 = laser.Width
	beam.Width1 = laser.Width
	beam.Color = ColorSequence.new(laser.Color)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Transparency = NumberSequence.new(0.25)
	beam.Parent = container()

	local dot = Instance.new("Part")
	dot.Name = "OrdnanceLaserDot"
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.one * 0.12
	dot.Material = Enum.Material.Neon
	dot.Color = laser.Color
	dot.Anchored = true
	dot.CanCollide = false
	dot.CanQuery = false
	dot.CanTouch = false
	dot.CastShadow = false
	dot.Parent = container()

	local made = { beam = beam, target = target, dot = dot, used = true }
	beams[emitter] = made
	return made
end

local function drawLaser(emitter: Attachment, laser: any, exclude: { Instance })
	local frame = emitter.WorldCFrame
	local reach = frame.LookVector * laser.Range
	local result = Hitscan.raycast(frame.Position, reach, Hitscan.params(exclude))
	local finish = if result then result.Position else frame.Position + reach
	local drawn = beamFor(emitter, laser)
	drawn.used = true
	drawn.target.WorldPosition = finish
	drawn.dot.Position = finish
	drawn.dot.Transparency = if result then 0 else 1
end

local function step()
	for _, drawn in beams do
		drawn.used = false
	end
	local camera = workspace.CurrentCamera
	local exclude: { Instance } = { container() }
	if camera then
		table.insert(exclude, camera)
	end
	if localPlayer.Character then
		table.insert(exclude, localPlayer.Character)
	end

	-- World weapons, everyone's.
	Characters.each(function(player, weapon, entry)
		local gadgets = entry.gadgets
		if gadgets.light == nil and gadgets.laser == nil then
			return
		end
		local on = weapon:GetAttribute(LIGHT_ATTRIBUTE) == true
		-- The local player's own world weapon is hidden in first person; the
		-- viewmodel's copy shines instead.
		local shown = not (player == localPlayer and Characters.isLocalFirstPerson())
		setLights(weapon, on and shown)
		if on and shown and gadgets.laser then
			local holder = if player.Character then { player.Character :: Instance } else {}
			for _, item in exclude do
				table.insert(holder, item)
			end
			for _, emitter in emitters(weapon) do
				drawLaser(emitter, gadgets.laser, holder)
			end
		end
	end)

	-- The first-person weapon.
	local model = Viewmodel.getModel()
	local entry = heldEntry
	local instance = heldInstance
	if model and entry and instance then
		local gadgets = entry.gadgets
		local on = instance:GetAttribute(LIGHT_ATTRIBUTE) == true
		setLights(model, on)
		if on and gadgets.laser then
			for _, emitter in emitters(model) do
				drawLaser(emitter, gadgets.laser, exclude)
			end
		end
	end

	for emitter, drawn in beams do
		if not drawn.used then
			drawn.beam:Destroy()
			drawn.target:Destroy()
			drawn.dot:Destroy()
			beams[emitter] = nil
		end
	end
end

-- The local player's held weapon, for its first-person light and laser.
function Gadgets.setHeld(instance: Instance?, entry: Registry.Entry?)
	heldInstance = instance
	heldEntry = entry
end

function Gadgets.start()
	RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value + 3, log:Wrap(step))
end

function Gadgets.stop()
	pcall(function()
		RunService:UnbindFromRenderStep(STEP)
	end)
	for _, drawn in beams do
		drawn.beam:Destroy()
		drawn.target:Destroy()
		drawn.dot:Destroy()
	end
	table.clear(beams)
	if folder then
		folder:Destroy()
		folder = nil
	end
	heldInstance = nil
	heldEntry = nil
end

return Gadgets
