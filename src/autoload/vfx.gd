extends Node
## VFX director. Every visual effect in the game is spawned through here so look,
## budget and pooling are controlled from one file.
##
## Particle presets are built once and cached per (preset, color). Damage numbers
## are pooled; decals are capped (oldest fades out first).

const ADD_SHADER := preload("res://assets/shaders/particle_add.gdshader")
const SMOKE_SHADER := preload("res://assets/shaders/particle_smoke.gdshader")
const RING_SHADER := preload("res://assets/shaders/ring.gdshader")
const SLASH_SHADER := preload("res://assets/shaders/slash_arc.gdshader")
const GHOST_SHADER := preload("res://assets/shaders/ghost.gdshader")
const CORRUPTION_SHADER := preload("res://assets/shaders/corruption.gdshader")
const STREAK_SHADER := preload("res://assets/shaders/particle_streak.gdshader")
const FLARE_SHADER := preload("res://assets/shaders/flare.gdshader")

const MAX_DECALS := 110
const MAX_NUMBERS := 56
const MAX_FLASH_LIGHTS := 10

# Shared palette
const GOO_PINK := Color(1.0, 0.18, 0.5)
const GOO_TEAL := Color(0.2, 1.0, 0.85)
const GOO_LIME := Color(0.6, 1.0, 0.15)
const GOO_PURPLE := Color(0.65, 0.2, 1.0)
const HOT_ORANGE := Color(1.0, 0.55, 0.15)
const PLASMA_CYAN := Color(0.3, 0.85, 1.0)
const GORE_DARK := Color(0.4, 0.02, 0.13)
const CRIT_PINK := Color(1.0, 0.35, 0.65)

var _ppm_cache: Dictionary = {}
var _draw_cache: Dictionary = {}
var _mat_cache: Dictionary = {}
var _decals: Array = []  # untyped: entries may be freed by their own fade tween
var _numbers: Array[Label3D] = []
var _number_idx: int = 0
var _splats: Array[Texture2D] = []
var _arc_meshes: Dictionary = {}
var _quad: QuadMesh
var _flash_lights: int = 0


func _ready() -> void:
	_splats = [_make_splat(0), _make_splat(1), _make_splat(2), _make_splat(3)]
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	for i in MAX_NUMBERS:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = false
		l.pixel_size = 0.0085
		l.font_size = 46
		l.outline_size = 12
		l.outline_modulate = Color(0.05, 0.0, 0.03, 0.95)
		l.render_priority = 10
		l.outline_render_priority = 9
		l.visible = false
		add_child(l)
		_numbers.append(l)


func world() -> Node:
	var s := get_tree().current_scene
	return s if s else get_tree().root


# =============================================================================
#  Public effects
# =============================================================================

func muzzle_flash(xform: Transform3D, color: Color, size: float = 1.0) -> void:
	var fwd := -xform.basis.z
	burst(&"flash", xform.origin + fwd * 0.12, Basis.IDENTITY, color, 1, 0.38 * size)
	burst(&"flash", xform.origin + fwd * 0.4 * size, Basis.IDENTITY, color, 1, 0.22 * size)
	burst(&"muzzle_sparks", xform.origin, basis_y(fwd), color, int(4 * size) + 3, size)


## Bullet striking flesh: star flare + a few sparks kicked back toward the shooter.
func bullet_hit(pos: Vector3, dir: Vector3, color: Color, crit: bool = false) -> void:
	burst(&"flash", pos, Basis.IDENTITY, CRIT_PINK if crit else color, 1, 0.6 if crit else 0.38)
	burst(&"sparks", pos, basis_y((-dir + Vector3.UP * 0.7).normalized()), color, 9 if crit else 5, 0.8)


func impact(pos: Vector3, normal: Vector3, color: Color, size: float = 1.0) -> void:
	burst(&"sparks", pos, basis_y(normal), color, int(10 * size), 1.0)
	burst(&"flash", pos, Basis.IDENTITY, color, 1, 0.55 * size)


