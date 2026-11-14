--!strict
--[[
	HUD
	The built-in heads-up display: ammo, fire mode, a reload bar, a crosshair
	that opens with spread, and a hitmarker.

	It is deliberately small. Turn it off with HUD.Enabled = false and build
	your own from Ordnance's client API if the game needs more.
]]

local Players = game:GetService("Players")

local Defaults = require(script.Parent.Parent.Config.Defaults)
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

	-- Crosshair: four hairs around the centre of the screen.
	crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(2, 2)
	crosshair.BackgroundTransparency = 1
	crosshair.Parent = screen
	for index = 1, 4 do
		local hair = bar(crosshair, INK)
		hair.AnchorPoint = Vector2.new(0.5, 0.5)
		hair.Size = if index <= 2 then UDim2.fromOffset(2, 9) else UDim2.fromOffset(9, 2)
		local outline = Instance.new("UIStroke")
		outline.Color = SHADE
		outline.Transparency = 0.5
		outline.Thickness = 1
		outline.Parent = hair
		hairs[index] = hair
	end

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

-- Refreshes the display. `spreadDegrees` drives the crosshair gap; `aim` is
-- 0 (hip) to 1 (aimed) and fades the crosshair out.
function HUD.update(state: State.State?, config: Config, now: number, spreadDegrees: number, aim: number)
	if gui == nil or not gui.Enabled then
		return
	end

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
		local camera = workspace.CurrentCamera
		local gap = 6
		if camera then
			local halfFov = math.rad(camera.FieldOfView) / 2
			gap = math.tan(math.rad(spreadDegrees)) / math.tan(halfFov) * camera.ViewportSize.Y / 2
		end
		gap = math.clamp(gap, 3, 220) + 5
		hairs[1].Position = UDim2.fromOffset(0, -gap)
		hairs[2].Position = UDim2.fromOffset(0, gap)
		hairs[3].Position = UDim2.fromOffset(-gap, 0)
		hairs[4].Position = UDim2.fromOffset(gap, 0)
		local fade = math.clamp(aim * 1.6, 0, 1)
		for _, hair in hairs do
			hair.BackgroundTransparency = fade
			local outline = hair:FindFirstChildOfClass("UIStroke")
			if outline then
				outline.Transparency = 0.5 + fade * 0.5
			end
		end
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
