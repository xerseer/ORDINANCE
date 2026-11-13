--!strict
--[[
	Ordnance Studio plugin.
	The tabs (installer, config, previewer, converter, IK helper, presets,
	catalogue) arrive in phase 4. Until then this only registers the toolbar
	button so the plugin project builds and loads cleanly.
]]

local toolbar = plugin:CreateToolbar("Ordnance")
local button = toolbar:CreateButton("Ordnance", "Open the Ordnance panel", "")
button.ClickableWhenViewportHidden = true

button.Click:Connect(function()
	print("[Ordnance:Plugin] The panel is not built yet.")
	button:SetActive(false)
end)