## Organic hit spray. dir = travel direction of the hit.
func gore(pos: Vector3, dir: Vector3, color: Color, amount: float = 1.0, secondary: Color = GOO_TEAL) -> void:
	var spray_dir := (dir.normalized() + Vector3.UP * 0.8).normalized()
	burst(&"goo", pos, basis_y(spray_dir), color, int(14 * amount), 1.0)
	if amount >= 0.8:
		burst(&"chunks", pos, basis_y(spray_dir), secondary, int(5 * amount), 1.0)
	if randf() < 0.6 * amount:
		var splat_pos := pos + Vector3(dir.x, 0, dir.z).normalized() * randf_range(0.6, 2.0)
		splat(Vector3(splat_pos.x, 0.0, splat_pos.z), color.lerp(GORE_DARK, 0.82), randf_range(0.5, 1.0) * maxf(amount, 0.6), 0.15)


func death_burst(pos: Vector3, dir: Vector3, primary: Color, secondary: Color, size: float = 1.0) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	flat = flat.normalized() if flat.length_squared() > 0.001 else Vector3.FORWARD
	burst(&"flash", pos, Basis.IDENTITY, primary.lerp(Color.WHITE, 0.3), 1, 1.2 * size)
	burst(&"goo", pos, basis_y((Vector3.UP + flat * 0.6).normalized()), primary, int(36 * size), size)
	burst(&"chunks", pos, basis_y((Vector3.UP + flat * 0.7).normalized()), secondary, int(14 * size), size)
	burst(&"chunks", pos, basis_y((Vector3.UP + flat * 0.3).normalized()), primary.darkened(0.2), int(8 * size), size)
	burst(&"mist", pos, Basis.IDENTITY, primary.darkened(0.3), int(6 * size), size)
	var ground := Vector3(pos.x, 0.0, pos.z)
	splat(ground + flat * 0.5 * size, primary.lerp(GORE_DARK, 0.78), 1.6 * size, 0.2)
	for i in 3:
		var off := flat.rotated(Vector3.UP, randf_range(-0.9, 0.9)) * randf_range(1.2, 2.8) * size
		splat(ground + off, primary.lerp(GORE_DARK, 0.85), randf_range(0.35, 0.7) * size, 0.15)
	splat(ground - flat * 0.4 * size, secondary.darkened(0.3), 0.55 * size, 0.9)
	shockwave(ground + Vector3.UP * 0.1, 1.6 * size, primary, 0.22, 0.12)
	light_flash(pos + Vector3.UP * 0.5, primary, 3.0 * size, 5.0 * size, 0.18)


func explosion(pos: Vector3, radius: float, color: Color = HOT_ORANGE) -> void:
	var s := radius / 3.0
	burst(&"flash", pos, Basis.IDENTITY, Color(1.0, 0.85, 0.6), 1, 1.6 * s)
	burst(&"fireball", pos, Basis.IDENTITY, color, int(16 * s) + 6, s)
	burst(&"sparks", pos, Basis.IDENTITY, color, int(30 * s) + 8, 1.3)
	burst(&"smoke", pos, Basis.IDENTITY, Color(0.08, 0.07, 0.07), int(8 * s) + 4, s)
	shockwave(Vector3(pos.x, 0.08, pos.z), radius * 1.3, color, 0.35, 0.06)
	splat(Vector3(pos.x, 0.0, pos.z), Color(0.02, 0.015, 0.015, 0.9), radius * 0.7, 0.0)
	light_flash(pos + Vector3.UP, color, 5.0 * s, radius * 2.5, 0.3)


func shockwave(pos: Vector3, radius: float, color: Color, duration: float = 0.4, thickness: float = 0.08) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	mi.mesh = plane
	var m := ShaderMaterial.new()
	m.shader = RING_SHADER
	m.set_shader_parameter(&"color", color)
	m.set_shader_parameter(&"thickness", thickness)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world().add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(radius, 1.0, radius)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter(&"progress", v), 0.0, 1.0, duration)
	tw.tween_callback(mi.queue_free)


