class_name PickupOrb
extends Node3D
## Glowing health / energy orb. Pops out with physics-y scatter, then magnetizes
## to the player when close (Doom-style push-forward loop).

enum Kind { HEALTH, ENERGY }

const K := preload("res://assets/placeholders/placeholder_kit.gd")

var kind: Kind = Kind.HEALTH
var amount: float = 5.0
var magnet_radius: float = 5.0
var lifetime: float = 18.0
var _vel: Vector3 = Vector3.ZERO
var _t: float = 0.0
var _magnet: bool = false
var _core: MeshInstance3D
var _halo: MeshInstance3D


static func spawn(parent: Node, pos: Vector3, p_kind: Kind, p_amount: float, scatter: float = 5.0) -> PickupOrb:
	var o := PickupOrb.new()
	o.kind = p_kind
	o.amount = p_amount
	parent.add_child(o)
	o.global_position = pos + Vector3.UP * 0.8
	var ang := randf() * TAU
	o._vel = Vector3(cos(ang), 0, sin(ang)) * randf_range(0.4, 1.0) * scatter + Vector3.UP * randf_range(5.0, 8.0)
	return o


func _ready() -> void:
	var col := Color(0.25, 1.0, 0.4) if kind == Kind.HEALTH else Color(0.2, 0.8, 1.0)
	_core = K.sphere(self, 0.16, Vector3.ZERO, K.glow(col.lightened(0.5), 9.0))
	_halo = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.3, 1.3)
	_halo.mesh = quad
	_halo.material_override = Vfx.glow_material(col, 2.5)
	add_child(_halo)
	for m in [_core, _halo]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if kind == Kind.HEALTH:
		# little plus sign
		K.box(_core, Vector3(0.5, 0.12, 0.12), Vector3.ZERO, K.glow(col, 6.0))
		K.box(_core, Vector3(0.12, 0.5, 0.12), Vector3.ZERO, K.glow(col, 6.0))
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 0.8
	light.omni_range = 2.5
	add_child(light)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_t += delta
	var player := Combat.get_player(get_tree())
	if player and not player.is_dead():
		var to := player.global_position + Vector3.UP * 1.0 - global_position
		var d := to.length()
		if _t > 0.35 and (d < magnet_radius or _magnet):
			_magnet = true
			_vel = _vel.lerp(to.normalized() * (18.0 + _t * 4.0), minf(delta * 10.0, 1.0))
		if d < 0.9 and _t > 0.2:
			if player.collect_pickup(self):
				queue_free()
				return
	if not _magnet:
		_vel.y -= 22.0 * delta
		_vel.x = move_toward(_vel.x, 0.0, delta * 6.0)
		_vel.z = move_toward(_vel.z, 0.0, delta * 6.0)
	global_position += _vel * delta
	if not _magnet and global_position.y < 0.6:
		global_position.y = 0.6
		_vel.y = absf(_vel.y) * 0.35
	_core.rotation.y += delta * 3.0
	var pulse := 1.0 + sin(_t * 8.0) * 0.12
	_halo.scale = Vector3.ONE * pulse
	if _t > lifetime - 3.0:
		visible = fmod(_t * 8.0, 1.0) > 0.3
	if _t > lifetime:
		queue_free()
