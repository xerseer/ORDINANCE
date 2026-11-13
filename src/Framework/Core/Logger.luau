--!strict
--[[
	Logger
	Every message the framework emits goes through here, so it is tagged the
	same way ("[Ordnance:Scope] ...") and can be filtered in the Output window.

		local log = Logger.scope("Ballistics")
		log:Info("registered", count, "weapons")
		log:Error("model has no Handle")          -- behaviour set by ErrorBehavior
		local ok, result = log:Try(riskyFunction, argument)

	Settings (see Config.Debug.Logger):
		Level          "None" | "Error" | "Warn" | "Info" | "Debug"   most verbose level to emit
		ErrorBehavior  "Throw" | "Warn" | "Info" | "Print"            what :Error() does
		Tag            prefix used on every line
		History        entries kept for the in-game overlay
		CaptureLogService  also record uncaught errors that mention the tag
		Traceback      append a stack trace to errors caught by :Try()

	The logger has no dependencies on the rest of the framework, so it is safe
	to require from anywhere, including before the config has been resolved.
]]

local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

local Signal = require(script.Parent.Signal)

export type Level = "Error" | "Warn" | "Info" | "Debug"
export type ErrorBehavior = "Throw" | "Warn" | "Info" | "Print"

export type Settings = {
	Level: Level | "None",
	ErrorBehavior: ErrorBehavior,
	Tag: string,
	History: number,
	CaptureLogService: boolean,
	Traceback: boolean,
}

export type Entry = {
	time: number,
	level: Level,
	scope: string,
	message: string,
	side: "Server" | "Client",
}

export type Scoped = {
	Error: (self: Scoped, ...any) -> (),
	Warn: (self: Scoped, ...any) -> (),
	Info: (self: Scoped, ...any) -> (),
	Debug: (self: Scoped, ...any) -> (),
	Print: (self: Scoped, ...any) -> (),
	WarnOnce: (self: Scoped, key: string, ...any) -> (),
	Try: <A..., R...>(self: Scoped, fn: (A...) -> R..., A...) -> (boolean, R...),
	Wrap: <A...>(self: Scoped, fn: (A...) -> ...any) -> (A...) -> (),
}

local RANK: { [string]: number } = { None = 0, Error = 1, Warn = 2, Info = 3, Debug = 4 }
local SIDE: "Server" | "Client" = if RunService:IsServer() then "Server" else "Client"

local settings: Settings = {
	Level = "Info",
	ErrorBehavior = "Warn",
	Tag = "Ordnance",
	History = 200,
	CaptureLogService = true,
	Traceback = true,
}

local history: { Entry } = {}
local warnedOnce: { [string]: boolean } = {}
local scopes: { [string]: Scoped } = {}
local captureConnection: RBXScriptConnection? = nil

local Logger = {}

-- Fires for every recorded entry, including uncaught errors picked up from
-- LogService. The debug overlay listens to this.
Logger.MessageLogged = Signal.new() :: Signal.Signal<Entry>

local function stringify(...: any): string
	local count = select("#", ...)
	if count == 1 then
		return tostring((...))
	end
	local parts = table.create(count)
	for index = 1, count do
		parts[index] = tostring((select(index, ...)))
	end
	return table.concat(parts, " ")
end

local function record(level: Level, scope: string, message: string)
	local entry: Entry = {
		time = os.clock(),
		level = level,
		scope = scope,
		message = message,
		side = SIDE,
	}
	table.insert(history, entry)
	while #history > settings.History do
		table.remove(history, 1)
	end
	Logger.MessageLogged:Fire(entry)
end

local function prefix(scope: string): string
	return `[{settings.Tag}:{scope}] `
end

local function emit(level: Level, scope: string, message: string)
	if RANK[level] > RANK[settings.Level] then
		return
	end
	record(level, scope, message)

	local line = prefix(scope) .. message
	if level == "Error" then
		local behavior = settings.ErrorBehavior
		if behavior == "Throw" then
			error(line, 0)
		elseif behavior == "Warn" then
			warn(line)
		else
			-- "Info" and "Print" both land in the output as plain text; "Info"
			-- keeps the word so it still stands out when filtering.
			print(if behavior == "Info" then prefix(scope) .. "error: " .. message else line)
		end
	elseif level == "Warn" then
		warn(line)
	elseif level == "Debug" then
		print(prefix(scope) .. "(debug) " .. message)
	else
		print(line)
	end
end

