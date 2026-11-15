--!strict
--[[
	Input
	Binds a weapon's keybinds while it is held.

	Bindings go through ContextActionService, which gives keyboard, mouse,
	gamepad and on-screen touch buttons from one list of key names. Inputs are
	passed on rather than sunk, so the camera's right-mouse drag and other
	game bindings keep working while a weapon is out.
]]

local ContextActionService = game:GetService("ContextActionService")

local Logger = require(script.Parent.Parent.Core.Logger)

export type Handler = (pressed: boolean) -> ()

local PREFIX = "Ordnance"

-- Where each touch button sits inside the mobile button area, and its label.
local TOUCH: { [string]: { position: UDim2, title: string } } = {
	Fire = { position = UDim2.new(0.3, 0, 0.32, 0), title = "Fire" },
	Aim = { position = UDim2.new(0.62, 0, 0.02, 0), title = "Aim" },
	Reload = { position = UDim2.new(0.02, 0, 0.55, 0), title = "Reload" },
	FireMode = { position = UDim2.new(0.02, 0, 0.18, 0), title = "Mode" },
	Cycle = { position = UDim2.new(0.32, 0, -0.08, 0), title = "Cycle" },
	Light = { position = UDim2.new(0.62, 0, 0.55, 0), title = "Light" },
	Attachments = { position = UDim2.new(0.02, 0, -0.08, 0), title = "Kit" },
}

local log = Logger.scope("Input")

local Input = {}

local bound: { string } = {}

local function toEnum(name: string): Enum.KeyCode | Enum.UserInputType | nil
	local ok, key = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	if ok and key then
		return key
	end
	local okType, inputType = pcall(function()
		return (Enum.UserInputType :: any)[name]
	end)
	if okType and inputType then
		return inputType
	end
	return nil
end

--[[
	Binds each action in `handlers` to its keys in `keybinds`. Call unbind
	before binding a different weapon.
]]
function Input.bind(
	keybinds: { [string]: { string } },
	touchButtons: boolean,
	handlers: { [string]: Handler }
)
	Input.unbind()
	for action, handler in handlers do
		local names = keybinds[action]
		if names == nil or #names == 0 then
			continue
		end
		local inputs = {}
		for _, name in names do
			local input = toEnum(name)
			if input then
				table.insert(inputs, input)
			end
		end
		if #inputs == 0 then
			continue
		end

		local id = PREFIX .. action
		local wrapped = log:Wrap(handler)
		ContextActionService:BindAction(id, function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				wrapped(true)
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				wrapped(false)
			end
			return Enum.ContextActionResult.Pass
		end, touchButtons, table.unpack(inputs))
		table.insert(bound, id)

		local touch = TOUCH[action]
		if touchButtons and touch then
			ContextActionService:SetTitle(id, touch.title)
			ContextActionService:SetPosition(id, touch.position)
		end
	end
end

function Input.unbind()
	for _, id in bound do
		ContextActionService:UnbindAction(id)
	end
	table.clear(bound)
end

-- The first key in a list that is a keyboard or mouse input, for HUD hints.
function Input.label(names: { string }): string
	for _, name in names do
		if string.sub(name, 1, 6) ~= "Button" and string.sub(name, 1, 4) ~= "DPad" then
			if name == "MouseButton1" then
				return "LMB"
			elseif name == "MouseButton2" then
				return "RMB"
			end
			return name
		end
	end
	return names[1] or ""
end

return Input
