extends Node3D
## Phase 1 sandbox root: wires camera <-> player, handles restart / pause /
## debug keys, and command-line automation (screenshots, smoke test, demo bot).

@onready var player: Player = $Player
@onready var camera: IsoCamera = $IsoCamera
@onready var director: WaveDirector = $WaveDirector
@onready var arena: TestArena = $Arena

var _pause_label: Label


func _ready() -> void:
	camera.set_target(player)
	player.camera = camera
	_build_pause_overlay()
	_handle_cmdline()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"restart"):
		get_tree().paused = false
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
		return
	if Input.is_action_just_pressed(&"pause"):
		_toggle_pause()
	if get_tree().paused:
		return
	if Input.is_action_just_pressed(&"debug_spawn_swarmers"):
		var p := arena.pick_spawn_point(player.global_position, 8.0)
		for i in 5:
			director.spawn_enemy(&"swarmer", p)
	if Input.is_action_just_pressed(&"debug_spawn_spitter"):
		director.spawn_enemy(&"spitter", arena.pick_spawn_point(player.global_position, 10.0))
	if Input.is_action_just_pressed(&"debug_spawn_brute"):
		director.spawn_enemy(&"brute", arena.pick_spawn_point(player.global_position, 10.0))
	if Input.is_action_just_pressed(&"debug_god_mode"):
		player.god_mode = not player.god_mode
		Events.announce.emit("GOD MODE " + ("ON" if player.god_mode else "OFF"), Color(1, 1, 0.4))
	if Input.is_action_just_pressed(&"debug_kill_all"):
		director.kill_all()
	if Input.is_action_just_pressed(&"debug_slowmo"):
		Feel.debug_slowmo = not Feel.debug_slowmo


func _toggle_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_pause_label.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CONFINED_HIDDEN


func _build_pause_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_pause_label = Label.new()
	_pause_label.text = "PAUSED\n\nESC  resume      R  restart"
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pause_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_label.add_theme_font_size_override(&"font_size", 48)
	_pause_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_pause_label.add_theme_constant_override(&"outline_size", 10)
	_pause_label.visible = false
	layer.add_child(_pause_label)
	process_mode = Node.PROCESS_MODE_ALWAYS
	for c in [player, arena, director, camera]:
		c.process_mode = Node.PROCESS_MODE_PAUSABLE


## User args after `--`:
##   --autopilot            bot plays the game (for demos / soak tests)
##   --showcase             line up one of each enemy, idle, for inspecting art
##   --smoke-test           run automated checks then quit with an exit code
##   --screenshot=PATH      save a frame after --shot-delay seconds (default 6) and quit
func _handle_cmdline() -> void:
	var args := OS.get_cmdline_user_args()
	var shot_path := ""
	var shot_delay := 6.0
	for a in args:
		if a == "--autopilot":
			add_child(preload("res://tests/autopilot.gd").new())
		elif a == "--showcase":
			_showcase()
		elif a == "--smoke-test":
			add_child(preload("res://tests/smoke_test.gd").new())
		elif a.begins_with("--screenshot="):
			shot_path = a.trim_prefix("--screenshot=")
		elif a.begins_with("--shot-delay="):
			shot_delay = float(a.trim_prefix("--shot-delay="))
	if shot_path != "":
		_take_screenshot(shot_path, shot_delay)


func _take_screenshot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Saved screenshot: ", path)
	get_tree().quit()


## Model line-up: player + one of each archetype, idle, facing the camera.
func _showcase() -> void:
	director.running = false
	camera.distance = 17.0
	camera.look_ahead = 0.0
	# line up along the camera's screen-right axis (camera yaw is 45 deg)
	var right := Vector3(1, 0, -1).normalized()
	var back := Vector3(-1, 0, -1).normalized()
	var center := Vector3(10, 0, 10)
	player.global_position = center - right * 4.6 + back * 0.4
	player.aim_override = player.global_position + Vector3(1, 0, 1) * 5.0 + Vector3.UP * 1.2
	var lineup := [[&"swarmer", center - right * 1.9], [&"spitter", center + right * 0.4 + back * 0.3], [&"brute", center + right * 3.6 + back * 0.8]]
	for entry in lineup:
		var e: Enemy = WaveDirector.SCENES[entry[0]].instantiate()
		e.spawn_grace = 99999.0
		e.aggro_range = 0.0
		arena.add_child(e)
		e.global_position = entry[1]
		e.facing = Vector3(1, 0, 1).normalized()
	camera.set_target(player)
	camera.target = null
	camera._focus = center + right * 0.2
