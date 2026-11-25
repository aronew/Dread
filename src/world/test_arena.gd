class_name TestArena
extends Node3D
## Phase 1 combat sandbox arena, built from modular pieces at runtime.
## Every surface material comes from the Assets registry (PolyHaven-ready) and
## every prop asks Assets.instance_prop() first, so Blender props drop in later.
##
## Camera sits toward +X/+Z, so those two sides use LOW glass barriers (never
## occlude the player) while -X/-Z get tall industrial walls.

const K := preload("res://assets/placeholders/placeholder_kit.gd")

@export var half_size: float = 22.0
@export var far_wall_height: float = 4.4
@export var near_wall_height: float = 1.1
@export var segment: float = 4.0

var nav_region: NavigationRegion3D
var spawn_points: Array[Vector3] = []
var _geo: Node3D      # collidable geometry (parsed for the navmesh)
var _decor: Node3D    # visual-only


func _ready() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.75
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Combat.LAYER_WORLD
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	_geo = nav_region
	_decor = Node3D.new()
	_decor.name = "Decor"
	add_child(_decor)

	_build_floor()
	_build_far_walls()
	_build_near_barriers()
	_build_cover()
	_build_centerpiece()
	_build_corruption()
	_build_lights()
	_build_atmosphere()
	_build_spawn_points()
	nav_region.bake_navigation_mesh(false)


# -----------------------------------------------------------------------------
#  Helpers
# -----------------------------------------------------------------------------

