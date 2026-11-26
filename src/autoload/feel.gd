extends Node
## Game-feel director: hitstop, slow motion, camera shake routing and rumble.
## Everything "juicy" goes through here so it can be tuned (or disabled) globally.

var camera: Node = null  ## IsoCamera registers itself
var shake_multiplier: float = 1.0
var debug_slowmo: bool = false

var _hitstop_left: float = 0.0
var _hitstop_scale: float = 1.0
var _slowmo_left: float = 0.0
var _slowmo_scale: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Freeze-frame on impact. Real-time duration (unaffected by time scale).
func hitstop(duration: float, time_scale: float = 0.03) -> void:
	if duration > _hitstop_left:
		_hitstop_left = duration
	_hitstop_scale = minf(time_scale, _hitstop_scale) if _hitstop_left > 0.0 else time_scale


func slowmo(duration: float, time_scale: float = 0.3) -> void:
	_slowmo_left = maxf(_slowmo_left, duration)
	_slowmo_scale = time_scale


## trauma 0..1 (squared internally). direction biases the kick (world space).
func shake(trauma: float, direction: Vector3 = Vector3.ZERO) -> void:
	if camera and camera.has_method(&"add_trauma"):
		camera.add_trauma(trauma * shake_multiplier, direction)


## Directional camera jolt without shake noise (recoil, dashes).
func kick(direction: Vector3, amount: float) -> void:
	if camera and camera.has_method(&"kick"):
		camera.kick(direction, amount * shake_multiplier)


func zoom_punch(amount: float) -> void:
	if camera and camera.has_method(&"zoom_punch"):
		camera.zoom_punch(amount)


func rumble(weak: float, strong: float, duration: float) -> void:
	for pad in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, weak, strong, duration)


func _process(delta: float) -> void:
	# Unscaled frame time (process delta is already multiplied by time_scale).
	var real_dt := minf(delta / maxf(Engine.time_scale, 0.0001), 0.1)
	_hitstop_left = maxf(_hitstop_left - real_dt, 0.0)
	_slowmo_left = maxf(_slowmo_left - real_dt, 0.0)
	var ts := 1.0
	if _hitstop_left > 0.0:
		ts = minf(ts, _hitstop_scale)
	else:
		_hitstop_scale = 1.0
	if _slowmo_left > 0.0:
		# ease back to full speed over the last 30% of the slow-mo window
		ts = minf(ts, lerpf(1.0, _slowmo_scale, clampf(_slowmo_left / 0.25, 0.0, 1.0)))
	if debug_slowmo:
		ts *= 0.25
	if get_tree().paused:
		ts = 1.0
	Engine.time_scale = ts
