extends ActorVisual
## "Hatch Runner" — hunched pink crawler with long bony fore-limbs, a split pod
## head that peels open around a yellow frowning mask, teal slime drips.

const K := preload("res://assets/placeholders/placeholder_kit.gd")

var body: Node3D
var head: Node3D
var jaw_l: Node3D
var jaw_r: Node3D
var legs: Array[Node3D] = []
var _velocity := Vector3.ZERO
var _max_speed := 7.0
var _yaw := 0.0
var _phase := randf() * TAU
var _jaw_open := 0.0
var _lunge := 0.0
var _stagger := 0.0
var _dead := false
var _tint: Color


func _build() -> void:
	scale = Vector3.ONE * 1.15
	_tint = config.get("tint", K.FLESH)
	var flesh := K.flesh(_tint)
	var dark := K.flesh(K.FLESH_DARK)
	var bone := K.mat(K.IVORY, 0.0, 0.5)
	var slime := K.flesh(K.SLIME, 1.6)

	body = K.pivot(self, Vector3(0, 0.62, 0), "Body")
	K.capsule(body, 0.3, 1.0, Vector3(0, 0, 0.05), flesh, Vector3(90, 0, 0), Vector3(1.1, 1.0, 0.85))
	K.sphere(body, 0.26, Vector3(0, 0.08, 0.42), dark, Vector3(1.0, 0.9, 1.2))
	# spine nodules
	for i in 4:
		K.sphere(body, 0.07 - i * 0.008, Vector3(0, 0.27 - i * 0.02, -0.2 + i * 0.2), K.flesh(K.CARAPACE))
	# slime drips
	for i in 3:
		var d := K.capsule(body, 0.035, 0.22 + i * 0.05, Vector3(-0.12 + i * 0.12, -0.3, 0.05 * i), slime)
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	head = K.pivot(body, Vector3(0, 0.22, -0.55), "Head")
	head.rotation.x = -0.35  # tilt the face up toward the camera
	K.mask_face(head, 0.2, Vector3(0, 0, -0.08))
	jaw_l = K.pivot(head, Vector3(-0.14, 0, 0.05))
	jaw_r = K.pivot(head, Vector3(0.14, 0, 0.05))
	# big split "pod" petals framing the mask (Hatch Runner silhouette)
	K.sphere(jaw_l, 0.36, Vector3(-0.14, 0.05, -0.08), flesh, Vector3(0.5, 1.0, 1.0))
	K.sphere(jaw_r, 0.36, Vector3(0.14, 0.05, -0.08), flesh, Vector3(0.5, 1.0, 1.0))
	K.sphere(jaw_l, 0.12, Vector3(-0.3, 0.2, -0.1), K.flesh(K.MASK_YELLOW), Vector3(0.6, 1, 1))
	K.sphere(jaw_r, 0.12, Vector3(0.3, 0.2, -0.1), K.flesh(K.MASK_YELLOW), Vector3(0.6, 1, 1))
	for j in [jaw_l, jaw_r]:
		for t in 3:
			K.cylinder(j, 0.0, 0.025, 0.12, Vector3(0, -0.12 + t * 0.1, -0.24), bone, Vector3(90, 0, 0))
	add_socket(&"mouth", head, Vector3(0, 0, -0.3))

	# limbs: two long fore-limbs, two short hind legs
	var limb_defs := [
		[Vector3(-0.28, 0.0, -0.3), 0.75, true], [Vector3(0.28, 0.0, -0.3), 0.75, true],
		[Vector3(-0.25, -0.05, 0.4), 0.55, false], [Vector3(0.25, -0.05, 0.4), 0.55, false],
	]
	for def in limb_defs:
		var pos: Vector3 = def[0]
		var length: float = def[1]
		var leg := K.pivot(body, pos * Vector3(1.0, 1.0, 1.0) + Vector3(0, 0.1, 0))
		var side := signf(pos.x)
		leg.rotation.z = -0.95 * side
		K.capsule(leg, 0.085, length, Vector3(0, -length * 0.5, 0), K.flesh(Color(0.98, 0.62, 0.62)))
		K.sphere(leg, 0.1, Vector3(0, -length * 0.55, 0), K.flesh(K.FLESH_DARK))
		var claw := K.cylinder(leg, 0.0, 0.05, 0.18, Vector3(0, -length - 0.05, -0.05), bone, Vector3(-30, 0, 0))
		claw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		legs.append(leg)


func set_locomotion(world_velocity: Vector3, max_speed: float) -> void:
	_velocity = world_velocity
	_max_speed = max_speed


func set_aim(world_direction: Vector3) -> void:
	if world_direction.length_squared() > 0.001:
		_yaw = atan2(-world_direction.x, -world_direction.z)


func play_action(action: StringName, _duration: float = -1.0) -> void:
	match action:
		&"telegraph":
			_jaw_open = 1.0
		&"attack":
			_lunge = 1.0
			_jaw_open = 1.0
		&"stagger", &"hit":
			_stagger = 1.0
		&"die":
			_dead = true


func _animate(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _yaw, minf(delta * 12.0, 1.0))
	if _dead:
		return
	var speed := Vector2(_velocity.x, _velocity.z).length()
	var r := clampf(speed / maxf(_max_speed, 0.1), 0.0, 1.5)
	_phase += delta * (5.0 + 16.0 * r)
	for i in legs.size():
		var off := PI if (i % 2 == 0) != (i >= 2) else 0.0
		legs[i].rotation.x = sin(_phase + off) * 0.7 * minf(r, 1.0) - 0.15
	body.position.y = 0.62 + absf(sin(_phase * 2.0)) * 0.06 * r - _stagger * 0.12
	body.rotation.x = -0.2 * r + _lunge * 0.35 + _stagger * 0.25
	body.rotation.z = sin(_phase) * 0.08 * r + sin(Time.get_ticks_msec() * 0.05) * 0.1 * _stagger
	body.position.z = -_lunge * 0.3
	head.rotation.x = sin(_phase * 0.5) * 0.08 - _jaw_open * 0.25
	jaw_l.rotation.y = _jaw_open * 0.9
	jaw_r.rotation.y = -_jaw_open * 0.9
	_jaw_open = move_toward(_jaw_open, 0.0, delta * 1.6)
	_lunge = move_toward(_lunge, 0.0, delta * 3.0)
	_stagger = move_toward(_stagger, 0.0, delta * 2.0)
