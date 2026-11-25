class_name PlaceholderKit
extends RefCounted
## Tiny helpers for building chunky stylized placeholder geometry from primitives.
## Meshes and materials are cached so 40 swarmers share the same resources.

static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}

# Palette pulled from the corrupted-creature concept sheets + DreadHunter screenshots.
const FLESH := Color(0.93, 0.22, 0.45)
const FLESH_DARK := Color(0.55, 0.08, 0.25)
const SLIME := Color(0.25, 0.95, 0.85)
const MASK_YELLOW := Color(1.0, 0.78, 0.12)
const CARAPACE := Color(0.55, 0.32, 0.85)
const COIL_TEAL := Color(0.16, 0.55, 0.65)
const IVORY := Color(0.92, 0.86, 0.72)
const BILE := Color(0.62, 1.0, 0.18)
const ARMOR_RED := Color(0.9, 0.12, 0.14)
const ARMOR_WHITE := Color(0.95, 0.95, 0.93)
const GUNMETAL := Color(0.16, 0.17, 0.2)
const THRUST_BLUE := Color(0.2, 0.55, 1.0)
const VISOR_CYAN := Color(0.2, 1.0, 0.95)


static func mat(color: Color, metallic: float = 0.0, roughness: float = 0.55,
		emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s|%.2f" % [color.to_html(), metallic, roughness, emission.to_html(), emission_energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	_mat_cache[key] = m
	return m


## Glossy wet flesh — slight rim lighting sells the "gooey" look of the concepts.
static func flesh(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key := "flesh|%s|%.2f" % [color.to_html(), glow]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.28
	m.metallic_specular = 0.7
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.4
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	_mat_cache[key] = m
	return m


static func glow(color: Color, energy: float = 4.0) -> StandardMaterial3D:
	var key := "glow|%s|%.2f" % [color.to_html(), energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_mat_cache[key] = m
	return m


static func _mesh(key: String, maker: Callable) -> Mesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = maker.call()
	return _mesh_cache[key]


static func _inst(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material, rot_deg: Vector3, scl: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material,
		rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mesh := _mesh("box%s" % size, func():
		var b := BoxMesh.new()
		b.size = size
		return b)
	return _inst(parent, mesh, pos, material, rot_deg, scl)


static func sphere(parent: Node3D, radius: float, pos: Vector3, material: Material,
		scl: Vector3 = Vector3.ONE, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := _mesh("sph%.3f" % radius, func():
		var s := SphereMesh.new()
		s.radius = radius
		s.height = radius * 2.0
		s.radial_segments = 20
		s.rings = 10
		return s)
	return _inst(parent, mesh, pos, material, rot_deg, scl)


static func capsule(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material,
		rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mesh := _mesh("cap%.3f|%.3f" % [radius, height], func():
		var c := CapsuleMesh.new()
		c.radius = radius
		c.height = maxf(height, radius * 2.0)
		c.radial_segments = 16
		c.rings = 6
		return c)
	return _inst(parent, mesh, pos, material, rot_deg, scl)


static func cylinder(parent: Node3D, top_radius: float, bottom_radius: float, height: float, pos: Vector3,
		material: Material, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, segments: int = 16) -> MeshInstance3D:
	var mesh := _mesh("cyl%.3f|%.3f|%.3f|%d" % [top_radius, bottom_radius, height, segments], func():
		var c := CylinderMesh.new()
		c.top_radius = top_radius
		c.bottom_radius = bottom_radius
		c.height = height
		c.radial_segments = segments
		c.rings = 1
		return c)
	return _inst(parent, mesh, pos, material, rot_deg, scl)


static func torus(parent: Node3D, inner: float, outer: float, pos: Vector3, material: Material,
		rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mesh := _mesh("tor%.3f|%.3f" % [inner, outer], func():
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 24
		t.ring_segments = 12
		return t)
	return _inst(parent, mesh, pos, material, rot_deg, scl)


static func pivot(parent: Node3D, pos: Vector3, node_name: String = "") -> Node3D:
	var p := Node3D.new()
	if node_name != "":
		p.name = node_name
	p.position = pos
	parent.add_child(p)
	return p


## Yellow "corruption mask" face with a frown, the signature motif of the concept art.
static func mask_face(parent: Node3D, radius: float, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	var root := pivot(parent, pos)
	root.rotation_degrees = rot_deg
	sphere(root, radius, Vector3.ZERO, flesh(MASK_YELLOW), Vector3(1.0, 1.0, 0.55))
	var ink := mat(Color(0.05, 0.03, 0.03), 0.0, 0.4)
	var r := radius
	sphere(root, r * 0.13, Vector3(-r * 0.36, r * 0.22, -r * 0.5), ink, Vector3(0.8, 1.4, 0.6))
	sphere(root, r * 0.13, Vector3(r * 0.36, r * 0.22, -r * 0.5), ink, Vector3(0.8, 1.4, 0.6))
	# frown: two tilted strokes forming a "/\" mouth
	capsule(root, r * 0.06, r * 0.5, Vector3(-r * 0.2, -r * 0.4, -r * 0.5), ink, Vector3(0, 0, -65))
	capsule(root, r * 0.06, r * 0.5, Vector3(r * 0.2, -r * 0.4, -r * 0.5), ink, Vector3(0, 0, 65))
	return root