## Melee arc. xform origin = swing pivot, -Z = swing center direction.
## direction +1 sweeps left->right (clockwise from above), -1 right->left.
func slash(xform: Transform3D, radius: float, direction: float, core: Color, edge: Color, duration: float = 0.16, arc_deg: float = 170.0) -> void:
	var key := int(arc_deg)
	if not _arc_meshes.has(key):
		_arc_meshes[key] = _make_arc_mesh(deg_to_rad(arc_deg), 0.42, 1.0, int(arc_deg / 5.0) + 8)
	var mi := MeshInstance3D.new()
	mi.mesh = _arc_meshes[key]
	var m := ShaderMaterial.new()
	m.shader = SLASH_SHADER
	m.set_shader_parameter(&"core_color", core)
	m.set_shader_parameter(&"edge_color", edge)
	m.set_shader_parameter(&"direction", direction)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world().add_child(mi)
	mi.global_transform = xform
	mi.scale = Vector3(radius, 1.0, radius)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter(&"progress", v), 0.0, 1.5, duration)
	tw.tween_callback(mi.queue_free)


## Bright diagonal cut streak across an enemy that just got hit by the blade.
func slash_mark(pos: Vector3, swing_dir: Vector3, side: float, color: Color, scale: float = 1.0) -> void:
	var radial := Vector3(swing_dir.x, 0.0, swing_dir.z)
	radial = radial.normalized() if radial.length_squared() > 0.0001 else Vector3.FORWARD
	var tangent := Vector3.UP.cross(radial) * (1.0 if side >= 0.0 else -1.0)
	var line_dir := (tangent + Vector3.UP * 0.55).normalized()
	var length := 2.3 * scale
	var mi := _ribbon(color, 0.34 * scale)
	var head := pos + line_dir * length * 0.5
	mi.global_position = head
	mi.look_at(head + line_dir, Vector3.UP)
	mi.set_instance_shader_parameter(&"taper", 0.55)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter(&"trail_len", v), length * 0.25, length, 0.05)
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter(&"fade", v), 1.0, 0.0, 0.16)
	tw.tween_callback(mi.queue_free)
	burst(&"flash", pos, Basis.IDENTITY, color.lerp(Color.WHITE, 0.3), 1, 0.6 * scale)
	burst(&"sparks", pos, basis_y((tangent + Vector3.UP * 0.4).normalized()), color, 6, 0.9)


## Speed-lines left behind by a dash.
func dash_streaks(from: Vector3, to: Vector3, color: Color) -> void:
	var d := to - from
	d.y = 0.0
	var length := d.length()
	if length < 0.6:
		return
	var dir := d / length
	var side := Vector3.UP.cross(dir)
	var heights := [0.35, 0.8, 1.3, 1.8]
	for i in heights.size():
		var mi := _ribbon(color, randf_range(0.06, 0.13))
		var head := Vector3(to.x, heights[i], to.z) + side * randf_range(-0.4, 0.4) - dir * randf_range(0.1, 0.5)
		mi.global_position = head
		mi.look_at(head + dir, Vector3.UP)
		mi.extra_cull_margin = length + 2.0
		mi.set_instance_shader_parameter(&"trail_len", length * randf_range(0.75, 1.1))
		mi.set_instance_shader_parameter(&"taper", 0.95)
		var tw := mi.create_tween()
		tw.tween_method(func(v: float): mi.set_instance_shader_parameter(&"fade", v), 1.0, 0.0, 0.26 + i * 0.04)
		tw.tween_callback(mi.queue_free)


func _ribbon(color: Color, width: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = Projectile.tracer_material(color, width)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	world().add_child(mi)
	return mi


func afterimage(visual: ActorVisual, color: Color, duration: float = 0.28) -> void:
	if not is_instance_valid(visual):
		return
	var root := Node3D.new()
	world().add_child(root)
	var m := ShaderMaterial.new()
	m.shader = GHOST_SHADER
	m.set_shader_parameter(&"color", color)
	for src in _all_meshes(visual):
		if not src.visible or src.mesh == null:
			continue
		var g := MeshInstance3D.new()
		g.mesh = src.mesh
		if src.skeleton != NodePath() and src.has_method(&"bake_mesh_from_current_skeleton_pose"):
			g.mesh = src.call(&"bake_mesh_from_current_skeleton_pose")
		g.material_override = m
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(g)
		g.global_transform = src.global_transform
	var tw := root.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter(&"alpha", v), 1.0, 0.0, duration)
	tw.tween_callback(root.queue_free)


