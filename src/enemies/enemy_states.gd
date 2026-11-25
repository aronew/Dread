class_name EnemyStates
extends RefCounted
## Shared enemy states. They contain the FLOW (when to move between states);
## archetypes supply the BEHAVIOUR through hook methods on Enemy:
##   chase_step(delta)          movement while hunting
##   can_attack() -> bool       gate into Telegraph
##   begin_telegraph()          spawn ground marker / wind-up
##   telegraph_step(delta, t)   track target while winding up
##   perform_attack()           the actual hit / projectile / slam
##   attack_step(delta, t)      movement during the attack (lunges, leaps)
##   end_attack()               cleanup + cooldown
## Staggered and Dead are entered by Enemy itself (poise break / health 0).


class Idle extends State:
	func enter(_from: StringName, _data: Dictionary) -> void:
		owner.velocity = Vector3.ZERO

	func physics_update(delta: float) -> void:
		owner.brake(delta)
		if machine.time_in_state < owner.spawn_grace:
			return
		if owner.has_target() and owner.distance_to_target() <= owner.aggro_range:
			owner.on_aggro()
			transition(&"chase")


class Chase extends State:
	func physics_update(delta: float) -> void:
		if not owner.has_target():
			transition(&"idle")
			return
		owner.chase_step(delta)
		if owner.can_attack():
			transition(&"telegraph")


class Windup extends State:
	func enter(_from: StringName, _data: Dictionary) -> void:
		owner.begin_telegraph()

	func physics_update(delta: float) -> void:
		var t: float = machine.time_in_state / maxf(owner.telegraph_time, 0.001)
		owner.telegraph_step(delta, clampf(t, 0.0, 1.0))
		if machine.time_in_state >= owner.telegraph_time:
			transition(&"attack")

	func exit(to: StringName) -> void:
		owner.visual.set_charge(0.0)
		if to != &"attack":
			owner.cancel_telegraph()


class Attack extends State:
	func enter(_from: StringName, _data: Dictionary) -> void:
		owner.perform_attack()

	func physics_update(delta: float) -> void:
		owner.attack_step(delta, machine.time_in_state)
		if machine.time_in_state >= owner.attack_duration:
			transition(&"chase")

	func exit(_to: StringName) -> void:
		owner.end_attack()


class Staggered extends State:
	var duration: float = 1.0

	func enter(_from: StringName, data: Dictionary) -> void:
		duration = data.get("duration", owner.stagger_duration)
		owner.on_stagger_start()

	func physics_update(delta: float) -> void:
		owner.brake(delta * 0.5)
		if machine.time_in_state >= duration:
			transition(&"chase")

	func exit(_to: StringName) -> void:
		owner.on_stagger_end()


class Dead extends State:
	func physics_update(delta: float) -> void:
		owner.brake(delta)
