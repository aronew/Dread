class_name WeaponController
extends Node
## Ranged weapon component: fire-rate timing, energy cost, aim-assisted shot
## direction (with target lead), projectile spawning and firing feedback.
##
## Phase 3 mod hooks:
##   shot_modifiers:       func(shots: Array[Dictionary], weapon: WeaponData) -> void
##                         (mutate / append shot specs before they spawn — e.g. Split Shot)
##   projectile_hit_hooks: forwarded to every projectile (e.g. Ricochet Rounds)

signal fired(weapon: WeaponData, projectiles: Array)
signal out_of_energy

@export var loadout: Array[WeaponData] = []

var current_index: int = 0
var player: Player
var shot_modifiers: Array[Callable] = []
var projectile_hit_hooks: Array[Callable] = []
var _cooldown: float = 0.0
var _muzzle_light: OmniLight3D
var _dry_t: float = 0.0


func setup(p: Player) -> void:
	player = p
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.omni_range = 6.0
	_muzzle_light.light_energy = 0.0
	_muzzle_light.shadow_enabled = false
	player.visual.get_socket(&"muzzle").add_child(_muzzle_light)


func current() -> WeaponData:
	return loadout[current_index] if not loadout.is_empty() else null


func switch_to(index: int) -> void:
	if index < 0 or index >= loadout.size() or index == current_index:
		return
	current_index = index
	_cooldown = maxf(_cooldown, 0.08)
	Sfx.play(&"weapon_switch", Vector3.INF, -6.0)
	Events.weapon_switched.emit(current_index, current())


func cycle(step: int) -> void:
	if loadout.size() > 1:
		switch_to(wrapi(current_index + step, 0, loadout.size()))


func tick(delta: float, wants_fire: bool, just_pressed: bool) -> void:
	var w := current()
	_cooldown -= delta
	_dry_t -= delta
	_muzzle_light.light_energy = move_toward(_muzzle_light.light_energy, 0.0, delta * 90.0)
	if not wants_fire:
		_cooldown = maxf(_cooldown, 0.0)
		return
	if w == null or _cooldown > 0.0 or player.is_dashing() or player.melee.blocks_shooting():
		return
	if not w.automatic and not just_pressed:
		return
	if not player.spend_energy(w.energy_cost):
		if _dry_t <= 0.0:
			_dry_t = 0.3
			Sfx.play(&"dry_fire", Vector3.INF, -4.0)
			out_of_energy.emit()
			Events.announce.emit("ENERGY DEPLETED — BLADE TO RECHARGE", Color(0.3, 0.85, 1.0))
		return
	_fire(w)
	_cooldown = maxf(_cooldown + 1.0 / w.fire_rate, 0.0)


func _fire(w: WeaponData) -> void:
	var muzzle := player.visual.get_socket(&"muzzle")
	var muzzle_pos := muzzle.global_position
	var origin := muzzle_pos
	# never spawn bullets on the far side of a wall the gun is clipping into
	var chest := player.global_position + Vector3.UP * Projectile.FLIGHT_HEIGHT
	if not Combat.raycast(player.get_world_3d(), chest, Vector3(origin.x, chest.y, origin.z), Combat.LAYER_WORLD).is_empty():
		origin = chest

	# aim assist: shoot where the target WILL be
	var target: Node3D = player.aim_target if is_instance_valid(player.aim_target) else null
	var aim_to := player.aim_point
	if target:
		var dist := Vector2(target.global_position.x - origin.x, target.global_position.z - origin.z).length()
		var lead: Vector3 = target.velocity * (dist / w.projectile_speed) * w.lead_factor
		aim_to = target.global_position + Vector3(lead.x, 0.0, lead.z)
	var dir := aim_to - origin
	dir.y = 0.0
	if dir.length() < 1.2:
		dir = player.aim_dir
	dir = dir.normalized()

	var shots: Array[Dictionary] = []
	for i in w.pellets:
		var ang: float
		if w.pellets > 1:
			ang = lerpf(-w.spread_deg * 0.5, w.spread_deg * 0.5, float(i) / float(w.pellets - 1)) + randf_range(-1.5, 1.5)
		else:
			ang = randf_range(-w.spread_deg * 0.5, w.spread_deg * 0.5)
		shots.append({
			"direction": dir.rotated(Vector3.UP, deg_to_rad(ang)),
			"origin": origin,
			"damage_mult": 1.0,
			"speed_mult": randf_range(0.9, 1.05) if w.pellets > 1 else 1.0,
		})
	for mod in shot_modifiers:
		mod.call(shots, w)

	var spawned: Array = []
	for s in shots:
		var p := Projectile.new()
		p.setup(w, player, s.origin, s.direction, target)
		p.damage *= float(s.damage_mult)
		p.velocity *= float(s.speed_mult)
		p.hit_hooks.append_array(projectile_hit_hooks)
		player.get_parent().add_child(p)
		spawned.append(p)

	Vfx.muzzle_flash(Transform3D(Basis.looking_at(dir, Vector3.UP), muzzle_pos), w.color, w.muzzle_size)
	_muzzle_light.light_color = w.color
	_muzzle_light.light_energy = 5.0 * w.muzzle_size
	Sfx.play(w.fire_sfx, Vector3.INF, -4.0, 0.06, 15)
	Feel.kick(-dir, w.shake * 3.0)
	if w.shake >= 0.15:
		Feel.shake(w.shake, -dir)
		Feel.rumble(0.2, 0.4, 0.08)
	player.visual.play_action(&"shoot")
	if w.recoil_push > 0.0:
		player.add_impulse(-dir * w.recoil_push)
	fired.emit(w, spawned)
	Events.weapon_fired.emit(w)
