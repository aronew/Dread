class_name Player
extends CharacterBody3D
## Exo-Suit player controller. Owns movement, aim (+ aim assist), dash,
## health/energy and input routing. Weapons, melee and suit abilities are separate
## child components so each can be modded independently (Phase 3).
##
## Movement and aim run in _process (every rendered frame) rather than on the
## physics tick, so motion is perfectly smooth on 60/120/144 Hz displays and the
## aim never lags the mouse.

signal dashed(from: Vector3, to: Vector3)
signal damaged(info: DamageInfo)

const AIM_PLANE_HEIGHT := 0.9   ## mouse ray hits this plane ~ enemy torso height

@export_group("Movement")
@export var move_speed: float = 10.0
@export var acceleration: float = 160.0
@export var deceleration: float = 130.0
@export_group("Dash")
@export var dash_speed: float = 36.0
@export var dash_duration: float = 0.13
@export var dash_iframes: float = 0.22
@export var dash_charges_max: int = 3
@export var dash_recharge: float = 0.75
@export var dash_exit_boost: float = 1.25   ## exit speed multiplier (momentum carry)
@export_group("Aim assist")
@export var assist_cursor_radius: float = 1.8  ## mouse: snap to enemies this close to the cursor
@export var assist_cone_deg: float = 7.0       ## mouse: or within this cone of the aim line
@export var assist_cone_pad_deg: float = 16.0  ## gamepad cone
@export var assist_range: float = 32.0
@export_group("Resources")
@export var max_energy: float = 100.0
@export var hurt_iframes: float = 0.4

@onready var health: HealthComponent = $Health
@onready var weapons: WeaponController = $Weapons
@onready var melee: MeleeController = $Melee
@onready var abilities: AbilityController = $Abilities

var visual: ActorVisual
var camera: IsoCamera
var energy: float = 100.0
var aim_point: Vector3 = Vector3.ZERO      ## world point under the cursor (on the aim plane)
var aim_dir: Vector3 = Vector3.FORWARD     ## flat direction player -> aim point
var aim_target: Node3D = null              ## enemy picked by aim assist (may be null)
var god_mode: bool = false
var input_enabled: bool = true
var aim_override: Vector3 = Vector3.INF    ## bots / cutscenes: world point to aim at
var move_speed_mult: float = 1.0           ## melee / abilities slow the player briefly
var gamepad_aim: bool = false

var _dash_charges: int = 3
var _dash_recharge_t: float = 0.0
var _dash_t: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _dash_from: Vector3 = Vector3.ZERO
var _dash_buffer: float = 0.0
var _iframes: float = 0.0
var _impulse: Vector3 = Vector3.ZERO
var _move_vel: Vector3 = Vector3.ZERO
var _dead: bool = false
var _last_mouse: Vector2 = Vector2.ZERO
var _face_lock_t: float = 0.0
var _face_lock_dir: Vector3 = Vector3.FORWARD
var _step_t: float = 0.0


func _ready() -> void:
	add_to_group(Combat.GROUP_PLAYER)
	collision_layer = Combat.LAYER_PLAYER
	collision_mask = Combat.LAYER_WORLD | Combat.LAYER_ENEMIES
	visual = Assets.create_actor_visual(&"player")
	add_child(visual)
	var indicator: Node3D = preload("res://src/player/player_indicator.gd").new()
	indicator.player = self
	add_child(indicator)
	_dash_charges = dash_charges_max
	energy = max_energy
	health.changed.connect(func(c: float, m: float): Events.player_health_changed.emit(c, m))
	health.died.connect(_on_died)
	for c in [weapons, melee, abilities]:
		c.setup(self)
	aim_point = global_position + Vector3.FORWARD * 5.0
	_broadcast_state.call_deferred()
	Events.player_spawned.emit(self)


func _broadcast_state() -> void:
	Events.player_health_changed.emit(health.current, health.max_health)
	Events.player_energy_changed.emit(energy, max_energy)
	Events.player_dash_charges_changed.emit(_dash_charges, dash_charges_max, 0.0)
	Events.weapon_switched.emit(weapons.current_index, weapons.current())