func damage_number(pos: Vector3, amount: float, crit: bool = false, color: Color = Color.WHITE) -> void:
	var l := _numbers[_number_idx]
	_number_idx = (_number_idx + 1) % MAX_NUMBERS
	if l.has_meta(&"tw"):
		var old: Tween = l.get_meta(&"tw")
		if old and old.is_valid():
			old.kill()
	l.text = str(int(round(amount)))
	l.font_size = 62 if crit else 44
	l.modulate = CRIT_PINK if crit else color
	l.visible = true
	var start := pos + Vector3(randf_range(-0.5, 0.5), 0.2, randf_range(-0.5, 0.5))
	l.global_position = start
	l.scale = Vector3.ONE * (2.1 if crit else 1.6)
	var drift := Vector3(randf_range(-0.5, 0.5), 1.1 if crit else 0.8, randf_range(-0.3, 0.3))
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "global_position", start + drift, 0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.25).set_delay(0.38)
	tw.chain().tween_callback(func(): l.visible = false)
	l.set_meta(&"tw", tw)
	if crit:
		text_popup(start + Vector3.UP * 0.5, "Critical!", CRIT_PINK, 30, 0.45)


func text_popup(pos: Vector3, text: String, color: Color, size: int = 64, life: float = 0.9) -> void:
	var l := _numbers[_number_idx]
	_number_idx = (_number_idx + 1) % MAX_NUMBERS
	if l.has_meta(&"tw"):
		var old: Tween = l.get_meta(&"tw")
		if old and old.is_valid():
			old.kill()
	l.text = text
	l.font_size = size
	l.modulate = color
	l.visible = true
	l.global_position = pos
	l.scale = Vector3.ONE * 2.2
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "global_position", pos + Vector3.UP * 0.9, life).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(life * 0.66)
	tw.chain().tween_callback(func(): l.visible = false)
	l.set_meta(&"tw", tw)


## Ground splat decal (goo / blood / scorch). glow > 0 makes it bioluminescent.
func splat(pos: Vector3, color: Color, radius: float, glow: float = 0.0, lifetime: float = 30.0) -> void:
	var d := Decal.new()
	var tex: Texture2D = _splats.pick_random()
	d.texture_albedo = tex
	if glow > 0.0:
		d.texture_emission = tex
		d.emission_energy = glow
	d.modulate = color
	d.size = Vector3(radius * 2.0, 1.6, radius * 2.0)
	d.cull_mask = 1
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.albedo_mix = color.a
	world().add_child(d)
	d.global_position = pos + Vector3.UP * 0.3
	d.rotation.y = randf() * TAU
	d.scale = Vector3(0.3, 1.0, 0.3)
	var tw := d.create_tween()
	tw.tween_property(d, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(lifetime)
	tw.tween_property(d, "albedo_mix", 0.0, 2.0)
	tw.parallel().tween_property(d, "emission_energy", 0.0, 2.0)
	tw.tween_callback(d.queue_free)
	_decals = _decals.filter(func(x): return is_instance_valid(x))
	_decals.append(d)
	while _decals.size() > MAX_DECALS:
		var old = _decals.pop_front()
		if is_instance_valid(old):
			var t2: Tween = old.create_tween()
			t2.tween_property(old, "albedo_mix", 0.0, 0.5)
			t2.tween_callback(old.queue_free)


func light_flash(pos: Vector3, color: Color, energy: float, light_range: float, duration: float) -> void:
	if _flash_lights >= MAX_FLASH_LIGHTS:
		return
	_flash_lights += 1
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.4
	world().add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_callback(func():
		_flash_lights -= 1
		l.queue_free())


## Corruption portal that precedes an enemy spawn.
func spawn_portal(pos: Vector3, radius: float, duration: float, color: Color = GOO_LIME) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	mi.mesh = plane
	var m := ShaderMaterial.new()
	m.shader = CORRUPTION_SHADER
	m.set_shader_parameter(&"seed", randf() * 100.0)
	m.set_shader_parameter(&"energy", 5.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world().add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.03
	mi.scale = Vector3(0.05, 1.0, 0.05)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), duration * 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(duration * 0.3 + 0.6)
	tw.tween_method(func(v: float): m.set_shader_parameter(&"opacity", v), 1.0, 0.0, 0.8)
	tw.tween_callback(mi.queue_free)
	burst(&"embers", pos, Basis.IDENTITY, color, 26, radius * 0.6)
	var later := get_tree().create_timer(duration)
	later.timeout.connect(func():
		burst(&"flash", pos + Vector3.UP * 0.6, Basis.IDENTITY, color, 1, 1.1)
		burst(&"goo", pos, Basis.IDENTITY, GOO_PURPLE, 18, 1.0)
		shockwave(pos + Vector3.UP * 0.05, radius * 1.6, color, 0.3, 0.07))


## Little glowing motes that fly from a point into a target (energy siphon / pickups).
func siphon(from: Vector3, target: Node3D, color: Color, count: int = 4) -> void:
	var m := _sprite_mat(color, 6.0)
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = _quad
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world().add_child(mi)
		var start := from + Vector3(randf_range(-0.5, 0.5), randf_range(0.2, 1.0), randf_range(-0.5, 0.5))
		mi.global_position = start
		mi.scale = Vector3.ONE * randf_range(0.25, 0.4)
		var ctrl := start + Vector3(randf_range(-2, 2), randf_range(1.5, 3.0), randf_range(-2, 2))
		var dur := randf_range(0.25, 0.4)
		var follow := func(t: float) -> void:
			if not is_instance_valid(target) or not is_instance_valid(mi):
				return
			var end := target.global_position + Vector3.UP * 1.2
			mi.global_position = start.lerp(ctrl, t).lerp(ctrl.lerp(end, t), t)
		var tw := mi.create_tween()
		tw.tween_method(follow, 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(i * 0.03)
		tw.tween_callback(mi.queue_free)


## Continuous world-space particle trail to parent under a moving object.
func make_trail(color: Color, amount: int = 24, lifetime: float = 0.35) -> GPUParticles3D:
	var cfg := _preset(&"trail", color)
	var p := GPUParticles3D.new()
	p.name = "Trail"
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.process_material = cfg.ppm
	p.draw_pass_1 = cfg.mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 10, 40))
	return p


