class_name MeleeController
extends Node
## Energy-blade combat — the heart of the Doom-style loop.
##
##  * 3-hit combo: R->L slash, L->R slash, heavy spin. ~0.2 s per light swing.
##    Presses are buffered and chain at 60% of the current swing, so mashing
##    flows; pausing a beat resets the combo.
##  * Each swing auto-targets the best enemy in front, snaps the body to it and
##    lunges to close the gap. Damage lands on an active frame mid-sweep.
##  * Every enemy hit refunds ENERGY. Swings reflect bile globs.
##  * Staggered / low-HP enemies glow: a press next to one performs a FINISHER.
##  * Dash -> slash: pressing melee mid-dash cancels the dash into a lunging strike.
##
## Phase 3 hooks: hit_hooks -> func(enemy, info, killed: bool)

signal swung(step: int, hits: int)
signal finisher_done(enemy: Node3D)

const COMBO := [
	{"damage": 34.0, "reach": 3.4, "arc": 160.0, "knock": 7.0, "poise": 30.0, "lunge": 7.0,
	 "dur": 0.2, "active": 0.045, "stop": 0.035, "energy": 6.0, "side": 1.0, "stun": 0.3, "big": false},
	{"damage": 34.0, "reach": 3.4, "arc": 160.0, "knock": 7.0, "poise": 30.0, "lunge": 7.0,
	 "dur": 0.2, "active": 0.045, "stop": 0.035, "energy": 6.0, "side": -1.0, "stun": 0.3, "big": false},
	{"damage": 72.0, "reach": 4.2, "arc": 300.0, "knock": 17.0, "poise": 85.0, "lunge": 9.0,
	 "dur": 0.34, "active": 0.08, "stop": 0.07, "energy": 10.0, "side": 1.0, "stun": 0.55, "big": true},
]
const CANCEL_FRACTION := 0.6
const COMBO_WINDOW := 0.45
const COMBO_COOLDOWN := 0.12
const BLADE_CORE := Color(0.88, 0.98, 1.0)
const BLADE_EDGE := Color(0.25, 0.55, 1.0)

@export var finisher_search_range: float = 5.5
@export var finisher_health_orbs: int = 5
@export var lowhp_kill_health_orbs: int = 2
@export var health_per_orb: float = 5.0
@export var energy_per_finisher: float = 35.0

var player: Player
var hit_hooks: Array[Callable] = []
var _step: int = -1
var _next: int = 0
var _t: float = 0.0
var _hit_done: bool = false
var _buffer: float = 0.0
var _window: float = 0.0
var _cooldown: float = 0.0
var _swing_dir: Vector3 = Vector3.FORWARD
var _dash_strike: bool = false


func setup(p: Player) -> void:
	player = p


func is_swinging() -> bool:
	return _step >= 0


## Guns can't fire during the wind-up/strike, but CAN cancel the recovery.
func blocks_shooting() -> bool:
	return _step >= 0 and _t < float(COMBO[_step].dur) * CANCEL_FRACTION


func cancel() -> void:
	_step = -1
	_buffer = 0.0


func try_melee() -> bool:
	if player.is_dead():
		return false
	if _step >= 0 or _cooldown > 0.0:
		_buffer = 0.28
		return true
	_begin()
	return true


func _begin() -> void:
	var f := _find_finisher_target()
	if f:
		_finisher(f)
	else:
		_start(_next if _window > 0.0 else 0)


func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_buffer = maxf(_buffer - delta, 0.0)
	if _step < 0:
		_window = maxf(_window - delta, 0.0)
		if _buffer > 0.0 and _cooldown <= 0.0 and not player.is_dead():
			_buffer = 0.0
			_begin()
		return
	_t += delta
	var s: Dictionary = COMBO[_step]
	if not _hit_done and _t >= float(s.active):
		_hit_done = true
		_resolve_hits(s)
	if _buffer > 0.0 and _hit_done and _t >= float(s.dur) * CANCEL_FRACTION and _step < COMBO.size() - 1:
		_buffer = 0.0
		_start(_step + 1)
		return
	if _t >= float(s.dur):
		var finished := _step
		_step = -1
		if finished >= COMBO.size() - 1:
			_next = 0
			_window = 0.0
			_cooldown = COMBO_COOLDOWN
		else:
			_next = finished + 1
			_window = COMBO_WINDOW


