extends Node
## Demo / soak-test bot. Plays the sandbox through the real input actions
## (so it exercises the same code paths as a human) with god mode on.

var player: Player
var _t: float = 0.0
var _orbit: float = 0.0
var _held: Dictionary = {}
var _melee_cd: float = 0.0


func _ready() -> void:
	process_priority = -100
	process_physics_priority = -100
	player = Combat.get_player(get_tree()) as Player
	player.god_mode = true
	Events.announce.emit("AUTOPILOT", Color(0.5, 0.9, 1.0))


func _physics_process(delta: float) -> void:
	if player == null or player.is_dead():
		return
	_t += delta
	_melee_cd -= delta
	_release_taps()
	var enemies := Combat.living_enemies(get_tree())
	var nearest: Node3D = Combat.nearest_enemy(get_tree(), player.global_position)
	var pos := player.global_position

	# --- aim
	if nearest:
		player.aim_override = nearest.global_position + Vector3.UP * 1.2 + nearest.velocity * 0.1
	else:
		player.aim_override = pos + Vector3(cos(_t), 0, sin(_t)) * 6.0 + Vector3.UP * 1.2

	# --- movement: orbit the arena, kite away from close threats
	_orbit += delta * 0.25
	var goal := Vector3(cos(_orbit), 0, sin(_orbit)) * 9.0
	var move := goal - pos
	move.y = 0.0
	if nearest:
		var away: Vector3 = pos - nearest.global_position
		away.y = 0.0
		var d := away.length()
		if d < 4.0 and not nearest.is_finishable():
			move = away.normalized() * 2.0 + away.cross(Vector3.UP).normalized()
	_set_move(move)

	# --- weapons
	var dist := INF if nearest == null else Combat._flat_dist(nearest.global_position, pos)
	_hold(&"fire", nearest != null and dist < 20.0)
	if int(_t) % 9 == 0 and fmod(_t, 1.0) < delta:
		player.weapons.switch_to(1 if player.weapons.current_index == 0 else 0)

	# --- melee / finishers
	var finishable := false
	for e in Combat.enemies_in_radius(get_tree(), pos, 5.0):
		if e.is_finishable():
			finishable = true
	if _melee_cd <= 0.0 and (finishable or dist < 3.0 or player.energy < 10.0 and dist < 4.5):
		_tap(&"melee")
		_melee_cd = 0.45

	# --- dash + abilities
	if nearest and dist < 2.0 and randf() < 0.05:
		_tap(&"dash")
	if Combat.enemies_in_radius(get_tree(), player.aim_point, 9.0).size() >= 3:
		_tap(&"ability_q")
	if Combat.enemies_in_radius(get_tree(), pos, 6.0).size() >= 3:
		_tap(&"ability_e")


func _set_move(v: Vector3) -> void:
	# convert world direction into camera-relative WASD strengths
	var local := v
	if player.camera:
		local = player.camera.ground_basis().inverse() * v
	var l := Vector2(local.x, local.z)
	if l.length() > 1.0:
		l = l.normalized()
	_axis(&"move_right", &"move_left", l.x)
	_axis(&"move_down", &"move_up", l.y)


func _axis(pos_action: StringName, neg_action: StringName, value: float) -> void:
	if value > 0.1:
		Input.action_press(pos_action, value)
		Input.action_release(neg_action)
	elif value < -0.1:
		Input.action_press(neg_action, -value)
		Input.action_release(pos_action)
	else:
		Input.action_release(pos_action)
		Input.action_release(neg_action)


func _hold(action: StringName, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	_held[action] = Engine.get_physics_frames()


func _release_taps() -> void:
	for a in _held.keys():
		if Engine.get_physics_frames() > _held[a]:
			Input.action_release(a)
			_held.erase(a)