## Detach a trail from a dying projectile so its particles finish naturally.
func release_trail(p: GPUParticles3D) -> void:
	if not is_instance_valid(p) or not p.is_inside_tree():
		return
	var t := p.global_transform
	p.get_parent().remove_child(p)
	world().add_child(p)
	p.global_transform = t
	p.emitting = false
	get_tree().create_timer(p.lifetime + 0.3, false).timeout.connect(p.queue_free)


func glow_material(color: Color, energy: float = 5.0) -> Material:
	return _sprite_mat(color, energy)


# =============================================================================
#  Particle presets
# =============================================================================

func burst(preset: StringName, pos: Vector3, basis: Basis, color: Color, amount: int, size: float) -> void:
	if amount <= 0:
		return
	var cfg := _preset(preset, color)
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = cfg.lifetime
	p.one_shot = true
	p.explosiveness = cfg.get("explosiveness", 1.0)
	p.randomness = 0.4
	p.local_coords = false
	p.process_material = cfg.ppm
	p.draw_pass_1 = cfg.mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 12, 16))
	p.fixed_fps = 0
	p.interpolate = false
	world().add_child(p)
	p.global_transform = Transform3D(basis, pos)
	p.scale = Vector3.ONE * size
	p.emitting = true
	get_tree().create_timer(cfg.lifetime * 1.5 + 0.3, false).timeout.connect(p.queue_free)


