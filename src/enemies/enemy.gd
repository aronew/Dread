class_name Enemy
extends CharacterBody3D
## Base corrupted-alien enemy. Owns health, poise/stagger, knockback, hit
## feedback, navigation, separation steering and death/loot. Archetypes extend
## this and override the hook methods documented in EnemyStates.

signal died(enemy: Enemy, info: DamageInfo)

@export var visual_id: StringName = &"swarmer"
@export_group("Stats")
@export var max_health: float = 50.0
@export var move_speed: float = 5.0
@export var acceleration: float = 30.0
@export var radius: float = 0.5
@export var knockback_resist: float = 0.0
@export var aggro_range: float = 60.0
@export var spawn_grace: float = 0.45
@export_group("Poise / Stagger")
@export var max_poise: float = 30.0
@export var poise_regen: float = 15.0
@export var stagger_duration: float = 1.2
@export var finishable_hp_ratio: float = 0.25
@export_group("Attack")
@export var attack_range: float = 2.5
@export var attack_cooldown: float = 1.2
@export var telegraph_time: float = 0.5
@export var attack_duration: float = 0.4
@export_group("Loot / Gore")
@export var gore_primary: Color = Color(1.0, 0.18, 0.5)
@export var gore_secondary: Color = Color(0.2, 1.0, 0.85)
@export var gore_scale: float = 1.0
@export var health_orb_chance: float = 0.12
@export var energy_orb_chance: float = 0.3
@export var energy_orb_amount: float = 8.0

var health: HealthComponent
var visual: ActorVisual
var fsm: StateMachine
var target: Player
var nav: NavigationAgent3D
var poise: float = 0.0
var facing: Vector3 = Vector3.FORWARD
var attack_cd: float = 0.0
var telegraph_marker: Telegraph

var _knock: Vector3 = Vector3.ZERO
var _dead: bool = false
var _nav_timer: float = 0.0
var _nav_point: Vector3 = Vector3.INF
var _finish_marker: Node3D
var _hit_sfx_t: float = 0.0
var _sep_frame: int = 0
var _sep_cache: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group(Combat.GROUP_ENEMIES)
	collision_layer = Combat.LAYER_ENEMIES
	collision_mask = Combat.LAYER_WORLD | Combat.LAYER_PLAYER
	health = HealthComponent.new()
	health.max_health = max_health
	add_child(health)
	health.died.connect(_on_died)
	visual = Assets.create_actor_visual(visual_id)
	add_child(visual)
	nav = get_node_or_null(^"NavigationAgent3D")
	if nav == null:
		nav = NavigationAgent3D.new()
		add_child(nav)
	nav.radius = radius
	nav.path_desired_distance = 0.9
	nav.target_desired_distance = 0.6
	nav.path_max_distance = 3.0
	poise = max_poise
	_sep_frame = randi() % 3
	attack_cd = randf_range(0.3, attack_cooldown)
	fsm = StateMachine.new(self)
	fsm.add(&"idle", EnemyStates.Idle.new())
	fsm.add(&"chase", EnemyStates.Chase.new())
	fsm.add(&"telegraph", EnemyStates.Windup.new())
	fsm.add(&"attack", EnemyStates.Attack.new())
	fsm.add(&"staggered", EnemyStates.Staggered.new())
	fsm.add(&"dead", EnemyStates.Dead.new())
	_setup()
	fsm.start(&"idle")
	target = Combat.get_player(get_tree()) as Player
	_emerge()
	Events.enemy_spawned.emit(self)


func _exit_tree() -> void:
	if fsm:
		fsm.dispose()


## Archetype setup hook (after base init, before the FSM starts).
func _setup() -> void:
	pass