func is_dead() -> bool:
	return _dead


func is_dashing() -> bool:
	return _dash_t > 0.0


## Direction the body is committed to (swing direction while attacking, else aim).
func facing_dir() -> Vector3:
	return _face_lock_dir if _face_lock_t > 0.0 else aim_dir


func lock_facing(dir: Vector3, duration: float) -> void:
	var f := Vector3(dir.x, 0, dir.z)
	if f.length_squared() > 0.0001:
		_face_lock_dir = f.normalized()
		_face_lock_t = duration


# -----------------------------------------------------------------------------
#  Frame loop (render rate)
# -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_iframes = maxf(_iframes - delta, 0.0)
	_face_lock_t = maxf(_face_lock_t - delta, 0.0)
	health.invulnerable = _iframes > 0.0 or god_mode
	_tick_dash_recharge(delta)
	if _dead:
		velocity = velocity.move_toward(Vector3.ZERO, deceleration * delta)
		move_and_slide()
		return

	_update_aim()
	var move_input := Vector2.ZERO
	if input_enabled:
		move_input = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var wish := Vector3(move_input.x, 0.0, move_input.y)
	if camera:
		wish = camera.ground_basis() * wish
	if wish.length() > 1.0:
		wish = wish.normalized()

	# dash (buffered so a slightly-early press still goes off)
	if input_enabled and Input.is_action_just_pressed(&"dash"):
		_dash_buffer = 0.15
	_dash_buffer = maxf(_dash_buffer - delta, 0.0)
	if _dash_buffer > 0.0 and _can_dash():
		_dash_buffer = 0.0
		_start_dash(wish)

	if _dash_t > 0.0:
		_dash_t -= delta
		velocity = _dash_dir * dash_speed
		if _dash_t <= 0.0:
			_end_dash()
	else:
		var speed := move_speed * move_speed_mult
		var target_v := wish * speed
		var rate := acceleration if wish.length_squared() > 0.01 else deceleration
		# turning against current motion gets extra grip so direction changes are instant
		if _move_vel.length_squared() > 1.0 and wish.dot(_move_vel.normalized()) < 0.0:
			rate *= 1.8
		_move_vel = _move_vel.move_toward(target_v, rate * delta)
		velocity = _move_vel + _impulse
	_impulse = _impulse.move_toward(Vector3.ZERO, 42.0 * delta)
	move_speed_mult = move_toward(move_speed_mult, 1.0, delta * 4.0)
	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0

	visual.set_locomotion(velocity, move_speed)
	visual.set_aim(facing_dir())
	_footsteps(delta)

	if input_enabled:
		_handle_combat_input()
	weapons.tick(delta, input_enabled and Input.is_action_pressed(&"fire"), input_enabled and Input.is_action_just_pressed(&"fire"))
	melee.tick(delta)
	abilities.tick(delta)


func _handle_combat_input() -> void:
	if Input.is_action_just_pressed(&"melee"):
		melee.try_melee()
	if Input.is_action_just_pressed(&"ability_q"):
		abilities.use(&"q")
	if Input.is_action_just_pressed(&"ability_e"):
		abilities.use(&"e")
	if Input.is_action_just_pressed(&"weapon_1"):
		weapons.switch_to(0)
	if Input.is_action_just_pressed(&"weapon_2"):
		weapons.switch_to(1)
	if Input.is_action_just_pressed(&"weapon_next"):
		weapons.cycle(1)
	if Input.is_action_just_pressed(&"weapon_prev"):
		weapons.cycle(-1)


# -----------------------------------------------------------------------------
#  Aim + aim assist
# -----------------------------------------------------------------------------

