extends Node
## Automated Phase 1 verification. Run headless:
##   godot --headless --path . --fixed-fps 60 -- --smoke-test
## Exits with code 0 when every check passes, 1 otherwise.

var player: Player
var director: WaveDirector
var arena: TestArena
var results: Array[String] = []
var failures: int = 0


func _ready() -> void:
	process_priority = -100
	var main := get_parent()
	player = main.get_node(^"Player")
	director = main.get_node(^"WaveDirector")
	arena = main.get_node(^"Arena")
	director.running = false
	get_tree().create_timer(240.0, true, false, true).timeout.connect(_watchdog)
	_run.call_deferred()


func _watchdog() -> void:
	print("FAIL  watchdog: smoke test did not finish in time")
	get_tree().quit(2)


func check(name: String, ok: bool, detail: String = "") -> void:
	var line := ("PASS  " if ok else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")")
	results.append(line)
	print(line)
	if not ok:
		failures += 1


## Process-frame timer so input presses land on the frame the player reads them.
func wait(t: float) -> void:
	await get_tree().create_timer(t, true, false).timeout


## Press an action at the START of a frame (before the player reads input), like
## real input events — presses from timer callbacks land after _process and would
## never register as "just pressed".
func tap(action: StringName) -> void:
	await get_tree().process_frame
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)


func clear_enemies() -> void:
	director.kill_all()
	for p in get_tree().get_nodes_in_group(Combat.GROUP_ENEMY_PROJECTILES):
		p.queue_free()
	await wait(0.6)


func spawn(id: StringName, at: Vector3, passive: bool = false) -> Enemy:
	var e: Enemy = WaveDirector.SCENES[id].instantiate()
	arena.add_child(e)
	e.global_position = at
	if passive:
		e.spawn_grace = 99999.0
	return e


func reset_player(at: Vector3 = Vector3.ZERO) -> void:
	player.health.reset()
	player.energy = player.max_energy
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.aim_override = at + Vector3(0, 0.9, -5)
	player.melee.cancel()
	player._dash_charges = player.dash_charges_max


