--!strict
--[[
	UI
	A small set of hand-built components. Flat, square, hairline-separated,
	one accent colour: the same language as the documentation site.

	Colours are given as palette keys ("surface", "accent") and re-applied
	whenever Studio's theme changes, so nothing here holds a fixed colour.
]]

local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

type Key = string

local UI = {}

-- Applies palette-keyed colours to an instance and keeps them current.
function UI.paint(instance: Instance, colors: { [string]: Key })
	Theme.bind(function()
		local palette = Theme.palette() :: any
		for property, key in colors do
			(instance :: any)[property] = palette[key]
		end
	end)
end

local function make(class: string, properties: { [string]: any }?, parent: Instance?): any
	local instance = Instance.new(class)
	if class ~= "UIListLayout" and class ~= "UIPadding" and class ~= "UICorner" and class ~= "UIStroke" then
		local gui = instance :: any
		if gui:IsA("GuiObject") then
			gui.BorderSizePixel = 0
			gui.BackgroundTransparency = 1
		end
	end
	for property, value in properties or {} do
		(instance :: any)[property] = value
	end
	instance.Parent = parent
	return instance
end

UI.make = make

function UI.padding(parent: Instance, top: number, right: number?, bottom: number?, left: number?)
	make("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
	}, parent)
end

-- A vertical stack. Children keep the order they were parented in.
function UI.stack(parent: Instance, gap: number, horizontal: boolean?): UIListLayout
	return make("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	}, parent)
end

-- A frame that grows to fit its stacked children.
function UI.column(parent: Instance, gap: number?, order: number?): Frame
	local frame = make("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order or 0,
	}, parent)
	UI.stack(frame, gap or Theme.space.sm)
	return frame
end

function UI.row(parent: Instance, height: number?, gap: number?, order: number?): Frame
	local frame = make("Frame", {
		Size = UDim2.new(1, 0, 0, height or Theme.rowHeight),
		LayoutOrder = order or 0,
	}, parent)
	local layout = UI.stack(frame, gap or Theme.space.sm, true)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	return frame
end

function UI.line(parent: Instance, order: number?, strong: boolean?): Frame
	local line = make(
		"Frame",
		{ Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0, LayoutOrder = order or 0 },
		parent
	)
	UI.paint(line, { BackgroundColor3 = if strong then "lineStrong" else "line" })
	return line
end

function UI.label(
	parent: Instance,
	text: string,
	options: {
		color: Key?,
		size: number?,
		font: Font?,
		order: number?,
		wrap: boolean?,
		align: Enum.TextXAlignment?,
		width: number?,
	}?
): TextLabel
	local o = options or {}
	local label = make("TextLabel", {
		Text = text,
		FontFace = o.font or Theme.fontBody,
		TextSize = o.size or Theme.textSize,
		TextXAlignment = o.align or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = o.wrap ~= false,
		RichText = false,
		LayoutOrder = o.order or 0,
		Size = if o.width then UDim2.fromOffset(o.width, 0) else UDim2.fromScale(1, 0),
		AutomaticSize = if o.width then Enum.AutomaticSize.Y else Enum.AutomaticSize.Y,
	}, parent)
	UI.paint(label, { TextColor3 = o.color or "fg" })
	return label
end

function UI.heading(parent: Instance, text: string, order: number?): TextLabel
	return UI.label(parent, text, { font = Theme.fontBold, size = 15, order = order })
end

function UI.caption(parent: Instance, text: string, order: number?): TextLabel
	return UI.label(parent, text, { color = "muted", size = 12, order = order })
end

-- A small uppercase section label with a hairline under it.
function UI.section(parent: Instance, text: string, order: number?): Frame
	local box = UI.column(parent, 4, order)
	local label = UI.label(box, string.upper(text), { color = "muted", size = 11, font = Theme.fontMedium })
	label.AutomaticSize = Enum.AutomaticSize.Y
	UI.line(box, 1)
	return box
end

