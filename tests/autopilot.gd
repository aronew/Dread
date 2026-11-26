extends Node
## Demo / soak-test bot. Plays the sandbox through the real input actions
## (same code paths as a human) with god mode on. Its "cursor" is deliberately
## sloppy (±1 m of noise) so the aim assist is exercised like a real player.

## "mixed" (default) or "melee": rushes in, mashes the combo, dash-strikes.
var style: String = "mixed"
var player: Player
var _t: float = 0.0
var _orbit: float = 0.0
var _held: Dictionary = {}
var _melee_cd: float = 0.0
var _jitter: Vector3 = Vector3.ZERO


func _ready() -> void:
	process_priority = -100   # act before the player reads input this frame
	player = Combat.get_player(get_tree()) as Player
	player.god_mode = true
	Events.announce.emit("AUTOPILOT", Color(0.5, 0.9, 1.0))


func _process(delta: float) -> void:
	if player == null or player.is_dead() or delta <= 0.0:
		return
	_t += delta
	_melee_cd -= delta
	_release_taps()
	var nearest: Node3D = Combat.nearest_enemy(get_tree(), player.global_position)
	var pos := player.global_position

	# --- sloppy aim
	_jitter = _jitter.lerp(Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)), minf(delta * 4.0, 1.0))
	if nearest:
		player.aim_override = nearest.global_position + _jitter + Vector3.UP * 0.9
	else:
		player.aim_override = pos + Vector3(cos(_t), 0, sin(_t)) * 6.0 + Vector3.UP * 0.9

	# --- movement: orbit the arena, kite away from close threats
	_orbit += delta * 0.3
	var goal := Vector3(cos(_orbit), 0, sin(_orbit)) * 9.0
	var move := goal - pos
	move.y = 0.0
	var dist := INF
	if nearest:
		dist = Combat._flat_dist(nearest.global_position, pos)
		var away: Vector3 = pos - nearest.global_position
		away.y = 0.0
		if dist < 4.5 and not nearest.is_finishable() and player.energy > 15.0:
			move = away.normalized() * 2.0 + away.cross(Vector3.UP).normalized()
		elif nearest.is_finishable() or player.energy < 15.0:
			move = -away  # go in for the blade
	if style == "melee" and nearest:
		move = nearest.global_position - pos
		move.y = 0.0
		if dist > 4.0 and dist < 8.0 and randf() < 0.05:
			_tap(&"dash")
	_set_move(move)

	# --- weapons
	var want_fire := nearest != null and dist < 22.0 and not (dist < 3.0 and player.energy < 15.0)
	if style == "melee":
		want_fire = nearest != null and dist > 7.0
	_hold(&"fire", want_fire)
	if int(_t) % 9 == 0 and fmod(_t, 1.0) < delta:
		player.weapons.switch_to(1 if player.weapons.current_index == 0 else 0)

	# --- melee / finishers (mash like a human: every ~0.12 s while in range)
	var finishable := false
	for e in Combat.enemies_in_radius(get_tree(), pos, 5.0):
		if e.is_finishable():
			finishable = true
	if _melee_cd <= 0.0 and (finishable or dist < 3.2):
		_tap(&"melee")
		_melee_cd = 0.12

	# --- dash + abilities
	if nearest and dist < 2.2 and randf() < 0.04:
		_tap(&"dash")
	if Combat.enemies_in_radius(get_tree(), player.aim_point, 9.0).size() >= 3:
		_tap(&"ability_q")
	if Combat.enemies_in_radius(get_tree(), pos, 6.0).size() >= 3:
		_tap(&"ability_e")


func _set_move(v: Vector3) -> void:
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
	_held[action] = Engine.get_process_frames()


func _release_taps() -> void:
	for a in _held.keys():
		if Engine.get_process_frames() > _held[a]:
			Input.action_release(a)
			_held.erase(a)
