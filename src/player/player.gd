class_name Player
extends CharacterBody3D
## Exo-Suit player controller. Owns movement, aim, dash, health/energy and input
## routing. Weapons, melee and suit abilities are separate child components so
## each can be modded independently (Phase 3).

signal dashed(from: Vector3, to: Vector3)
signal damaged(info: DamageInfo)

@export_group("Movement")
@export var move_speed: float = 8.5
@export var acceleration: float = 75.0
@export var deceleration: float = 60.0
@export_group("Dash")
@export var dash_speed: float = 27.0
@export var dash_duration: float = 0.16
@export var dash_iframes: float = 0.26
@export var dash_charges_max: int = 2
@export var dash_recharge: float = 1.1
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
var aim_point: Vector3 = Vector3.ZERO
var aim_dir: Vector3 = Vector3.FORWARD
var god_mode: bool = false
var input_enabled: bool = true
var aim_override: Vector3 = Vector3.INF  ## bots / cutscenes: world point to aim at

var _dash_charges: int = 2
var _dash_recharge_t: float = 0.0
var _dash_t: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _iframes: float = 0.0
var _afterimage_t: float = 0.0
var _impulse: Vector3 = Vector3.ZERO
var _move_vel: Vector3 = Vector3.ZERO
var _dead: bool = false
var _gamepad_aim: bool = false
var _last_mouse: Vector2 = Vector2.ZERO


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


# -----------------------------------------------------------------------------
#  Frame loop
# -----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_iframes = maxf(_iframes - delta, 0.0)
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

	if input_enabled and Input.is_action_just_pressed(&"dash"):
		_try_dash(wish)

	if _dash_t > 0.0:
		_dash_t -= delta
		velocity = _dash_dir * dash_speed
		_afterimage_t -= delta
		if _afterimage_t <= 0.0:
			_afterimage_t = 0.025
			Vfx.afterimage(visual, Color(0.25, 0.6, 1.0), 0.25)
		if _dash_t <= 0.0:
			collision_mask = Combat.LAYER_WORLD | Combat.LAYER_ENEMIES
			_move_vel = _dash_dir * move_speed
	else:
		var target_v := wish * move_speed
		var rate := acceleration if wish.length_squared() > 0.01 else deceleration
		_move_vel = _move_vel.move_toward(target_v, rate * delta)
		velocity = _move_vel + _impulse
	_impulse = _impulse.move_toward(Vector3.ZERO, 40.0 * delta)
	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0

	visual.set_locomotion(velocity, move_speed)
	visual.set_aim(aim_dir)

	if input_enabled:
		_handle_combat_input(delta)
	weapons.tick(delta, input_enabled and Input.is_action_pressed(&"fire"), input_enabled and Input.is_action_just_pressed(&"fire"))
	melee.tick(delta)
	abilities.tick(delta)


func _handle_combat_input(_delta: float) -> void:
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


func _update_aim() -> void:
	if aim_override != Vector3.INF:
		aim_point = aim_override
		var f := aim_point - global_position
		f.y = 0.0
		if f.length() > 0.25:
			aim_dir = f.normalized()
		if camera:
			camera.aim_point = aim_point
		return
	var stick := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
	var mouse := get_viewport().get_mouse_position()
	if stick.length() > 0.3:
		_gamepad_aim = true
	elif mouse.distance_to(_last_mouse) > 2.0:
		_gamepad_aim = false
	_last_mouse = mouse
	if _gamepad_aim and camera:
		var d := camera.ground_basis() * Vector3(stick.x, 0, stick.y)
		if d.length() > 0.3:
			aim_dir = d.normalized()
		aim_point = global_position + aim_dir * 8.0 + Vector3.UP * 1.2
	elif camera:
		aim_point = camera.screen_to_ground(mouse, 1.2)
		var flat := aim_point - global_position
		flat.y = 0.0
		if flat.length() > 0.25:
			aim_dir = flat.normalized()
	if camera:
		camera.aim_point = aim_point


# -----------------------------------------------------------------------------
#  Dash
# -----------------------------------------------------------------------------

func _try_dash(wish: Vector3) -> void:
	if _dash_charges <= 0 or _dash_t > 0.0:
		return
	var dir := wish.normalized() if wish.length_squared() > 0.01 else aim_dir
	_dash_charges -= 1
	_dash_dir = dir
	_dash_t = dash_duration
	_iframes = maxf(_iframes, dash_iframes)
	collision_mask = Combat.LAYER_WORLD  # phase through enemies
	var from := global_position
	visual.play_action(&"dash")
	Vfx.afterimage(visual, Color(0.35, 0.7, 1.0), 0.3)
	Vfx.shockwave(global_position + Vector3.UP * 0.1, 1.6, Color(0.3, 0.6, 1.0), 0.25, 0.12)
	Vfx.burst(&"sparks", global_position + Vector3.UP * 0.4, Vfx.basis_y(-dir + Vector3.UP * 0.3), Color(0.3, 0.6, 1.0), 12, 1.0)
	Sfx.play(&"dash", global_position, -2.0)
	Feel.shake(0.08, dir)
	Feel.rumble(0.3, 0.0, 0.1)
	Events.player_dash_charges_changed.emit(_dash_charges, dash_charges_max, 0.0)
	_emit_dashed.call_deferred(from)


func _emit_dashed(from: Vector3) -> void:
	# fire after the dash resolves so mods (e.g. Explosive Dash) know the endpoint
	await get_tree().create_timer(dash_duration).timeout
	dashed.emit(from, global_position)


func _tick_dash_recharge(delta: float) -> void:
	if _dash_charges >= dash_charges_max:
		return
	_dash_recharge_t += delta
	if _dash_recharge_t >= dash_recharge:
		_dash_recharge_t = 0.0
		_dash_charges += 1
	Events.player_dash_charges_changed.emit(_dash_charges, dash_charges_max, _dash_recharge_t / dash_recharge)


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
			Vfx.burst(&"flash", global_position + Vector3.UP, Basis.IDENTITY, Color(0.3, 1.0, 0.4), 1, 1.2)
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
		Feel.shake(clampf(info.amount / 40.0, 0.15, 0.55), info.direction)
		Feel.hitstop(0.045, 0.05)
		Feel.rumble(0.5, 0.6, 0.2)
		Sfx.play(&"player_hurt", Vector3.INF, -3.0)
	visual.flash(Color(1.0, 0.2, 0.2), 0.8 if not is_dot else 0.3)
	Vfx.damage_number(global_position + Vector3.UP * 2.2, info.amount, false, Color(1.0, 0.25, 0.3))
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
