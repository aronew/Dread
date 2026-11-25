extends Node
## Pooled one-shot SFX playback with pitch jitter, distance attenuation and
## anti-spam throttling. Streams are resolved through the Assets registry.

const POOL_SIZE := 40

var listener_position: Vector3 = Vector3.ZERO  ## updated by the camera each frame
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _last_played: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)


func _setup_buses() -> void:
	if AudioServer.get_bus_index(&"SFX") != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, &"SFX")
	AudioServer.set_bus_send(idx, &"Master")
	var comp := AudioEffectCompressor.new()
	comp.threshold = -14.0
	comp.ratio = 4.0
	comp.attack_us = 300.0
	comp.release_ms = 120.0
	AudioServer.add_bus_effect(idx, comp)
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, limiter)


## at = world position for distance attenuation (Vector3.INF = UI / non-positional).
func play(id: StringName, at: Vector3 = Vector3.INF, volume_db: float = 0.0,
		pitch_jitter: float = 0.07, min_interval_ms: int = 30, pitch: float = 1.0) -> void:
	var stream := Assets.get_sfx(id)
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(id, -100000)) < min_interval_ms:
		return
	_last_played[id] = now
	var vol := volume_db
	if at != Vector3.INF:
		var dist := Vector2(at.x - listener_position.x, at.z - listener_position.z).length()
		vol -= clampf((dist - 10.0) * 0.9, 0.0, 30.0)
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = vol
	p.pitch_scale = maxf(0.05, pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter)) * clampf(Engine.time_scale * 0.5 + 0.5, 0.6, 1.0))
	p.play()
