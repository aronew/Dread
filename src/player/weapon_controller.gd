class_name WeaponController
extends Node
## Ranged weapon component. Handles fire-rate timing, energy cost, spread/bloom,
## projectile spawning and firing feedback.
##
## Phase 3 mod hooks:
##   shot_modifiers:      func(shots: Array[Dictionary], weapon: WeaponData) -> void
##                        (mutate / append shot specs before they spawn — e.g. Split Shot)
##   projectile_hit_hooks: forwarded to every projectile (e.g. Ricochet Rounds)

signal fired(weapon: WeaponData, projectiles: Array)
signal out_of_energy

@export var loadout: Array[WeaponData] = []

var current_index: int = 0
var player: Player
var shot_modifiers: Array[Callable] = []
var projectile_hit_hooks: Array[Callable] = []
var _cooldown: float = 0.0
var _bloom: float = 0.0
var _muzzle_light: OmniLight3D
var _dry_t: float = 0.0


func setup(p: Player) -> void:
	player = p
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.omni_range = 5.0
	_muzzle_light.light_energy = 0.0
	_muzzle_light.shadow_enabled = false
	player.visual.get_socket(&"muzzle").add_child(_muzzle_light)


func current() -> WeaponData:
	return loadout[current_index] if not loadout.is_empty() else null


func switch_to(index: int) -> void:
	if index < 0 or index >= loadout.size() or index == current_index:
		return
	current_index = index
	_cooldown = maxf(_cooldown, 0.12)
	_bloom = 0.0
	Sfx.play(&"weapon_switch", Vector3.INF, -6.0)
	Events.weapon_switched.emit(current_index, current())


func cycle(step: int) -> void:
	if loadout.size() > 1:
		switch_to(wrapi(current_index + step, 0, loadout.size()))


func tick(delta: float, wants_fire: bool, just_pressed: bool) -> void:
	var w := current()
	_cooldown -= delta
	_dry_t -= delta
	_muzzle_light.light_energy = move_toward(_muzzle_light.light_energy, 0.0, delta * 60.0)
	if not wants_fire:
		_bloom = move_toward(_bloom, 0.0, delta * 12.0)
		_cooldown = maxf(_cooldown, 0.0)
		return
	if w == null or _cooldown > 0.0 or player.is_dashing():
		return
	if not w.automatic and not just_pressed:
		return
	if not player.spend_energy(w.energy_cost):
		if _dry_t <= 0.0:
			_dry_t = 0.3
			Sfx.play(&"dry_fire", Vector3.INF, -4.0)
			out_of_energy.emit()
			Events.announce.emit("ENERGY DEPLETED — MELEE TO RECHARGE", Color(0.3, 0.85, 1.0))
		return
	_fire(w)
	_cooldown = maxf(_cooldown + 1.0 / w.fire_rate, 0.0)


func _fire(w: WeaponData) -> void:
	var muzzle := player.visual.get_socket(&"muzzle")
	var origin := muzzle.global_position
	var chest := player.global_position + Vector3.UP * 1.3
	var blocked := Combat.raycast(player.get_world_3d(), chest, origin, Combat.LAYER_WORLD)
	if not blocked.is_empty():
		origin = chest
	var dir := player.aim_point - origin
	dir.y = 0.0
	if dir.length() < 2.0:
		dir = player.aim_dir
	dir = dir.normalized()

	var shots: Array[Dictionary] = []
	var spread := w.spread_deg + _bloom
	for i in w.pellets:
		var ang: float
		if w.pellets > 1:
			ang = lerpf(-spread * 0.5, spread * 0.5, float(i) / float(w.pellets - 1)) + randf_range(-2.0, 2.0)
		else:
			ang = randf_range(-spread * 0.5, spread * 0.5)
		shots.append({
			"direction": dir.rotated(Vector3.UP, deg_to_rad(ang)),
			"origin": origin,
			"damage_mult": 1.0,
			"speed_mult": randf_range(0.92, 1.05) if w.pellets > 1 else 1.0,
		})
	for mod in shot_modifiers:
		mod.call(shots, w)

	var spawned: Array = []
	for s in shots:
		var p := Projectile.new()
		p.setup(w, player, s.origin, s.direction)
		p.damage *= float(s.damage_mult)
		p.velocity *= float(s.speed_mult)
		p.hit_hooks.append_array(projectile_hit_hooks)
		player.get_parent().add_child(p)
		spawned.append(p)

	_bloom = minf(_bloom + w.bloom_per_shot_deg, w.bloom_max_deg)
	var flash_xf := Transform3D(Basis.looking_at(dir, Vector3.UP), origin)
	Vfx.muzzle_flash(flash_xf, w.color, w.muzzle_size)
	_muzzle_light.light_color = w.color
	_muzzle_light.light_energy = 4.0 * w.muzzle_size
	Sfx.play(w.fire_sfx, Vector3.INF, -5.0, 0.06, 20)
	Feel.shake(w.shake, -dir)
	player.visual.play_action(&"shoot")
	if w.recoil_push > 0.0:
		player.add_impulse(-dir * w.recoil_push)
	fired.emit(w, spawned)
	Events.weapon_fired.emit(w)