func _emerge() -> void:
	visual.position.y = -1.8
	visual.scale = Vector3(0.6, 1.4, 0.6)
	var tw := visual.create_tween().set_parallel(true)
	tw.tween_property(visual, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	attack_cd = maxf(attack_cd - delta, 0.0)
	_hit_sfx_t -= delta
	if not _dead and not fsm.is_in(&"staggered"):
		poise = minf(poise + poise_regen * delta, max_poise)
	fsm.update(delta)
	fsm.physics_update(delta)
	velocity += _knock
	_knock = _knock.move_toward(Vector3.ZERO, 45.0 * delta)
	velocity.y = 0.0
	move_and_slide()
	velocity -= _knock
	global_position.y = 0.0
	visual.set_locomotion(velocity, move_speed)
	visual.set_aim(facing)
	_update_finish_marker(delta)


# =============================================================================
#  Queries
# =============================================================================

func is_dead() -> bool:
	return _dead


func has_target() -> bool:
	return is_instance_valid(target) and not target.is_dead()


func distance_to_target() -> float:
	if not has_target():
		return INF
	return Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length()


func dir_to_target() -> Vector3:
	if not has_target():
		return facing
	var d := target.global_position - global_position
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.0001 else facing


func is_finishable() -> bool:
	if _dead:
		return false
	return fsm.is_in(&"staggered") or health.ratio() <= finishable_hp_ratio


func has_line_of_sight(from_height: float = 1.2) -> bool:
	if not has_target():
		return false
	var from := global_position + Vector3.UP * from_height
	var to := target.global_position + Vector3.UP * 1.2
	return Combat.raycast(get_world_3d(), from, to, Combat.LAYER_WORLD).is_empty()


# =============================================================================
#  Movement helpers
# =============================================================================

func face(dir: Vector3, _delta: float = 0.0) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length_squared() > 0.0001:
		facing = flat.normalized()


func brake(delta: float) -> void:
	velocity = velocity.move_toward(Vector3.ZERO, acceleration * 2.0 * delta)


## Steer toward a world point using the navmesh (falls back to direct steering).
func move_toward_point(point: Vector3, speed: float, delta: float, face_move: bool = true) -> void:
	var next := point
	_nav_timer -= delta
	if _nav_timer <= 0.0 or _nav_point.distance_squared_to(point) > 4.0:
		_nav_timer = randf_range(0.15, 0.3)
		_nav_point = point
		nav.target_position = point
	if NavigationServer3D.map_get_iteration_id(nav.get_navigation_map()) > 0 and not nav.is_navigation_finished():
		next = nav.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
	var desired := dir * speed + _separation() * speed * 0.8
	velocity = velocity.move_toward(desired, acceleration * delta)
	if face_move and velocity.length_squared() > 0.25:
		face(velocity)


func _separation() -> Vector3:
	_sep_frame += 1
	if _sep_frame % 3 != 0:
		return _sep_cache
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group(Combat.GROUP_ENEMIES):
		if other == self or other.is_dead():
			continue
		var d: Vector3 = global_position - other.global_position
		d.y = 0.0
		var min_d: float = radius + float(other.radius) + 0.35
		var l := d.length()
		if l < min_d and l > 0.001:
			push += d / l * (1.0 - l / min_d)
	_sep_cache = push.limit_length(1.5)
	return _sep_cache


# =============================================================================
#  Archetype hooks (override)
# =============================================================================

func on_aggro() -> void:
	pass


func chase_step(delta: float) -> void:
	if has_target():
		move_toward_point(target.global_position, move_speed, delta)


func can_attack() -> bool:
	return attack_cd <= 0.0 and distance_to_target() <= attack_range


func begin_telegraph() -> void:
	visual.play_action(&"telegraph", telegraph_time)


func telegraph_step(delta: float, progress: float) -> void:
	brake(delta)
	face(dir_to_target())
	visual.set_charge(progress)


func perform_attack() -> void:
	visual.play_action(&"attack", attack_duration)


func attack_step(delta: float, _t: float) -> void:
	brake(delta)


func end_attack() -> void:
	attack_cd = attack_cooldown


func cancel_telegraph() -> void:
	if is_instance_valid(telegraph_marker):
		telegraph_marker.finish(false)
	telegraph_marker = null


func on_stagger_start() -> void:
	visual.play_action(&"stagger")
	Sfx.play(&"stagger", global_position, -4.0)
	if max_health >= 80.0:
		Vfx.text_popup(global_position + Vector3.UP * (2.2 + radius), "STAGGERED", Color(1.0, 0.65, 0.2), 44)
	Events.enemy_staggered.emit(self)


func on_stagger_end() -> void:
	poise = max_poise


# =============================================================================
#  Damage
# =============================================================================

## Returns the damage actually applied.
func apply_damage(info: DamageInfo) -> float:
	if _dead:
		return 0.0
	var applied := health.take_damage(info)
	if info.kind != DamageInfo.Kind.FINISHER:
		_hit_feedback(info)
	if _dead:
		return applied
	var kb := info.knockback * (1.0 - knockback_resist)
	if fsm.is_in(&"staggered"):
		kb *= 0.4
	_knock += Vector3(info.direction.x, 0, info.direction.z) * kb
	poise -= info.poise_damage
	if poise <= 0.0 and not fsm.is_in(&"staggered") and not fsm.is_in(&"dead"):
		fsm.change(&"staggered", {"duration": stagger_duration})
	else:
		visual.play_action(&"hit")
	Events.enemy_damaged.emit(self, info)
	Events.hit_confirmed.emit(false, info.is_crit)
	return applied


func _hit_feedback(info: DamageInfo) -> void:
	visual.flash(Color(1.0, 1.0, 1.0), 1.0 if info.amount > 20.0 else 0.7)
	var num_color := Color(1.0, 1.0, 1.0)
	if info.is_crit:
		num_color = Color(1.0, 0.85, 0.2)
	elif info.is_melee():
		num_color = Color(0.45, 0.85, 1.0)
	elif info.kind == DamageInfo.Kind.EXPLOSION:
		num_color = Color(1.0, 0.55, 0.2)
	Vfx.damage_number(info.position + Vector3.UP * (0.6 + radius), info.amount, info.is_crit, num_color)
	var amt := clampf(info.amount / 25.0, 0.4, 1.6) * gore_scale
	Vfx.gore(info.position, info.direction, gore_primary, amt, gore_secondary)
	if _hit_sfx_t <= 0.0:
		_hit_sfx_t = 0.05
		Sfx.play(&"crit_hit" if info.is_crit else &"flesh_hit", global_position, -8.0 if not info.is_crit else -4.0, 0.12, 25)


func _on_died(info: DamageInfo) -> void:
	_dead = true
	cancel_telegraph()
	fsm.change(&"dead")
	collision_layer = 0
	collision_mask = Combat.LAYER_WORLD
	visual.play_action(&"die")
	visual.set_charge(0.0)
	if _finish_marker:
		_finish_marker.queue_free()
		_finish_marker = null
	var dir := info.direction if info.direction.length_squared() > 0.01 else Vector3.UP
	var big := info.kind in [DamageInfo.Kind.FINISHER, DamageInfo.Kind.EXPLOSION] or info.is_crit
	Vfx.death_burst(global_position + Vector3.UP * (0.6 + radius * 0.5), dir, gore_primary, gore_secondary, gore_scale * (1.4 if big else 1.0))
	Sfx.play(&"enemy_die", global_position, -3.0, 0.15, 30)
	Feel.hitstop(0.025 * gore_scale, 0.1)
	Feel.shake(0.06 * gore_scale, dir)
	_drop_loot(info)
	Events.enemy_killed.emit(self, info)
	Events.hit_confirmed.emit(true, info.is_crit)
	died.emit(self, info)
	_knock = Vector3(dir.x, 0, dir.z) * 6.0
	var tw := visual.create_tween().set_parallel(true)
	tw.tween_property(visual, "scale", Vector3(1.3, 0.05, 1.3), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "position:y", -0.3, 0.25)
	tw.chain().tween_callback(queue_free)


func _drop_loot(info: DamageInfo) -> void:
	var parent := get_parent()
	if info.kind != DamageInfo.Kind.FINISHER and randf() < health_orb_chance:
		PickupOrb.spawn(parent, global_position, PickupOrb.Kind.HEALTH, 5.0)
	if randf() < energy_orb_chance:
		PickupOrb.spawn(parent, global_position, PickupOrb.Kind.ENERGY, energy_orb_amount)


# =============================================================================
#  Finisher marker (Doom-style glory-kill tell)
# =============================================================================

func _update_finish_marker(_delta: float) -> void:
	var show := is_finishable()
	if show and _finish_marker == null:
		_finish_marker = Node3D.new()
		add_child(_finish_marker)
		var gem := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.32, 0.32, 0.32)
		gem.mesh = box
		gem.rotation_degrees = Vector3(45, 0, 45)
		gem.material_override = PlaceholderKit.glow(Color(1.0, 0.55, 0.15), 8.0)
		gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_finish_marker.add_child(gem)
		_finish_marker.position.y = 2.4 + radius * 1.2
		Vfx.shockwave(global_position + Vector3.UP * 0.1, radius + 1.2, Color(1.0, 0.55, 0.15), 0.3, 0.12)
	elif not show and _finish_marker != null:
		_finish_marker.queue_free()
		_finish_marker = null
	if _finish_marker:
		var t := Time.get_ticks_msec() * 0.001
		_finish_marker.rotation.y = t * 4.0
		_finish_marker.position.y = 2.4 + radius * 1.2 + sin(t * 6.0) * 0.12
		if not fsm.is_in(&"telegraph"):
			visual.set_charge(0.45 + 0.35 * sin(t * 12.0), Color(1.0, 0.55, 0.15))
