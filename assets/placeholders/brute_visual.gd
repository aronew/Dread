extends ActorVisual
## "Tusk Hulk" — a towering mass of teal coils with two screaming pink heads,
## ivory tusks, a riveted yellow mask plate and huge slam fists.
## When it becomes staggerable a corrupted core on its chest pulses orange.

const K := preload("res://assets/placeholders/placeholder_kit.gd")

var body: Node3D
var upper: Node3D
var head_l: Node3D
var head_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var core: MeshInstance3D
var core_light: OmniLight3D
var _velocity := Vector3.ZERO
var _max_speed := 3.0
var _yaw := 0.0
var _phase := 0.0
var _raise := 0.0       # 0..1 arms overhead (telegraph)
var _slam := 0.0        # impulse after slam
var _stagger := 0.0
var _weak := 0.0
var _dead := false


func _build() -> void:
	var coil := K.flesh(K.COIL_TEAL)
	var coil_dark := K.flesh(Color(0.1, 0.36, 0.45))
	var flesh := K.flesh(K.FLESH)
	var dark := K.flesh(K.FLESH_DARK)
	var bone := K.mat(K.IVORY, 0.0, 0.45)
	var plate := K.mat(Color(0.86, 0.7, 0.4), 0.35, 0.45)
	var drip := K.flesh(K.FLESH, 0.4)

	body = K.pivot(self, Vector3.ZERO, "Body")
	# stacked coils
	var coils := [[0.95, 0.35], [0.88, 0.85], [0.8, 1.32], [0.7, 1.76]]
	for i in coils.size():
		var c: Array = coils[i]
		K.torus(body, c[0] * 0.35, c[0], Vector3(0, c[1], 0), coil if i % 2 == 0 else coil_dark,
				Vector3(0, i * 37.0, (i % 2) * 6.0 - 3.0), Vector3(1.0, 1.6, 1.0))
	K.cylinder(body, 0.62, 0.8, 1.9, Vector3(0, 1.0, 0), coil_dark)

	upper = K.pivot(body, Vector3(0, 2.0, 0), "Upper")
	K.sphere(upper, 0.75, Vector3(0, 0.2, 0.05), flesh, Vector3(1.25, 0.9, 1.0))
	# flesh drips
	for i in 6:
		var a := i * TAU / 6.0
		var d := K.capsule(upper, 0.07, 0.5 + (i % 3) * 0.15, Vector3(cos(a) * 0.75, -0.3, sin(a) * 0.55), drip)
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# yellow V plate
	K.box(upper, Vector3(0.9, 0.9, 0.12), Vector3(0, 0.05, -0.72), plate, Vector3(0, 0, 45), Vector3(1.0, 1.0, 1.0))
	K.box(upper, Vector3(0.55, 0.3, 0.14), Vector3(0, 0.45, -0.74), plate)
	core = K.sphere(upper, 0.16, Vector3(0, 0.05, -0.82), K.glow(Color(1.0, 0.45, 0.1), 2.0))
	core.set_meta(&"no_overlay", true)
	core_light = OmniLight3D.new()
	core_light.light_color = Color(1.0, 0.45, 0.1)
	core_light.omni_range = 4.0
	core_light.light_energy = 0.0
	core_light.position = Vector3(0, 0.05, -1.1)
	upper.add_child(core_light)

	# twin heads
	head_l = K.pivot(upper, Vector3(-0.55, 0.75, -0.1))
	head_r = K.pivot(upper, Vector3(0.55, 0.75, -0.1))
	for h in [head_l, head_r]:
		var side := signf(h.position.x)
		K.sphere(h, 0.42, Vector3.ZERO, flesh, Vector3(0.9, 1.15, 1.0))
		K.box(h, Vector3(0.42, 0.22, 0.3), Vector3(0, -0.12, -0.3), dark)
		for t in 4:
			K.cylinder(h, 0.0, 0.035, 0.14, Vector3(-0.15 + t * 0.1, -0.02, -0.42), bone, Vector3(180, 0, 0))
		K.sphere(h, 0.1, Vector3(0.12 * side, 0.22, -0.32), K.glow(Color(1, 1, 0.95), 2.0))
		# curved tusk: two angled cone segments
		var tusk := K.pivot(h, Vector3(0.32 * side, 0.1, -0.1))
		K.cylinder(tusk, 0.07, 0.13, 0.7, Vector3(0.18 * side, 0.3, 0), bone, Vector3(0, 0, -35 * side))
		K.cylinder(tusk, 0.0, 0.07, 0.6, Vector3(0.38 * side, 0.85, -0.05), bone, Vector3(-10, 0, -10 * side))
	add_socket(&"mouth", upper, Vector3(0, 0.7, -1.0))

	# slam arms
	arm_l = K.pivot(upper, Vector3(-0.95, 0.15, 0))
	arm_r = K.pivot(upper, Vector3(0.95, 0.15, 0))
	for a in [arm_l, arm_r]:
		var side := signf(a.position.x)
		K.capsule(a, 0.24, 1.1, Vector3(0.1 * side, -0.5, 0), coil)
		K.sphere(a, 0.42, Vector3(0.12 * side, -1.15, -0.05), flesh, Vector3(1.0, 0.85, 1.1))
		for t in 3:
			K.cylinder(a, 0.0, 0.06, 0.25, Vector3(0.12 * side + (t - 1) * 0.16, -1.5, -0.2), bone, Vector3(160, 0, 0))
	add_socket(&"slam", self, Vector3(0, 0.1, -1.6))