--[[
	A button. `style` is "primary" (filled with the accent), "default" (outlined)
	or "ghost" (text only). Returns the button and a function to enable or
	disable it.
]]
function UI.button(
	parent: Instance,
	text: string,
	style: string?,
	onClick: () -> (),
	order: number?
): (TextButton, (enabled: boolean) -> ())
	local kind = style or "default"
	local button = make("TextButton", {
		Text = text,
		FontFace = Theme.fontMedium,
		TextSize = Theme.textSize,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(0, Theme.rowHeight),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order or 0,
		BackgroundTransparency = if kind == "ghost" then 1 else 0,
	}, parent)
	UI.padding(button, 0, Theme.space.md, 0, Theme.space.md)
	local stroke = make("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)

	local enabled, hovered = true, false
	local function paint()
		local p = Theme.palette()
		if kind == "primary" then
			button.BackgroundColor3 = if hovered and enabled then p.fg else p.accent
			button.TextColor3 = p.onAccent
			stroke.Color = button.BackgroundColor3
		elseif kind == "ghost" then
			button.TextColor3 = if hovered then p.fg else p.muted
			stroke.Transparency = 1
		else
			button.BackgroundColor3 = if hovered and enabled then p.raised else p.surface
			button.TextColor3 = p.fg
			stroke.Color = p.lineStrong
		end
		button.TextTransparency = if enabled then 0 else 0.55
	end
	Theme.bind(paint)

	button.MouseEnter:Connect(function()
		hovered = true
		paint()
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		paint()
	end)
	button.Activated:Connect(function()
		if enabled then
			onClick()
		end
	end)
	return button, function(value: boolean)
		enabled = value
		paint()
	end
end

-- An on/off switch. Returns the frame and a setter.
function UI.toggle(
	parent: Instance,
	value: boolean,
	onChange: (boolean) -> (),
	order: number?
): (Frame, (boolean) -> ())
	local track = make("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(34, 18),
		BackgroundTransparency = 0,
		LayoutOrder = order or 0,
	}, parent)
	local stroke = make("UIStroke", { Thickness = 1 }, track)
	local knob = make("Frame", { Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 0 }, track)

	local state = value
	local function paint()
		local p = Theme.palette()
		track.BackgroundColor3 = if state then p.accentSoft else p.surface
		stroke.Color = if state then p.accent else p.lineStrong
		knob.BackgroundColor3 = if state then p.accent else p.muted
		knob.Position = if state then UDim2.fromOffset(19, 3) else UDim2.fromOffset(3, 3)
	end
	Theme.bind(paint)
	track.Activated:Connect(function()
		state = not state
		paint()
		onChange(state)
	end)
	return track :: any, function(next: boolean)
		state = next
		paint()
	end
end

--[[
	A text box. `onCommit` runs when focus leaves it. Returns the box and a
	function that sets its text without firing `onCommit`.
]]
function UI.input(
	parent: Instance,
	text: string,
	onCommit: (string) -> (),
	options: { width: number?, placeholder: string?, mono: boolean?, order: number? }?
): (TextBox, (string) -> ())
	local o = options or {}
	local box = make("TextBox", {
		Text = text,
		PlaceholderText = o.placeholder or "",
		ClearTextOnFocus = false,
		FontFace = if o.mono then Theme.fontMono else Theme.fontBody,
		TextSize = Theme.textSize,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = if o.width
			then UDim2.fromOffset(o.width, Theme.rowHeight)
			else UDim2.new(1, 0, 0, Theme.rowHeight),
		BackgroundTransparency = 0,
		LayoutOrder = o.order or 0,
	}, parent)
	UI.padding(box, 0, Theme.space.sm, 0, Theme.space.sm)
	local stroke = make("UIStroke", { Thickness = 1 }, box)
	local focused = false
	Theme.bind(function()
		local p = Theme.palette()
		box.BackgroundColor3 = p.code
		box.TextColor3 = p.fg
		box.PlaceholderColor3 = p.muted
		stroke.Color = if focused then p.accent else p.lineStrong
	end)
	box.Focused:Connect(function()
		focused = true
		stroke.Color = Theme.palette().accent
	end)
	box.FocusLost:Connect(function()
		focused = false
		stroke.Color = Theme.palette().lineStrong
		onCommit(box.Text)
	end)
	return box, function(value: string)
		box.Text = value
	end
end

