class_name IsoCamera
extends Camera3D
## Isometric follow camera.
##  * ~54 deg pitch, 45 deg yaw, framed wide like DreadHunter (hero ~8% of screen).
##  * Snappy exponential follow with a small trail so speed reads.
##  * Look-ahead driven by the mouse's SCREEN offset (not its world point), so the
##    camera moving never drags the aim around — no "swimmy" feedback loop.
##  * Trauma shake (noise) + directional kick spring (recoil, dashes, impacts).
##  * Zoom punch for finishers.

@export var target_path: NodePath
@export var pitch_deg: float = 54.0
@export var yaw_deg: float = 45.0
@export var distance: float = 36.0
@export var follow_sharpness: float = 16.0
@export var look_ahead: float = 3.2          ## metres of look-ahead at the screen edge
@export var look_ahead_sharpness: float = 7.0
@export var max_shake_offset: float = 0.55
@export var max_shake_roll_deg: float = 1.4

var target: Node3D
var aim_point: Vector3 = Vector3.ZERO       ## set by the player each frame
var _focus: Vector3 = Vector3.ZERO
var _ahead: Vector3 = Vector3.ZERO
var _trauma: float = 0.0
var _kick: Vector3 = Vector3.ZERO
var _kick_vel: Vector3 = Vector3.ZERO
var _zoom: float = 0.0
var _noise := FastNoiseLite.new()
var _t: float = 0.0
var _base_fov: float = 30.0


func _ready() -> void:
	process_priority = 100  # after the player has moved this frame
	_noise.frequency = 1.2
	_noise.fractal_octaves = 2
	_base_fov = fov
	Feel.camera = self
	if target_path != NodePath():
		target = get_node_or_null(target_path)
	if target:
		_focus = target.global_position
	_apply()


func set_target(t: Node3D, snap: bool = true) -> void:
	target = t
	if snap and t:
		_focus = t.global_position
		aim_point = t.global_position


func add_trauma(amount: float, direction: Vector3 = Vector3.ZERO) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
	if direction.length_squared() > 0.0001:
		kick(direction, amount * 1.4)


## Directional jolt without noise (recoil, dash, heavy hits).
func kick(direction: Vector3, amount: float) -> void:
	var d := Vector3(direction.x, 0, direction.z)
	if d.length_squared() > 0.0001:
		_kick_vel += d.normalized() * amount * 10.0


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
	return Basis(Vector3.UP, deg_to_rad(yaw_deg))


func _process(delta: float) -> void:
	# unscaled time so hitstop/slow-mo don't freeze the camera's own motion
	var real_dt := minf(delta / maxf(Engine.time_scale, 0.001), 0.05)
	_t += real_dt
	if target and is_instance_valid(target):
		_ahead = _ahead.lerp(_desired_look_ahead(), 1.0 - exp(-look_ahead_sharpness * real_dt))
		_focus = _focus.lerp(target.global_position, 1.0 - exp(-follow_sharpness * real_dt))
	_kick_vel += (-_kick * 220.0 - _kick_vel * 22.0) * real_dt
	_kick += _kick_vel * real_dt
	_trauma = maxf(_trauma - real_dt * 2.0, 0.0)
	_zoom = move_toward(_zoom, 0.0, real_dt * 1.4)
	_apply()
	Sfx.listener_position = _focus


func _desired_look_ahead() -> Vector3:
	var uses_mouse: bool = target is Player and not target.gamepad_aim and target.aim_override == Vector3.INF
	if uses_mouse:
		var vp := get_viewport()
		var size := vp.get_visible_rect().size
		var off := (vp.get_mouse_position() - size * 0.5) / (size.y * 0.5)
		off = off.limit_length(1.4)
		return ground_basis() * Vector3(off.x, 0.0, off.y) * look_ahead
	var d := aim_point - target.global_position
	d.y = 0.0
	return d.limit_length(look_ahead)


func _apply() -> void:
	var pitch := deg_to_rad(pitch_deg)
	var offset := Vector3(0, sin(pitch), cos(pitch)) * distance * (1.0 - _zoom * 0.22)
	offset = offset.rotated(Vector3.UP, deg_to_rad(yaw_deg))
	var shake := _trauma * _trauma
	var n1 := _noise.get_noise_2d(_t * 25.0, 0.0)
	var n2 := _noise.get_noise_2d(0.0, _t * 25.0)
	var n3 := _noise.get_noise_2d(_t * 25.0, 100.0)
	var right := global_transform.basis.x
	var up := global_transform.basis.y
	var shake_off := (right * n1 + up * n2) * max_shake_offset * shake
	var focus := _focus + _ahead + _kick
	global_position = focus + offset + shake_off
	look_at(focus + shake_off * 0.5, Vector3.UP)
	rotate_object_local(Vector3.FORWARD, deg_to_rad(max_shake_roll_deg) * shake * n3)
	fov = _base_fov * (1.0 - _zoom * 0.12)
