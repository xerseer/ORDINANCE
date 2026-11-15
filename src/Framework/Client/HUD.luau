--!strict
--[[
	HUD
	The built-in heads-up display: ammo, fire mode, a reload bar, a crosshair
	that opens with spread, and a hitmarker.

	The crosshair is drawn from the Crosshair settings, with the player's own
	choices (Ordnance.SetCrosshair) laid over the game's. When aiming it turns
	into a dot, or goes away when there is a sight to look through.

	It is deliberately small. Turn it off with HUD.Enabled = false and build
	your own from Ordnance's client API if the game needs more.
]]

local Players = game:GetService("Players")

local Defaults = require(script.Parent.Parent.Config.Defaults)
local Merge = require(script.Parent.Parent.Config.Merge)
local State = require(script.Parent.Parent.Weapons.State)

type Config = Defaults.Config

local INK = Color3.fromRGB(232, 231, 226)
local MUTED = Color3.fromRGB(156, 154, 146)
local SHADE = Color3.fromRGB(22, 22, 21)
local DANGER = Color3.fromRGB(217, 122, 108)

local NUMERALS = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
local LABELS = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium)

local HUD = {}

local gui: ScreenGui? = nil
local panel: Frame
local magazine: TextLabel
local reserve: TextLabel
local title: TextLabel
local mode: TextLabel
local status: TextLabel
local progressTrack: Frame
local progressFill: Frame
local crosshair: Frame
local hairs: { Frame } = {}
local ring: Frame
local ringOutline: Frame
local dot: Frame
local playerCrosshair: { [string]: any }? = nil
local styledFrom: any = nil -- the settings table the crosshair was last drawn with
local styledWith: any = nil -- the player overrides it was drawn with
local crosshairStyle: { [string]: any } = Defaults.Crosshair :: any
local marker: Frame
local markerLines: { Frame } = {}
local markerUntil = 0
local accent = Color3.fromRGB(179, 191, 125)

