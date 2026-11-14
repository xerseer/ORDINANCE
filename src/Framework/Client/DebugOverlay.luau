--!strict
--[[
	DebugOverlay
	Shows the framework's recent log messages on screen, for testing on
	devices where the Output window is not to hand. Turn it on with
	Debug.Overlay = true.

	It listens to the Logger, so it shows exactly what the Output window
	would, including uncaught framework errors picked up from LogService.
]]

local Players = game:GetService("Players")

local Logger = require(script.Parent.Parent.Core.Logger)
local Signal = require(script.Parent.Parent.Core.Signal)

local MAX_LINES = 10
local LINE_HEIGHT = 16

local COLORS: { [string]: Color3 } = {
	Error = Color3.fromRGB(217, 122, 108),
	Warn = Color3.fromRGB(217, 162, 122),
	Info = Color3.fromRGB(232, 231, 226),
	Debug = Color3.fromRGB(156, 154, 146),
}

local DebugOverlay = {}

local gui: ScreenGui? = nil
local list: Frame? = nil
local connection: Signal.Connection? = nil
local lines: { TextLabel } = {}

local function add(entry: Logger.Entry)
	local parent = list
	if parent == nil then
		return
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextColor3 = COLORS[entry.level] or COLORS.Info
	label.Size = UDim2.new(1, -12, 0, LINE_HEIGHT)
	-- First line only: stack traces belong in the Output window.
	label.Text = `{entry.scope}  {string.match(entry.message, "[^\n]*") or ""}`
	label.Parent = parent
	table.insert(lines, label)
	if #lines > MAX_LINES then
		table.remove(lines, 1):Destroy()
	end
end

function DebugOverlay.start()
	if gui then
		return
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "OrdnanceDebug"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 50

	local panel = Instance.new("Frame")
	panel.Position = UDim2.fromOffset(12, 12)
	panel.Size = UDim2.fromOffset(460, MAX_LINES * LINE_HEIGHT + 12)
	panel.BackgroundColor3 = Color3.fromRGB(22, 22, 21)
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Parent = screen

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	screen.Parent = playerGui
	gui = screen
	list = panel

	for _, entry in Logger.getHistory() do
		add(entry)
	end
	connection = Logger.MessageLogged:Connect(add)
end

function DebugOverlay.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if gui then
		gui:Destroy()
		gui = nil
	end
	list = nil
	table.clear(lines)
end

return DebugOverlay
