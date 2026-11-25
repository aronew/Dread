extends Node
## Registers every input action in code so the bindings live in one readable place
## (and survive project.godot merges). Keyboard+mouse and gamepad twin-stick.

const DEADZONE := 0.2

func _enter_tree() -> void:
	_bind(&"move_up", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_bind(&"move_down", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_bind(&"move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_bind(&"move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_bind(&"aim_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_bind(&"aim_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_bind(&"aim_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_bind(&"aim_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)])

	_bind(&"fire", [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_bind(&"melee", [_mouse(MOUSE_BUTTON_RIGHT), _key(KEY_F), _joy(JOY_BUTTON_RIGHT_SHOULDER)])
	_bind(&"dash", [_key(KEY_SPACE), _key(KEY_SHIFT), _joy(JOY_BUTTON_A), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_bind(&"ability_q", [_key(KEY_Q), _joy(JOY_BUTTON_LEFT_SHOULDER)])
	_bind(&"ability_e", [_key(KEY_E), _joy(JOY_BUTTON_Y)])
	_bind(&"weapon_1", [_key(KEY_1)])
	_bind(&"weapon_2", [_key(KEY_2)])
	_bind(&"weapon_next", [_mouse(MOUSE_BUTTON_WHEEL_DOWN), _joy(JOY_BUTTON_X)])
	_bind(&"weapon_prev", [_mouse(MOUSE_BUTTON_WHEEL_UP)])

	_bind(&"restart", [_key(KEY_R), _joy(JOY_BUTTON_START)])
	_bind(&"pause", [_key(KEY_ESCAPE)])
	# Sandbox debug keys
	_bind(&"debug_spawn_swarmers", [_key(KEY_F1)])
	_bind(&"debug_spawn_spitter", [_key(KEY_F2)])
	_bind(&"debug_spawn_brute", [_key(KEY_F3)])
	_bind(&"debug_god_mode", [_key(KEY_F5)])
	_bind(&"debug_kill_all", [_key(KEY_F6)])
	_bind(&"debug_slowmo", [_key(KEY_F7)])


func _bind(action: StringName, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)
	for ev in events:
		InputMap.action_add_event(action, ev)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _joy(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