local function label(parent: Instance, font: Font, size: number, color: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.FontFace = font
	text.TextSize = size
	text.TextColor3 = color
	text.TextXAlignment = Enum.TextXAlignment.Right
	text.TextYAlignment = Enum.TextYAlignment.Bottom
	text.Text = ""
	text.Parent = parent
	return text
end

local function bar(parent: Instance, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.Parent = parent
	return frame
end

local function build()
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "OrdnanceHUD"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 5
	screen.Enabled = false

	-- Ammo block, bottom right.
	panel = Instance.new("Frame")
	panel.Name = "Ammo"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -28, 1, -28)
	panel.Size = UDim2.fromOffset(260, 96)
	panel.BackgroundTransparency = 1
	panel.Parent = screen

	title = label(panel, LABELS, 14, MUTED)
	title.Name = "Weapon"
	title.Position = UDim2.fromOffset(0, 0)
	title.Size = UDim2.new(1, 0, 0, 16)

	magazine = label(panel, NUMERALS, 52, INK)
	magazine.Name = "Magazine"
	magazine.Position = UDim2.new(0, 0, 0, 18)
	magazine.Size = UDim2.new(1, -78, 0, 52)

	reserve = label(panel, NUMERALS, 20, MUTED)
	reserve.Name = "Reserve"
	reserve.TextXAlignment = Enum.TextXAlignment.Left
	reserve.Position = UDim2.new(1, -70, 0, 40)
	reserve.Size = UDim2.fromOffset(70, 26)

	mode = label(panel, LABELS, 13, accent)
	mode.Name = "Mode"
	mode.TextXAlignment = Enum.TextXAlignment.Left
	mode.Position = UDim2.new(1, -70, 0, 24)
	mode.Size = UDim2.fromOffset(70, 14)

	progressTrack = bar(panel, SHADE)
	progressTrack.Name = "Progress"
	progressTrack.BackgroundTransparency = 0.35
	progressTrack.Position = UDim2.new(0, 0, 0, 76)
	progressTrack.Size = UDim2.new(1, 0, 0, 3)
	progressFill = bar(progressTrack, accent)
	progressFill.Size = UDim2.fromScale(0, 1)

	status = label(panel, LABELS, 13, MUTED)
	status.Name = "Status"
	status.Position = UDim2.new(0, 0, 0, 82)
	status.Size = UDim2.new(1, 0, 0, 14)

	-- Crosshair: four lines (top, bottom, left, right), a ring and a dot,
	-- shown and sized by the Crosshair settings.
	crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(2, 2)
	crosshair.BackgroundTransparency = 1
	crosshair.Parent = screen
	for index, name in { "Top", "Bottom", "Left", "Right" } do
		local hair = bar(crosshair, INK)
		hair.Name = name
		hair.AnchorPoint = Vector2.new(0.5, 0.5)
		local outline = Instance.new("UIStroke")
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		outline.Parent = hair
		hairs[index] = hair
	end
	local function circle(name: string): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundTransparency = 1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame
		frame.Parent = crosshair
		return frame
	end
	ringOutline = circle("RingOutline")
	ring = circle("Ring")
	dot = bar(crosshair, INK)
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(0.5, 0)
	dotCorner.Parent = dot
	local dotOutline = Instance.new("UIStroke")
	dotOutline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dotOutline.Parent = dot
	styledFrom = nil

	-- Hitmarker: four short diagonals.
	marker = Instance.new("Frame")
	marker.Name = "Hitmarker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.fromOffset(2, 2)
	marker.BackgroundTransparency = 1
	marker.Visible = false
	marker.Parent = screen
	for index = 1, 4 do
		local line = bar(marker, INK)
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Size = UDim2.fromOffset(2, 10)
		local angle = 45 + (index - 1) * 90
		line.Rotation = angle
		local radians = math.rad(angle)
		line.Position = UDim2.fromOffset(math.sin(radians) * 11, -math.cos(radians) * 11)
		markerLines[index] = line
	end

	screen.Parent = playerGui
	gui = screen
end

local function paint(frame: GuiObject, color: Color3, transparency: number, style: { [string]: any })
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if frame.Name == "Ring" then
		frame.BackgroundTransparency = 1
		if stroke then
			stroke.Color = color
			stroke.Thickness = style.Thickness
			stroke.Transparency = transparency
		end
		return
	elseif frame.Name == "RingOutline" then
		frame.BackgroundTransparency = 1
		if stroke then
			stroke.Color = style.OutlineColor
			stroke.Thickness = style.Thickness + style.OutlineThickness * 2
			stroke.Transparency = if style.Outline then transparency else 1
		end
		return
	end
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	if stroke then
		stroke.Color = style.OutlineColor
		stroke.Thickness = style.OutlineThickness
		stroke.Transparency = if style.Outline then transparency else 1
	end
end

-- The crosshair settings in effect: the weapon's, with the player's on top.
local function resolveStyle(config: Config): { [string]: any }
	local from = config.Crosshair
	if from ~= styledFrom or playerCrosshair ~= styledWith then
		styledFrom = from
		styledWith = playerCrosshair
		crosshairStyle = if playerCrosshair then Merge.deep(from :: any, playerCrosshair) else from :: any
	end
	return crosshairStyle
end

local function updateCrosshair(config: Config, spreadDegrees: number, aim: number, sighted: boolean?)
	local style = resolveStyle(config)
	local camera = workspace.CurrentCamera

	local gap = style.Gap
	if style.Dynamic and camera then
		local halfFov = math.rad(camera.FieldOfView) / 2
		gap += math.tan(math.rad(spreadDegrees)) / math.tan(halfFov) * camera.ViewportSize.Y / 2
	end
	gap = math.clamp(gap, 0, 260)

	-- What aiming turns the crosshair into.
	local aimed = style.AimStyle
	if aimed == "Auto" then
		aimed = if sighted then "Hidden" else "Dot"
	end
	local blend = if aimed == "Same" then 0 else math.clamp((aim - 0.15) / 0.6, 0, 1)
	local base = 1 - style.Opacity
	local hipFade = base + (1 - base) * blend -- transparency of the hip crosshair
	local aimedDot = if aimed == "Dot" then base + (1 - base) * (1 - blend) else 1

	local kind = style.Style
	local length = style.Length
	local thickness = style.Thickness
	local color = style.Color

	local lines = kind == "Cross" or kind == "T"
	local half = gap + length / 2
	for index, hair in hairs do
		local shown = lines and not (kind == "T" and index == 1) and hipFade < 0.99
		hair.Visible = shown
		if shown then
			if index <= 2 then
				hair.Size = UDim2.fromOffset(thickness, length)
				hair.Position = UDim2.fromOffset(0, if index == 1 then -half else half)
			else
				hair.Size = UDim2.fromOffset(length, thickness)
				hair.Position = UDim2.fromOffset(if index == 3 then -half else half, 0)
			end
			paint(hair, color, hipFade, style)
		end
	end

	local showRing = kind == "Circle" and hipFade < 0.99
	ring.Visible = showRing
	ringOutline.Visible = showRing and style.Outline
	if showRing then
		local diameter = math.max(gap * 2, 4)
		ring.Size = UDim2.fromOffset(diameter, diameter)
		ringOutline.Size = ring.Size
		paint(ring, color, hipFade, style)
		paint(ringOutline, color, hipFade, style)
	end

	-- The dot: the centre dot at the hip, and the whole crosshair when aimed.
	local hipDot = (style.CenterDot and kind ~= "None") or kind == "Dot"
	local dotTransparency = math.min(if hipDot then hipFade else 1, aimedDot)
	dot.Visible = dotTransparency < 0.99
	if dot.Visible then
		dot.Size = UDim2.fromOffset(style.DotSize, style.DotSize)
		paint(dot, color, dotTransparency, style)
	end
end

--[[
	Sets the local player's own crosshair settings, laid over the game's for
	every weapon. Pass nil to go back to the game's. Fields are the same as
	the Crosshair section of the config.
]]
function HUD.setPlayerCrosshair(settings: { [string]: any }?)
	playerCrosshair = settings
end

function HUD.show(config: Config)
	if not config.HUD.Enabled then
		HUD.hide()
		return
	end
	if gui == nil or gui.Parent == nil then
		build()
	end
	if gui == nil then
		return
	end
	accent = config.HUD.Accent
	mode.TextColor3 = accent
	progressFill.BackgroundColor3 = accent
	title.Text = string.upper(config.Name)
	crosshair.Visible = config.HUD.Crosshair
	gui.Enabled = true
end

function HUD.hide()
	if gui then
		gui.Enabled = false
	end
end

-- Refreshes the display. `spreadDegrees` opens the crosshair; `aim` is
-- 0 (hip) to 1 (aimed); `sighted` is true when the player is looking
-- through a sight, which the crosshair makes way for.
function HUD.update(
	state: State.State?,
	config: Config,
	now: number,
	spreadDegrees: number,
	aim: number,
	point: Vector2,
	sighted: boolean?
)
	if gui == nil or not gui.Enabled then
		return
	end
	-- The crosshair and hitmarker sit on the aim point: the cursor when the
	-- mouse is free, the centre of the screen otherwise.
	crosshair.Position = UDim2.fromOffset(point.X, point.Y)
	marker.Position = UDim2.fromOffset(point.X, point.Y)

	if state == nil then
		magazine.Text = "--"
		reserve.Text = ""
		mode.Text = ""
		status.Text = ""
		progressTrack.Visible = false
	else
		local loaded = State.loaded(state)
		magazine.Text = tostring(loaded)
		magazine.TextColor3 = if loaded == 0 then DANGER else INK
		reserve.Text = if config.Ammo.Infinite or state.reserve == math.huge
			then "/ INF"
			else `/ {state.reserve}`
		mode.Text = string.upper(state.mode)

		local busy = state.action ~= "Idle"
		progressTrack.Visible = busy
		if busy then
			progressFill.Size = UDim2.fromScale(State.progress(state, now), 1)
		end

		if state.jammed then
			status.Text = "JAMMED"
			status.TextColor3 = DANGER
		elseif state.action == "Reload" then
			status.Text = "RELOADING"
			status.TextColor3 = MUTED
		elseif state.needsCycle then
			status.Text = "CYCLE"
			status.TextColor3 = accent
		elseif loaded == 0 then
			status.Text = if state.reserve > 0 or config.Ammo.Infinite then "RELOAD" else "NO AMMO"
			status.TextColor3 = DANGER
		else
			status.Text = ""
		end
	end

	if config.HUD.Crosshair then
		updateCrosshair(config, spreadDegrees, aim, sighted)
	end

	if marker.Visible and now >= markerUntil then
		marker.Visible = false
	end
end

-- Flashes the hitmarker. Headshots use the accent colour, kills use red.
function HUD.hitmarker(config: Config, now: number, headshot: boolean, killed: boolean)
	if gui == nil or not config.HUD.Hitmarker then
		return
	end
	local color = if killed then DANGER elseif headshot then accent else INK
	for _, line in markerLines do
		line.BackgroundColor3 = color
	end
	marker.Visible = true
	markerUntil = now + (if killed then 0.3 else 0.12)
end

function HUD.destroy()
	if gui then
		gui:Destroy()
		gui = nil
	end
end

return HUD
