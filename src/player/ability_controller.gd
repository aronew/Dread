class_name AbilityController
extends Node
## Suit abilities on cooldowns.
##   Q — MICRO-ROCKET SWARM: shoulder pod fires a homing salvo that spreads over
##       the enemies nearest the cursor.
##   E — ARC NOVA: radial electric shockwave. Heavy knockback + poise damage
##       (staggers almost everything) and vaporizes enemy projectiles.

signal ability_used(slot: StringName)

@export_group("Micro-Rocket Swarm (Q)")
@export var rocket_cooldown: float = 6.0
@export var rocket_count: int = 8
@export var rocket_damage: float = 42.0
@export var rocket_search_radius: float = 10.0
@export_group("Arc Nova (E)")
@export var nova_cooldown: float = 8.0
@export var nova_radius: float = 7.0
@export var nova_damage: float = 35.0
@export var nova_knockback: float = 20.0
@export var nova_poise: float = 120.0

var player: Player
var _cd := {&"q": 0.0, &"e": 0.0}
var _max := {&"q": 1.0, &"e": 1.0}


func setup(p: Player) -> void:
	player = p
	_max[&"q"] = rocket_cooldown
	_max[&"e"] = nova_cooldown


func ratio(slot: StringName) -> float:
	return clampf(_cd[slot] / _max[slot], 0.0, 1.0)


func tick(delta: float) -> void:
	for slot in _cd:
		if _cd[slot] > 0.0:
			_cd[slot] = maxf(_cd[slot] - delta, 0.0)
			Events.ability_cooldown_changed.emit(slot, ratio(slot))


func use(slot: StringName) -> bool:
	if player.is_dead() or _cd[slot] > 0.0:
		return false
	match slot:
		&"q":
			_rockets()
		&"e":
			_nova()
	_cd[slot] = _max[slot]
	Events.ability_cooldown_changed.emit(slot, 1.0)
	ability_used.emit(slot)
	return true


func _rockets() -> void:
	var tree := player.get_tree()
	var center := Vector3(player.aim_point.x, 0.0, player.aim_point.z)
	var targets := Combat.enemies_in_radius(tree, center, rocket_search_radius)
	targets.sort_custom(func(a, b): return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	player.visual.play_action(&"ability")
	Sfx.play(&"rocket_launch", Vector3.INF, -2.0)
	for i in rocket_count:
		var r := MicroRocket.new()
		r.damage = rocket_damage
		player.get_parent().add_child(r)
		var pod := player.visual.get_socket(&"rocket_pod")
		var back := -player.aim_dir
		var side := player.aim_dir.cross(Vector3.UP).normalized() * randf_range(-1.0, 1.0)
		var launch := (Vector3.UP * 2.0 + back * 0.6 + side).normalized()
		var tgt: Node3D = targets[i % targets.size()] if not targets.is_empty() else null
		var scatter := Vector3(randf_range(-2.5, 2.5), 0.5, randf_range(-2.5, 2.5))
		r.setup(player, pod.global_position, launch, tgt, center + scatter)
		r._arming = 0.12 + i * 0.035
		Vfx.burst(&"flash", pod.global_position, Basis.IDENTITY, Color(1.0, 0.55, 0.2), 1, 0.7)
	Feel.shake(0.1, -player.aim_dir)


func _nova() -> void:
	var origin := player.global_position
	player.visual.play_action(&"ability")
	player.add_iframes(0.35)
	Vfx.shockwave(origin + Vector3.UP * 0.12, nova_radius, Color(0.35, 0.8, 1.0), 0.45, 0.06)
	Vfx.shockwave(origin + Vector3.UP * 0.15, nova_radius * 0.7, Color(0.7, 0.4, 1.0), 0.3, 0.1)
	Vfx.burst(&"flash", origin + Vector3.UP, Basis.IDENTITY, Color(0.5, 0.85, 1.0), 1, 2.4)
	Vfx.burst(&"sparks", origin + Vector3.UP * 0.5, Basis.IDENTITY, Color(0.4, 0.8, 1.0), 40, 1.5)
	Vfx.light_flash(origin + Vector3.UP * 1.5, Color(0.4, 0.8, 1.0), 6.0, nova_radius * 1.6, 0.35)
	Sfx.play(&"nova", Vector3.INF, 0.0)
	Feel.shake(0.4)
	Feel.hitstop(0.06)
	Feel.rumble(0.6, 0.7, 0.25)
	Combat.explode(player.get_tree(), origin, nova_radius, nova_damage, player, nova_knockback, nova_poise, DamageInfo.Kind.PLASMA)
	for p in player.get_tree().get_nodes_in_group(Combat.GROUP_ENEMY_PROJECTILES):
		if Combat._flat_dist(p.global_position, origin) <= nova_radius:
			Vfx.impact(p.global_position, Vector3.UP, Color(0.4, 0.8, 1.0), 1.0)
			p.queue_free()
