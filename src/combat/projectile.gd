class_name Projectile
extends Node3D
## Player projectile. Swept raycast each physics tick (no tunneling at high speed).
## Mod hooks: `hit_hooks` callables run on every hit -> func(projectile, target, info).

var weapon: WeaponData
var source: Node
var velocity: Vector3 = Vector3.ZERO
var damage: float = 10.0
var travelled: float = 0.0
var max_range: float = 30.0
var pierce_left: int = 0
var crit_chance: float = 0.1
var hit_hooks: Array[Callable] = []
var _already_hit: Array[RID] = []
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _dead: bool = false

static var _shared_mesh: CapsuleMesh
static var _mat_cache: Dictionary = {}


var _origin: Vector3


## Call BEFORE add_child (only stores data; transform is applied in _ready).
func setup(p_weapon: WeaponData, p_source: Node, origin: Vector3, direction: Vector3) -> void:
	weapon = p_weapon
	source = p_source
	velocity = direction.normalized() * weapon.projectile_speed
	damage = weapon.damage
	max_range = weapon.projectile_range
	pierce_left = weapon.pierce
	crit_chance = weapon.crit_chance
	_origin = origin


func _ready() -> void:
	global_position = _origin
	if velocity.length_squared() > 0.0001:
		look_at(_origin + velocity, Vector3.UP)
	if _shared_mesh == null:
		_shared_mesh = CapsuleMesh.new()
		_shared_mesh.radius = 0.5
		_shared_mesh.height = 2.0
		_shared_mesh.radial_segments = 10
		_shared_mesh.rings = 4
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _shared_mesh
	_mesh.rotation_degrees.x = 90.0
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var w := weapon.projectile_width
	_mesh.scale = Vector3(w, weapon.projectile_length * 0.5, w)
	_mesh.position.z = weapon.projectile_length * 0.25
	var key := weapon.color.to_html()
	if not _mat_cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = preload("res://assets/shaders/tracer.gdshader")
		m.set_shader_parameter(&"color", weapon.color)
		_mat_cache[key] = m
	_mesh.material_override = _mat_cache[key]
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var from := global_position
	var step := velocity * delta
	var to := from + step
	var space := get_world_3d()
	# Several hits per tick possible when piercing.
	var guard := 0
	while guard < 4:
		guard += 1
		var exclude: Array[RID] = _already_hit.duplicate()
		var hit := Combat.raycast(space, from, to, Combat.LAYER_WORLD | Combat.LAYER_ENEMIES, exclude)
		if hit.is_empty():
			break
		var collider: Object = hit.collider
		var point: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		if collider and collider.has_method(&"apply_damage") and collider.is_in_group(Combat.GROUP_ENEMIES):
			_hit_enemy(collider, point)
			_already_hit.append(hit.rid)
			if pierce_left <= 0:
				_die()
				return
			pierce_left -= 1
			from = point
		else:
			_hit_world(point, normal)
			return
	global_position = to
	travelled += step.length()
	if travelled >= max_range:
		_fizzle()


func _hit_enemy(enemy: Node, point: Vector3) -> void:
	var crit := randf() < crit_chance
	var info := DamageInfo.make(damage * (weapon.crit_multiplier if crit else 1.0), weapon.damage_kind, source, point, velocity)
	info.is_crit = crit
	info.knockback = weapon.knockback
	info.poise_damage = weapon.poise_damage
	enemy.apply_damage(info)
	for hook in hit_hooks:
		hook.call(self, enemy, info)


func _hit_world(point: Vector3, normal: Vector3) -> void:
	Vfx.impact(point + normal * 0.05, normal, weapon.color, 0.8)
	Sfx.play(&"bullet_impact", point, -10.0, 0.15, 40)
	for hook in hit_hooks:
		hook.call(self, null, null)
	_die()


func _fizzle() -> void:
	Vfx.impact(global_position, -velocity.normalized(), weapon.color, 0.3)
	_die()


func _die() -> void:
	_dead = true
	queue_free()