func _static_box(size: Vector3, pos: Vector3, mat: Material, rot_y_deg: float = 0.0, visible_mesh: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Combat.LAYER_WORLD
	body.collision_mask = 0
	_geo.add_child(body)
	body.position = pos
	body.rotation_degrees.y = rot_y_deg
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	if visible_mesh:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		body.add_child(mi)
	return body


func _deco_box(size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	return K.box(parent if parent else _decor, size, pos, mat, rot_deg)


func _omni(pos: Vector3, color: Color, energy: float, light_range: float, shadows: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadows
	_decor.add_child(l)
	l.position = pos
	return l


# -----------------------------------------------------------------------------
#  Floor
# -----------------------------------------------------------------------------

func _build_floor() -> void:
	var H := half_size
	_static_box(Vector3(H * 2.0 + 4.0, 1.0, H * 2.0 + 4.0), Vector3(0, -0.5, 0), null, 0.0, false)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(H * 2.0 + 2.0, H * 2.0 + 2.0)
	floor_mi.mesh = plane
	floor_mi.material_override = Assets.get_material(&"floor_metal")
	floor_mi.name = "Floor"
	_decor.add_child(floor_mi)

	# Glowing abyss beyond the near barriers (sells depth like the reference shots).
	var pit := MeshInstance3D.new()
	var pit_plane := PlaneMesh.new()
	pit_plane.size = Vector2(160, 160)
	pit.mesh = pit_plane
	var pit_mat := StandardMaterial3D.new()
	pit_mat.albedo_color = Color(0.0, 0.05, 0.06)
	pit_mat.emission_enabled = true
	pit_mat.emission = Color(0.05, 0.6, 0.55)
	pit_mat.emission_energy_multiplier = 0.55
	pit.material_override = pit_mat
	pit.position.y = -6.0
	_decor.add_child(pit)
	# Floor slab edge visible over the drop.
	var edge_mat := Assets.get_material(&"wall_trim")
	_deco_box(Vector3(H * 2.0 + 2.0, 1.2, 0.6), Vector3(0, -0.6, H + 1.3), edge_mat)
	_deco_box(Vector3(0.6, 1.2, H * 2.0 + 2.0), Vector3(H + 1.3, -0.6, 0), edge_mat)
	# Support girders below
	for i in range(-2, 3):
		_deco_box(Vector3(0.5, 6.0, 0.5), Vector3(i * 9.0, -3.5, H + 1.5), edge_mat)
		_deco_box(Vector3(0.5, 6.0, 0.5), Vector3(H + 1.5, -3.5, i * 9.0), edge_mat)

	# Particle floor collider (sparks/gibs bounce instead of falling through).
	var pcol := GPUParticlesCollisionBox3D.new()
	pcol.size = Vector3(H * 2.0 + 10.0, 1.0, H * 2.0 + 10.0)
	pcol.position.y = -0.5
	_decor.add_child(pcol)

	# Cyan floor pads
	var pad_mat := Assets.get_material(&"floor_pad")
	for p in [Vector3(-14, 0, 4), Vector3(4, 0, -14), Vector3(14, 0, -6), Vector3(-6, 0, 14), Vector3(12, 0, 12), Vector3(-12, 0, -12)]:
		_deco_box(Vector3(1.3, 0.05, 1.3), p + Vector3.UP * 0.02, pad_mat, Vector3(0, 45, 0))
		_omni(p + Vector3.UP * 0.6, Color(0.3, 0.9, 1.0), 1.4, 4.5)


# -----------------------------------------------------------------------------
#  Walls
# -----------------------------------------------------------------------------

func _build_far_walls() -> void:
	var H := half_size
	var h := far_wall_height
	var wall_mat := Assets.get_material(&"wall_panel")
	var trim := Assets.get_material(&"wall_trim")
	var neon := Assets.get_material(&"neon_cyan")
	var cap_mat := K.mat(Color(0.85, 0.85, 0.83), 0.2, 0.3)
	# collision: north (-Z) and west (-X)
	_static_box(Vector3(H * 2.0 + 2.0, h, 1.0), Vector3(0, h * 0.5, -H - 0.5), null, 0.0, false)
	_static_box(Vector3(1.0, h, H * 2.0 + 2.0), Vector3(-H - 0.5, h * 0.5, 0), null, 0.0, false)

	var count := int(H * 2.0 / segment)
	for i in count:
		var c := -H + segment * (i + 0.5)
		var door := i == count / 2
		for side in [0, 1]:
			var pos := Vector3(c, 0, -H - 0.5) if side == 0 else Vector3(-H - 0.5, 0, c)
			var rot := 0.0 if side == 0 else 90.0
			var seg := Node3D.new()
			_decor.add_child(seg)
			seg.position = pos
			seg.rotation_degrees.y = rot
			if door:
				_build_sealed_door(seg)
				continue
			var custom := Assets.instance_prop(&"wall_segment")
			if custom:
				seg.add_child(custom)
				continue
			# rounded white panel with red livery (see wall_panel shader)
			K.box(seg, Vector3(segment - 0.25, h - 0.4, 0.8), Vector3(0, (h - 0.4) * 0.5, 0), wall_mat)
			K.cylinder(seg, 0.42, 0.42, segment - 0.25, Vector3(0, h - 0.35, 0.0), cap_mat, Vector3(0, 0, 90), Vector3.ONE, 20)
			K.box(seg, Vector3(segment - 0.3, 0.06, 0.05), Vector3(0, 0.5, 0.42), neon)
			# vertical seam pillar
			K.box(seg, Vector3(0.35, h + 0.2, 1.1), Vector3(segment * 0.5, (h + 0.2) * 0.5, 0), trim)
			K.box(seg, Vector3(0.08, 0.5, 0.05), Vector3(segment * 0.5, h * 0.55, 0.56), K.glow(Color(1.0, 0.2, 0.25), 5.0))
			# occasional tech panel
			if i % 3 == 1:
				K.box(seg, Vector3(1.4, 0.8, 0.08), Vector3(-0.6, 1.6, 0.42), K.mat(Color(0.04, 0.05, 0.06), 0.8, 0.3))
				K.box(seg, Vector3(1.2, 0.08, 0.05), Vector3(-0.6, 1.75, 0.47), K.glow(Color(1.0, 0.7, 0.2), 4.0))
				K.box(seg, Vector3(0.8, 0.08, 0.05), Vector3(-0.8, 1.55, 0.47), K.glow(Color(0.3, 0.9, 1.0), 4.0))
	# corner tower
	_deco_box(Vector3(2.0, h + 1.0, 2.0), Vector3(-H - 0.5, (h + 1.0) * 0.5, -H - 0.5), trim)
	_deco_box(Vector3(0.15, h, 0.15), Vector3(-H + 0.55, h * 0.5, -H + 0.55), K.glow(Color(1.0, 0.25, 0.55), 6.0))
	_omni(Vector3(-H + 1.5, 2.5, -H + 1.5), Color(1.0, 0.25, 0.55), 2.5, 7.0)


## Sealed blast door with a laser barrier — previews Phase 2's arena lock-in.
func _build_sealed_door(seg: Node3D) -> void:
	var h := far_wall_height
	var trim := Assets.get_material(&"wall_trim")
	var frame := K.mat(Color(0.75, 0.75, 0.73), 0.3, 0.35)
	K.box(seg, Vector3(0.6, h, 1.2), Vector3(-segment * 0.5 + 0.3, h * 0.5, 0), frame)
	K.box(seg, Vector3(0.6, h, 1.2), Vector3(segment * 0.5 - 0.3, h * 0.5, 0), frame)
	K.box(seg, Vector3(segment, 0.7, 1.2), Vector3(0, h - 0.35, 0), trim)
	K.box(seg, Vector3(segment - 1.2, h - 0.7, 0.3), Vector3(0, (h - 0.7) * 0.5, -0.3), K.mat(Color(0.05, 0.05, 0.06), 0.7, 0.4))
	var laser := K.glow(Color(1.0, 0.08, 0.12), 9.0)
	for j in 6:
		var bar := K.box(seg, Vector3(segment - 1.2, 0.035, 0.035), Vector3(0, 0.35 + j * 0.55, 0.3), laser)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	K.box(seg, Vector3(segment - 1.2, 0.04, 0.6), Vector3(0, 0.02, 0.5), K.glow(Color(1.0, 0.1, 0.1), 3.0))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.1, 0.12)
	l.light_energy = 2.5
	l.omni_range = 6.0
	l.position = Vector3(0, 1.4, 1.2)
	seg.add_child(l)


func _build_near_barriers() -> void:
	var H := half_size
	var h := near_wall_height
	# collision only up to 1.0 m so projectiles at chest height fly over
	_static_box(Vector3(H * 2.0 + 2.0, 1.0, 0.6), Vector3(0, 0.5, H + 0.4), null, 0.0, false)
	_static_box(Vector3(0.6, 1.0, H * 2.0 + 2.0), Vector3(H + 0.4, 0.5, 0), null, 0.0, false)
	var post_mat := K.mat(Color(0.86, 0.86, 0.84), 0.2, 0.3)
	var rail_mat := Assets.get_material(&"wall_trim")
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.2, 0.9, 0.8, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.emission_enabled = true
	glass.emission = Color(0.1, 0.8, 0.7)
	glass.emission_energy_multiplier = 0.6
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	var accent := K.glow(Color(1.0, 0.2, 0.25), 4.0)
	var count := int(H * 2.0 / segment)
	for i in count + 1:
		var c := -H + segment * i
		for side in [0, 1]:
			var p := Vector3(c, 0, H + 0.4) if side == 0 else Vector3(H + 0.4, 0, c)
			var rot := 0.0 if side == 0 else 90.0
			var post := Node3D.new()
			_decor.add_child(post)
			post.position = p
			post.rotation_degrees.y = rot
			K.box(post, Vector3(0.5, h + 0.25, 0.7), Vector3(0, (h + 0.25) * 0.5, 0), post_mat)
			K.box(post, Vector3(0.52, 0.08, 0.72), Vector3(0, h - 0.1, 0), accent)
			if i < count:
				K.box(post, Vector3(segment - 0.5, h - 0.25, 0.06), Vector3(segment * 0.5, (h - 0.25) * 0.5 + 0.1, 0), glass)
				K.box(post, Vector3(segment - 0.5, 0.12, 0.3), Vector3(segment * 0.5, h - 0.02, 0), rail_mat)
				K.box(post, Vector3(segment - 0.5, 0.18, 0.4), Vector3(segment * 0.5, 0.09, 0), rail_mat)


# -----------------------------------------------------------------------------
#  Cover + centerpiece
# -----------------------------------------------------------------------------

func _build_cover() -> void:
	var pillar_mat := Assets.get_material(&"pillar")
	var trim := Assets.get_material(&"wall_trim")
	var neon := Assets.get_material(&"neon_magenta")
	for p in [Vector3(-9, 0, -9), Vector3(9, 0, -9), Vector3(-9, 0, 9), Vector3(9, 0, 9)]:
		var custom := Assets.instance_prop(&"pillar")
		if custom:
			_geo.add_child(custom)
			custom.position = p
			continue
		# Low cover (iso camera friendly): tall enough to block shots, short enough not to hide you.
		_static_box(Vector3(2.2, 1.9, 2.2), p + Vector3.UP * 0.95, pillar_mat)
		_deco_box(Vector3(2.6, 0.3, 2.6), p + Vector3.UP * 0.15, trim)
		_deco_box(Vector3(2.4, 0.2, 2.4), p + Vector3.UP * 1.95, trim)
		_deco_box(Vector3(1.6, 0.06, 1.6), p + Vector3.UP * 2.07, K.glow(Color(0.15, 0.7, 1.0), 1.2))
		for corner in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
			var strip := _deco_box(Vector3(0.08, 1.4, 0.08), p + corner * 1.12 + Vector3.UP * 1.0, neon)
			strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var crate_mat := Assets.get_material(&"crate")
	var hazard := K.glow(Color(1.0, 0.6, 0.1), 2.5)
	var crates := [
		[Vector3(-15, 0, -3), 0.0], [Vector3(-14, 0, -1.4), 20.0], [Vector3(3, 0, -16), 10.0],
		[Vector3(16, 0, 3), -15.0], [Vector3(-3, 0, 16), 30.0], [Vector3(15.5, 0, 15), 0.0],
	]
	for c in crates:
		var pos: Vector3 = c[0]
		var custom := Assets.instance_prop(&"crate")
		if custom:
			_geo.add_child(custom)
			custom.position = pos
			custom.rotation_degrees.y = c[1]
			continue
		var body := _static_box(Vector3(1.5, 1.1, 1.5), pos + Vector3.UP * 0.55, crate_mat, c[1])
		K.box(body, Vector3(1.54, 0.12, 1.54), Vector3(0, 0.25, 0), hazard)
		K.box(body, Vector3(1.6, 0.08, 1.6), Vector3(0, 0.56, 0), Assets.get_material(&"wall_trim"))


func _build_centerpiece() -> void:
	var ring_mat := K.glow(Color(0.1, 0.75, 1.0), 0.7)
	var dark := K.mat(Color(0.1, 0.12, 0.13), 0.5, 0.22)
	var t := K.torus(_decor, 5.6, 6.0, Vector3(0, 0.02, 0), ring_mat, Vector3.ZERO, Vector3(1, 0.05, 1))
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	K.cylinder(_decor, 5.5, 5.5, 0.03, Vector3(0, 0.012, 0), dark, Vector3.ZERO, Vector3.ONE, 48)
	var t2 := K.torus(_decor, 3.0, 3.15, Vector3(0, 0.035, 0), K.glow(Color(0.25, 0.9, 1.0), 1.0), Vector3.ZERO, Vector3(1, 0.05, 1))
	t2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 16:
		var a := i * TAU / 16.0
		var seg := K.box(_decor, Vector3(0.9, 0.04, 0.25), Vector3(cos(a) * 4.3, 0.04, sin(a) * 4.3), K.glow(Color(0.2, 1.0, 0.6), 0.6), Vector3(0, -rad_to_deg(a), 0))
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core := K.cylinder(_decor, 1.3, 1.3, 0.05, Vector3(0, 0.04, 0), K.glow(Color(0.2, 0.9, 0.5), 0.3), Vector3.ZERO, Vector3.ONE, 32)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_omni(Vector3(0, 1.0, 0), Color(0.3, 1.0, 0.7), 2.0, 8.0)


# -----------------------------------------------------------------------------
#  Corruption
# -----------------------------------------------------------------------------

func _build_corruption() -> void:
	var shader := preload("res://assets/shaders/corruption.gdshader")
	var patches := [
		[Vector3(-17, 0, -16), 5.0], [Vector3(-18, 0, 6), 3.6], [Vector3(10, 0, -18), 4.2],
		[Vector3(-4, 0, -6), 2.4], [Vector3(6, 0, 8), 2.0], [Vector3(17, 0, -12), 3.0],
	]
	var pod_mat := K.flesh(Color(0.9, 0.2, 0.5))
	var pod_glow := K.flesh(Color(0.3, 1.0, 0.8), 3.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for p in patches:
		var pos: Vector3 = p[0]
		var r: float = p[1]
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(r * 2.0, r * 2.0)
		mi.mesh = plane
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter(&"seed", rng.randf() * 100.0)
		m.set_shader_parameter(&"energy", 2.2)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = pos + Vector3.UP * 0.015
		mi.rotation.y = rng.randf() * TAU
		_decor.add_child(mi)
		# organic pods on the larger patches
		if r >= 3.0:
			for j in int(r * 1.5):
				var a := rng.randf() * TAU
				var d := rng.randf_range(0.3, r * 0.55)
				var s := rng.randf_range(0.25, 0.6)
				var pp := pos + Vector3(cos(a) * d, s * 0.5, sin(a) * d)
				K.sphere(_decor, s, pp, pod_mat, Vector3(1.0, rng.randf_range(0.7, 1.3), 1.0))
				K.sphere(_decor, s * 0.35, pp + Vector3(0, s * 0.6, -s * 0.2), pod_glow)
		_omni(pos + Vector3.UP * 1.2, Color(0.6, 0.2, 1.0) if rng.randf() < 0.5 else Color(0.3, 1.0, 0.4), 1.8, r * 2.2)


# -----------------------------------------------------------------------------
#  Lighting + atmosphere
# -----------------------------------------------------------------------------

func _build_lights() -> void:
	var lamp_mat := K.glow(Color(0.85, 0.95, 1.0), 6.0)
	var housing := K.mat(Color(0.08, 0.09, 0.1), 0.8, 0.4)
	for p in [Vector3(-11, 0, -11), Vector3(11, 0, -11), Vector3(-11, 0, 11), Vector3(11, 0, 11), Vector3(0, 0, 0)]:
		var spot := SpotLight3D.new()
		spot.light_color = Color(0.75, 0.9, 1.0)
		spot.light_energy = 9.0 if p != Vector3.ZERO else 6.0
		spot.spot_range = 16.0
		spot.spot_angle = 38.0
		spot.spot_attenuation = 0.9
		spot.shadow_enabled = true
		spot.light_volumetric_fog_energy = 1.6
		_decor.add_child(spot)
		spot.position = p + Vector3.UP * 11.0
		spot.rotation_degrees.x = -90.0
		# lamp fixture only on the far side (near-side fixtures would sit between camera and play)
		if p.x + p.z < 0.0:
			K.cylinder(_decor, 0.6, 0.9, 0.5, p + Vector3.UP * 7.5, housing)
			K.cylinder(_decor, 0.75, 0.75, 0.05, p + Vector3.UP * 7.24, lamp_mat)


func _build_atmosphere() -> void:
	var H := half_size
	var dust := GPUParticles3D.new()
	dust.amount = 380
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.visibility_aabb = AABB(Vector3(-H, -1, -H), Vector3(H * 2.0, 10, H * 2.0))
	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	ppm.emission_box_extents = Vector3(H, 3.0, H)
	ppm.direction = Vector3(0.3, 1, 0.1)
	ppm.spread = 60.0
	ppm.initial_velocity_min = 0.05
	ppm.initial_velocity_max = 0.3
	ppm.gravity = Vector3(0, 0.02, 0)
	ppm.turbulence_enabled = true
	ppm.turbulence_noise_strength = 0.4
	ppm.scale_min = 0.05
	ppm.scale_max = 0.14
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	g.colors = PackedColorArray([Color(0.5, 0.9, 1.0, 0.0), Color(0.5, 0.9, 1.0, 0.5), Color(0.6, 1.0, 0.8, 0.5), Color(0.5, 0.9, 1.0, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	ppm.color_ramp = gt
	dust.process_material = ppm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/particle_add.gdshader")
	m.set_shader_parameter(&"energy", 1.5)
	q.material = m
	dust.draw_pass_1 = q
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.position = Vector3(0, 3.0, 0)
	_decor.add_child(dust)

	var probe := ReflectionProbe.new()
	probe.size = Vector3(H * 2.0, 10.0, H * 2.0)
	probe.position = Vector3(0, 4.0, 0)
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	_decor.add_child(probe)


func _build_spawn_points() -> void:
	var H := half_size
	var inset := 3.0
	var step := 5.0
	var x := -H + inset
	while x <= H - inset:
		spawn_points.append(Vector3(x, 0, -H + inset))
		spawn_points.append(Vector3(-H + inset, 0, x))
		spawn_points.append(Vector3(x, 0, H - inset))
		spawn_points.append(Vector3(H - inset, 0, x))
		x += step
	for p in [Vector3(-5, 0, -13), Vector3(13, 0, 5), Vector3(-13, 0, 5), Vector3(5, 0, 13)]:
		spawn_points.append(p)


## Spawn point at least `min_dist` from `avoid`, preferring ones ahead of nothing in particular.
func pick_spawn_point(avoid: Vector3, min_dist: float = 9.0) -> Vector3:
	var candidates := spawn_points.filter(func(p: Vector3): return Vector2(p.x - avoid.x, p.z - avoid.z).length() >= min_dist)
	if candidates.is_empty():
		return spawn_points.pick_random()
	return candidates.pick_random()