func _update_aim() -> void:
	if aim_override != Vector3.INF:
		aim_point = aim_override
	else:
		var stick := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
		var mouse := get_viewport().get_mouse_position()
		if stick.length() > 0.3:
			gamepad_aim = true
		elif mouse.distance_to(_last_mouse) > 2.0:
			gamepad_aim = false
		_last_mouse = mouse
		if gamepad_aim and camera:
			var d := camera.ground_basis() * Vector3(stick.x, 0, stick.y)
			if d.length() > 0.3:
				aim_dir = d.normalized()
			aim_point = global_position + aim_dir * 10.0 + Vector3.UP * AIM_PLANE_HEIGHT
		elif camera:
			aim_point = camera.screen_to_ground(mouse, AIM_PLANE_HEIGHT)
	var flat := aim_point - global_position
	flat.y = 0.0
	if flat.length() > 0.3:
		aim_dir = flat.normalized()
	_update_aim_target()
	if camera:
		camera.aim_point = aim_point


## Picks the enemy the player is "obviously" aiming at: closest to the cursor,
## or the one nearest the aim line inside a narrow cone. Weapons shoot at it
## (with lead), which makes small fast enemies hittable without auto-aim feel.
func _update_aim_target() -> void:
	var best: Node3D = null
	var best_score := INF
	var cursor := Vector2(aim_point.x, aim_point.z)
	var origin := Vector2(global_position.x, global_position.z)
	var dir2 := Vector2(aim_dir.x, aim_dir.z)
	var cone := deg_to_rad(assist_cone_pad_deg if gamepad_aim else assist_cone_deg)
	for e in Combat.living_enemies(get_tree()):
		var p := Vector2(e.global_position.x, e.global_position.z)
		var to := p - origin
		var dist := to.length()
		if dist > assist_range or dist < 0.01:
			continue
		var r: float = float(e.radius)
		var score := INF
		if not gamepad_aim:
			var cd := p.distance_to(cursor) - r
			if cd <= assist_cursor_radius:
				score = cd
		var ang := absf(dir2.angle_to(to))
		var perp := dist * sin(minf(ang, PI * 0.5))
		if ang <= cone + atan2(r, dist) and to.dot(dir2) > 0.0:
			# prefer what's close to the aim line, then what's close to the player
			score = minf(score, 0.5 + perp + dist * 0.04)
		if score < best_score:
			best_score = score
			best = e
	if best != aim_target:
		if is_instance_valid(aim_target) and aim_target.has_method(&"set_aimed"):
			aim_target.set_aimed(false)
		aim_target = best
		if best and best.has_method(&"set_aimed"):
			best.set_aimed(true)
		Events.aim_target_changed.emit(best)


# -----------------------------------------------------------------------------
#  Dash
# -----------------------------------------------------------------------------

func _can_dash() -> bool:
	return _dash_charges > 0 and _dash_t <= 0.0


func _start_dash(wish: Vector3) -> void:
	var dir := wish.normalized() if wish.length_squared() > 0.01 else aim_dir
	_dash_charges -= 1
	_dash_dir = dir
	_dash_t = dash_duration
	_dash_from = global_position
	_iframes = maxf(_iframes, dash_iframes)
	collision_mask = Combat.LAYER_WORLD  # phase through enemies
	melee.cancel()
	visual.play_action(&"dash")
	Vfx.afterimage(visual, Color(0.3, 0.65, 1.0), 0.22)
	Vfx.burst(&"sparks", global_position + Vector3.UP * 0.4, Vfx.basis_y(-dir + Vector3.UP * 0.4), Color(0.35, 0.65, 1.0), 10, 1.0)
	Vfx.burst(&"dust", global_position + Vector3.UP * 0.1, Basis.IDENTITY, Color(0.5, 0.6, 0.7), 6, 1.0)
	Sfx.play(&"dash", Vector3.INF, -3.0, 0.08)
	Feel.kick(dir, 0.35)
	Feel.rumble(0.35, 0.0, 0.08)
	Events.player_dash_charges_changed.emit(_dash_charges, dash_charges_max, _dash_recharge_t / dash_recharge)


func _end_dash() -> void:
	_dash_t = 0.0
	collision_mask = Combat.LAYER_WORLD | Combat.LAYER_ENEMIES
	_move_vel = _dash_dir * move_speed * dash_exit_boost
	Vfx.dash_streaks(_dash_from, global_position, Color(0.3, 0.6, 1.0))
	Vfx.afterimage(visual, Color(0.3, 0.65, 1.0), 0.18)
	dashed.emit(_dash_from, global_position)


