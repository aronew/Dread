class_name StateMachine
extends RefCounted
## Generic finite state machine. The actor ticks it from its own _process /
## _physics_process, which keeps update order explicit and deterministic.

signal state_changed(from: StringName, to: StringName)

var states: Dictionary = {}       # StringName -> State
var current: State = null
var current_name: StringName = &""
var time_in_state: float = 0.0
var _owner: Node


func _init(p_owner: Node) -> void:
	_owner = p_owner


func add(state_name: StringName, state: State) -> StateMachine:
	state.machine = self
	state.owner = _owner
	states[state_name] = state
	return self


func start(state_name: StringName, data: Dictionary = {}) -> void:
	current_name = state_name
	current = states[state_name]
	time_in_state = 0.0
	current.enter(&"", data)


func change(to: StringName, data: Dictionary = {}) -> void:
	if not states.has(to):
		push_error("StateMachine: unknown state '%s'" % to)
		return
	var from := current_name
	if current:
		current.exit(to)
	current_name = to
	current = states[to]
	time_in_state = 0.0
	current.enter(from, data)
	state_changed.emit(from, to)


## Break the State <-> StateMachine reference cycle (RefCounted cycles never free).
## Call from the owner's _exit_tree().
func dispose() -> void:
	for s in states.values():
		s.machine = null
		s.owner = null
	states.clear()
	current = null


func is_in(state_name: StringName) -> bool:
	return current_name == state_name


func update(delta: float) -> void:
	time_in_state += delta
	if current and current.machine:
		current.update(delta)


func physics_update(delta: float) -> void:
	if current and current.machine:
		current.physics_update(delta)
