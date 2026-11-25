class_name WaveDirector
extends Node
## Phase 1 sandbox spawner: escalating waves of the three archetypes, delivered
## through corruption portals in staggered bursts. (Phase 2 replaces this with
## per-arena lock-in encounters that reuse spawn_enemy()).

const SCENES := {
	&"swarmer": preload("res://src/enemies/swarmer.tscn"),
	&"spitter": preload("res://src/enemies/spitter.tscn"),
	&"brute": preload("res://src/enemies/brute.tscn"),
}

## Hand-authored opening waves; afterwards waves are generated with scaling.
const WAVES := [
	{"swarmer": 6},
	{"swarmer": 8, "spitter": 2},
	{"swarmer": 6, "spitter": 3},
	{"brute": 1, "swarmer": 6},
	{"swarmer": 12, "spitter": 3},
	{"brute": 1, "spitter": 3, "swarmer": 8},
]

@export var arena_path: NodePath
@export var auto_start: bool = true
@export var first_wave_delay: float = 2.5
@export var breather: float = 4.0
@export var portal_time: float = 0.9
@export var burst_size: int = 4
@export var burst_interval: float = 1.6

var arena: TestArena
var wave: int = 0
var alive: int = 0
var pending: int = 0
var running: bool = false
var _queue: Array[StringName] = []
var _burst_t: float = 0.0
var _break_t: float = 0.0


func _ready() -> void:
	arena = get_node(arena_path) as TestArena
	Events.enemy_killed.connect(_on_enemy_killed)
	if auto_start:
		_break_t = first_wave_delay
		running = true


func _process(delta: float) -> void:
	if not running:
		return
	var player := Combat.get_player(get_tree())
	if player == null or player.is_dead():
		return
	if _queue.is_empty() and alive <= 0 and pending <= 0:
		_break_t -= delta
		if _break_t <= 0.0:
			_start_next_wave()
		return
	if not _queue.is_empty():
		_burst_t -= delta
		if _burst_t <= 0.0:
			_burst_t = burst_interval
			for i in mini(burst_size, _queue.size()):
				spawn_enemy(_queue.pop_front(), arena.pick_spawn_point(player.global_position))


func _start_next_wave() -> void:
	wave += 1
	var comp: Dictionary = WAVES[wave - 1] if wave <= WAVES.size() else _generate(wave)
	_queue.clear()
	# brutes first so they arrive early, then interleave the rest
	for id in ["brute", "spitter", "swarmer"]:
		for i in int(comp.get(id, 0)):
			_queue.append(StringName(id))
	if _queue.size() > 2:
		var first: StringName = _queue[0]
		var rest := _queue.slice(1)
		rest.shuffle()
		_queue.clear()
		_queue.append(first)
		_queue.append_array(rest)
	_burst_t = 0.4
	Events.wave_started.emit(wave, _queue.size())
	Events.announce.emit("WAVE %d" % wave, Color(1.0, 0.3, 0.35))
	Sfx.play(&"wave_start", Vector3.INF, -6.0)


func _generate(n: int) -> Dictionary:
	var k := n - WAVES.size()
	return {
		"swarmer": 10 + k * 2,
		"spitter": 3 + k / 2,
		"brute": 1 + k / 3,
	}


## Public: spawn one enemy through a portal. Returns immediately; the enemy
## appears after `portal_time`.
func spawn_enemy(id: StringName, at: Vector3) -> void:
	if not SCENES.has(id):
		push_error("WaveDirector: unknown enemy id %s" % id)
		return
	pending += 1
	var jitter := Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
	var pos := at + jitter
	var size := 2.6 if id == &"brute" else 1.3
	Vfx.spawn_portal(pos, size, portal_time, Color(0.6, 1.0, 0.2) if id != &"brute" else Color(1.0, 0.25, 0.5))
	Sfx.play(&"spawn_portal", pos, -10.0, 0.15, 120)
	await get_tree().create_timer(portal_time, false).timeout
	if not is_inside_tree():
		return
	pending -= 1
	var e: Enemy = SCENES[id].instantiate()
	arena.add_child(e)
	e.global_position = pos
	alive += 1


func kill_all() -> void:
	for e in Combat.living_enemies(get_tree()):
		var info := DamageInfo.make(99999.0, DamageInfo.Kind.EXPLOSION, null, e.global_position, Vector3.UP)
		e.apply_damage(info)


func _on_enemy_killed(_enemy: Node3D, _info: DamageInfo) -> void:
	alive = maxi(alive - 1, 0)
	if alive == 0 and pending == 0 and _queue.is_empty() and wave > 0:
		_break_t = breather
		Events.wave_cleared.emit(wave)
		Events.announce.emit("WAVE %d CLEARED" % wave, Color(0.35, 1.0, 0.6))
		Sfx.play(&"wave_clear", Vector3.INF, -6.0)
