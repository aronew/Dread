extends Node3D
## ARPG-style ground ring + aim chevron under the player. Keeps the hero readable
## in the middle of heavy VFX. Purely visual; follows the player's aim.

var player: Node3D
var _ring: MeshInstance3D
var _chevron: Node3D
var _mat: ShaderMaterial


func _ready() -> void:
	top_level = true
	_ring = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.4, 2.4)
	_ring.mesh = plane
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://assets/shaders/ring.gdshader")
	_mat.set_shader_parameter(&"color", Color(0.25, 0.85, 1.0))
	_mat.set_shader_parameter(&"progress", 0.62)
	_mat.set_shader_parameter(&"thickness", 0.05)
	_mat.set_shader_parameter(&"energy", 2.2)
	_ring.material_override = _mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_chevron = Node3D.new()
	add_child(_chevron)
	var glow := PlaceholderKit.glow(Color(0.3, 0.9, 1.0), 3.0)
	for side in [-1.0, 1.0]:
		var bar := PlaceholderKit.box(_chevron, Vector3(0.07, 0.02, 0.4), Vector3(0.13 * side, 0, -1.45), glow, Vector3(0, -35 * side, 0))
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	global_position = Vector3(player.global_position.x, 0.03, player.global_position.z)
	var dir: Vector3 = player.aim_dir
	_chevron.rotation.y = atan2(-dir.x, -dir.z)
	visible = not player.is_dead()
