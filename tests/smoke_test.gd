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
	process_physics_priority = -100
	var main := get_parent()
	player = main.get_node(^"Player")
	director = main.get_node(^"WaveDirector")
	arena = main.get_node(^"Arena")
	director.running = false
	get_tree().create_timer(180.0, true, false, true).timeout.connect(_watchdog)
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


func wait(t: float) -> void:
	await get_tree().create_timer(t, true, true).timeout


func clear_enemies() -> void:
	director.kill_all()
	await wait(0.6)


func spawn(id: StringName, offset: Vector3) -> Enemy:
	var e: Enemy = WaveDirector.SCENES[id].instantiate()
	arena.add_child(e)
	e.global_position = player.global_position + offset
	return e


func _run() -> void:
	print("==== DREAD PHASE 1 SMOKE TEST ====")
	await wait(0.5)

	# --- World / nav
	var nm := arena.nav_region.navigation_mesh
	check("navmesh baked", nm != null and nm.get_polygon_count() > 50, "%d polys" % (nm.get_polygon_count() if nm else 0))
	check("spawn points", arena.spawn_points.size() > 10, "%d points" % arena.spawn_points.size())
	check("player visual is ActorVisual", player.visual is ActorVisual)
	check("muzzle socket exists", player.visual.get_socket(&"muzzle") != player.visual)

	# --- Movement
	var start := player.global_position
	Input.action_press(&"move_up")
	await wait(0.5)
	Input.action_release(&"move_up")
	check("WASD moves player", player.global_position.distance_to(start) > 2.0, "moved %.2f m" % player.global_position.distance_to(start))

	# --- Dash
	var charges := player._dash_charges
	start = player.global_position
	player.aim_override = player.global_position + Vector3(5, 1.2, 0)
	Input.action_press(&"dash")
	await wait(0.05)
	Input.action_release(&"dash")
	check("dash grants i-frames", player.health.invulnerable)
	await wait(0.25)
	check("dash consumes a charge", player._dash_charges == charges - 1)
	check("dash bursts distance", player.global_position.distance_to(start) > 3.0, "%.2f m" % player.global_position.distance_to(start))

	# --- Shooting
	player.global_position = Vector3(0, 0, 4)
	var dummy := spawn(&"spitter", Vector3(0, 0, -9))
	dummy.spawn_grace = 999.0
	await wait(0.6)
	player.aim_override = dummy.global_position + Vector3.UP * 1.2
	var energy_before := player.energy
	var hp_before := dummy.health.current
	Input.action_press(&"fire")
	await wait(0.8)
	Input.action_release(&"fire")
	await wait(0.3)
	check("firing consumes energy", player.energy < energy_before, "%.0f -> %.0f" % [energy_before, player.energy])
	var dummy_hurt := not is_instance_valid(dummy) or dummy.is_dead() or dummy.health.current < hp_before
	check("projectiles damage enemy", dummy_hurt, "%.0f -> %.0f" % [hp_before, dummy.health.current if is_instance_valid(dummy) else 0.0])
	await clear_enemies()

	# --- Melee refunds energy
	player.energy = 20.0
	var sw := spawn(&"brute", Vector3(0, 0, -2.6))
	sw.spawn_grace = 999.0
	await wait(0.5)
	player.aim_override = sw.global_position + Vector3.UP
	var e0 := player.energy
	var bhp := sw.health.current
	player.melee.try_melee()
	await wait(0.1)
	check("melee damages", sw.health.current < bhp, "%.0f -> %.0f" % [bhp, sw.health.current])
	check("melee refunds energy", player.energy > e0, "%.0f -> %.0f" % [e0, player.energy])

	# --- Brute vulnerability -> stagger -> finisher
	sw.health.current = sw.max_health * 0.3
	var info := DamageInfo.make(1.0, DamageInfo.Kind.BULLET, player, sw.global_position, Vector3.FORWARD)
	sw.apply_damage(info)
	check("brute exposes core below threshold", sw._vulnerable)
	await wait(0.5)
	for i in 3:
		if sw.fsm.is_in(&"staggered"):
			break
		player.melee._cd = 0.0
		player.melee.try_melee()
		await wait(0.1)
	check("brute staggers after poise break", sw.fsm.is_in(&"staggered") or sw.is_dead(), str(sw.fsm.current_name))
	check("staggered brute is finishable", sw.is_dead() or sw.is_finishable())
	if not sw.fsm.is_in(&"staggered"):
		sw.fsm.change(&"staggered", {"duration": 5.0})
	var orbs_before := _count_orbs()
	player.health.current = 50.0
	await wait(0.45)
	player.melee._cd = 0.0
	player.melee.try_melee()
	await wait(0.3)
	check("finisher kills brute", not is_instance_valid(sw) or sw.is_dead())
	check("finisher drops health orbs", _count_orbs() > orbs_before, "%d orbs" % _count_orbs())
	await wait(1.6)
	check("health orbs heal player", player.health.current > 50.0, "hp %.0f" % player.health.current)
	await clear_enemies()

	# --- Enemy AI: telegraph + attack
	player.god_mode = false
	player.health.reset()
	player.global_position = Vector3.ZERO
	var states_seen := {}
	var swarm := spawn(&"swarmer", Vector3(7, 0, 0))
	swarm.fsm.state_changed.connect(func(_f, t): states_seen[t] = true)
	var hp0 := player.health.current
	player.aim_override = Vector3(-10, 1.2, 0)
	await wait(4.0)
	check("swarmer chases", states_seen.has(&"chase"))
	check("swarmer telegraphs", states_seen.has(&"telegraph"))
	check("swarmer attacks", states_seen.has(&"attack"))
	check("swarmer damages player", player.health.current < hp0, "hp %.0f" % player.health.current)
	await clear_enemies()

	player.health.reset()
	player.global_position = Vector3.ZERO
	var sp := spawn(&"spitter", Vector3(-11, 0, 0))
	var sp_states := {}
	sp.fsm.state_changed.connect(func(_f, t): sp_states[t] = true)
	var globs_seen := false
	for i in 80:
		await wait(0.05)
		if not get_tree().get_nodes_in_group(Combat.GROUP_ENEMY_PROJECTILES).is_empty():
			globs_seen = true
			break
	check("spitter telegraphs", sp_states.has(&"telegraph"))
	check("spitter fires bile globs", globs_seen)
	# reflect test
	var globs := get_tree().get_nodes_in_group(Combat.GROUP_ENEMY_PROJECTILES)
	if not globs.is_empty():
		var g: EnemyProjectile = globs[0]
		var gp := g.global_position + g.velocity.normalized() * 1.5
		player.global_position = Vector3(gp.x, 0.0, gp.z)
		player.aim_override = sp.global_position + Vector3.UP
		player.melee._cd = 0.0
		player.melee.try_melee()
		check("melee reflects bile", g.reflected)
	await clear_enemies()

	player.health.reset()
	player.global_position = Vector3.ZERO
	var br := spawn(&"brute", Vector3(4, 0, 0))
	var br_states := {}
	br.fsm.state_changed.connect(func(_f, t): br_states[t] = true)
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

	# --- Abilities
	player.global_position = Vector3.ZERO
	for i in 3:
		spawn(&"swarmer", Vector3(-3 + i * 3, 0, -8)).spawn_grace = 999.0
	await wait(0.5)
	player.aim_override = Vector3(0, 1.2, -8)
	await wait(0.1)  # aim_point refreshes on the player's next physics tick
	check("Q micro-rockets fire", player.abilities.use(&"q"))
	await wait(1.5)
	check("rockets kill swarmers", Combat.living_enemies(get_tree()).size() < 3, "%d left" % Combat.living_enemies(get_tree()).size())
	check("E nova fires", player.abilities.use(&"e"))
	check("abilities go on cooldown", player.abilities.ratio(&"q") > 0.0 and player.abilities.ratio(&"e") > 0.0)
	await clear_enemies()

	# --- Waves + autopilot soak
	player.god_mode = true
	director.running = true
	director._break_t = 0.1
	add_child(preload("res://tests/autopilot.gd").new())
	await wait(25.0)
	check("waves progress under autopilot", director.wave >= 2, "reached wave %d" % director.wave)
	check("no runaway node count", get_tree().get_node_count() < 6000, "%d nodes" % get_tree().get_node_count())

	print("==== %d checks, %d failed ====" % [results.size(), failures])
	get_tree().quit(1 if failures > 0 else 0)


func _count_orbs() -> int:
	var n := 0
	for c in get_parent().get_children():
		if c is PickupOrb:
			n += 1
	return n