func _preset(preset: StringName, color: Color) -> Dictionary:
	var key := "%s|%s" % [preset, color.to_html()]
	if _ppm_cache.has(key):
		return _ppm_cache[key]
	var ppm := ParticleProcessMaterial.new()
	var cfg := {"ppm": ppm, "lifetime": 0.5}
	var hot := color.lerp(Color.WHITE, 0.7)
	match preset:
		&"flash":
			ppm.gravity = Vector3.ZERO
			ppm.scale_min = 1.0
			ppm.scale_max = 1.35
			ppm.scale_curve = _curve([Vector2(0, 0.7), Vector2(0.15, 1.0), Vector2(1, 0.1)])
			ppm.color_ramp = _ramp([color.lerp(Color.WHITE, 0.35) * 1.25, color, Color(color, 0.0)], [0.0, 0.35, 1.0])
			ppm.angle_min = 0.0
			ppm.angle_max = 360.0
			cfg.lifetime = 0.08
			cfg.mesh = _draw(&"flare")
		&"muzzle_sparks":
			ppm.direction = Vector3.UP
			ppm.spread = 16.0
			ppm.initial_velocity_min = 10.0
			ppm.initial_velocity_max = 22.0
			ppm.gravity = Vector3.ZERO
			ppm.damping_min = 20.0
			ppm.damping_max = 40.0
			ppm.particle_flag_align_y = true
			ppm.scale_min = 0.5
			ppm.scale_max = 1.0
			ppm.scale_curve = _curve([Vector2(0, 1), Vector2(1, 0)])
			ppm.color_ramp = _ramp([hot * 2.0, color, Color(color, 0.0)], [0.0, 0.4, 1.0])
			cfg.lifetime = 0.1
			cfg.mesh = _draw(&"streak")
		&"sparks":
			ppm.direction = Vector3.UP
			ppm.spread = 55.0
			ppm.initial_velocity_min = 4.0
			ppm.initial_velocity_max = 13.0
			ppm.gravity = Vector3(0, -22, 0)
			ppm.damping_min = 1.0
			ppm.damping_max = 3.0
			ppm.particle_flag_align_y = true
			ppm.scale_min = 0.4
			ppm.scale_max = 1.0
			ppm.scale_curve = _curve([Vector2(0, 1), Vector2(1, 0)])
			ppm.color_ramp = _ramp([hot * 2.5, color * 1.5, Color(color, 0.0)], [0.0, 0.35, 1.0])
			ppm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
			ppm.collision_bounce = 0.35
			ppm.collision_friction = 0.3
			cfg.lifetime = 0.45
			cfg.mesh = _draw(&"streak")
		&"goo":
			ppm.direction = Vector3.UP
			ppm.spread = 50.0
			ppm.initial_velocity_min = 3.0
			ppm.initial_velocity_max = 9.0
			ppm.gravity = Vector3(0, -20, 0)
			ppm.scale_min = 0.18
			ppm.scale_max = 0.5
			ppm.scale_curve = _curve([Vector2(0, 1), Vector2(0.7, 0.8), Vector2(1, 0)])
			ppm.color_ramp = _ramp([color * 1.6, color, Color(color.darkened(0.4), 0.0)], [0.0, 0.5, 1.0])
			ppm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
			ppm.collision_bounce = 0.05
			ppm.collision_friction = 0.9
			ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			ppm.emission_sphere_radius = 0.2
			cfg.lifetime = 0.7
			cfg.mesh = _draw(&"sprite_dim")
		&"chunks":
			ppm.direction = Vector3.UP
			ppm.spread = 60.0
			ppm.initial_velocity_min = 4.0
			ppm.initial_velocity_max = 10.0
			ppm.gravity = Vector3(0, -24, 0)
			ppm.scale_min = 0.6
			ppm.scale_max = 1.4
			ppm.angular_velocity_min = -400.0
			ppm.angular_velocity_max = 400.0
			ppm.color = color
			ppm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
			ppm.collision_bounce = 0.3
			ppm.collision_friction = 0.6
			ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			ppm.emission_sphere_radius = 0.25
			ppm.scale_curve = _curve([Vector2(0, 1), Vector2(0.85, 1), Vector2(1, 0)])
			cfg.lifetime = 1.6
			cfg.mesh = _draw(&"chunk")
		&"mist":
			ppm.direction = Vector3.UP
			ppm.spread = 90.0
			ppm.initial_velocity_min = 0.5
			ppm.initial_velocity_max = 2.5
			ppm.gravity = Vector3(0, 0.3, 0)
			ppm.damping_min = 1.0
			ppm.damping_max = 2.0
			ppm.scale_min = 1.0
			ppm.scale_max = 2.0
			ppm.scale_curve = _curve([Vector2(0, 0.4), Vector2(1, 1.3)])
			ppm.color_ramp = _ramp([Color(color, 0.7), Color(color, 0.0)], [0.0, 1.0])
			ppm.angle_max = 360.0
			cfg.lifetime = 0.9
			cfg.mesh = _draw(&"smoke")
		&"fireball":
			ppm.direction = Vector3.UP
			ppm.spread = 180.0
			ppm.initial_velocity_min = 1.0
			ppm.initial_velocity_max = 6.0
			ppm.gravity = Vector3(0, 2.0, 0)
			ppm.damping_min = 4.0
			ppm.damping_max = 7.0
			ppm.scale_min = 1.2
			ppm.scale_max = 2.6
			ppm.scale_curve = _curve([Vector2(0, 0.5), Vector2(0.25, 1.0), Vector2(1, 0.2)])
			ppm.color_ramp = _ramp([Color(1, 0.95, 0.8) * 3.0, color * 1.8, Color(0.6, 0.08, 0.04, 0.6), Color(0.1, 0.02, 0.02, 0.0)], [0.0, 0.2, 0.6, 1.0])
			ppm.angle_max = 360.0
			ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			ppm.emission_sphere_radius = 0.6
			cfg.lifetime = 0.55
			cfg.mesh = _draw(&"sprite")
		&"smoke":
			ppm.direction = Vector3.UP
			ppm.spread = 70.0
			ppm.initial_velocity_min = 1.0
			ppm.initial_velocity_max = 3.5
			ppm.gravity = Vector3(0, 0.8, 0)
			ppm.damping_min = 1.5
			ppm.damping_max = 2.5
			ppm.scale_min = 1.5
			ppm.scale_max = 3.0
			ppm.scale_curve = _curve([Vector2(0, 0.3), Vector2(1, 1.4)])
			ppm.color_ramp = _ramp([Color(color, 0.0), Color(color, 0.85), Color(color, 0.0)], [0.0, 0.15, 1.0])
			ppm.angle_max = 360.0
			ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			ppm.emission_sphere_radius = 0.8
			cfg.lifetime = 1.8
			cfg.explosiveness = 0.85
			cfg.mesh = _draw(&"smoke")
		&"embers":
			ppm.direction = Vector3.UP
			ppm.spread = 25.0
			ppm.initial_velocity_min = 1.5
			ppm.initial_velocity_max = 5.0
			ppm.gravity = Vector3(0, 1.0, 0)
			ppm.scale_min = 0.12
			ppm.scale_max = 0.3
			ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			ppm.emission_sphere_radius = 1.4
			ppm.color_ramp = _ramp([Color(color, 0.0), color * 2.0, Color(color, 0.0)], [0.0, 0.2, 1.0])
			ppm.turbulence_enabled = true
			ppm.turbulence_noise_strength = 2.0
			cfg.lifetime = 1.2
			cfg.explosiveness = 0.3
			cfg.mesh = _draw(&"sprite")
		&"dust":
			ppm.direction = Vector3.UP
			ppm.spread = 85.0
			ppm.initial_velocity_min = 0.4
			ppm.initial_velocity_max = 1.6
			ppm.gravity = Vector3(0, 0.5, 0)
			ppm.damping_min = 2.0
			ppm.damping_max = 3.0
			ppm.scale_min = 0.45
			ppm.scale_max = 0.8
			ppm.scale_curve = _curve([Vector2(0, 0.5), Vector2(1, 1.4)])
			ppm.color_ramp = _ramp([Color(color, 0.0), Color(color, 0.32), Color(color, 0.0)], [0.0, 0.2, 1.0])
			ppm.angle_max = 360.0
			ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			ppm.emission_sphere_radius = 0.25
			cfg.lifetime = 0.6
			cfg.mesh = _draw(&"smoke")
		&"trail":
			ppm.direction = Vector3.UP
			ppm.spread = 180.0
			ppm.initial_velocity_min = 0.0
			ppm.initial_velocity_max = 0.6
			ppm.gravity = Vector3.ZERO
			ppm.scale_min = 0.5
			ppm.scale_max = 0.9
			ppm.scale_curve = _curve([Vector2(0, 1), Vector2(1, 0)])
			ppm.color_ramp = _ramp([color * 2.0, color, Color(color, 0.0)], [0.0, 0.3, 1.0])
			cfg.lifetime = 0.35
			cfg.mesh = _draw(&"sprite")
		_:
			push_warning("Vfx: unknown preset %s" % preset)
			cfg.mesh = _draw(&"sprite")
	_ppm_cache[key] = cfg
	return cfg


