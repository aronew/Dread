extends ActorVisual
## "Bloom Spitter" — gaunt mossy-teal husk crowned with coral mushroom caps,
## a yellow frowning mask and a glowing bile sac that swells before each volley.

const K := preload("res://assets/placeholders/placeholder_kit.gd")

var body: Node3D
var crown: Node3D
var sac: MeshInstance3D
var sac_light: OmniLight3D
var arm_l: Node3D
var arm_r: Node3D
var _velocity := Vector3.ZERO
var _max_speed := 4.0
var _yaw := 0.0
var _phase := randf() * TAU
var _charge_vis := 0.0
var _recoil := 0.0
var _stagger := 0.0
var _dead := false


func _build() -> void:
	var husk := K.flesh(Color(0.36, 0.55, 0.42))
	var flesh := K.flesh(K.FLESH)
	var cap_a := K.flesh(Color(1.0, 0.42, 0.45))
	var cap_b := K.flesh(Color(1.0, 0.62, 0.3))
	var gill := K.flesh(Color(1.0, 0.85, 0.75))
	var teal := K.flesh(K.SLIME, 0.8)

	body = K.pivot(self, Vector3(0, 0.0, 0), "Body")
	# robe-like lower body
	K.cylinder(body, 0.28, 0.48, 1.0, Vector3(0, 0.55, 0), husk)
	K.cylinder(body, 0.5, 0.46, 0.12, Vector3(0, 0.06, 0), K.flesh(Color(0.25, 0.4, 0.3)))
	# torso + neck
	K.capsule(body, 0.26, 0.8, Vector3(0, 1.25, 0), husk)
	K.capsule(body, 0.11, 0.4, Vector3(0, 1.62, -0.04), flesh)
	# bile sac (chest) — scales with charge
	sac = K.sphere(body, 0.24, Vector3(0, 1.18, -0.2), K.flesh(K.BILE, 2.5), Vector3(1.0, 1.0, 0.9))
	sac.set_meta(&"no_overlay", true)
	sac_light = OmniLight3D.new()
	sac_light.light_color = K.BILE
	sac_light.omni_range = 3.5
	sac_light.light_energy = 0.4
	sac_light.position = Vector3(0, 1.2, -0.45)
	body.add_child(sac_light)
	# mask face
	K.mask_face(body, 0.19, Vector3(0, 1.82, -0.1))
	add_socket(&"mouth", body, Vector3(0, 1.5, -0.55))
	# mushroom crown
	crown = K.pivot(body, Vector3(0, 2.0, 0.02), "Crown")
	var caps := [
		[Vector3(0, 0.12, 0), 0.42, cap_a, Vector3(0, 0, 0)],
		[Vector3(-0.32, -0.02, 0.1), 0.3, cap_b, Vector3(10, 0, 30)],
		[Vector3(0.3, 0.0, 0.08), 0.32, cap_a, Vector3(-5, 0, -28)],
		[Vector3(0.05, 0.3, 0.2), 0.24, cap_b, Vector3(-20, 0, 8)],
	]
	for c in caps:
		var p := K.pivot(crown, c[0])
		p.rotation_degrees = c[3]
		K.sphere(p, c[1], Vector3.ZERO, c[2], Vector3(1.0, 0.38, 1.0))
		K.cylinder(p, c[1] * 0.92, c[1] * 0.6, 0.04, Vector3(0, -c[1] * 0.18, 0), gill)
		K.cylinder(p, 0.05, 0.07, 0.3, Vector3(0, -0.2, 0), gill)
		# glowing spots
		K.sphere(p, c[1] * 0.12, Vector3(c[1] * 0.4, c[1] * 0.3, 0), K.glow(Color(1.0, 0.9, 0.5), 3.0))
	# arms
	arm_l = K.pivot(body, Vector3(-0.3, 1.5, 0))
	arm_r = K.pivot(body, Vector3(0.3, 1.5, 0))
	for a in [arm_l, arm_r]:
		K.capsule(a, 0.06, 0.95, Vector3(0, -0.45, 0), husk)
		K.capsule(a, 0.05, 0.3, Vector3(0, -0.98, -0.05), teal, Vector3(20, 0, 0))


func set_locomotion(world_velocity: Vector3, max_speed: float) -> void:
	_velocity = world_velocity
	_max_speed = max_speed


func set_aim(world_direction: Vector3) -> void:
	if world_direction.length_squared() > 0.001:
		_yaw = atan2(-world_direction.x, -world_direction.z)


func play_action(action: StringName, _duration: float = -1.0) -> void:
	match action:
		&"attack":
			_recoil = 1.0
			_charge_vis = 0.0
		&"stagger", &"hit":
			_stagger = 1.0
		&"die":
			_dead = true


func set_charge(amount: float, color: Color = Color(1.0, 0.25, 0.15)) -> void:
	super.set_charge(amount, color)
	_charge_vis = amount


func _animate(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _yaw, minf(delta * 8.0, 1.0))
	if _dead:
		return
	var speed := Vector2(_velocity.x, _velocity.z).length()
	var r := clampf(speed / maxf(_max_speed, 0.1), 0.0, 1.5)
	_phase += delta * (2.0 + 6.0 * r)
	body.position.y = sin(_phase * 2.0) * 0.04
	body.rotation.z = sin(_phase) * 0.06 + sin(Time.get_ticks_msec() * 0.04) * 0.1 * _stagger
	body.rotation.x = -_recoil * 0.3 + _charge_vis * 0.12 + _stagger * 0.2
	crown.rotation.z = sin(_phase * 0.7) * 0.08
	arm_l.rotation.x = sin(_phase) * 0.3 - _charge_vis * 1.2
	arm_r.rotation.x = -sin(_phase) * 0.3 - _charge_vis * 1.2
	arm_l.rotation.z = -0.2 - _charge_vis * 0.4
	arm_r.rotation.z = 0.2 + _charge_vis * 0.4
	var swell := 1.0 + _charge_vis * 0.7 + sin(Time.get_ticks_msec() * 0.03) * 0.05 * _charge_vis
	sac.scale = Vector3(swell, swell, swell * 0.9)
	sac_light.light_energy = 0.4 + _charge_vis * 3.5
	_recoil = move_toward(_recoil, 0.0, delta * 3.0)
	_stagger = move_toward(_stagger, 0.0, delta * 2.0)
