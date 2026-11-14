--!strict
--[[
	Ordnance Studio plugin.

	One dock widget, seven tabs: install and update, a visual config editor,
	presets, an animation previewer, an animation converter, an IK attachment
	helper and a catalogue. Each tab lives in its own module under Tabs and
	exposes { name, build(parent), onShow? }.

	A tab that fails to build or show is replaced by an error message; it never
	takes the rest of the plugin down.
]]

local Theme = require(script.Theme)
local UI = require(script.UI)

local TAB_MODULES = { "Install", "Config", "Presets", "Previewer", "Converter", "Helper", "Catalogue" }

Theme.start()

local toolbar = plugin:CreateToolbar("Ordnance")
local button = toolbar:CreateButton(
	"Ordnance",
	"Open the Ordnance panel",
	"rbxasset://textures/ui/GuiImagePlaceholder.png"
)
button.ClickableWhenViewportHidden = true

-- The Async form is the current API; the old name remains as a fallback.
local createWidget = (plugin :: any).CreateDockWidgetPluginGuiAsync
	or (plugin :: any).CreateDockWidgetPluginGui
local widget: DockWidgetPluginGui = createWidget(
	plugin,
	"OrdnancePanel",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 440, 640, 360, 420)
)
widget.Title = "Ordnance"
widget.Name = "Ordnance"

local root = UI.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0 }, widget)
UI.paint(root, { BackgroundColor3 = "bg" })

local bar = UI.make("ScrollingFrame", {
	Size = UDim2.new(1, 0, 0, 36),
	CanvasSize = UDim2.fromScale(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	ScrollingDirection = Enum.ScrollingDirection.X,
	ScrollBarThickness = 0,
	BackgroundTransparency = 0,
}, root)
UI.paint(bar, { BackgroundColor3 = "surface" })
local barLayout = UI.stack(bar, 0, true)
barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
local rule = UI.make(
	"Frame",
	{ Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromOffset(0, 36), BackgroundTransparency = 0 },
	root
)
UI.paint(rule, { BackgroundColor3 = "line" })

local body = UI.make("Frame", { Size = UDim2.new(1, 0, 1, -37), Position = UDim2.fromOffset(0, 37) }, root)

type Tab = { name: string, build: (parent: Frame) -> (), onShow: (() -> ())?, onHide: (() -> ())? }

local pages: { [string]: Frame } = {}
local headers: { [string]: TextButton } = {}
local tabs: { [string]: Tab } = {}
local selected = ""

local function paintTabs()
	local p = Theme.palette()
	for name, header in headers do
		local on = name == selected
		header.TextColor3 = if on then p.fg else p.muted
		local underline = header:FindFirstChild("Underline") :: Frame?
		if underline then
			underline.BackgroundColor3 = p.accent
			underline.Visible = on
		end
	end
end
Theme.bind(paintTabs)

local function showTab(name: string)
	local previous = tabs[selected]
	if previous and previous.onHide and selected ~= name then
		pcall(previous.onHide)
	end
	selected = name
	for pageName, page in pages do
		page.Visible = pageName == name
	end
	paintTabs()
	local tab = tabs[name]
	if tab and tab.onShow then
		local ok, err = pcall(tab.onShow)
		if not ok then
			warn(`[Ordnance:Plugin] {name} failed to refresh: {err}`)
		end
	end
	plugin:SetSetting("Tab", name)
end

for index, moduleName in TAB_MODULES do
	local page = UI.make("Frame", { Size = UDim2.fromScale(1, 1), Visible = false, Name = moduleName }, body)
	pages[moduleName] = page

	local ok, result = pcall(function()
		local tab = require(script.Tabs[moduleName]) :: Tab
		tabs[moduleName] = tab
		tab.build(page)
	end)
	if not ok then
		UI.label(page, `The {moduleName} tab could not load.\n\n{result}`, { color = "danger" })
		UI.padding(page, Theme.space.lg)
	end

	local title = if tabs[moduleName] then tabs[moduleName].name else moduleName
	local header = UI.make("TextButton", {
		Text = title,
		FontFace = Theme.fontMedium,
		TextSize = Theme.textSize,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = index,
	}, bar)
	UI.padding(header, 0, Theme.space.md)
	local underline = UI.make("Frame", {
		Name = "Underline",
		Size = UDim2.new(1, 0, 0, 2),
		Position = UDim2.new(0, 0, 1, -2),
		BackgroundTransparency = 0,
	}, header)
	underline.Visible = false
	header.Activated:Connect(function()
		showTab(moduleName)
	end)
	headers[moduleName] = header
end

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
end)

local remembered = plugin:GetSetting("Tab")
showTab(if type(remembered) == "string" and pages[remembered] then remembered else TAB_MODULES[1])
