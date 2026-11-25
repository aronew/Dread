extends ActorVisual
## Placeholder Exo-Suit: red/white armored hunter mech with a pulse-cannon arm,
## an energy blade arm, shoulder rocket pods and blue back thrusters.
## Twin-stick rig: hips/legs face the movement direction, torso faces the aim.

const K := preload("res://assets/placeholders/placeholder_kit.gd")

var hips: Node3D
var torso: Node3D
var leg_l: Node3D
var leg_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var gun_arm: Node3D
var blade_arm: Node3D
var blade_mesh: MeshInstance3D
var thrusters: Array[MeshInstance3D] = []
var thruster_light: OmniLight3D

var _velocity := Vector3.ZERO
var _max_speed := 8.0
var _aim_yaw := 0.0
var _hips_yaw := 0.0
var _torso_yaw := 0.0
var _phase := 0.0
var _leg_dir := 1.0
var _recoil := 0.0
var _melee_t := -1.0
var _melee_dur := 0.22
var _melee_side := 1.0
var _thrust := 0.0
var _lean := Vector2.ZERO
var _hit_kick := 0.0
var _ability_t := 0.0
var _dead := false


func _build() -> void:
	scale = Vector3.ONE * 1.2
	var red := K.mat(K.ARMOR_RED, 0.35, 0.3)
	var white := K.mat(K.ARMOR_WHITE, 0.15, 0.3)
	var metal := K.mat(K.GUNMETAL, 0.85, 0.38)
	var joint := K.mat(Color(0.18, 0.19, 0.22), 0.9, 0.45)
	var visor := K.glow(K.VISOR_CYAN, 5.0)
	var thrust := K.glow(K.THRUST_BLUE, 7.0)

	# ---- Hips + legs ------------------------------------------------------
	hips = K.pivot(self, Vector3(0, 0.98, 0), "Hips")
	K.box(hips, Vector3(0.56, 0.24, 0.36), Vector3.ZERO, metal)
	K.box(hips, Vector3(0.6, 0.12, 0.4), Vector3(0, 0.12, 0), red)
	for side in [-1.0, 1.0]:
		var leg := K.pivot(hips, Vector3(0.2 * side, -0.05, 0))
		K.box(leg, Vector3(0.22, 0.48, 0.26), Vector3(0, -0.24, 0), red)
		K.sphere(leg, 0.11, Vector3(0, -0.5, 0), joint)
		var shin := K.pivot(leg, Vector3(0, -0.5, 0))
		K.box(shin, Vector3(0.2, 0.44, 0.24), Vector3(0, -0.2, 0.02), white)
		K.box(shin, Vector3(0.12, 0.08, 0.04), Vector3(0, -0.06, -0.13), K.glow(K.THRUST_BLUE, 3.0))
		K.box(shin, Vector3(0.24, 0.1, 0.38), Vector3(0, -0.43, -0.05), metal)
		if side < 0.0:
			leg_l = leg
			shin_l = shin
		else:
			leg_r = leg
			shin_r = shin

	# ---- Torso (aims) -----------------------------------------------------
	torso = K.pivot(self, Vector3(0, 1.08, 0), "Torso")
	K.box(torso, Vector3(0.74, 0.56, 0.46), Vector3(0, 0.3, 0), red)
	K.box(torso, Vector3(0.52, 0.3, 0.06), Vector3(0, 0.34, -0.24), white)
	K.box(torso, Vector3(0.5, 0.2, 0.4), Vector3(0, 0.02, 0.0), metal)
	K.sphere(torso, 0.07, Vector3(0, 0.3, -0.28), K.glow(K.VISOR_CYAN, 8.0))
	# head
	K.box(torso, Vector3(0.28, 0.26, 0.32), Vector3(0, 0.72, -0.02), metal)
	K.box(torso, Vector3(0.24, 0.05, 0.03), Vector3(0, 0.74, -0.18), visor)
	K.box(torso, Vector3(0.05, 0.16, 0.2), Vector3(0, 0.88, 0.02), red)
	# shoulder pads
	for side in [-1.0, 1.0]:
		K.box(torso, Vector3(0.34, 0.22, 0.44), Vector3(0.52 * side, 0.56, 0), white, Vector3(0, 0, -12 * side))
		K.box(torso, Vector3(0.36, 0.05, 0.46), Vector3(0.52 * side, 0.6, 0), red, Vector3(0, 0, -12 * side))
	# backpack + rocket pod
	K.box(torso, Vector3(0.52, 0.56, 0.26), Vector3(0, 0.34, 0.33), metal)
	var pod := K.pivot(torso, Vector3(0.38, 0.86, 0.22))
	K.box(pod, Vector3(0.3, 0.2, 0.34), Vector3.ZERO, white)
	for ix in 3:
		for iy in 2:
			K.box(pod, Vector3(0.05, 0.05, 0.02), Vector3(-0.08 + ix * 0.08, -0.04 + iy * 0.08, -0.175), K.glow(Color(1.0, 0.45, 0.1), 5.0)).set_meta(&"no_overlay", true)
	add_socket(&"rocket_pod", pod, Vector3(0, 0.05, -0.2))
	# thrusters
	for side in [-1.0, 1.0]:
		K.cylinder(torso, 0.09, 0.12, 0.3, Vector3(0.16 * side, 0.1, 0.48), metal, Vector3(-60, 0, 0))
		var flame := K.cylinder(torso, 0.1, 0.0, 0.5, Vector3(0.16 * side, -0.06, 0.62), thrust, Vector3(-60, 0, 0))
		flame.set_meta(&"no_overlay", true)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		thrusters.append(flame)
	add_socket(&"thruster", torso, Vector3(0, 0.0, 0.6))
	thruster_light = OmniLight3D.new()
	thruster_light.light_color = K.THRUST_BLUE
	thruster_light.omni_range = 3.0
	thruster_light.light_energy = 0.6
	thruster_light.position = Vector3(0, 0.0, 0.7)
	torso.add_child(thruster_light)

	# ---- Gun arm (right) -----------------------------------------------------
	gun_arm = K.pivot(torso, Vector3(0.5, 0.42, 0), "GunArm")
	K.box(gun_arm, Vector3(0.2, 0.36, 0.22), Vector3(0, -0.14, 0), white)
	K.box(gun_arm, Vector3(0.18, 0.18, 0.5), Vector3(0, -0.28, -0.24), metal)
	K.box(gun_arm, Vector3(0.16, 0.2, 0.86), Vector3(0.02, -0.25, -0.7), metal)
	K.box(gun_arm, Vector3(0.17, 0.05, 0.6), Vector3(0.02, -0.13, -0.66), red)
	K.box(gun_arm, Vector3(0.02, 0.04, 0.5), Vector3(0.115, -0.25, -0.7), K.glow(K.VISOR_CYAN, 6.0))
	K.cylinder(gun_arm, 0.06, 0.07, 0.3, Vector3(0.02, -0.27, -1.2), metal, Vector3(90, 0, 0))
	add_socket(&"muzzle", gun_arm, Vector3(0.02, -0.27, -1.4))

	# ---- Blade arm (left) ------------------------------------------------------
	blade_arm = K.pivot(torso, Vector3(-0.5, 0.42, 0), "BladeArm")
	K.box(blade_arm, Vector3(0.2, 0.36, 0.22), Vector3(0, -0.14, 0), white)
	K.box(blade_arm, Vector3(0.18, 0.18, 0.46), Vector3(0, -0.3, -0.22), metal)
	K.box(blade_arm, Vector3(0.12, 0.14, 0.18), Vector3(0, -0.3, -0.5), red)
	blade_mesh = K.box(blade_arm, Vector3(0.035, 0.14, 1.35), Vector3(0, -0.3, -1.22), K.glow(Color(0.35, 0.75, 1.0), 6.0))
	blade_mesh.set_meta(&"no_overlay", true)
	add_socket(&"blade_tip", blade_arm, Vector3(0, -0.3, -1.9))


