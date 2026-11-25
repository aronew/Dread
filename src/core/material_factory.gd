class_name MaterialFactory
extends RefCounted
## Procedural fallback materials, used when no PolyHaven set is present for an id.

static func build(id: StringName) -> Material:
	match id:
		&"floor_metal":
			return _shader("res://assets/shaders/floor_metal.gdshader")
		&"wall_panel":
			return _shader("res://assets/shaders/wall_panel.gdshader")
		&"pillar":
			var m := _shader("res://assets/shaders/wall_panel.gdshader")
			m.set_shader_parameter(&"panel_width", 0.8)
			m.set_shader_parameter(&"stripe_color", Color(0.12, 0.13, 0.15))
			m.set_shader_parameter(&"neon_color", Color(1.0, 0.2, 0.55))
			return m
		&"wall_trim":
			var t := StandardMaterial3D.new()
			t.albedo_color = Color(0.06, 0.065, 0.075)
			t.metallic = 0.9
			t.roughness = 0.3
			return t
		&"crate":
			var c := StandardMaterial3D.new()
			c.albedo_color = Color(0.32, 0.34, 0.37)
			c.metallic = 0.45
			c.roughness = 0.4
			return c
		&"corruption":
			return _shader("res://assets/shaders/corruption.gdshader")
		&"neon_cyan":
			return PlaceholderKit.glow(Color(0.15, 0.85, 1.0), 6.0)
		&"neon_magenta":
			return PlaceholderKit.glow(Color(1.0, 0.15, 0.55), 6.0)
		&"floor_pad":
			var p := StandardMaterial3D.new()
			p.albedo_color = Color(0.1, 0.45, 0.55)
			p.emission_enabled = true
			p.emission = Color(0.2, 0.85, 1.0)
			p.emission_energy_multiplier = 1.4
			p.roughness = 0.2
			return p
	push_warning("MaterialFactory: unknown id '%s'" % id)
	return StandardMaterial3D.new()


static func _shader(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


## Builds a StandardMaterial3D from a PolyHaven-style folder. Returns null when the
## folder has no diffuse map. Handles exported builds (files listed as *.import).
static func from_polyhaven(folder: String, uv_scale: float, triplanar: bool) -> Material:
	if folder == "" or not DirAccess.dir_exists_absolute(folder):
		return null
	var maps := {}
	for f in DirAccess.get_files_at(folder):
		var file := f.trim_suffix(".import")
		var lower := file.to_lower()
		if not (lower.ends_with(".jpg") or lower.ends_with(".png") or lower.ends_with(".exr") or lower.ends_with(".webp")):
			continue
		for key in ["_diff", "_nor_gl", "_rough", "_metal", "_arm", "_ao", "_disp"]:
			if lower.contains(key) and not maps.has(key):
				maps[key] = folder.path_join(file)
	if not maps.has("_diff"):
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(maps["_diff"])
	if maps.has("_nor_gl"):
		m.normal_enabled = true
		m.normal_texture = load(maps["_nor_gl"])
	if maps.has("_arm"):
		var arm: Texture2D = load(maps["_arm"])
		m.ao_enabled = true
		m.ao_texture = arm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness_texture = arm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = arm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.metallic = 1.0
	else:
		if maps.has("_rough"):
			m.roughness_texture = load(maps["_rough"])
		if maps.has("_metal"):
			m.metallic_texture = load(maps["_metal"])
			m.metallic = 1.0
		if maps.has("_ao"):
			m.ao_enabled = true
			m.ao_texture = load(maps["_ao"])
	m.uv1_scale = Vector3.ONE * uv_scale
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
	return m