## Melee can cut a dash short (dash -> slash flows straight into the swing).
func cancel_dash() -> void:
	if _dash_t > 0.0:
		_end_dash()


func _tick_dash_recharge(delta: float) -> void:
	if _dash_charges >= dash_charges_max:
		_dash_recharge_t = 0.0
		return
	_dash_recharge_t += delta
	if _dash_recharge_t >= dash_recharge:
		_dash_recharge_t = 0.0
		_dash_charges += 1
	Events.player_dash_charges_changed.emit(_dash_charges, dash_charges_max, _dash_recharge_t / dash_recharge)


func _footsteps(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 3.0 or _dash_t > 0.0:
		_step_t = 0.0
		return
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = 0.26
		Vfx.burst(&"dust", global_position + Vector3.UP * 0.05, Basis.IDENTITY, Color(0.45, 0.55, 0.6), 2, 0.6)


# -----------------------------------------------------------------------------
#  Resources / damage
# -----------------------------------------------------------------------------

func spend_energy(amount: float) -> bool:
	if god_mode:
		return true
	if energy < amount:
		return false
	energy -= amount
	Events.player_energy_changed.emit(energy, max_energy)
	return true


func gain_energy(amount: float) -> void:
	energy = minf(energy + amount, max_energy)
	Events.player_energy_changed.emit(energy, max_energy)


func heal(amount: float) -> void:
	health.heal(amount)


func add_iframes(t: float) -> void:
	_iframes = maxf(_iframes, t)


func add_impulse(v: Vector3) -> void:
	_impulse += Vector3(v.x, 0, v.z)


func collect_pickup(orb: PickupOrb) -> bool:
	if _dead:
		return false
	match orb.kind:
		PickupOrb.Kind.HEALTH:
			heal(orb.amount)
			Sfx.play(&"pickup_health", Vector3.INF, -6.0, 0.1, 40)
			Vfx.burst(&"flash", global_position + Vector3.UP, Basis.IDENTITY, Color(0.3, 1.0, 0.4), 1, 1.0)
		PickupOrb.Kind.ENERGY:
			gain_energy(orb.amount)
			Sfx.play(&"pickup_energy", Vector3.INF, -8.0, 0.1, 40)
	return true


## Returns true if damage was applied (false while invulnerable / dashing).
func apply_damage(info: DamageInfo) -> bool:
	if _dead or health.invulnerable:
		return false
	var applied := health.take_damage(info)
	if applied <= 0.0 and not health.is_dead:
		return false
	var is_dot := info.tags.has("dot")
	if not is_dot:
		_iframes = maxf(_iframes, hurt_iframes)
		add_impulse(info.direction * info.knockback * 2.0)
		visual.play_action(&"hit")
		visual.squash(0.2)
		Feel.shake(clampf(info.amount / 40.0, 0.2, 0.55), info.direction)
		Feel.hitstop(0.05, 0.05)
		Feel.rumble(0.5, 0.6, 0.2)
		Sfx.play(&"player_hurt", Vector3.INF, -3.0)
	visual.flash(Color(1.0, 0.2, 0.2), 1.2 if not is_dot else 0.4)
	Vfx.damage_number(global_position + Vector3.UP * 2.4, info.amount, false, Color(1.0, 0.25, 0.3))
	Events.player_damaged.emit(info.amount, info.direction)
	damaged.emit(info)
	return true


func _on_died(_info: DamageInfo) -> void:
	_dead = true
	input_enabled = false
	visual.play_action(&"die")
	collision_layer = 0
	Vfx.death_burst(global_position + Vector3.UP, Vector3.UP, Color(1.0, 0.3, 0.15), Color(0.3, 0.6, 1.0), 1.2)
	Vfx.explosion(global_position + Vector3.UP, 3.0)
	Sfx.play(&"explosion")
	Feel.slowmo(1.5, 0.25)
	Feel.shake(0.8)
	Events.player_died.emit()
