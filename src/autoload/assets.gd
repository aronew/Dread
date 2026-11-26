extends Node
## Asset registry. Resolves logical IDs to real assets (Blender scenes, PolyHaven
## materials, audio files) and falls back to procedural placeholders.
## See assets/asset_manifest.gd for the mapping table.

const Manifest := preload("res://assets/asset_manifest.gd")

var _materials: Dictionary = {}
var _sfx: Dictionary = {}
var _props: Dictionary = {}


func _exit_tree() -> void:
	# static caches would otherwise be reported as leaks at shutdown
	PlaceholderKit._mat_cache.clear()
	PlaceholderKit._mesh_cache.clear()
	Projectile._mat_cache.clear()
	Projectile._quad = null


func create_actor_visual(id: StringName) -> ActorVisual:
	var entry: Dictionary = Manifest.ACTORS.get(id, {})
	if entry.is_empty():
		push_error("Assets: unknown actor id '%s'" % id)
		return ActorVisual.new()
	var scene_path: String = entry.get("scene", "")
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var packed := load(scene_path) as PackedScene
		if packed:
			var imported := ImportedActorVisual.new()
			imported.setup_from_scene(packed, entry)
			imported.name = "Visual"
			return imported
	var script: Script = load(entry["placeholder"])
	var vis: ActorVisual = script.new()
	vis.config = entry.duplicate()
	vis.name = "Visual"
	return vis


func get_material(id: StringName) -> Material:
	if _materials.has(id):
		return _materials[id]
	var entry: Dictionary = Manifest.MATERIALS.get(id, {})
	var m: Material = MaterialFactory.from_polyhaven(entry.get("polyhaven", ""), float(entry.get("uv_scale", 1.0)), bool(entry.get("triplanar", false)))
	if m == null:
		m = MaterialFactory.build(entry.get("fallback", id))
	_materials[id] = m
	return m


## Returns an instanced prop scene, or null so the caller builds a placeholder.
func instance_prop(id: StringName) -> Node3D:
	if not _props.has(id):
		var path: String = Manifest.PROPS.get(id, "")
		_props[id] = load(path) if path != "" and ResourceLoader.exists(path) else null
	var packed: PackedScene = _props[id]
	return packed.instantiate() as Node3D if packed else null


func get_music(id: StringName) -> AudioStream:
	var base: String = Manifest.MUSIC.get(id, "")
	for ext in [".ogg", ".mp3", ".wav"]:
		if base != "" and ResourceLoader.exists(base + ext):
			return load(base + ext)
	return null


func get_sfx(id: StringName) -> AudioStream:
	if _sfx.has(id):
		return _sfx[id]
	var stream: AudioStream = null
	for ext in [".wav", ".ogg", ".mp3"]:
		var path: String = Manifest.SFX_DIR + String(id) + ext
		if ResourceLoader.exists(path):
			stream = load(path)
			break
	_sfx[id] = stream
	return stream