-- A number field that clamps to a range. Returns a setter.
function UI.number(
	parent: Instance,
	value: number,
	min: number?,
	max: number?,
	onChange: (number) -> (),
	width: number?
): (number) -> ()
	local setText: (string) -> ()
	local function show(number: number)
		setText(string.format("%g", math.round(number * 10000) / 10000))
	end
	local _, set = UI.input(parent, "", function(text)
		local parsed = tonumber(text)
		if parsed == nil then
			show(value)
			return
		end
		parsed = math.clamp(parsed, min or -math.huge, max or math.huge)
		value = parsed
		show(parsed)
		onChange(parsed)
	end, { width = width or 72, mono = true })
	setText = set
	show(value)
	return function(next: number)
		value = next
		show(next)
	end
end

-- A drop-down made from a row of choices, one of which is selected.
function UI.segmented(
	parent: Instance,
	choices: { string },
	selected: string,
	onChange: (string) -> (),
	order: number?
): (string) -> ()
	local group = make("Frame", {
		Size = UDim2.fromOffset(0, Theme.rowHeight),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order or 0,
	}, parent)
	local layout = UI.stack(group, 0, true)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	local buttons: { [string]: TextButton } = {}
	local current = selected

	local function paint()
		local p = Theme.palette()
		for name, button in buttons do
			local on = name == current
			button.BackgroundColor3 = if on then p.accentSoft else p.surface
			button.TextColor3 = if on then p.accent else p.muted
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if on then p.accent else p.lineStrong
			end
		end
	end

	for index, choice in choices do
		local button = make("TextButton", {
			Text = choice,
			FontFace = Theme.fontMedium,
			TextSize = 12,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(0, Theme.rowHeight),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 0,
			LayoutOrder = index,
		}, group)
		UI.padding(button, 0, Theme.space.md, 0, Theme.space.md)
		make("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
		button.Activated:Connect(function()
			current = choice
			paint()
			onChange(choice)
		end)
		buttons[choice] = button
	end
	Theme.bind(paint)
	return function(next: string)
		current = next
		paint()
	end
end

-- A scrolling column that fills its parent.
function UI.scroll(parent: Instance, gap: number?): (ScrollingFrame, Frame)
	local scroll = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		BorderSizePixel = 0,
	}, parent)
	Theme.bind(function()
		local p = Theme.palette()
		scroll.ScrollBarImageColor3 = p.lineStrong
	end)
	local content = UI.column(scroll, gap or Theme.space.md)
	UI.padding(content, Theme.space.lg)
	return scroll, content
end

-- A framed block: surface fill, hairline border.
function UI.card(parent: Instance, order: number?): Frame
	local card = make("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0,
		LayoutOrder = order or 0,
	}, parent)
	local stroke = make("UIStroke", { Thickness = 1 }, card)
	Theme.bind(function()
		local p = Theme.palette()
		card.BackgroundColor3 = p.surface
		stroke.Color = p.line
	end)
	UI.padding(card, Theme.space.md)
	UI.stack(card, Theme.space.sm)
	return card
end

-- A monospaced block of text for code and output.
function UI.code(parent: Instance, text: string, order: number?): TextBox
	local box = make("TextBox", {
		Text = text,
		FontFace = Theme.fontMono,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ClearTextOnFocus = false,
		TextEditable = false,
		MultiLine = true,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0,
		LayoutOrder = order or 0,
	}, parent)
	UI.padding(box, Theme.space.sm)
	local stroke = make("UIStroke", { Thickness = 1 }, box)
	Theme.bind(function()
		local p = Theme.palette()
		box.BackgroundColor3 = p.code
		box.TextColor3 = p.fg
		stroke.Color = p.line
	end)
	return box
end

-- A status line that can be set to info, good, warn or bad.
function UI.status(parent: Instance, order: number?): (TextLabel, (text: string, kind: string?) -> ())
	local label = UI.label(parent, "", { color = "muted", size = 12, order = order })
	local kind = "info"
	local function paint()
		local p = Theme.palette()
		label.TextColor3 = if kind == "good"
			then p.accent
			elseif kind == "warn" then p.warn
			elseif kind == "bad" then p.danger
			else p.muted
	end
	Theme.bind(paint)
	return label,
		function(text: string, nextKind: string?)
			label.Text = text
			kind = nextKind or "info"
			paint()
		end
end

-- Width of a string at the standard size, for sizing columns.
function UI.textWidth(text: string, size: number?): number
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = Theme.fontBody
	params.Size = size or Theme.textSize
	params.Width = 10000
	local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
	return if ok then bounds.X else #text * 7
end

UI.isShiftDown = function(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

return UI