func _draw(kind: StringName) -> Mesh:
	if _draw_cache.has(kind):
		return _draw_cache[kind]
	var mesh: Mesh
	match kind:
		&"sprite", &"sprite_dim":
			var q := QuadMesh.new()
			q.size = Vector2(0.5, 0.5)
			var m := ShaderMaterial.new()
			m.shader = ADD_SHADER
			m.set_shader_parameter(&"energy", 2.6 if kind == &"sprite" else 1.6)
			q.material = m
			mesh = q
		&"streak":
			var b := QuadMesh.new()
			b.size = Vector2(0.07, 0.75)
			var m2 := ShaderMaterial.new()
			m2.shader = STREAK_SHADER
			m2.set_shader_parameter(&"energy", 3.2)
			b.material = m2
			mesh = b
		&"flare":
			var fq := QuadMesh.new()
			fq.size = Vector2(1.0, 1.0)
			var fm := ShaderMaterial.new()
			fm.shader = FLARE_SHADER
			fm.set_shader_parameter(&"energy", 1.7)
			fq.material = fm
			mesh = fq
		&"chunk":
			var s := SphereMesh.new()
			s.radius = 0.07
			s.height = 0.12
			s.radial_segments = 8
			s.rings = 4
			var m3 := StandardMaterial3D.new()
			m3.vertex_color_use_as_albedo = true
			m3.roughness = 0.25
			m3.emission_enabled = true
			m3.emission = Color(0.3, 0.05, 0.12)
			s.material = m3
			mesh = s
		&"smoke":
			var q2 := QuadMesh.new()
			q2.size = Vector2(1.0, 1.0)
			var m4 := ShaderMaterial.new()
			m4.shader = SMOKE_SHADER
			q2.material = m4
			mesh = q2
	_draw_cache[kind] = mesh
	return mesh


