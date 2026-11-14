--!strict
--[[
	Theme
	One palette, two moods, chosen from Studio's own theme and updated live.

	The dark palette is the docs site's: warm near-black, one olive accent,
	flat surfaces separated by hairlines. The light palette is the same idea
	on warm paper. Nothing in the plugin uses a colour that is not in here.
]]

local Studio = settings().Studio

export type Palette = {
	bg: Color3,
	surface: Color3,
	raised: Color3,
	line: Color3,
	lineStrong: Color3,
	fg: Color3,
	muted: Color3,
	accent: Color3,
	accentSoft: Color3,
	onAccent: Color3,
	danger: Color3,
	warn: Color3,
	code: Color3,
}

local DARK: Palette = {
	bg = Color3.fromHex("#161615"),
	surface = Color3.fromHex("#1c1c1a"),
	raised = Color3.fromHex("#242422"),
	line = Color3.fromHex("#242422"),
	lineStrong = Color3.fromHex("#2f2f2c"),
	fg = Color3.fromHex("#e8e7e2"),
	muted = Color3.fromHex("#9c9a92"),
	accent = Color3.fromHex("#b3bf7d"),
	accentSoft = Color3.fromHex("#2a2e1f"),
	onAccent = Color3.fromHex("#161615"),
	danger = Color3.fromHex("#d97a6c"),
	warn = Color3.fromHex("#d9a27a"),
	code = Color3.fromHex("#1f1f1d"),
}

local LIGHT: Palette = {
	bg = Color3.fromHex("#f4f3ee"),
	surface = Color3.fromHex("#eceae3"),
	raised = Color3.fromHex("#e3e1d8"),
	line = Color3.fromHex("#dcdad0"),
	lineStrong = Color3.fromHex("#c7c5b9"),
	fg = Color3.fromHex("#1f1f1d"),
	muted = Color3.fromHex("#6b6a63"),
	accent = Color3.fromHex("#5b6828"),
	accentSoft = Color3.fromHex("#e0e5cc"),
	onAccent = Color3.fromHex("#f4f3ee"),
	danger = Color3.fromHex("#b4483a"),
	warn = Color3.fromHex("#9a6228"),
	code = Color3.fromHex("#e6e4dc"),
}

local Theme = {}

Theme.fontBody = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Regular)
Theme.fontMedium = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium)
Theme.fontBold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
Theme.fontMono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular)

-- Spacing scale, in pixels. Everything in the UI is a multiple of 4.
Theme.space = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 }
Theme.rowHeight = 28
Theme.textSize = 13

local isDark = true
local listeners: { () -> () } = {}

local function current(): Palette
	return if isDark then DARK else LIGHT
end

local function refresh()
	local name = tostring(Studio.Theme)
	isDark = string.find(name, "Light") == nil
	for _, listener in listeners do
		listener()
	end
end

-- The active palette. Read it fresh each time; it changes with Studio's theme.
function Theme.palette(): Palette
	return current()
end

-- Runs `apply` now and whenever Studio's theme changes. Returns a disconnect.
function Theme.bind(apply: () -> ()): () -> ()
	apply()
	table.insert(listeners, apply)
	return function()
		local index = table.find(listeners, apply)
		if index then
			table.remove(listeners, index)
		end
	end
end

function Theme.start()
	refresh()
	Studio.ThemeChanged:Connect(refresh)
end

return Theme
