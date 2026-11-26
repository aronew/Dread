class_name MicroRocket
extends Node3D
## Shoulder-pod micro-rocket: pops upward, then curves onto its target and detonates.

var source: Node
var target_node: Node3D
var target_point: Vector3
var velocity: Vector3
var damage: float = 45.0
var blast_radius: float = 2.6
var speed: float = 26.0
var turn_rate: float = 9.0
var _t: float = 0.0
var _arming: float = 0.18
var _trail: GPUParticles3D


func setup(p_source: Node, origin: Vector3, launch_dir: Vector3, p_target: Node3D, p_point: Vector3) -> void:
	source = p_source
	global_position = origin
	velocity = launch_dir.normalized() * 14.0
	target_node = p_target
	target_point = p_point


func _ready() -> void:
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.07
	cap.height = 0.45
	body.mesh = cap
	body.rotation_degrees.x = 90.0
	body.material_override = PlaceholderKit.mat(Color(0.85, 0.85, 0.82), 0.6, 0.3)
	add_child(body)
	var flame := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	flame.mesh = s
	flame.position.z = 0.3
	flame.scale = Vector3(1, 1, 2.2)
	flame.material_override = PlaceholderKit.glow(Color(1.0, 0.55, 0.15), 10.0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)
	_trail = Vfx.make_trail(Color(1.0, 0.5, 0.15), 40, 0.4)
	add_child(_trail)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_t += delta
	if is_instance_valid(target_node) and not target_node.is_dead():
		target_point = target_node.global_position + Vector3.UP * 0.8
	if _t > _arming:
		var to_target := target_point - global_position
		var desired := to_target.normalized() * speed
		if to_target.length() < 5.0:
			# terminal guidance: lock on so missiles never orbit their target
			velocity = desired
		else:
			velocity = velocity.lerp(desired, minf((turn_rate + _t * 12.0) * delta, 1.0))
		speed = minf(speed + 30.0 * delta, 40.0)
	else:
		velocity += Vector3.DOWN * 10.0 * delta
	var from := global_position
	var to := from + velocity * delta
	# Smart missiles arc over cover: they only collide with enemies (and the floor below).
	var hit := Combat.raycast(get_world_3d(), from, to, Combat.LAYER_ENEMIES)
	if not hit.is_empty():
		_detonate(hit.position)
		return
	global_position = to
	if velocity.length_squared() > 0.01:
		look_at(to + velocity, Vector3.UP)
	if global_position.distance_to(target_point) < 0.9 or _t > 2.5 or global_position.y < 0.05:
		_detonate(global_position)


func _detonate(at: Vector3) -> void:
	Vfx.explosion(at, blast_radius)
	Sfx.play(&"explosion", at, -3.0, 0.12, 50)
	Feel.shake(0.16)
	Combat.explode(get_tree(), at, blast_radius, damage, source, 9.0, 45.0)
	Vfx.release_trail(_trail)
	queue_free()
