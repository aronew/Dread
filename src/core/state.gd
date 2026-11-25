class_name State
extends RefCounted
## Base state. Lightweight (RefCounted, not a Node) so dozens of enemies can each
## own a full state set without bloating the scene tree.

var machine: StateMachine
var owner  ## the actor this state drives (untyped: states call archetype hooks)


func enter(_from: StringName, _data: Dictionary) -> void:
	pass


func exit(_to: StringName) -> void:
	pass


func update(_delta: float) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func transition(to: StringName, data: Dictionary = {}) -> void:
	machine.change(to, data)