func set_locomotion(world_velocity: Vector3, max_speed: float) -> void:
	_velocity = world_velocity
	_max_speed = max_speed


func set_aim(world_direction: Vector3) -> void:
	if world_direction.length_squared() > 0.001:
		_aim_yaw = atan2(-world_direction.x, -world_direction.z)


func play_action(action: StringName, duration: float = -1.0) -> void:
	match action:
		&"shoot":
			_recoil = 1.0
		&"melee":
			_melee_dur = duration if duration > 0.0 else 0.22
			_melee_t = 0.0
			_melee_side = -_melee_side
		&"dash":
			_thrust = 1.0
		&"ability":
			_ability_t = 1.0
		&"hit":
			_hit_kick = 1.0
		&"die":
			_dead = true


func _animate(delta: float) -> void:
	if _dead:
		torso.rotation.x = lerpf(torso.rotation.x, 0.6, delta * 4.0)
		hips.position.y = lerpf(hips.position.y, 0.55, delta * 4.0)
		for t in thrusters:
			t.scale = t.scale.lerp(Vector3.ONE * 0.05, delta * 6.0)
		return

	var flat := Vector3(_velocity.x, 0, _velocity.z)
	var speed := flat.length()
	var speed_ratio := clampf(speed / maxf(_max_speed, 0.1), 0.0, 1.6)

	# --- Hips face movement; flip to backpedal when moving against the aim.
	if speed > 0.5:
		var move_yaw := atan2(-flat.x, -flat.z)
		var diff := wrapf(move_yaw - _aim_yaw, -PI, PI)
		if absf(diff) > PI * 0.6:
			move_yaw = wrapf(move_yaw + PI, -PI, PI)
			_leg_dir = -1.0
		else:
			_leg_dir = 1.0
		_hips_yaw = lerp_angle(_hips_yaw, move_yaw, minf(delta * 14.0, 1.0))
	else:
		_hips_yaw = lerp_angle(_hips_yaw, _aim_yaw, minf(delta * 6.0, 1.0))
	hips.rotation.y = _hips_yaw
	_torso_yaw = lerp_angle(_torso_yaw, _aim_yaw, minf(delta * 30.0, 1.0))
	var twist := 0.0

	# --- Gait
	_phase += delta * (4.0 + 9.0 * speed_ratio) * _leg_dir * (1.0 if speed > 0.3 else 0.0)
	var swing := sin(_phase) * 0.75 * minf(speed_ratio, 1.0)
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	shin_l.rotation.x = maxf(0.0, -cos(_phase)) * 0.9 * minf(speed_ratio, 1.0)
	shin_r.rotation.x = maxf(0.0, cos(_phase)) * 0.9 * minf(speed_ratio, 1.0)
	var bob := absf(sin(_phase)) * 0.07 * minf(speed_ratio, 1.0)
	var breathe := sin(Time.get_ticks_msec() * 0.0025) * 0.015
	hips.position.y = 0.98 + bob + breathe
	torso.position.y = 1.08 + bob * 1.2 + breathe

	# --- Lean into movement (in torso-local space)
	var local_v := flat.rotated(Vector3.UP, -_aim_yaw) / maxf(_max_speed, 0.1)
	_lean = _lean.lerp(Vector2(local_v.x, local_v.z), minf(delta * 8.0, 1.0))
	torso.rotation.x = _lean.y * 0.22 - _hit_kick * 0.25
	torso.rotation.z = -_lean.x * 0.15

	# --- Gun recoil
	_recoil = move_toward(_recoil, 0.0, delta * 9.0)
	gun_arm.rotation.x = _recoil * 0.28 + _ability_t * 0.3
	gun_arm.position.z = _recoil * 0.12

	# --- Blade swing (wide horizontal cleave)
	if _melee_t >= 0.0:
		_melee_t += delta / _melee_dur
		var t := clampf(_melee_t, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - t, 3.0)
		blade_arm.rotation.y = lerpf(1.5, -1.7, e) * _melee_side * -1.0
		blade_arm.rotation.x = -0.3
		blade_arm.rotation.z = lerpf(0.4, -0.4, e) * _melee_side
		twist = lerpf(0.5, -0.6, e) * _melee_side * -1.0 * (1.0 - clampf(_melee_t - 1.0, 0.0, 0.6) / 0.6)
		if _melee_t >= 1.6:
			_melee_t = -1.0
	else:
		blade_arm.rotation.y = lerp_angle(blade_arm.rotation.y, 0.35, minf(delta * 10.0, 1.0))
		blade_arm.rotation.x = lerpf(blade_arm.rotation.x, 0.25, minf(delta * 10.0, 1.0))
		blade_arm.rotation.z = lerpf(blade_arm.rotation.z, 0.0, minf(delta * 10.0, 1.0))

	torso.rotation.y = _torso_yaw + twist

	# --- Thrusters
	_thrust = move_toward(_thrust, 0.0, delta * 3.5)
	_hit_kick = move_toward(_hit_kick, 0.0, delta * 6.0)
	_ability_t = move_toward(_ability_t, 0.0, delta * 3.0)
	var flicker := 0.85 + randf() * 0.3
	var flame_len := (0.35 + speed_ratio * 0.5 + _thrust * 2.4) * flicker
	for t in thrusters:
		t.scale = Vector3(1.0 + _thrust * 0.6, flame_len, 1.0 + _thrust * 0.6)
	thruster_light.light_energy = (0.5 + speed_ratio * 0.6 + _thrust * 4.0) * flicker
