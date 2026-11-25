class_name MeleeController
extends Node
## Energy-blade cleave + glory-kill finisher. This is the heart of the Doom loop:
##   * Every enemy hit by the cleave refunds ENERGY (ammo).
##   * Cleave reflects enemy bile globs back toward the cursor.
##   * Staggered / low-HP enemies glow; melee on them = FINISHER: execute,
##     burst of health orbs, energy refund, slow-mo.
##
## Phase 3 hooks: hit_hooks -> func(enemy, info, killed: bool)

signal swung(hits: int)
signal finisher_done(enemy: Node3D)

@export var damage: float = 55.0
@export var reach: float = 3.5
@export var arc_deg: float = 160.0
@export var cooldown: float = 0.4
@export var swing_duration: float = 0.18
@export var knockback: float = 10.0
@export var poise_damage: float = 70.0
@export var energy_per_hit: float = 12.0
@export var energy_per_finisher: float = 35.0
@export var finisher_search_range: float = 5.5
@export var finisher_health_orbs: int = 5
@export var lowhp_kill_health_orbs: int = 2
@export var health_per_orb: float = 5.0

var player: Player
var hit_hooks: Array[Callable] = []
var _cd: float = 0.0
var _side: float = 1.0


func setup(p: Player) -> void:
	player = p


func tick(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)


func cooldown_ratio() -> float:
	return _cd / cooldown


func try_melee() -> bool:
	if _cd > 0.0 or player.is_dead():
		return false
	_cd = cooldown
	var target := _find_finisher_target()
	if target:
		_finisher(target)
	else:
		_cleave()
	return true


func _find_finisher_target() -> Node3D:
	var origin := player.global_position
	var best: Node3D = null
	var best_score := INF
	for e in Combat.enemies_in_radius(player.get_tree(), origin, finisher_search_range):
		if not e.is_finishable():
			continue
		var to: Vector3 = e.global_position - origin
		to.y = 0.0
		var ang := rad_to_deg(player.aim_dir.angle_to(to.normalized())) if to.length() > 0.1 else 0.0
		if ang > 80.0 and to.length() > 2.2:
			continue
		var score := to.length() + ang * 0.03
		if score < best_score:
			best_score = score
			best = e
	return best


func _cleave() -> void:
	var origin := player.global_position
	var dir := player.aim_dir
	_side = -_side
	player.visual.play_action(&"melee", swing_duration)
	var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), origin + Vector3.UP * 1.05)
	Vfx.slash(xf, reach + 0.4, _side, Color(0.85, 0.97, 1.0), Color(0.2, 0.45, 1.0), swing_duration + 0.06)
	Sfx.play(&"melee_swing", Vector3.INF, -3.0, 0.1)
	player.add_impulse(dir * 6.0)

	var hits := 0
	for e in Combat.enemies_in_radius(player.get_tree(), origin, reach):
		var to: Vector3 = e.global_position - origin
		to.y = 0.0
		if to.length() > float(e.radius) + 0.6 and rad_to_deg(dir.angle_to(to.normalized())) > arc_deg * 0.5:
			continue
		var was_finishable: bool = e.is_finishable()
		var info := DamageInfo.make(damage, DamageInfo.Kind.MELEE, player, e.global_position + Vector3.UP, to)
		info.knockback = knockback
		info.poise_damage = poise_damage
		e.apply_damage(info)
		var killed: bool = e.is_dead()
		hits += 1
		player.gain_energy(energy_per_hit)
		Vfx.siphon(e.global_position, player, Color(0.3, 0.85, 1.0), 2)
		if killed and was_finishable:
			_drop_orbs(e.global_position, lowhp_kill_health_orbs)
		for hook in hit_hooks:
			hook.call(e, info, killed)

	var reflected := 0
	for p in player.get_tree().get_nodes_in_group(Combat.GROUP_ENEMY_PROJECTILES):
		var to: Vector3 = p.global_position - origin
		to.y = 0.0
		if to.length() <= reach + 0.5 and (to.length() < 1.0 or rad_to_deg(dir.angle_to(to.normalized())) <= arc_deg * 0.5):
			var aim_to: Vector3 = player.aim_point - p.global_position
			aim_to.y = 0.0
			p.reflect(aim_to if aim_to.length() > 1.0 else dir, player)
			reflected += 1
	if reflected > 0:
		Vfx.text_popup(origin + Vector3.UP * 2.6, "REFLECT!", Color(0.4, 0.9, 1.0), 52)
		Feel.hitstop(0.05)

	if hits > 0:
		Feel.hitstop(0.05 + 0.012 * mini(hits, 5), 0.02)
		Feel.shake(0.22 + 0.03 * mini(hits, 5), dir)
		Feel.rumble(0.4, 0.5, 0.12)
		Sfx.play(&"melee_hit", Vector3.INF, -1.0, 0.08)
	swung.emit(hits)


func _finisher(e: Node3D) -> void:
	var origin := player.global_position
	var to := e.global_position - origin
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.1 else player.aim_dir
	# Burst-lunge into the target, leaving afterimages.
	var stop := e.global_position - dir * (float(e.radius) + 0.9)
	stop.y = 0.0
	for i in 4:
		Vfx.afterimage(player.visual, Color(1.0, 0.45, 0.2), 0.3)
		player.global_position = origin.lerp(stop, float(i + 1) / 4.0)
	player.aim_dir = dir
	player.visual.set_aim(dir)
	player.visual.play_action(&"melee", 0.16)
	player.add_iframes(0.5)

	var info := DamageInfo.make(99999.0, DamageInfo.Kind.FINISHER, player, e.global_position + Vector3.UP, dir)
	info.knockback = 16.0
	e.apply_damage(info)

	var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), player.global_position + Vector3.UP * 1.05)
	Vfx.slash(xf, reach + 1.2, _side, Color(1.0, 0.95, 0.8), Color(1.0, 0.35, 0.15), 0.26)
	Vfx.shockwave(e.global_position + Vector3.UP * 0.1, 4.0, Color(1.0, 0.5, 0.2), 0.35, 0.1)
	Vfx.text_popup(e.global_position + Vector3.UP * 3.2, "FINISHER", Color(1.0, 0.6, 0.2), 76)
	Vfx.light_flash(e.global_position + Vector3.UP, Color(1.0, 0.6, 0.3), 8.0, 8.0, 0.35)
	Sfx.play(&"finisher", Vector3.INF, 0.0, 0.05)
	Feel.hitstop(0.11, 0.01)
	Feel.slowmo(0.45, 0.3)
	Feel.zoom_punch(0.35)
	Feel.shake(0.5, dir)
	Feel.rumble(0.8, 1.0, 0.3)

	player.gain_energy(energy_per_finisher)
	Vfx.siphon(e.global_position, player, Color(0.3, 0.85, 1.0), 6)
	_drop_orbs(e.global_position, finisher_health_orbs)
	for hook in hit_hooks:
		hook.call(e, info, true)
	Events.finisher_performed.emit(e)
	finisher_done.emit(e)


func _drop_orbs(at: Vector3, count: int) -> void:
	for i in count:
		PickupOrb.spawn(player.get_parent(), at, PickupOrb.Kind.HEALTH, health_per_orb, 5.0)