func set_locomotion(world_velocity: Vector3, max_speed: float) -> void:
	_velocity = world_velocity
	_max_speed = max_speed


func set_aim(world_direction: Vector3) -> void:
	if world_direction.length_squared() > 0.001:
		_yaw = atan2(-world_direction.x, -world_direction.z)


func play_action(action: StringName, _duration: float = -1.0) -> void:
	match action:
		&"telegraph":
			_raise = 0.01
		&"attack":
			_raise = 0.0
			_slam = 1.0
		&"stagger":
			_stagger = 1.0
		&"hit":
			_stagger = maxf(_stagger, 0.2)
		&"weak":
			_weak = 1.0
		&"die":
			_dead = true


func set_charge(amount: float, color: Color = Color(1.0, 0.25, 0.15)) -> void:
	super.set_charge(amount, color)
	if _raise > 0.0:
		_raise = maxf(amount, 0.01)


func _animate(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _yaw, minf(delta * (2.0 if _raise > 0.0 else 5.0), 1.0))
	if _dead:
		return
	var speed := Vector2(_velocity.x, _velocity.z).length()
	var r := clampf(speed / maxf(_max_speed, 0.1), 0.0, 1.5)
	_phase += delta * (1.5 + 4.5 * r)
	var t := Time.get_ticks_msec() * 0.001
	body.rotation.z = sin(_phase) * 0.06 * r + sin(t * 30.0) * 0.06 * _stagger
	body.position.y = absf(sin(_phase)) * 0.08 * r - _slam * 0.25
	upper.rotation.x = _raise * -0.35 + _slam * 0.45 + _stagger * 0.3
	head_l.rotation.z = sin(t * 2.3) * 0.15
	head_r.rotation.z = -sin(t * 2.1 + 1.0) * 0.15
	head_l.rotation.x = -_raise * 0.4
	head_r.rotation.x = -_raise * 0.4
	var arm_swing := sin(_phase) * 0.35 * r
	arm_l.rotation.x = arm_swing - _raise * 2.6 + _slam * 0.8
	arm_r.rotation.x = -arm_swing - _raise * 2.6 + _slam * 0.8
	arm_l.rotation.z = -_raise * 0.3
	arm_r.rotation.z = _raise * 0.3
	_slam = move_toward(_slam, 0.0, delta * 1.5)
	_stagger = move_toward(_stagger, 0.0, delta * 0.8)
	var pulse := 0.5 + 0.5 * sin(t * 10.0)
	core.scale = Vector3.ONE * (1.0 + _weak * (0.6 + pulse * 0.5))
	core_light.light_energy = _weak * (2.0 + pulse * 3.0)
