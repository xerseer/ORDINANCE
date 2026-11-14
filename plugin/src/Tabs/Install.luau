--!strict
--[[
	Install tab
	Shows what is installed, what is newest, and the one button that gets from
	one to the other. Works offline: the plugin carries a copy of the version
	it was built with.
]]

local Installer = require(script.Parent.Parent.Installer)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local Install = { name = "Install" }

local refresh: () -> () = function() end

function Install.build(parent: Frame)
	local _, content = UI.scroll(parent)

	UI.heading(content, "Ordnance", 1)
	UI.caption(
		content,
		"A modular gun framework. One object in ReplicatedStorage; delete it and nothing is left behind.",
		2
	)

	local state = UI.card(content, 3)
	local installedLine = UI.label(state, "", { font = Theme.fontMedium })
	local latestLine = UI.label(state, "", { color = "muted" })
	local _, setStatus = UI.status(state)

	local buttons = UI.row(content, Theme.rowHeight, Theme.space.sm, 4)
	local updateButton, enableUpdate = UI.button(buttons, "Update & Install", "primary", function() end)
	local checkButton = UI.button(buttons, "Check for updates", "default", function() end)
	local bundledButton = UI.button(content, "Install the bundled copy (offline)", "ghost", function() end, 5)
	local removeButton = UI.button(content, "Remove Ordnance from this place", "ghost", function() end, 6)

	UI.section(content, "What an update touches", 7)
	local note = UI.column(content, 4, 8)
	UI.label(note, "Replaced: the Framework folder and the Ordnance module.", { color = "muted", size = 12 })
	UI.label(
		note,
		"Never touched: your Config, your Weapons and any presets you made. Missing built-in presets are added.",
		{ color = "muted", size = 12 }
	)
	UI.label(note, "The whole install is one undo step.", { color = "muted", size = 12 })

	UI.section(content, "Connection", 9)
	UI.label(
		content,
		`Updates come from github.com/{Installer.repository} over HTTP. Studio asks once to allow raw.githubusercontent.com. If you decline, or you are offline, the bundled copy still installs.`,
		{ color = "muted", size = 12, order = 10 }
	)

	local latest: string? = nil
	local busy = false

	local function describe()
		local installed = Installer.installedVersion()
		installedLine.Text = if installed
			then `Installed: v{installed}`
			elseif Installer.installed() then "Installed (version unknown)"
			else "Not installed in this place"
		if latest then
			latestLine.Text = `Latest release: v{latest}`
		else
			latestLine.Text = "Latest release: not checked yet"
		end
		local newer = installed ~= nil and latest ~= nil and Installer.isNewer(latest, installed)
		updateButton.Text = if installed == nil
			then "Install"
			elseif newer then `Update to v{latest}`
			else "Update & Install"
		bundledButton.Visible = Installer.embedded() ~= nil
		removeButton.Visible = Installer.installed() ~= nil
	end

	local function run(job: () -> Installer.Result)
		if busy then
			return
		end
		busy = true
		enableUpdate(false)
		setStatus("Working...", "info")
		task.spawn(function()
			local ok, result = pcall(job)
			busy = false
			enableUpdate(true)
			if not ok then
				setStatus(tostring(result), "bad")
			else
				setStatus(result.message, if result.ok then "good" else "bad")
			end
			describe()
		end)
	end

	updateButton.Activated:Connect(function()
		run(Installer.update)
	end)
	bundledButton.Activated:Connect(function()
		run(Installer.installEmbedded)
	end)
	removeButton.Activated:Connect(function()
		run(Installer.uninstall)
	end)
	checkButton.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		setStatus("Checking...", "info")
		task.spawn(function()
			local version, problem = Installer.latest()
			busy = false
			latest = version
			if version then
				local installed = Installer.installedVersion()
				if installed and not Installer.isNewer(version, installed) then
					setStatus("You are up to date.", "good")
				else
					setStatus("A release is available.", "good")
				end
			else
				setStatus(problem or "Could not check.", "warn")
			end
			describe()
		end)
	end)

	refresh = describe
	describe()
end

function Install.onShow()
	refresh()
end

return Install
