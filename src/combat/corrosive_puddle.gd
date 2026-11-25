extends Node3D
## Lingering corrosive pool left by bile globs. Damages the player over time.

const CORRUPTION := preload("res://assets/shaders/corruption.gdshader")

var radius: float = 1.4
var duration: float = 3.5
var tick_damage: float = 4.0
var tick_interval: float = 0.4
var _t: float = 0.0
var _tick: float = 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.4, radius * 2.4)
	mi.mesh = plane
	_mat = ShaderMaterial.new()
	_mat.shader = CORRUPTION
	_mat.set_shader_parameter(&"seed", randf() * 50.0)
	_mat.set_shader_parameter(&"vein_a", Color(0.65, 1.0, 0.1))
	_mat.set_shader_parameter(&"vein_b", Color(0.2, 1.0, 0.8))
	_mat.set_shader_parameter(&"goo_color", Color(0.12, 0.25, 0.02))
	_mat.set_shader_parameter(&"energy", 4.0)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.04
	add_child(mi)
	scale = Vector3(0.2, 1.0, 0.2)
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	_t += delta
	_tick -= delta
	if _t > duration - 0.6:
		_mat.set_shader_parameter(&"opacity", clampf((duration - _t) / 0.6, 0.0, 1.0))
	if _t >= duration:
		queue_free()
		return
	if _tick <= 0.0:
		var player := Combat.get_player(get_tree())
		if player and Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length() < radius:
			var info := DamageInfo.make(tick_damage, DamageInfo.Kind.CORROSIVE, self, player.global_position, Vector3.ZERO)
			info.tags.append("dot")
			player.apply_damage(info)
			_tick = tick_interval
