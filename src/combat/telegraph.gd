class_name Telegraph
extends Node3D
## Ground danger marker for enemy attacks. Fills over `duration`, flashes on
## completion, then fades. Shapes: CIRCLE (radius) or LINE (width x length along -Z).

enum Shape { CIRCLE, LINE }

const SHADER := preload("res://assets/shaders/telegraph.gdshader")

var shape: Shape = Shape.CIRCLE
var duration: float = 1.0
var color: Color = Color(1.0, 0.15, 0.08)
var _mat: ShaderMaterial
var _mesh: MeshInstance3D
var _t: float = 0.0
var _done: bool = false


static func circle(parent: Node, pos: Vector3, radius: float, p_duration: float, p_color: Color = Color(1.0, 0.15, 0.08)) -> Telegraph:
	var t := Telegraph.new()
	t.shape = Shape.CIRCLE
	t.duration = p_duration
	t.color = p_color
	parent.add_child(t)
	t.global_position = Vector3(pos.x, 0.03, pos.z)
	t._build(Vector2(radius * 2.0, radius * 2.0), 0.0)
	return t


static func line(parent: Node, origin: Vector3, direction: Vector3, width: float, length: float,
		p_duration: float, p_color: Color = Color(1.0, 0.15, 0.08)) -> Telegraph:
	var t := Telegraph.new()
	t.shape = Shape.LINE
	t.duration = p_duration
	t.color = p_color
	parent.add_child(t)
	t.global_position = Vector3(origin.x, 0.03, origin.z)
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	if flat.length_squared() > 0.001:
		t.look_at(t.global_position + flat, Vector3.UP)
	t._build(Vector2(width, length), -length * 0.5)
	return t


func _build(size: Vector2, z_offset: float) -> void:
	_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	_mesh.mesh = plane
	_mesh.position.z = z_offset
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"color", color)
	_mat.set_shader_parameter(&"shape", int(shape))
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_mat.set_shader_parameter(&"progress", clampf(_t / duration, 0.0, 1.0))


## Call when the attack lands (flash + fade). Safe to call early to cancel.
func finish(flash_out: bool = true) -> void:
	if _done:
		return
	_done = true
	_mat.set_shader_parameter(&"progress", 1.0)
	var tw := create_tween()
	if flash_out:
		tw.tween_method(func(v: float): _mat.set_shader_parameter(&"flash", v), 1.0, 0.0, 0.15)
	tw.tween_method(func(v: float): _mat.set_shader_parameter(&"fade", v), 1.0, 0.0, 0.2)
	tw.tween_callback(queue_free)
