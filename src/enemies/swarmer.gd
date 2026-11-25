class_name Swarmer
extends Enemy
## HATCH RUNNER — fast, fragile pack hunter. Flanks to surround the player, then
## telegraphs a short line and lunges with its split jaw.

@export var lunge_speed: float = 17.0
@export var lunge_time: float = 0.2
@export var bite_damage: float = 9.0
@export var flank_radius: float = 4.0

var _flank_angle: float = 0.0
var _lunge_dir: Vector3 = Vector3.FORWARD
var _bit: bool = false


func _setup() -> void:
	_flank_angle = randf_range(-PI, PI)
	move_speed *= randf_range(0.9, 1.12)


func on_aggro() -> void:
	if randf() < 0.35:
		Sfx.play(&"swarmer_screech", global_position, -10.0, 0.2, 120)


func chase_step(delta: float) -> void:
	if not has_target():
		return
	var tp := target.global_position
	var dist := distance_to_target()
	var goal := tp
	if dist > 5.0:
		# approach from a personal flank angle so packs surround instead of conga-lining
		goal = tp + Vector3(cos(_flank_angle), 0, sin(_flank_angle)) * flank_radius
	move_toward_point(goal, move_speed, delta)


func can_attack() -> bool:
	return attack_cd <= 0.0 and distance_to_target() <= attack_range and has_line_of_sight(0.6)


func begin_telegraph() -> void:
	super.begin_telegraph()
	face(dir_to_target())
	_lunge_dir = facing
	telegraph_marker = Telegraph.line(get_parent(), global_position, facing, 1.1, lunge_speed * lunge_time + 1.0, telegraph_time)


func telegraph_step(delta: float, progress: float) -> void:
	brake(delta)
	# keep tracking during the first half of the wind-up, then commit
	if progress < 0.5:
		face(dir_to_target())
		_lunge_dir = facing
		if is_instance_valid(telegraph_marker):
			telegraph_marker.look_at(telegraph_marker.global_position + facing, Vector3.UP)
	visual.set_charge(progress)


func perform_attack() -> void:
	super.perform_attack()
	_bit = false
	if is_instance_valid(telegraph_marker):
		telegraph_marker.finish()
	telegraph_marker = null
	Sfx.play(&"swarmer_screech", global_position, -12.0, 0.25, 60)


func attack_step(delta: float, t: float) -> void:
	if t < lunge_time:
		velocity = _lunge_dir * lunge_speed
	else:
		brake(delta)
	if not _bit and has_target():
		var to := target.global_position - global_position
		to.y = 0.0
		if to.length() < radius + 0.9 and _lunge_dir.dot(to.normalized()) > 0.2:
			var info := DamageInfo.make(bite_damage, DamageInfo.Kind.MELEE, self, target.global_position + Vector3.UP, _lunge_dir)
			info.knockback = 5.0
			if target.apply_damage(info):
				Vfx.gore(target.global_position + Vector3.UP, _lunge_dir, Color(1.0, 0.3, 0.2), 0.6)
			_bit = true
