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

	-- Animation: encoded sampling, the procedural fallback, and the arm solver.
	local Encoded = require(clone.Framework.Animation.Encoded)
	local Animator = require(clone.Framework.Animation.Animator)
	local Arms = require(clone.Framework.Animation.Arms)
	local Registry = require(clone.Framework.Weapons.Registry)
	clone.Config.Source = "return {}"
	Config.load(clone)
	Registry.load(clone)

	local track = Encoded.compile("Test", "Slide", {
		Keyframes = {
			{ Time = 0, Mag = { 0, 0, 0, 0, 0, 0 } },
			{ Time = 1, Mag = { 0, -2, 0, 0, 90, 0 }, Easing = "Linear" },
			{ Time = 2, Bolt = { 0, 0, 1, 0, 0, 0 } },
		},
	})
	local sampled: { [string]: CFrame } = {}
	if track then
		Encoded.sample(track, 0.5, sampled)
	end
	local _, yaw = (sampled.Mag or CFrame.identity):ToOrientation()
	test(
		"encoded keyframes interpolate",
		track ~= nil and math.abs(sampled.Mag.Y + 1) < 1e-3 and math.abs(math.deg(yaw) - 45) < 0.1
	)
	test("a channel holds its only key", sampled.Bolt ~= nil and math.abs(sampled.Bolt.Z - 1) < 1e-3)
	test("length defaults to the last keyframe", track ~= nil and track.length == 2)
	local numbers = Encoded.numbers(Encoded.frame({ 1, 2, 3, 10, 20, 30 }) :: CFrame)
	test("six numbers round-trip", table.concat(numbers, ",") == "1,2,3,10,20,30")
	local bad = Encoded.compile("Test", "Bad", { Keyframes = { { Time = 0, Mag = "x" } } })
	test("a bad animation is rejected, not thrown", bad == nil)

	local glock = Registry.get("Glock17")
	local rifle = Registry.get("G36C")
	if glock and rifle then
		local now = os.clock()
		local encoded = Animator.new(glock)
		encoded:setAction("Reload", now - 0.46 * 1.6, 1.6, false)
		local pose = encoded:update(now)
		test(
			"encoded reload moves the magazine",
			pose.parts.Mag ~= nil and math.abs(pose.parts.Mag.Y + 1.5) < 0.01
		)

		local procedural = Animator.new(rifle)
		procedural:setAction("Reload", now - 0.32 * 2, 2, false)
		local reach = procedural:update(now)
		local attachments = procedural.attachments
		test(
			"weapon attachments are found",
			attachments.mag ~= nil and attachments.side ~= nil and attachments.aim ~= nil
		)
		test(
			"procedural reload sends the hand to the magazine",
			(reach.left.Position - attachments.grip.Position).Magnitude > 0.5
		)
		procedural:fire(now)
		test("procedural fire moves the bolt", procedural:update(now + 0.03).parts.Bolt ~= nil)
	else
		test("example weapons are loaded", false)
	end

	local target = Vector3.new(0, -1.2, -0.8)
	local elbow, wrist = Arms.twoBone(Vector3.zero, target, 1, 1, Vector3.xAxis)
	test(
		"two-bone IK keeps both bone lengths",
		math.abs(elbow.Magnitude - 1) < 1e-3 and math.abs((wrist - elbow).Magnitude - 1) < 1e-3
	)
	test("two-bone IK reaches a reachable target", (wrist - target).Magnitude < 1e-3)
	local _, short = Arms.twoBone(Vector3.zero, Vector3.new(0, -5, 0), 1, 1, Vector3.xAxis)
	test("two-bone IK stops at full stretch", math.abs(short.Magnitude - 2) < 0.01)

	clone:Destroy()
	table.insert(
		lines,
		if failed == 0 then `all {#lines} checks passed` else `{failed} of {#lines} checks FAILED`
	)
	return table.concat(lines, "\n")
end
