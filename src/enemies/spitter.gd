class_name Spitter
extends Enemy
## BLOOM SPITTER — artillery. Holds medium range, strafes, and after a clear
## wind-up (bile sac swells + lime aim line) lobs a fan of slow corrosive globs.
## Globs can be dodged, dashed through, or REFLECTED with melee.

@export var preferred_min: float = 7.5
@export var preferred_max: float = 12.0
@export var max_fire_range: float = 17.0
@export var glob_count: int = 3
@export var glob_spread_deg: float = 13.0
@export var glob_speed: float = 11.5
@export var glob_damage: float = 12.0

var _strafe_dir: float = 1.0
var _strafe_t: float = 0.0
var _aim_dir: Vector3 = Vector3.FORWARD
var _los_t: float = 0.0
var _los: bool = true


func _setup() -> void:
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0


func chase_step(delta: float) -> void:
	if not has_target():
		return
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.2, 2.6)
		_strafe_dir = -_strafe_dir
	var to := dir_to_target()
	var dist := distance_to_target()
	var tangent := to.cross(Vector3.UP) * _strafe_dir
	var goal: Vector3
	if dist < preferred_min:
		goal = global_position - to * 4.0 + tangent * 2.0
	elif dist > preferred_max or not _los:
		goal = target.global_position
	else:
		goal = global_position + tangent * 3.0
	move_toward_point(goal, move_speed, delta, false)
	face(to)


func can_attack() -> bool:
	_los_t -= 0.016
	if _los_t <= 0.0:
		_los_t = 0.25
		_los = has_line_of_sight(1.5)
	var dist := distance_to_target()
	return attack_cd <= 0.0 and _los and dist <= max_fire_range and dist >= 3.0


func begin_telegraph() -> void:
	super.begin_telegraph()
	_aim_dir = _predict_dir()
	face(_aim_dir)
	telegraph_marker = Telegraph.line(get_parent(), global_position, _aim_dir, 0.4, minf(distance_to_target() + 2.0, max_fire_range), telegraph_time, Color(0.5, 0.9, 0.1))


func telegraph_step(delta: float, progress: float) -> void:
	brake(delta)
	if progress < 0.7:
		_aim_dir = _aim_dir.slerp(_predict_dir(), minf(delta * 6.0, 1.0)).normalized()
		face(_aim_dir)
		if is_instance_valid(telegraph_marker):
			telegraph_marker.global_position = Vector3(global_position.x, 0.03, global_position.z)
			telegraph_marker.look_at(telegraph_marker.global_position + _aim_dir, Vector3.UP)
	visual.set_charge(progress, Color(0.6, 1.0, 0.15))


func perform_attack() -> void:
	super.perform_attack()
	if is_instance_valid(telegraph_marker):
		telegraph_marker.finish()
	telegraph_marker = null
	var mouth := visual.get_socket(&"mouth")
	var origin := mouth.global_position
	origin.y = 1.2
	for i in glob_count:
		var ang := 0.0
		if glob_count > 1:
			ang = lerpf(-glob_spread_deg, glob_spread_deg, float(i) / float(glob_count - 1))
		var g := EnemyProjectile.new()
		get_parent().add_child(g)
		g.setup(self, origin, _aim_dir.rotated(Vector3.UP, deg_to_rad(ang)), glob_speed, glob_damage)
	Vfx.burst(&"goo", origin, Vfx.basis_y(_aim_dir + Vector3.UP * 0.4), Color(0.6, 1.0, 0.15), 14, 1.0)
	Vfx.burst(&"flash", origin, Basis.IDENTITY, Color(0.6, 1.0, 0.15), 1, 1.4)
	Sfx.play(&"enemy_spit", global_position, -2.0)


func _predict_dir() -> Vector3:
	if not has_target():
		return facing
	var lead := target.velocity * clampf(distance_to_target() / glob_speed, 0.0, 1.2) * 0.5
	var p := target.global_position + lead - global_position
	p.y = 0.0
	return p.normalized() if p.length_squared() > 0.01 else facing
