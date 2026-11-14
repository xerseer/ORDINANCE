--[[
	Checks the parts of the framework that are pure logic: the config schema,
	preset and tuning resolution, and the weapon state machine.

	It works on a clone of the Ordnance object, so the real modules are never
	loaded in edit mode and the real Config is never touched.

	Run from the command bar while `rojo serve` is connected:
		print(require(game.ServerStorage.OrdnanceDev.SelfTest)())
]]

return function(): string
	local clone = game:GetService("ReplicatedStorage").Ordnance:Clone()
	local Config = require(clone.Framework.Config)
	local State = require(clone.Framework.Weapons.State)
	local Schema = Config.Schema

	local lines: { string } = {}
	local failed = 0
	local function test(label: string, ok: boolean)
		if not ok then
			failed += 1
		end
		table.insert(lines, (if ok then "PASS " else "FAIL ") .. label)
	end

	-- Schema: bad input is cleaned and reported, never thrown on.
	local clean, problems = Schema.validate({
		Fire = { RPM = 99999, Mod = "Auto", Mode = "Full" },
		Ammo = "x",
		Keybinds = { Fire = { "MouseButton1", "Banana" } },
		Debug = { Logger = { Level = "Debug" } },
	}, "Weapon")
	local hinted = false
	for _, problem in problems do
		if problem.path == "Fire.Mod" and string.find(problem.message, 'Did you mean "Mode"', 1, true) then
			hinted = true
		end
	end
	test("out-of-range number is clamped", clean.Fire.RPM == 6000)
	test("unknown key is dropped with a suggestion", clean.Fire.Mod == nil and hinted)
	test("invalid choice is dropped", clean.Fire.Mode == nil)
	test("wrong type is dropped", clean.Ammo == nil)
	test("invalid key name is dropped", #clean.Keybinds.Fire == 1)
	test("global-only section is stripped from a weapon", clean.Debug == nil)
	test("every problem is reported once", #problems == 6)

	-- Resolution: Defaults < Preset < Config < weapon, then tuning.
	clone.Config.Source = 'return { Preset = "Realistic", Tuning = { Damage = 2 } }'
	Config.load(clone)
	local global = Config.global()
	test("preset is applied", global.Realism.ManualCycle == true and global.HUD.Crosshair == false)
	test("global config overrides the preset", global.Tuning.Damage == 2 and global.Tuning.Recoil == 1.5)
	local weapon = Config.weapon("T", {
		Damage = { Base = 10 },
		Recoil = { Vertical = 2 },
		Fire = { Modes = { "Semi" } },
	})
	test("tuning multipliers are folded in", weapon.Damage.Base == 20 and weapon.Recoil.Vertical == 3)
	test("start mode follows the selectable modes", weapon.Fire.Mode == "Semi")
	test("resolved config is frozen", table.isfrozen(weapon) and table.isfrozen(weapon.Fire))
	test("name defaults to the module name", weapon.Name == "T")

	-- State: a pump shotgun loaded one shell at a time.
	local off = { Chambering = false, ManualCycle = false, DropMagazine = false }
	local pump = Config.weapon("Pump", {
		Fire = { Action = "Pump", CycleTime = 0.5, Modes = { "Semi" } },
		Ammo = { Magazine = 4, Reserve = 3, ReloadType = "Single", ShellTime = 0.5 },
		Realism = off,
		Tuning = { ReloadTime = 1 },
	})
	local s = State.new(pump, 0)
	test("cannot fire while equipping", State.canFire(s, pump, 0.1) == false)
	State.advance(s, pump, 10)
	test("can fire once equipped", State.canFire(s, pump, 10) == true)
	State.fire(s, pump, 10)
	test("firing starts the pump cycle", s.action == "Cycle" and s.mag == 3)
	for _, time in { 10.6, 11.2 } do
		State.advance(s, pump, time)
		State.fire(s, pump, time)
	end
	State.advance(s, pump, 11.8)
	test("three shots leave one round", s.mag == 1)
	test("reload queues the shells it can", State.startReload(s, pump, 12) and s.shellsToLoad == 3)
	State.advance(s, pump, 12.6)
	test("one shell is in after one shell time", s.mag == 2 and s.reserve == 2 and s.action == "Reload")
	test("a shell reload can be interrupted by firing", State.canFire(s, pump, 12.6) == true)
	State.fire(s, pump, 12.6)
	test("firing cancels the reload", s.action == "Cycle" and s.mag == 1 and s.reserve == 2)
	State.advance(s, pump, 20)
	State.startReload(s, pump, 20)
	State.advance(s, pump, 30)
	test("reload stops when the reserve runs out", s.mag == 3 and s.reserve == 0 and s.action == "Idle")

	-- State: a bolt action with every realism option on.
	local bolt = Config.weapon("Bolt", {
		Fire = { Action = "Bolt", Modes = { "Semi" } },
		Ammo = { Magazine = 5, Reserve = 10 },
		Realism = { Chambering = true, ManualCycle = true, DropMagazine = true },
	})
	local b = State.new(bolt, 0)
	State.advance(b, bolt, 5)
	test("starts with a round chambered", State.loaded(b) == 6)
	State.fire(b, bolt, 5)
	test(
		"needs a manual cycle after firing",
		b.needsCycle and not b.chambered and State.canFire(b, bolt, 6) == false
	)
	test("cycle is accepted", State.cycle(b, bolt, 6))
	State.advance(b, bolt, 10)
	test("cycling chambers from the magazine", b.chambered and b.mag == 4)
	State.startReload(b, bolt, 10)
	State.advance(b, bolt, 20)
	test("a dropped magazine takes its rounds", b.mag == 5 and b.reserve == 5 and b.chambered)
	local copy = State.new(bolt, 100)
	State.apply(copy, State.snapshot(b, 20), 100)
	test(
		"snapshot survives a round trip",
		copy.mag == b.mag and copy.reserve == b.reserve and copy.action == "Idle"
	)

	clone:Destroy()
	table.insert(
		lines,
		if failed == 0 then `all {#lines} checks passed` else `{failed} of {#lines} checks FAILED`
	)
	return table.concat(lines, "\n")
end
