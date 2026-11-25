class_name IsoCamera
extends Camera3D
## Isometric follow camera.
##  * ~50 deg pitch, 45 deg yaw, narrow FOV for a near-orthographic read.
##  * Critically-damped follow with look-ahead toward the aim point.
##  * Trauma-based shake (noise) + directional kick spring for impacts.
##  * Zoom punch for finishers / big hits.

@export var target_path: NodePath
@export var pitch_deg: float = 52.0
@export var yaw_deg: float = 45.0
@export var distance: float = 27.0
@export var follow_sharpness: float = 9.0
@export var look_ahead: float = 0.28        ## fraction of cursor offset
@export var look_ahead_max: float = 5.0
@export var max_shake_offset: float = 0.65
@export var max_shake_roll_deg: float = 1.6

var target: Node3D
var aim_point: Vector3 = Vector3.ZERO       ## set by the player each frame
var _focus: Vector3 = Vector3.ZERO
var _trauma: float = 0.0
var _kick: Vector3 = Vector3.ZERO
var _kick_vel: Vector3 = Vector3.ZERO
var _zoom: float = 0.0
var _noise := FastNoiseLite.new()
var _t: float = 0.0
var _base_fov: float = 30.0


func _ready() -> void:
	_noise.frequency = 1.2
	_noise.fractal_octaves = 2
	_base_fov = fov
	Feel.camera = self
	if target_path != NodePath():
		target = get_node_or_null(target_path)
	if target:
		_focus = target.global_position
	_apply(0.0)


func set_target(t: Node3D, snap: bool = true) -> void:
	target = t
	if snap and t:
		_focus = t.global_position
		aim_point = t.global_position


func add_trauma(amount: float, direction: Vector3 = Vector3.ZERO) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
	if direction.length_squared() > 0.0001:
		var d := Vector3(direction.x, 0, direction.z).normalized()
		_kick_vel += d * amount * 14.0


func zoom_punch(amount: float) -> void:
	_zoom = clampf(_zoom + amount, -0.5, 0.5)


## Ray from the camera through a screen point onto the horizontal plane y = height.
func screen_to_ground(screen_pos: Vector2, height: float = 0.0) -> Vector3:
	var origin := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return origin
	var t := (height - origin.y) / dir.y
	return origin + dir * t


## Camera-relative ground axes for WASD movement.
func ground_basis() -> Basis:
	var yaw := deg_to_rad(yaw_deg)
	return Basis(Vector3.UP, yaw)


func _process(delta: float) -> void:
	# Use unscaled time for shake decay so hitstop doesn't freeze the shake.
	var real_dt := delta / maxf(Engine.time_scale, 0.001)
	real_dt = minf(real_dt, 0.05)
	_t += real_dt
	if target and is_instance_valid(target):
		var tp := target.global_position
		var ahead := aim_point - tp
		ahead.y = 0.0
		ahead = ahead * look_ahead
		if ahead.length() > look_ahead_max:
			ahead = ahead.normalized() * look_ahead_max
		var goal := tp + ahead
		_focus = _focus.lerp(goal, 1.0 - exp(-follow_sharpness * real_dt))
	# kick spring (critically damped-ish)
	var k := 160.0
	var damp := 18.0
	_kick_vel += (-_kick * k - _kick_vel * damp) * real_dt
	_kick += _kick_vel * real_dt
	_trauma = maxf(_trauma - real_dt * 1.6, 0.0)
	_zoom = move_toward(_zoom, 0.0, real_dt * 1.2)
	_apply(real_dt)
	Sfx.listener_position = _focus


func _apply(_dt: float) -> void:
	var pitch := deg_to_rad(pitch_deg)
	var yaw := deg_to_rad(yaw_deg)
	var offset := Vector3(0, sin(pitch), cos(pitch)) * distance * (1.0 - _zoom * 0.25)
	offset = offset.rotated(Vector3.UP, yaw)
	var shake := _trauma * _trauma
	var n1 := _noise.get_noise_2d(_t * 25.0, 0.0)
	var n2 := _noise.get_noise_2d(0.0, _t * 25.0)
	var n3 := _noise.get_noise_2d(_t * 25.0, 100.0)
	var right := global_transform.basis.x
	var up := global_transform.basis.y
	var shake_off := (right * n1 + up * n2) * max_shake_offset * shake
	var focus := _focus + _kick
	global_position = focus + offset + shake_off
	look_at(focus + shake_off * 0.5, Vector3.UP)
	rotate_object_local(Vector3.FORWARD, deg_to_rad(max_shake_roll_deg) * shake * n3)
	fov = _base_fov * (1.0 - _zoom * 0.15)
