--!strict
--[[
	Sessions
	What the server knows about each player: which weapons they carry, the
	authoritative state of each, and which one is in their hands.

	In the default "Tool" inventory mode every weapon is a Backpack Tool built
	from the weapon's model, so equipping, the hotbar, mobile and gamepad all
	work the way players already expect. In "Custom" mode nothing is handed
	out; the game calls Ordnance.Equip itself.
]]

local Players = game:GetService("Players")

local Framework = script.Parent.Parent

local Config = require(Framework.Config)
local Events = require(Framework.Core.Events)
local Logger = require(Framework.Core.Logger)
local Net = require(Framework.Core.Net)
local Registry = require(Framework.Weapons.Registry)
local Rig = require(Framework.Weapons.Rig)
local State = require(Framework.Weapons.State)

export type Session = {
	player: Player,
	seed: number,
	states: { [string]: State.State },
	tools: { [string]: Tool },
	equipped: string?,
	heldModel: Model?, -- Custom mode only
	lastShotId: number,
	fireTokens: number,
	fireTime: number,
}

local WEAPON_ATTRIBUTE = "OrdnanceWeapon"

local log = Logger.scope("Sessions")

local Sessions = {}

Sessions.WeaponAttribute = WEAPON_ATTRIBUTE

local sessions: { [Player]: Session } = {}
local connections: { RBXScriptConnection } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}
local seedSource = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

function Sessions.get(player: Player): Session?
	return sessions[player]
end

-- The authoritative state of a weapon, created full on first use.
function Sessions.state(session: Session, entry: Registry.Entry): State.State
	local state = session.states[entry.id]
	if state == nil then
		state = State.new(entry.config, now())
		session.states[entry.id] = state
	end
	return state
end

-- Sends the client the server's view of a weapon.
function Sessions.sync(session: Session, id: string)
	local state = session.states[id]
	if state then
		Net.fireClient(session.player, "Sync", id, State.snapshot(state, now()), session.seed)
	end
end

local function onEquipped(session: Session, entry: Registry.Entry)
	session.equipped = entry.id
	local state = Sessions.state(session, entry)
	State.equip(state, entry.config, now())
	-- A fresh allowance so the first shots after a swap are never throttled.
	session.fireTokens = 3
	session.fireTime = os.clock()
	Sessions.sync(session, entry.id)
	Events.Equipped:Fire(session.player, entry.id)
end

local function onUnequipped(session: Session, id: string)
	if session.equipped ~= id then
		return
	end
	session.equipped = nil
	local state = session.states[id]
	if state and state.action == "Reload" then
		state.action = "Idle" -- putting the weapon away abandons the reload
	end
	Events.Unequipped:Fire(session.player, id)
end

local function buildTool(session: Session, entry: Registry.Entry): Tool
	local tool = Instance.new("Tool")
	tool.Name = entry.config.Name
	tool.ToolTip = entry.config.Description
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute(WEAPON_ATTRIBUTE, entry.id)

	local model = entry.template:Clone()
	local handle = model.PrimaryPart :: BasePart
	tool.Grip = Rig.gripCFrame(model)
	handle.Name = "Handle"
	for _, child in model:GetChildren() do
		child.Parent = tool
	end
	model:Destroy()

	tool.Equipped:Connect(log:Wrap(function()
		onEquipped(session, entry)
	end))
	tool.Unequipped:Connect(log:Wrap(function()
		onUnequipped(session, entry.id)
	end))
	return tool
end

-- Adds a weapon to the player's inventory. In Tool mode this puts a Tool in
-- their Backpack. Returns false if the weapon does not exist.
function Sessions.give(player: Player, id: string): boolean
	local session = sessions[player]
	local entry = Registry.get(id)
	if session == nil then
		return false
	end
	if entry == nil then
		log:Warn(`cannot give "{id}" to {player.Name}: no weapon has that name`)
		return false
	end
	Sessions.state(session, entry)

	if Config.global().Inventory.Mode ~= "Tool" then
		return true
	end
	local existing = session.tools[id]
	if existing and existing.Parent ~= nil then
		return true
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack == nil then
		return false
	end
	local tool = buildTool(session, entry)
	session.tools[id] = tool
	tool.Parent = backpack
	return true
end

