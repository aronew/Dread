class_name PostFX
extends CanvasLayer
## Screen-space post effects driven by gameplay events.

var _rect: ColorRect
var _mat: ShaderMaterial
var _damage: float = 0.0
var _aberration: float = 0.0
var _low: float = 0.0


func _ready() -> void:
	layer = 5
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://assets/shaders/post_fx.gdshader")
	_rect.material = _mat
	add_child(_rect)
	Events.player_damaged.connect(func(amount: float, _dir: Vector3):
		_damage = clampf(_damage + 0.25 + amount / 40.0, 0.0, 1.0)
		_aberration = clampf(_aberration + 0.5 + amount / 30.0, 0.0, 1.5))
	Events.player_health_changed.connect(func(c: float, m: float): _low = clampf(1.0 - (c / m) / 0.3, 0.0, 1.0) if m > 0.0 else 0.0)
	Events.finisher_performed.connect(func(_e): _aberration = 1.2)
	Events.player_died.connect(_on_died)


func _on_died() -> void:
	_aberration = 1.5
	_damage = 1.0


func _process(delta: float) -> void:
	var dt := delta / maxf(Engine.time_scale, 0.05)
	_damage = move_toward(_damage, 0.0, dt * 1.6)
	_aberration = move_toward(_aberration, 0.0, dt * 3.0)
	_mat.set_shader_parameter(&"damage", _damage)
	_mat.set_shader_parameter(&"aberration", _aberration)
	_mat.set_shader_parameter(&"low_health", _low)
