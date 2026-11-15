--!strict
--[[
	AttachmentMenu
	The built-in attachment picker, opened with the Attachments key when the
	weapon's Attachments.Menu is on. Each slot the weapon has options for is
	a row of buttons; picking one asks the server to fit it, and the weapon
	comes back rebuilt with the menu still open.

	The mouse is freed while it is open (a modal button), and the trigger
	does nothing, so clicking the menu never fires the weapon.
]]

local Players = game:GetService("Players")

local Framework = script.Parent.Parent

local Attachments = require(Framework.Weapons.Attachments)
local Registry = require(Framework.Weapons.Registry)

type Pick = (slot: string, attachmentId: string?) -> ()

local INK = Color3.fromRGB(232, 231, 226)
local MUTED = Color3.fromRGB(156, 154, 146)
local SHADE = Color3.fromRGB(22, 22, 21)
local RAISED = Color3.fromRGB(40, 40, 37)
local ACCENT = Color3.fromRGB(179, 191, 125)

local LABELS = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium)
local TITLES = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local AttachmentMenu = {}

local gui: ScreenGui? = nil
local list: Frame
local title: TextLabel
local open = false
local onPick: Pick? = nil
local shown: Registry.Entry? = nil
local generation = 0 -- bumped on every refresh, so a pending close can tell it is stale

local function text(parent: Instance, font: Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function build()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "OrdnanceAttachments"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 6
	screen.Enabled = false

	-- An invisible modal button frees the mouse in first person.
	local modal = Instance.new("TextButton")
	modal.Name = "Modal"
	modal.Modal = true
	modal.BackgroundTransparency = 1
	modal.Text = ""
	modal.Size = UDim2.fromOffset(0, 0)
	modal.Parent = screen

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 28, 0.5, 0)
	panel.Size = UDim2.fromOffset(340, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = SHADE
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Parent = screen
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	title = text(panel, TITLES, 18, INK)
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 22)
	title.LayoutOrder = 0

	list = Instance.new("Frame")
	list.Name = "Slots"
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(1, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.LayoutOrder = 1
	list.Parent = panel
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 12)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local hint = text(panel, LABELS, 13, MUTED)
	hint.Name = "Hint"
	hint.Size = UDim2.new(1, 0, 0, 16)
	hint.LayoutOrder = 2
	hint.Text = "Press the attachments key again to close"

	screen.Parent = playerGui
	gui = screen
end

local function button(parent: Instance, label: string, selected: boolean, order: number, pressed: () -> ())
	local item = Instance.new("TextButton")
	item.AutoButtonColor = true
	item.BackgroundColor3 = if selected then ACCENT else RAISED
	item.BorderSizePixel = 0
	item.FontFace = LABELS
	item.TextSize = 14
	item.TextColor3 = if selected then SHADE else INK
	item.Text = label
	item.AutomaticSize = Enum.AutomaticSize.X
	item.Size = UDim2.fromOffset(0, 26)
	item.LayoutOrder = order
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = item
	item.Activated:Connect(pressed)
	item.Parent = parent
end

local function render(entry: Registry.Entry)
	shown = entry
	if gui == nil or gui.Parent == nil then
		build()
	end
	if gui == nil then
		return
	end
	title.Text = string.upper(entry.config.Name)
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local base = Registry.get(entry.id) or entry
	local any = false
	for order, slot in Attachments.Slots do
		local options = Registry.options(base, slot)
		if #options == 0 then
			continue
		end
		any = true
		local row = Instance.new("Frame")
		row.Name = slot
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromScale(1, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = order
		row.Parent = list
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.Padding = UDim.new(0, 6)
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Parent = row

		local heading = text(row, LABELS, 13, MUTED)
		heading.Text = string.upper(slot)
		heading.Size = UDim2.new(1, 0, 0, 16)
		heading.LayoutOrder = 0

		local buttons = Instance.new("Frame")
		buttons.BackgroundTransparency = 1
		buttons.Size = UDim2.fromScale(1, 0)
		buttons.AutomaticSize = Enum.AutomaticSize.Y
		buttons.LayoutOrder = 1
		buttons.Parent = row
		local flow = Instance.new("UIGridLayout")
		flow.CellSize = UDim2.fromOffset(150, 26)
		flow.CellPadding = UDim2.fromOffset(6, 6)
		flow.SortOrder = Enum.SortOrder.LayoutOrder
		flow.Parent = buttons

		local current = entry.fitted[slot]
		button(buttons, "None", current == nil, 0, function()
			if onPick then
				onPick(slot, nil)
			end
		end)
		for index, id in options do
			local attachment = Attachments.get(id)
			button(buttons, if attachment then attachment.name else id, current == id, index, function()
				if onPick then
					onPick(slot, id)
				end
			end)
		end
	end
	if not any then
		local none = text(list, LABELS, 14, MUTED)
		none.Text = "This weapon takes no attachments."
		none.Size = UDim2.new(1, 0, 0, 18)
	end
end

-- Opens the menu for `entry`, or closes it if it is open.
function AttachmentMenu.toggle(entry: Registry.Entry, pick: Pick)
	if open then
		AttachmentMenu.close()
		return
	end
	onPick = pick
	render(entry)
	if gui then
		gui.Enabled = true
		open = true
	end
end

-- Shows the weapon again after it was rebuilt, if the menu is open.
function AttachmentMenu.refresh(entry: Registry.Entry)
	generation += 1
	if open and shown and shown.id == entry.id then
		render(entry)
	elseif open then
		AttachmentMenu.close()
	end
end

--[[
	Closes the menu unless the weapon comes back first. Fitting an attachment
	rebuilds the weapon, which puts it away and draws it again a moment later;
	the menu should stay open through that.
]]
function AttachmentMenu.closeSoon()
	if not open then
		return
	end
	local waitingFor = generation
	task.delay(0.75, function()
		if generation == waitingFor then
			AttachmentMenu.close()
		end
	end)
end

function AttachmentMenu.isOpen(): boolean
	return open
end

function AttachmentMenu.close()
	open = false
	if gui then
		gui.Enabled = false
	end
end

return AttachmentMenu