func _sprite_mat(color: Color, energy: float) -> ShaderMaterial:
	var key := "spr|%s|%.1f" % [color.to_html(), energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = ADD_SHADER
	m.set_shader_parameter(&"energy", energy)
	m.set_shader_parameter(&"tint", color)
	_mat_cache[key] = m
	return m


# =============================================================================
#  Helpers
# =============================================================================

static func basis_y(dir: Vector3) -> Basis:
	var d := dir.normalized()
	if d.length_squared() < 0.001:
		return Basis.IDENTITY
	if d.dot(Vector3.UP) < -0.999:
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, d))


static func _ramp(colors: Array, offsets: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true
	return t


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 3.0
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


func _all_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		stack.append_array(n.get_children())
	return out


## Irregular goo splat alpha mask with satellite droplets.
func _make_splat(variant: int) -> Texture2D:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 1337 + variant * 71
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	var drops: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 911 + 5
	for i in 9:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.45, 0.85) * size * 0.5
		drops.append(Vector3(size * 0.5 + cos(ang) * dist, size * 0.5 + sin(ang) * dist, rng.randf_range(2.0, 6.0)))
	for y in size:
		for x in size:
			var dx := (x - size * 0.5) / (size * 0.5)
			var dy := (y - size * 0.5) / (size * 0.5)
			var r := sqrt(dx * dx + dy * dy)
			var n := noise.get_noise_2d(x, y)
			var a := clampf((0.62 + n * 0.45 - r) * 6.0, 0.0, 1.0)
			for d in drops:
				var dd := Vector2(x - d.x, y - d.y).length()
				a = maxf(a, clampf((d.z - dd) * 0.8, 0.0, 1.0))
			var inner := clampf(1.0 - r * 1.2, 0.0, 1.0)
			var alpha := a * (0.75 + inner * 0.25)
			# RGB premultiplied by alpha: decal emission reads RGB only
			img.set_pixel(x, y, Color(alpha, alpha, alpha, alpha))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Flat arc ring segment around -Z. UV.x = angle (0..1), UV.y = radial (0 inner..1 outer).
static func _make_arc_mesh(arc: float, inner: float, outer: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var t0 := float(i) / segments
		var t1 := float(i + 1) / segments
		var a0 := -arc * 0.5 + arc * t0
		var a1 := -arc * 0.5 + arc * t1
		var d0 := Vector3(sin(a0), 0, -cos(a0))
		var d1 := Vector3(sin(a1), 0, -cos(a1))
		var v := [d0 * inner, d0 * outer, d1 * outer, d1 * inner]
		var uv := [Vector2(t0, 0), Vector2(t0, 1), Vector2(t1, 1), Vector2(t1, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
	return st.commit()