func _run() -> void:
	print("==== DREAD PHASE 1 SMOKE TEST ====")
	await wait(0.5)

	# --- World / nav ---------------------------------------------------------
	var nm := arena.nav_region.navigation_mesh
	check("navmesh baked", nm != null and nm.get_polygon_count() > 50, "%d polys" % (nm.get_polygon_count() if nm else 0))
	check("spawn points", arena.spawn_points.size() > 10, "%d points" % arena.spawn_points.size())
	check("player visual is ActorVisual", player.visual is ActorVisual)
	check("muzzle socket exists", player.visual.get_socket(&"muzzle") != player.visual)

	# --- Movement ------------------------------------------------------------
	reset_player()
	var start := player.global_position
	Input.action_press(&"move_up")
	await wait(0.5)
	Input.action_release(&"move_up")
	var moved := player.global_position.distance_to(start)
	check("WASD moves player fast", moved > 4.0, "moved %.2f m in 0.5 s" % moved)

	# --- Dash ------------------------------------------------------------------
	reset_player()
	start = player.global_position
	await tap(&"dash")
	check("dash grants i-frames", player.health.invulnerable)
	await wait(0.2)
	check("dash consumes a charge", player._dash_charges == player.dash_charges_max - 1, "%d left" % player._dash_charges)
	check("dash bursts distance", player.global_position.distance_to(start) > 4.0, "%.2f m" % player.global_position.distance_to(start))
	for i in 2:
		await tap(&"dash")
		await wait(0.15)
	check("three dash charges chain", player._dash_charges == 0, "%d left" % player._dash_charges)

	# --- Rifle vs small enemies ----------------------------------------------
	reset_player()
	player.weapons.switch_to(0)
	var sw := spawn(&"swarmer", Vector3(0, 0, -9), true)
	await wait(0.6)
	player.aim_override = sw.global_position + Vector3.UP * 0.9
	Input.action_press(&"fire")
	await wait(0.6)
	Input.action_release(&"fire")
	check("rifle kills a Hatch Runner", not is_instance_valid(sw) or sw.is_dead())
	await clear_enemies()

	# strafing target, sloppy cursor: aim assist + magnetism must land shots
	reset_player()
	var target := spawn(&"swarmer", Vector3(-7, 0, -10), true)
	target.max_health = 99999.0
	target.health.reset(99999.0)
	await wait(0.6)
	target.process_mode = Node.PROCESS_MODE_DISABLED  # the test drives its motion
	var hits := [0]
	var on_hit := func(e: Node3D, _i: DamageInfo):
		if e == target:
			hits[0] += 1
	Events.enemy_damaged.connect(on_hit)
	var shots_before := _shots_fired
	Events.weapon_fired.connect(_count_shot)
	var t := 0.0
	var dir := 1.0
	Input.action_press(&"fire")
	while t < 2.5:
		var dt := get_process_delta_time()
		t += dt
		var p := target.global_position + Vector3(dir * 7.6 * dt, 0, 0)
		if absf(p.x) > 7.0:
			dir = -dir
		target.global_position = p
		target.velocity = Vector3(dir * 7.6, 0, 0)
		player.aim_override = target.global_position + Vector3(sin(t * 9.0) * 1.0, 0.9, cos(t * 7.0) * 0.8)
		await get_tree().process_frame
	Input.action_release(&"fire")
	await wait(0.4)
	Events.enemy_damaged.disconnect(on_hit)
	var shots := _shots_fired - shots_before
	var rate := float(hits[0]) / maxf(float(shots), 1.0)
	check("aim assist hits a strafing runner with a sloppy cursor", rate >= 0.7, "%d/%d hits = %d%%" % [hits[0], shots, int(rate * 100.0)])
	await clear_enemies()

	# scattergun one-shots a runner up close
	reset_player()
	player.weapons.switch_to(1)
	var close := spawn(&"swarmer", Vector3(0, 0, -4.5), true)
	await wait(0.5)
	player.aim_override = close.global_position + Vector3.UP * 0.9
	Input.action_press(&"fire")
	await wait(0.1)
	Input.action_release(&"fire")
	await wait(0.2)
	check("scattergun one-shots a runner up close", not is_instance_valid(close) or close.is_dead())
	player.weapons.switch_to(0)
	await clear_enemies()

	# --- Melee combo -----------------------------------------------------------
	reset_player()
	player.energy = 20.0
	var dummy := spawn(&"brute", Vector3(0, 0, -3.2), true)
	dummy.max_health = 99999.0
	dummy.health.reset(99999.0)
	await wait(0.5)
	player.aim_override = dummy.global_position + Vector3.UP
	var steps: Array[int] = []
	var step_hits: Array[int] = []
	var on_swing := func(step: int, n: int):
		steps.append(step)
		step_hits.append(n)
	player.melee.swung.connect(on_swing)
	var e0 := player.energy
	for i in 3:
		await tap(&"melee")
		await wait(0.1)
	await wait(0.5)
	player.melee.swung.disconnect(on_swing)
	check("melee combo plays 3 distinct swings", steps == [0, 1, 2], str(steps))
	check("every combo swing connects", step_hits.size() == 3 and step_hits.min() > 0, str(step_hits))
	check("combo swings chain fast (mashing)", steps.size() == 3, "3 presses within 0.4 s")
	check("melee refunds energy", player.energy > e0, "%.0f -> %.0f" % [e0, player.energy])
	await clear_enemies()

	# blade interrupts a light enemy's wind-up
	reset_player()
	var lunger := spawn(&"swarmer", Vector3(0, 0, -2.6))
	var interrupted := false
	for i in 120:
		await get_tree().process_frame
		player.aim_override = lunger.global_position + Vector3.UP
		if lunger.fsm.is_in(&"telegraph"):
			player.melee.try_melee()
			await wait(0.1)
			interrupted = lunger.is_dead() or not lunger.fsm.is_in(&"attack")
			break
	check("blade interrupts a runner's lunge wind-up", interrupted)
	await clear_enemies()

	# --- Brute vulnerability -> stagger -> finisher -------------------------------
	reset_player()
	var br := spawn(&"brute", Vector3(0, 0, -3.0), true)
	await wait(0.5)
	player.aim_override = br.global_position + Vector3.UP
	br.health.current = br.max_health * 0.3
	br.apply_damage(DamageInfo.make(1.0, DamageInfo.Kind.BULLET, player, br.global_position, Vector3.FORWARD))
	check("brute exposes core below threshold", br._vulnerable)
	for i in 6:
		if br.fsm.is_in(&"staggered"):
			break
		player.melee.cancel()
		player.melee._cooldown = 0.0
		player.melee.try_melee()
		await wait(0.12)
	check("brute staggers after poise break", br.fsm.is_in(&"staggered") or br.is_dead(), str(br.fsm.current_name))
	check("staggered brute is finishable", br.is_dead() or br.is_finishable())
	if not br.fsm.is_in(&"staggered"):
		br.fsm.change(&"staggered", {"duration": 5.0})
	var orbs_before := _count_orbs()
	player.health.current = 50.0
	await wait(0.4)
	player.melee.cancel()
	player.melee._cooldown = 0.0
	player.melee.try_melee()
	await wait(0.3)
	check("finisher kills brute", not is_instance_valid(br) or br.is_dead())
	check("finisher drops health orbs", _count_orbs() > orbs_before, "%d orbs" % _count_orbs())
	await wait(1.6)
	check("health orbs heal player", player.health.current > 50.0, "hp %.0f" % player.health.current)
	await clear_enemies()

	# --- Enemy AI: telegraph + attack -------------------------------------------
	reset_player()
	player.god_mode = false
	var states_seen := {}
	var runner := spawn(&"swarmer", Vector3(7, 0, 0))
	runner.fsm.state_changed.connect(func(_f, s): states_seen[s] = true)
	var hp0 := player.health.current
	player.aim_override = Vector3(-10, 0.9, 0)
	await wait(4.0)
	check("swarmer chases", states_seen.has(&"chase"))
	check("swarmer telegraphs", states_seen.has(&"telegraph"))
	check("swarmer attacks", states_seen.has(&"attack"))
	check("swarmer damages player", player.health.current < hp0, "hp %.0f" % player.health.current)
	await clear_enemies()

	reset_player()
	var sp := spawn(&"spitter", Vector3(-11, 0, 0))
	var sp_states := {}
	sp.fsm.state_changed.connect(func(_f, s): sp_states[s] = true)
	var globs_seen := false
	for i in 80:
		await wait(0.05)
		if not get_tree().get_nodes_in_group(Combat.GROUP_ENEMY_PROJECTILES).is_empty():
			globs_seen = true
			break
	check("spitter telegraphs", sp_states.has(&"telegraph"))
	check("spitter fires bile globs", globs_seen)
	var globs := get_tree().get_nodes_in_group(Combat.GROUP_ENEMY_PROJECTILES)
	if not globs.is_empty():
		player.god_mode = true  # let the glob reach the blade instead of splashing on us
		player.add_iframes(1.0)
		player.health.invulnerable = true
		var g: EnemyProjectile = globs[0]
		var gp := g.global_position + g.velocity.normalized() * 1.5
		player.global_position = Vector3(gp.x, 0.0, gp.z)
		player.aim_override = sp.global_position + Vector3.UP
		player.melee.cancel()
		player.melee._cooldown = 0.0
		var reflected_hit := [false]
		var on_dmg := func(_e: Node3D, info: DamageInfo):
			if info.tags.has("reflected"):
				reflected_hit[0] = true
		Events.enemy_damaged.connect(on_dmg)
		player.melee.try_melee()
		await wait(0.5)
		Events.enemy_damaged.disconnect(on_dmg)
		var ok: bool = reflected_hit[0] or (is_instance_valid(g) and g.reflected)
		check("melee reflects bile back into the spitter", ok, "reflected hit landed" if reflected_hit[0] else "no reflected hit")
		player.god_mode = false
	await clear_enemies()

	reset_player()
	var hulk := spawn(&"brute", Vector3(4, 0, 0))
	var br_states := {}
	hulk.fsm.state_changed.connect(func(_f, s): br_states[s] = true)
	var tele_seen := false
	for i in 120:
		await wait(0.05)
		for n in arena.get_children():
			if n is Telegraph:
				tele_seen = true
		if br_states.has(&"attack"):
			break
	check("brute shows ground telegraph", tele_seen)
	check("brute slams", br_states.has(&"attack"))
	await clear_enemies()

	# --- Abilities --------------------------------------------------------------
	reset_player()
	player.god_mode = true
	for i in 3:
		spawn(&"swarmer", Vector3(-3 + i * 3, 0, -8), true)
	await wait(0.5)
	player.aim_override = Vector3(0, 0.9, -8)
	await wait(0.1)
	check("Q micro-rockets fire", player.abilities.use(&"q"))
	await wait(1.5)
	check("rockets kill swarmers", Combat.living_enemies(get_tree()).size() < 3, "%d left" % Combat.living_enemies(get_tree()).size())
	check("E nova fires", player.abilities.use(&"e"))
	check("abilities go on cooldown", player.abilities.ratio(&"q") > 0.0 and player.abilities.ratio(&"e") > 0.0)
	await clear_enemies()

	# --- Waves + autopilot soak --------------------------------------------------
	reset_player()
	director.running = true
	director._break_t = 0.1
	add_child(preload("res://tests/autopilot.gd").new())
	await wait(30.0)
	check("waves progress under autopilot", director.wave >= 2, "reached wave %d" % director.wave)
	check("no runaway node count", get_tree().get_node_count() < 6000, "%d nodes" % get_tree().get_node_count())

	print("==== %d checks, %d failed ====" % [results.size(), failures])
	get_tree().quit(1 if failures > 0 else 0)


var _shots_fired: int = 0


func _count_shot(_w: Resource) -> void:
	_shots_fired += 1


func _count_orbs() -> int:
	var n := 0
	for c in get_parent().get_children():
		if c is PickupOrb:
			n += 1
	return n
