class_name HealthComponent
extends Node
## Reusable HP pool with optional invulnerability window. Owners call
## take_damage(); listeners connect to the signals.

signal changed(current: float, maximum: float)
signal damaged(info: DamageInfo)
signal healed(amount: float)
signal died(info: DamageInfo)

@export var max_health: float = 100.0
var current: float = 0.0
var invulnerable: bool = false
var is_dead: bool = false


func _ready() -> void:
	current = max_health


func reset(new_max: float = -1.0) -> void:
	if new_max > 0.0:
		max_health = new_max
	current = max_health
	is_dead = false
	changed.emit(current, max_health)


func ratio() -> float:
	return clampf(current / max_health, 0.0, 1.0) if max_health > 0.0 else 0.0


## Returns the damage actually applied.
func take_damage(info: DamageInfo) -> float:
	if is_dead or invulnerable or info.amount <= 0.0:
		return 0.0
	var applied := minf(info.amount, current)
	current -= info.amount
	damaged.emit(info)
	if current <= 0.0:
		current = 0.0
		is_dead = true
		changed.emit(current, max_health)
		died.emit(info)
	else:
		changed.emit(current, max_health)
	return applied


func heal(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var before := current
	current = minf(current + amount, max_health)
	var gained := current - before
	if gained > 0.0:
		healed.emit(gained)
		changed.emit(current, max_health)
	return gained