func _start(index: int) -> void:
	_dash_strike = player.is_dashing()
	player.cancel_dash()
	_step = index
	_t = 0.0
	_hit_done = false
	var s: Dictionary = COMBO[index]
	var reach: float = s.reach
	var target := _pick_target(reach + 2.2)
	var dir := player.aim_dir
	if target:
		var to := target.global_position - player.global_position
		to.y = 0.0
		if to.length() > 0.1:
			dir = to.normalized()
	_swing_dir = dir
	player.lock_facing(dir, float(s.dur) + 0.06)
	player.move_speed_mult = 0.3
	# lunge: close the gap to the target (v = sqrt(2 a d) for the impulse decay), else a short step
	var lunge: float = s.lunge
	if target:
		var gap := Vector2(target.global_position.x - player.global_position.x, target.global_position.z - player.global_position.z).length() - (float(target.radius) + 1.1)
		lunge = clampf(sqrt(maxf(gap, 0.0) * 2.0 * 42.0), 3.0, 16.0)
	if _dash_strike:
		lunge = maxf(lunge, 14.0)
	player.add_impulse(dir * lunge)

	var side: float = s.side
	var action := &"melee_spin" if s.big else (&"melee_r" if side > 0.0 else &"melee_l")
	player.visual.play_action(action, float(s.dur) * 0.85)
	var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), player.global_position + Vector3.UP * 0.95)
	if s.big:
		Vfx.slash(xf, reach + 0.5, -side, Color(1.0, 0.97, 0.85), Color(1.0, 0.45, 0.2), 0.2, float(s.arc))
	else:
		Vfx.slash(xf, reach + 0.4, -side, BLADE_CORE, BLADE_EDGE, 0.15, float(s.arc))
	Sfx.play(&"melee_swing", Vector3.INF, -4.0 if not s.big else -1.0, 0.12, 20, 1.0 if not s.big else 0.8)


func _resolve_hits(s: Dictionary) -> void:
	var origin := player.global_position
	var reach: float = s.reach
	var hits := 0
	for e in Combat.enemies_in_radius(player.get_tree(), origin, reach):
		var to: Vector3 = e.global_position - origin
		to.y = 0.0
		var close := to.length() <= float(e.radius) + 1.0
		if not close and rad_to_deg(_swing_dir.angle_to(to.normalized())) > float(s.arc) * 0.5:
			continue
		var was_finishable: bool = e.is_finishable()
		var knock_dir := to.normalized() if to.length() > 0.1 else _swing_dir
		var info := DamageInfo.make(float(s.damage) * (1.35 if _dash_strike else 1.0), DamageInfo.Kind.MELEE, player,
				e.global_position + Vector3.UP * (0.5 + float(e.radius) * 0.5), knock_dir)
		info.knockback = s.knock
		info.poise_damage = s.poise
		info.stun = s.stun
		e.apply_damage(info)
		var killed: bool = e.is_dead()
		hits += 1
		Vfx.slash_mark(e.global_position + Vector3.UP * (0.55 + float(e.radius) * 0.5), _swing_dir, s.side,
				Color(1.0, 0.6, 0.25) if s.big else BLADE_EDGE)
		player.gain_energy(s.energy)
		if killed and was_finishable:
			_drop_orbs(e.global_position, lowhp_kill_health_orbs)
		for hook in hit_hooks:
			hook.call(e, info, killed)
	if hits > 0:
		Vfx.siphon(origin + _swing_dir * 1.5, player, Color(0.3, 0.85, 1.0), mini(hits, 4) + 1)

	var reflected := 0
	for p in player.get_tree().get_nodes_in_group(Combat.GROUP_ENEMY_PROJECTILES):
		var to: Vector3 = p.global_position - origin
		to.y = 0.0
		if to.length() <= reach + 0.8 and (to.length() < 1.2 or rad_to_deg(_swing_dir.angle_to(to.normalized())) <= float(s.arc) * 0.5 + 15.0):
			var aim_to: Vector3 = player.aim_point - p.global_position
			aim_to.y = 0.0
			p.reflect(aim_to if aim_to.length() > 1.0 else _swing_dir, player)
			reflected += 1
	if reflected > 0:
		Vfx.text_popup(origin + Vector3.UP * 2.8, "REFLECT!", Color(0.4, 0.9, 1.0), 44)
		Feel.hitstop(0.05)

	if hits > 0:
		var n := mini(hits, 5)
		Feel.hitstop(float(s.stop) + 0.008 * n, 0.02)
		Feel.shake((0.14 + 0.03 * n) * (1.6 if s.big else 1.0), _swing_dir)
		Feel.kick(_swing_dir, 0.45 if not s.big else 0.9)
		Feel.rumble(0.4, 0.55 if not s.big else 0.9, 0.1)
		Sfx.play(&"melee_hit", Vector3.INF, -2.0 if not s.big else 1.0, 0.1, 20)
	if s.big:
		Vfx.shockwave(origin + Vector3.UP * 0.12, reach + 0.6, Color(1.0, 0.6, 0.3), 0.3, 0.07)
		Vfx.burst(&"sparks", origin + Vector3.UP * 0.6, Basis.IDENTITY, Color(1.0, 0.6, 0.3), 18, 1.3)
	swung.emit(_step, hits)


