class_name ActorVisual
extends Node3D
## The ONLY interface gameplay code uses to drive a character's look.
##
## Gameplay never touches meshes, bones or AnimationPlayers directly. It calls:
##   set_locomotion(velocity, max_speed)   every physics frame
##   set_aim(world_direction)              every frame (where the upper body faces)
##   play_action(&"melee" | &"shoot" | &"dash" | &"telegraph" | &"attack" | &"stagger" | &"hit" | &"die" ...)
##   set_charge(0..1)                      telegraph / wind-up glow
##   get_socket(&"muzzle")                 attachment points for VFX and projectiles
##
## Two implementations exist:
##   * Placeholder visuals (assets/placeholders/*.gd): primitive geometry + procedural animation.
##   * ImportedActorVisual: wraps a Blender .glb + AnimationPlayer using the clip/socket
##     mapping declared in assets/asset_manifest.gd.
## Swapping art = editing the manifest. No gameplay code changes.

const FLASH_SHADER := preload("res://assets/shaders/hit_flash.gdshader")

var config: Dictionary = {}
var sockets: Dictionary = {}  # StringName -> Node3D
var overlay: ShaderMaterial
var _flash: float = 0.0
var _charge: float = 0.0
var _squash: float = 0.0
var _squash_vel: float = 0.0
var _base_scale: Vector3 = Vector3.ONE
var _highlight: float = 0.0
var _highlight_target: float = 0.0


func _ready() -> void:
	_build()
	_base_scale = scale
	_install_overlay()


## Override: construct geometry / instance the imported scene.
func _build() -> void:
	pass


func _process(delta: float) -> void:
	if _flash > 0.0:
		# values above 1.0 hold pure white for a moment before fading (crisp hit frames)
		_flash = maxf(_flash - delta * 9.0, 0.0)
		overlay.set_shader_parameter(&"flash", _flash)
	if _highlight != _highlight_target:
		_highlight = move_toward(_highlight, _highlight_target, delta * 8.0)
		overlay.set_shader_parameter(&"highlight", _highlight)
	# hit squash: damped spring back to rest
	if absf(_squash) > 0.001 or absf(_squash_vel) > 0.001:
		_squash_vel += (-_squash * 900.0 - _squash_vel * 28.0) * delta
		_squash += _squash_vel * delta
		scale = _base_scale * Vector3(1.0 + _squash, 1.0 - _squash * 1.2, 1.0 + _squash)
	_animate(delta)


## Flinch on hit: amount ~0.1 (bullet) .. 0.35 (heavy melee).
func squash(amount: float) -> void:
	_squash = clampf(_squash + amount, -0.4, 0.4)


## Constant silhouette rim so the actor reads against dark floors.
func set_base_rim(color: Color, strength: float) -> void:
	if overlay:
		overlay.set_shader_parameter(&"base_rim_color", color)
		overlay.set_shader_parameter(&"base_rim", strength)


## Aim-target highlight (thin cool rim).
func set_highlight(on: bool) -> void:
	_highlight_target = 1.0 if on else 0.0


## Override: procedural animation tick.
func _animate(_delta: float) -> void:
	pass


func set_locomotion(_world_velocity: Vector3, _max_speed: float) -> void:
	pass


func set_aim(_world_direction: Vector3) -> void:
	pass


func play_action(_action: StringName, _duration: float = -1.0) -> void:
	pass


func set_charge(amount: float, color: Color = Color(1.0, 0.25, 0.15)) -> void:
	_charge = clampf(amount, 0.0, 1.0)
	if overlay:
		overlay.set_shader_parameter(&"rim_strength", _charge)
		overlay.set_shader_parameter(&"rim_color", color)


func flash(color: Color = Color.WHITE, strength: float = 1.0) -> void:
	if not overlay:
		return
	_flash = maxf(_flash, strength)
	overlay.set_shader_parameter(&"flash_color", color)
	overlay.set_shader_parameter(&"flash", _flash)


func get_socket(socket_name: StringName) -> Node3D:
	var s: Node3D = sockets.get(socket_name)
	return s if is_instance_valid(s) else self


func add_socket(socket_name: StringName, parent: Node3D, local_pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = String(socket_name)
	m.position = local_pos
	parent.add_child(m)
	sockets[socket_name] = m
	return m


func get_mesh_instances() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect_meshes(self, out)
	return out


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	for c in node.get_children():
		if c is MeshInstance3D and not c.has_meta(&"no_overlay"):
			out.append(c)
		_collect_meshes(c, out)


## One shared overlay material per actor: hit-flash + fresnel charge rim. Works the
## same on primitives and on imported Blender meshes.
func _install_overlay() -> void:
	overlay = ShaderMaterial.new()
	overlay.shader = FLASH_SHADER
	for m in get_mesh_instances():
		m.material_overlay = overlay