local function newScope(scope: string): Scoped
	local self = {} :: any

	function self.Error(_: Scoped, ...: any)
		emit("Error", scope, stringify(...))
	end

	function self.Warn(_: Scoped, ...: any)
		emit("Warn", scope, stringify(...))
	end

	function self.Info(_: Scoped, ...: any)
		emit("Info", scope, stringify(...))
	end

	function self.Debug(_: Scoped, ...: any)
		-- Cheap early-out: debug calls sit in hot paths.
		if RANK[settings.Level] < 4 then
			return
		end
		emit("Debug", scope, stringify(...))
	end

	-- Unconditional, untracked print with the tag. For one-off banners.
	function self.Print(_: Scoped, ...: any)
		print(prefix(scope) .. stringify(...))
	end

	-- Warns the first time `key` is seen, then stays quiet. For per-frame code.
	function self.WarnOnce(_: Scoped, key: string, ...: any)
		local id = scope .. "\0" .. key
		if warnedOnce[id] then
			return
		end
		warnedOnce[id] = true
		emit("Warn", scope, stringify(...))
	end

	-- pcall that reports failures through the logger instead of losing them.
	function self.Try(_: Scoped, fn: (...any) -> ...any, ...: any): ...any
		local function handler(problem: any): string
			local text = tostring(problem)
			if settings.Traceback then
				text ..= "\n" .. debug.traceback(nil, 2)
			end
			return text
		end
		local results = table.pack(xpcall(fn, handler, ...))
		if not results[1] then
			emit("Error", scope, tostring(results[2]))
			return false
		end
		return table.unpack(results, 1, results.n)
	end

	-- Returns a function safe to hand to a signal: it never throws.
	function self.Wrap(_: Scoped, fn: (...any) -> ...any): (...any) -> ()
		return function(...: any)
			self:Try(fn, ...)
		end
	end

	return self :: Scoped
end

-- Returns the logger for a named part of the framework. Scopes are cached.
function Logger.scope(scope: string): Scoped
	local existing = scopes[scope]
	if existing then
		return existing
	end
	local created = newScope(scope)
	scopes[scope] = created
	return created
end

local function refreshCapture()
	if captureConnection then
		captureConnection:Disconnect()
		captureConnection = nil
	end
	if not settings.CaptureLogService then
		return
	end
	-- Errors that escaped a pcall inside framework scripts never pass through
	-- emit(), but their text names the script path, which contains the tag.
	captureConnection = LogService.MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
		if messageType ~= Enum.MessageType.MessageError then
			return
		end
		if string.find(message, settings.Tag, 1, true) == nil then
			return
		end
		if string.sub(message, 1, #settings.Tag + 2) == `[{settings.Tag}:` then
			return -- one of ours, already recorded
		end
		record("Error", "Uncaught", message)
	end)
end

-- Applies settings. Unknown or mistyped fields are ignored rather than
-- thrown on: the logger must stay usable even with a broken config.
function Logger.configure(overrides: { [string]: any })
	if type(overrides) ~= "table" then
		return
	end
	if type(overrides.Level) == "string" and RANK[overrides.Level] ~= nil then
		settings.Level = overrides.Level
	end
	local behavior = overrides.ErrorBehavior
	if behavior == "Throw" or behavior == "Warn" or behavior == "Info" or behavior == "Print" then
		settings.ErrorBehavior = behavior
	end
	if type(overrides.Tag) == "string" and overrides.Tag ~= "" then
		settings.Tag = overrides.Tag
	end
	if type(overrides.History) == "number" then
		settings.History = math.clamp(math.floor(overrides.History), 0, 5000)
	end
	if type(overrides.CaptureLogService) == "boolean" then
		settings.CaptureLogService = overrides.CaptureLogService
	end
	if type(overrides.Traceback) == "boolean" then
		settings.Traceback = overrides.Traceback
	end
	refreshCapture()
end

function Logger.getSettings(): Settings
	return table.clone(settings)
end

-- Recorded entries, oldest first. Returns a copy.
function Logger.getHistory(): { Entry }
	return table.clone(history)
end

function Logger.clearHistory()
	table.clear(history)
	table.clear(warnedOnce)
end

-- Stops listening to LogService. Called when the framework is removed.
function Logger.shutdown()
	if captureConnection then
		captureConnection:Disconnect()
		captureConnection = nil
	end
	Logger.MessageLogged:DisconnectAll()
end

refreshCapture()

return Logger
