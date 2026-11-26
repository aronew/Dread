extends Node
## CPU cost probe: spawns a big horde and measures game-logic frame time
## (headless => no rendering cost). Run:
##   godot --headless --path . -- --perf-probe
## Prints average/p95 process + physics time per frame in milliseconds.

var _samples_p: Array[float] = []
var _samples_ph: Array[float] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := get_parent()
	var arena: TestArena = main.get_node(^"Arena")
	var director: WaveDirector = main.get_node(^"WaveDirector")
	director.running = false
	var bot: Node = preload("res://tests/autopilot.gd").new()
	add_child(bot)
	var ids := []
	for i in 40:
		ids.append(&"swarmer")
	for i in 6:
		ids.append(&"spitter")
	for i in 2:
		ids.append(&"brute")
	for id in ids:
		var e: Enemy = WaveDirector.SCENES[id].instantiate()
		e.max_health *= 50.0  # keep the horde alive for the whole probe
		arena.add_child(e)
		e.health.reset(e.max_health)
		e.global_position = arena.pick_spawn_point(Vector3.ZERO, 6.0) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	await get_tree().create_timer(2.0).timeout
	for i in 600:
		await get_tree().process_frame
		_samples_p.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_samples_ph.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_samples_p.sort()
	_samples_ph.sort()
	var avg_p := 0.0
	var avg_ph := 0.0
	for v in _samples_p:
		avg_p += v
	for v in _samples_ph:
		avg_ph += v
	avg_p /= _samples_p.size()
	avg_ph /= _samples_ph.size()
	print("PERF enemies=%d nodes=%d" % [Combat.living_enemies(get_tree()).size(), get_tree().get_node_count()])
	print("PERF process  avg %.2f ms  p95 %.2f ms" % [avg_p, _samples_p[int(_samples_p.size() * 0.95)]])
	print("PERF physics  avg %.2f ms  p95 %.2f ms (per physics step)" % [avg_ph, _samples_ph[int(_samples_ph.size() * 0.95)]])
	get_tree().quit()
