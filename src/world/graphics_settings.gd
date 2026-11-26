class_name GraphicsSettings
extends Node
## F8 cycles LOW / MEDIUM / HIGH, F9 toggles the FPS readout, M toggles music.
## The choice is saved to user://settings.cfg. A smooth framerate matters more to
## game feel than any single effect, so MEDIUM is the default.

enum Quality { LOW, MEDIUM, HIGH }
const NAMES := ["LOW", "MEDIUM", "HIGH"]
const CFG_PATH := "user://settings.cfg"

var environment: Environment
var quality: Quality = Quality.MEDIUM
var _label: Label
var _show_fps: bool = true
var _accum: float = 0.0
var _frames: int = 0


func setup(env: Environment) -> void:
	environment = env


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		quality = int(cfg.get_value("graphics", "quality", Quality.MEDIUM)) as Quality
		_show_fps = bool(cfg.get_value("graphics", "show_fps", true))
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	_label = Label.new()
	_label.anchor_left = 1.0
	_label.anchor_right = 1.0
	_label.offset_left = -330.0
	_label.offset_right = -20.0
	_label.offset_top = 14.0
	_label.offset_bottom = 40.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override(&"font_size", 16)
	_label.add_theme_color_override(&"font_color", Color(0.7, 0.9, 1.0, 0.75))
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_label)
	_apply.call_deferred()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"cycle_quality"):
		quality = ((quality + 1) % 3) as Quality
		_apply()
		_save()
		Events.announce.emit("GRAPHICS: " + NAMES[quality], Color(0.6, 0.9, 1.0))
	if Input.is_action_just_pressed(&"toggle_fps"):
		_show_fps = not _show_fps
		_save()
	if Input.is_action_just_pressed(&"toggle_music"):
		var on := Sfx.toggle_music()
		Events.announce.emit("MUSIC " + ("ON" if on else "OFF"), Color(0.6, 0.9, 1.0))
	_label.visible = _show_fps
	_accum += delta / maxf(Engine.time_scale, 0.01)
	_frames += 1
	if _accum >= 0.5:
		_label.text = "%d FPS · %s (F8)" % [roundi(_frames / _accum), NAMES[quality]]
		_accum = 0.0
		_frames = 0


func _apply() -> void:
	var vp := get_viewport()
	if environment:
		environment.ssao_enabled = quality >= Quality.MEDIUM
		environment.ssr_enabled = quality == Quality.HIGH
		environment.volumetric_fog_enabled = quality >= Quality.MEDIUM
	vp.msaa_3d = Viewport.MSAA_DISABLED if quality == Quality.LOW else Viewport.MSAA_2X
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if quality == Quality.LOW else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 0.77 if quality == Quality.LOW else 1.0
	for spot in get_tree().root.find_children("*", "SpotLight3D", true, false):
		spot.shadow_enabled = quality == Quality.HIGH


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "show_fps", _show_fps)
	cfg.save(CFG_PATH)