function Sessions.take(player: Player, id: string)
	local session = sessions[player]
	if session == nil then
		return
	end
	if session.equipped == id then
		Sessions.unequip(player)
	end
	local tool = session.tools[id]
	if tool then
		tool:Destroy()
		session.tools[id] = nil
	end
	session.states[id] = nil
end

local function removeHeldModel(session: Session)
	if session.heldModel then
		session.heldModel:Destroy()
		session.heldModel = nil
	end
end

-- Puts a weapon in the player's hands. In Tool mode this equips the Tool; in
-- Custom mode it welds the weapon model to the character.
function Sessions.equip(player: Player, id: string): boolean
	local session = sessions[player]
	local entry = Registry.get(id)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if session == nil or entry == nil or character == nil or humanoid == nil then
		return false
	end

	if Config.global().Inventory.Mode == "Tool" then
		if not Sessions.give(player, id) then
			return false
		end
		humanoid:EquipTool(session.tools[id])
		return true
	end

	Sessions.unequip(player)
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand == nil or not hand:IsA("BasePart") then
		log:Warn(`cannot equip "{id}" on {player.Name}: the character has no right hand`)
		return false
	end

	local model = entry.template:Clone()
	local handle = model.PrimaryPart :: BasePart
	local handGrip = hand:FindFirstChild("RightGripAttachment")
	local motor = Instance.new("Motor6D")
	motor.Name = "OrdnanceGrip"
	motor.Part0 = hand
	motor.Part1 = handle
	motor.C0 = if handGrip and handGrip:IsA("Attachment") then handGrip.CFrame else CFrame.identity
	motor.C1 = Rig.gripCFrame(model)
	motor.Parent = handle
	model:SetAttribute(WEAPON_ATTRIBUTE, id)
	model.Parent = character
	session.heldModel = model

	Net.fireClient(player, "Equip", id)
	onEquipped(session, entry)
	return true
end

function Sessions.unequip(player: Player)
	local session = sessions[player]
	if session == nil then
		return
	end
	local id = session.equipped
	if Config.global().Inventory.Mode == "Tool" then
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			humanoid:UnequipTools()
		end
		return
	end
	removeHeldModel(session)
	if id then
		Net.fireClient(player, "Equip", nil)
		onUnequipped(session, id)
	end
end

local function giveLoadout(player: Player)
	local inventory = Config.global().Inventory
	if inventory.Mode ~= "Tool" or not inventory.GiveOnSpawn then
		return
	end
	local ids = if table.find(inventory.Loadout, "*") then Registry.ids() else inventory.Loadout
	for _, id in ids do
		Sessions.give(player, id)
	end
end

local function onCharacter(player: Player)
	local session = sessions[player]
	if session == nil then
		return
	end
	-- A new life starts with full weapons and nothing in hand.
	table.clear(session.states)
	table.clear(session.tools)
	session.equipped = nil
	session.heldModel = nil
	giveLoadout(player)
end

local function onPlayer(player: Player)
	sessions[player] = {
		player = player,
		seed = seedSource:NextInteger(1, 2 ^ 30),
		states = {},
		tools = {},
		equipped = nil,
		heldModel = nil,
		lastShotId = 0,
		fireTokens = 3,
		fireTime = os.clock(),
	}
	characterConnections[player] = player.CharacterAdded:Connect(log:Wrap(function()
		onCharacter(player)
	end))
	if player.Character then
		onCharacter(player)
	end
end

local function onPlayerRemoving(player: Player)
	local connection = characterConnections[player]
	if connection then
		connection:Disconnect()
		characterConnections[player] = nil
	end
	sessions[player] = nil
end

function Sessions.start()
	table.insert(connections, Players.PlayerAdded:Connect(log:Wrap(onPlayer)))
	table.insert(connections, Players.PlayerRemoving:Connect(log:Wrap(onPlayerRemoving)))
	for _, player in Players:GetPlayers() do
		log:Try(onPlayer, player)
	end
end

function Sessions.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for player, session in sessions do
		for _, tool in session.tools do
			tool:Destroy()
		end
		removeHeldModel(session)
		local connection = characterConnections[player]
		if connection then
			connection:Disconnect()
		end
	end
	table.clear(characterConnections)
	table.clear(sessions)
end

return Sessions
