class_name Projectile
extends Node3D
## Player projectile.
##  * Hit detection is TOP-DOWN (2D, XZ plane): a bullet hits anything whose
##    footprint circle it crosses, regardless of height. That is how isometric
##    shooters read — what you see under the cursor is what you hit.
##  * Walls are a swept raycast at flight height (low cover can be shot over).
##  * Optional gentle homing toward the aim-assist target ("bullet magnetism").
##  * Moves every rendered frame for smooth tracers.
## Mod hooks: `hit_hooks` callables run on every hit -> func(projectile, target, info).

const FLIGHT_HEIGHT := 1.4
const TRACER_SHADER := preload("res://assets/shaders/tracer.gdshader")

var weapon: WeaponData
var source: Node
var velocity: Vector3 = Vector3.ZERO
var damage: float = 10.0
var travelled: float = 0.0
var max_range: float = 30.0
var pierce_left: int = 0
var crit_chance: float = 0.1
var radius: float = 0.25
var homing_target: Node3D = null
var hit_hooks: Array[Callable] = []
var _hit_ids: Dictionary = {}
var _mesh: MeshInstance3D
var _origin: Vector3
var _dead: bool = false

static var _quad: QuadMesh
static var _mat_cache: Dictionary = {}


## Call BEFORE add_child (only stores data; transform is applied in _ready).
func setup(p_weapon: WeaponData, p_source: Node, origin: Vector3, direction: Vector3, target: Node3D = null) -> void:
	weapon = p_weapon
	source = p_source
	var d := Vector3(direction.x, 0.0, direction.z).normalized()
	velocity = d * weapon.projectile_speed
	damage = weapon.damage
	max_range = weapon.projectile_range
	pierce_left = weapon.pierce
	crit_chance = weapon.crit_chance
	radius = weapon.hit_radius
	homing_target = target
	_origin = Vector3(origin.x, FLIGHT_HEIGHT, origin.z)


func _ready() -> void:
	global_position = _origin
	if velocity.length_squared() > 0.0001:
		look_at(_origin + velocity, Vector3.UP)
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _quad
	_mesh.material_override = tracer_material(weapon.color, weapon.projectile_width)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.extra_cull_margin = weapon.projectile_length + 1.0
	_mesh.set_instance_shader_parameter(&"trail_len", 0.05)
	add_child(_mesh)


static func tracer_material(color: Color, width: float) -> ShaderMaterial:
	var key := "%s|%.3f" % [color.to_html(), width]
	if not _mat_cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = TRACER_SHADER
		m.set_shader_parameter(&"color", color)
		m.set_shader_parameter(&"width", width)
		_mat_cache[key] = m
	return _mat_cache[key]


func _process(delta: float) -> void:
	if _dead or delta <= 0.0:
		return
	_steer(delta)
	var from := global_position
	var step := velocity * delta
	var step_len := step.length()
	var to := from + step

	var world_t := INF
	var world_hit := Combat.raycast(get_world_3d(), from, to, Combat.LAYER_WORLD)
	if not world_hit.is_empty():
		world_t = from.distance_to(world_hit.position) / maxf(step_len, 0.00001)

	# enemies along this step, nearest first (pierce can hit several)
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var guard := 0
	while guard < 6:
		guard += 1
		var best: Node3D = null
		var best_t := world_t
		for e in Combat.living_enemies(get_tree()):
			if _hit_ids.has(e.get_instance_id()):
				continue
			var t := seg_circle(a, b, Vector2(e.global_position.x, e.global_position.z), float(e.radius) + radius)
			if t < best_t:
				best_t = t
				best = e
		if best == null:
			break
		_hit_ids[best.get_instance_id()] = true
		var point := from.lerp(to, best_t)
		_hit_enemy(best, Vector3(point.x, minf(point.y, 0.5 + float(best.radius)), point.z))
		if pierce_left <= 0:
			_die()
			return
		pierce_left -= 1

	if world_t <= 1.0:
		_hit_world(world_hit.position, world_hit.normal)
		return
	global_position = to
	travelled += step_len
	_mesh.set_instance_shader_parameter(&"trail_len", minf(weapon.projectile_length, travelled + 0.3))
	if travelled >= max_range:
		_fizzle()


func _steer(delta: float) -> void:
	if weapon.homing <= 0.0 or not is_instance_valid(homing_target) or homing_target.is_dead():
		return
	var to := homing_target.global_position - global_position
	to.y = 0.0
	if to.length() < 0.3:
		return
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var ang := flat.signed_angle_to(to, Vector3.UP)
	if absf(ang) > deg_to_rad(weapon.homing_cone_deg):
		return
	var turn := clampf(ang, -weapon.homing * delta, weapon.homing * delta)
	velocity = velocity.rotated(Vector3.UP, turn)
	look_at(global_position + velocity, Vector3.UP)


## 2D segment vs circle. Returns the entry fraction t in [0,1], or INF.
static func seg_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> float:
	var d := b - a
	var f := a - c
	var qa := d.dot(d)
	var qc := f.dot(f) - r * r
	if qc <= 0.0:
		return 0.0
	if qa < 0.0000001:
		return INF
	var qb := 2.0 * f.dot(d)
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return INF
	var t := (-qb - sqrt(disc)) / (2.0 * qa)
	return t if t >= 0.0 and t <= 1.0 else INF


func _hit_enemy(enemy: Node, point: Vector3) -> void:
	var crit := randf() < crit_chance
	var info := DamageInfo.make(damage * (weapon.crit_multiplier if crit else 1.0), weapon.damage_kind, source, point, velocity)
	info.is_crit = crit
	info.knockback = weapon.knockback
	info.poise_damage = weapon.poise_damage
	enemy.apply_damage(info)
	Vfx.bullet_hit(point, velocity.normalized(), weapon.color, crit)
	for hook in hit_hooks:
		hook.call(self, enemy, info)


func _hit_world(point: Vector3, normal: Vector3) -> void:
	Vfx.impact(point + normal * 0.05, normal, weapon.color, 0.8)
	Sfx.play(&"bullet_impact", point, -12.0, 0.15, 40)
	for hook in hit_hooks:
		hook.call(self, null, null)
	_die()


func _fizzle() -> void:
	Vfx.burst(&"flash", global_position, Basis.IDENTITY, weapon.color, 1, 0.35)
	_die()


func _die() -> void:
	_dead = true
	queue_free()
