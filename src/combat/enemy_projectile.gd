class_name EnemyProjectile
extends Node3D
## Glowing corrosive bile glob. Slow enough to dodge, leaves a corrosive puddle.
## Melee can REFLECT it: it then becomes a player projectile dealing bonus damage.

const K := preload("res://assets/placeholders/placeholder_kit.gd")
const PUDDLE := preload("res://src/combat/corrosive_puddle.gd")

var velocity: Vector3 = Vector3.ZERO
var damage: float = 12.0
var source: Node
var lifetime: float = 4.0
var reflected: bool = false
var color: Color = Color(0.6, 1.0, 0.15)
var radius: float = 0.35
var _body: MeshInstance3D
var _light: OmniLight3D
var _t: float = 0.0
var _trail: GPUParticles3D


func setup(p_source: Node, origin: Vector3, dir: Vector3, speed: float, p_damage: float) -> void:
	source = p_source
	global_position = origin
	velocity = dir.normalized() * speed
	damage = p_damage


func _ready() -> void:
	add_to_group(Combat.GROUP_ENEMY_PROJECTILES)
	_body = K.sphere(self, 0.26, Vector3.ZERO, K.flesh(color, 4.0))
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core := K.sphere(self, 0.13, Vector3.ZERO, K.glow(Color(0.95, 1.0, 0.7), 8.0))
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 1.6
	_light.omni_range = 3.2
	add_child(_light)
	_trail = Vfx.make_trail(color, 28)
	add_child(_trail)


func reflect(new_dir: Vector3, by: Node) -> void:
	reflected = true
	source = by
	velocity = new_dir.normalized() * velocity.length() * 1.8
	damage *= 4.0
	color = Color(0.3, 0.9, 1.0)
	_light.light_color = color
	_body.material_override = K.flesh(color, 5.0)
	remove_from_group(Combat.GROUP_ENEMY_PROJECTILES)
	lifetime = 2.0
	Vfx.impact(global_position, new_dir, color, 1.5)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_t += delta
	var wob := 1.0 + sin(_t * 30.0) * 0.12
	_body.scale = Vector3(wob, 1.0 / wob, wob)
	var from := global_position
	var to := from + velocity * delta
	var hit := Combat.raycast(get_world_3d(), from, to, Combat.LAYER_WORLD)
	if not hit.is_empty():
		_splash(hit.position)
		return
	global_position = to
	if reflected:
		for e in Combat.enemies_in_radius(get_tree(), global_position, radius):
			var info := DamageInfo.make(damage, DamageInfo.Kind.CORROSIVE, source, global_position, velocity)
			info.knockback = 8.0
			info.poise_damage = 60.0
			info.tags.append("reflected")
			e.apply_damage(info)
			_splash(global_position)
			return
	else:
		var player := Combat.get_player(get_tree())
		if player and player.has_method(&"apply_damage"):
			var d := Vector2(player.global_position.x - to.x, player.global_position.z - to.z).length()
			if d < radius + 0.45:
				var info := DamageInfo.make(damage, DamageInfo.Kind.CORROSIVE, source, global_position, velocity)
				info.knockback = 4.0
				if player.apply_damage(info):
					_splash(global_position)
					return
	lifetime -= delta
	if lifetime <= 0.0:
		_splash(global_position)


func _splash(at: Vector3) -> void:
	var ground := Vector3(at.x, 0.0, at.z)
	Vfx.gore(at, velocity, color, 1.0, Color(0.55, 0.2, 1.0))
	Sfx.play(&"spit_impact", at, -4.0)
	if not reflected:
		var puddle: Node3D = PUDDLE.new()
		get_parent().add_child(puddle)
		puddle.global_position = ground
	else:
		Vfx.explosion(at, 2.2, color)
		Combat.explode(get_tree(), at, 2.2, damage * 0.5, source, 6.0, 40.0, DamageInfo.Kind.CORROSIVE)
	Vfx.release_trail(_trail)
	queue_free()
