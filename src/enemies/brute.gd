class_name Brute
extends Enemy
## TUSK HULK — elite heavy. Two attacks, both with long, readable telegraphs:
##   * GROUND SLAM: raises its fists, red circle fills in front of it, then a
##     shockwave AoE with big knockback.
##   * LEAP SLAM: when the player kites far away, it marks the player's position,
##     hurls itself across the arena and slams down there.
## Immune to stagger until it drops below `vulnerable_ratio` HP; then its chest
## core ignites and poise can be broken for a melee FINISHER.

@export var slam_radius: float = 4.4
@export var slam_damage: float = 28.0
@export var slam_knockback: float = 16.0
@export var leap_min_distance: float = 9.0
@export var leap_cooldown: float = 7.0
@export var leap_air_time: float = 0.5
@export var vulnerable_ratio: float = 0.35
@export var vulnerable_poise: float = 140.0

var _leap: bool = false
var _leap_cd: float = 4.0
var _leap_from: Vector3
var _leap_to: Vector3
var _slam_center: Vector3
var _vulnerable: bool = false
var _landed: bool = false


func _setup() -> void:
	max_poise = 999999.0
	poise = max_poise
	health.damaged.connect(_check_vulnerable)


func on_aggro() -> void:
	Sfx.play(&"brute_roar", global_position, -2.0)
	Feel.shake(0.15)


func _physics_process(delta: float) -> void:
	_leap_cd = maxf(_leap_cd - delta, 0.0)
	super._physics_process(delta)


func can_attack() -> bool:
	if attack_cd > 0.0:
		return false
	var dist := distance_to_target()
	if dist <= slam_radius * 0.85:
		_leap = false
		return true
	if dist >= leap_min_distance and _leap_cd <= 0.0 and dist < 22.0:
		_leap = true
		return true
	return false


func begin_telegraph() -> void:
	super.begin_telegraph()
	face(dir_to_target())
	if _leap:
		telegraph_time = 1.15
		_leap_to = target.global_position
		_leap_to.y = 0.0
		_slam_center = _leap_to
		telegraph_marker = Telegraph.circle(get_parent(), _slam_center, slam_radius * 0.85, telegraph_time, Color(1.0, 0.1, 0.05))
		Sfx.play(&"brute_roar", global_position, -4.0, 0.1)
	else:
		telegraph_time = 0.95
		_slam_center = global_position + facing * 1.6
		telegraph_marker = Telegraph.circle(get_parent(), _slam_center, slam_radius, telegraph_time, Color(1.0, 0.15, 0.05))


func telegraph_step(delta: float, progress: float) -> void:
	brake(delta)
	if _leap:
		face(_leap_to - global_position)
	elif progress < 0.35:
		# small tracking window before committing
		face(dir_to_target())
		_slam_center = global_position + facing * 1.6
		if is_instance_valid(telegraph_marker):
			telegraph_marker.global_position = Vector3(_slam_center.x, 0.03, _slam_center.z)
	visual.set_charge(progress)


func perform_attack() -> void:
	_landed = false
	if _leap:
		attack_duration = leap_air_time + 0.9
		_leap_from = global_position
		_leap_cd = leap_cooldown
		collision_mask = Combat.LAYER_WORLD
		visual.play_action(&"telegraph")
	else:
		attack_duration = 0.95
		visual.play_action(&"attack", attack_duration)
		_slam()


func attack_step(delta: float, t: float) -> void:
	if _leap and not _landed:
		var k := clampf(t / leap_air_time, 0.0, 1.0)
		var p := _leap_from.lerp(_leap_to - facing * 1.0, k)
		velocity = Vector3.ZERO
		global_position = Vector3(p.x, 0.0, p.z)
		visual.position.y = sin(k * PI) * 4.0
		if k >= 1.0:
			_landed = true
			visual.position.y = 0.0
			collision_mask = Combat.LAYER_WORLD | Combat.LAYER_PLAYER
			visual.play_action(&"attack", 0.6)
			_slam()
	else:
		brake(delta)


func end_attack() -> void:
	super.end_attack()
	visual.position.y = 0.0
	collision_mask = Combat.LAYER_WORLD | Combat.LAYER_PLAYER
	_leap = false


func cancel_telegraph() -> void:
	super.cancel_telegraph()
	visual.position.y = 0.0


func _slam() -> void:
	if is_instance_valid(telegraph_marker):
		telegraph_marker.finish()
	telegraph_marker = null
	var c := Vector3(_slam_center.x, 0.0, _slam_center.z)
	Vfx.shockwave(c + Vector3.UP * 0.1, slam_radius * 1.3, Color(1.0, 0.35, 0.15), 0.45, 0.07)
	Vfx.shockwave(c + Vector3.UP * 0.12, slam_radius * 0.8, Color(1.0, 0.8, 0.5), 0.25, 0.12)
	Vfx.burst(&"smoke", c, Basis.IDENTITY, Color(0.12, 0.1, 0.1), 10, 1.4)
	Vfx.burst(&"sparks", c + Vector3.UP * 0.3, Basis.IDENTITY, Color(1.0, 0.5, 0.2), 30, 1.4)
	Vfx.burst(&"chunks", c + Vector3.UP * 0.3, Basis.IDENTITY, Color(0.2, 0.22, 0.25), 18, 1.4)
	Vfx.splat(c, Color(0.02, 0.015, 0.015, 0.85), slam_radius * 0.6)
	Vfx.light_flash(c + Vector3.UP, Color(1.0, 0.45, 0.2), 8.0, slam_radius * 3.0, 0.3)
	Sfx.play(&"brute_slam", c, 0.0, 0.08)
	var p := target
	var dir_to_p := Vector3.ZERO
	if has_target():
		dir_to_p = target.global_position - c
		dir_to_p.y = 0.0
	Feel.shake(0.55, dir_to_p)
	Feel.rumble(0.7, 1.0, 0.35)
	if has_target() and dir_to_p.length() <= slam_radius:
		var info := DamageInfo.make(slam_damage, DamageInfo.Kind.MELEE, self, p.global_position + Vector3.UP, dir_to_p)
		info.knockback = slam_knockback
		p.apply_damage(info)


func _check_vulnerable(_info: DamageInfo) -> void:
	if _vulnerable or health.ratio() > vulnerable_ratio or health.is_dead:
		return
	_vulnerable = true
	max_poise = vulnerable_poise
	poise = vulnerable_poise * 0.5
	poise_regen = 25.0
	visual.play_action(&"weak")
	Sfx.play(&"brute_roar", global_position, 0.0, 0.05)
	Vfx.text_popup(global_position + Vector3.UP * 4.2, "CORE EXPOSED", Color(1.0, 0.55, 0.15), 64)
	Events.announce.emit("HULK CORE EXPOSED — BREAK ITS POISE, THEN FINISH IT", Color(1.0, 0.55, 0.15))


func is_finishable() -> bool:
	return not _dead and fsm.is_in(&"staggered")