## Best enemy to swing at: in front of the aim, weighted by distance and angle.
func _pick_target(max_dist: float) -> Node3D:
	var origin := player.global_position
	var best: Node3D = null
	var best_score := INF
	if is_instance_valid(player.aim_target) and not player.aim_target.is_dead():
		var d := Vector2(player.aim_target.global_position.x - origin.x, player.aim_target.global_position.z - origin.z).length()
		if d <= max_dist:
			return player.aim_target
	for e in Combat.enemies_in_radius(player.get_tree(), origin, max_dist):
		var to: Vector3 = e.global_position - origin
		to.y = 0.0
		var ang := rad_to_deg(player.aim_dir.angle_to(to.normalized())) if to.length() > 0.1 else 0.0
		if ang > 75.0 and to.length() > 1.8:
			continue
		var score := to.length() + ang * 0.04
		if score < best_score:
			best_score = score
			best = e
	return best


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


func _finisher(e: Node3D) -> void:
	player.cancel_dash()
	_step = -1
	_next = 0
	_window = 0.0
	_cooldown = 0.2
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
	player.lock_facing(dir, 0.3)
	player.visual.set_aim(dir)
	player.visual.play_action(&"melee_spin", 0.22)
	player.add_iframes(0.5)

	var info := DamageInfo.make(99999.0, DamageInfo.Kind.FINISHER, player, e.global_position + Vector3.UP, dir)
	info.knockback = 16.0
	e.apply_damage(info)

	var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), player.global_position + Vector3.UP * 1.0)
	Vfx.slash(xf, 4.6, -1.0, Color(1.0, 0.95, 0.8), Color(1.0, 0.35, 0.15), 0.22, 300.0)
	Vfx.slash_mark(e.global_position + Vector3.UP * 1.0, dir, 1.0, Color(1.0, 0.55, 0.2), 2.4)
	Vfx.shockwave(e.global_position + Vector3.UP * 0.1, 4.5, Color(1.0, 0.5, 0.2), 0.35, 0.1)
	Vfx.text_popup(e.global_position + Vector3.UP * 3.2, "FINISHER", Color(1.0, 0.6, 0.2), 70)
	Vfx.light_flash(e.global_position + Vector3.UP, Color(1.0, 0.6, 0.3), 8.0, 8.0, 0.35)
	Sfx.play(&"finisher", Vector3.INF, 0.0, 0.05)
	Feel.hitstop(0.12, 0.01)
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
