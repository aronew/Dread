class_name ImportedActorVisual
extends ActorVisual
## Adapter for Blender-authored characters (.glb / .gltf / .blend / .tscn).
## Reads from the manifest entry:
##   "scene":     res:// path of the model
##   "scale":     uniform scale (default 1)
##   "yaw_offset_deg": rotate model so it faces -Z (glTF exports usually face +Z => 180)
##   "anims":     { logical_action: "ClipName" }   e.g. { "idle": "Idle", "run": "Run", "melee": "Slash" }
##   "sockets":   { logical_socket: "NodeOrBoneAttachmentName" }
##   "run_speed_ref": speed (m/s) at which the run clip plays at 1x

var scene: PackedScene
var model: Node3D
var anim: AnimationPlayer
var _aim_yaw: float = 0.0
var _locomotion_clip: StringName = &""
var _action_lock: float = 0.0


func setup_from_scene(p_scene: PackedScene, p_config: Dictionary) -> void:
	scene = p_scene
	config = p_config


func _build() -> void:
	model = scene.instantiate() as Node3D
	add_child(model)
	model.scale = Vector3.ONE * float(config.get("scale", 1.0))
	model.rotation.y = deg_to_rad(float(config.get("yaw_offset_deg", 180.0)))
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var socket_map: Dictionary = config.get("sockets", {})
	for key in socket_map:
		var n := model.find_child(String(socket_map[key]), true, false) as Node3D
		if n:
			sockets[StringName(key)] = n
	_play_clip(&"idle")


func _clip(action: StringName) -> StringName:
	var anims: Dictionary = config.get("anims", {})
	var clip: String = anims.get(String(action), "")
	if clip != "" and anim and anim.has_animation(clip):
		return StringName(clip)
	return &""


func _play_clip(action: StringName, speed: float = 1.0, blend: float = 0.12) -> bool:
	var clip := _clip(action)
	if clip == &"":
		return false
	anim.play(clip, blend, speed)
	return true


func _animate(delta: float) -> void:
	_action_lock = maxf(_action_lock - delta, 0.0)
	rotation.y = lerp_angle(rotation.y, _aim_yaw, minf(delta * 18.0, 1.0))


func set_aim(world_direction: Vector3) -> void:
	if world_direction.length_squared() > 0.001:
		_aim_yaw = atan2(-world_direction.x, -world_direction.z)


func set_locomotion(world_velocity: Vector3, max_speed: float) -> void:
	if not anim or _action_lock > 0.0:
		return
	var speed := Vector2(world_velocity.x, world_velocity.z).length()
	var want: StringName = &"run" if speed > 0.4 else &"idle"
	var ref := float(config.get("run_speed_ref", max_speed))
	var spd := clampf(speed / maxf(ref, 0.1), 0.6, 1.8) if want == &"run" else 1.0
	if want != _locomotion_clip or not anim.is_playing():
		if _play_clip(want, spd):
			_locomotion_clip = want
	else:
		anim.speed_scale = spd


func play_action(action: StringName, duration: float = -1.0) -> void:
	if not anim:
		return
	var clip := _clip(action)
	if clip == &"":
		return
	var length := anim.get_animation(clip).length
	var speed := length / duration if duration > 0.0 else 1.0
	anim.play(clip, 0.06, speed)
	_action_lock = duration if duration > 0.0 else length
	_locomotion_clip = &""
