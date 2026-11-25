class_name Combat
extends RefCounted
## Shared combat queries and helpers (physics layers, AoE, target lookup).

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMIES := 4
const LAYER_PICKUPS := 8

const GROUP_ENEMIES := &"enemies"
const GROUP_PLAYER := &"player"
const GROUP_ENEMY_PROJECTILES := &"enemy_projectiles"


static func get_player(tree: SceneTree) -> Node3D:
	return tree.get_first_node_in_group(GROUP_PLAYER) as Node3D


static func living_enemies(tree: SceneTree) -> Array[Node]:
	var out: Array[Node] = []
	for e in tree.get_nodes_in_group(GROUP_ENEMIES):
		if is_instance_valid(e) and not e.is_dead():
			out.append(e)
	return out


static func enemies_in_radius(tree: SceneTree, center: Vector3, radius: float) -> Array[Node]:
	var out: Array[Node] = []
	for e in living_enemies(tree):
		var d: float = _flat_dist(e.global_position, center) - float(e.radius)
		if d <= radius:
			out.append(e)
	return out


static func nearest_enemy(tree: SceneTree, from: Vector3, max_dist: float = INF) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for e in living_enemies(tree):
		var d := _flat_dist(e.global_position, from)
		if d < best_d:
			best_d = d
			best = e
	return best


## Radial damage with falloff. Returns number of enemies hit.
static func explode(tree: SceneTree, center: Vector3, radius: float, damage: float, source: Node,
		knockback: float = 10.0, poise: float = 40.0, kind: DamageInfo.Kind = DamageInfo.Kind.EXPLOSION) -> int:
	var hits := 0
	for e in enemies_in_radius(tree, center, radius):
		var to: Vector3 = e.global_position - center
		to.y = 0.0
		var falloff := clampf(1.0 - (to.length() - e.radius) / radius, 0.35, 1.0)
		var info := DamageInfo.make(damage * falloff, kind, source, e.global_position + Vector3.UP, to)
		info.knockback = knockback * falloff
		info.poise_damage = poise * falloff
		e.apply_damage(info)
		hits += 1
	return hits


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func raycast(world: World3D, from: Vector3, to: Vector3, mask: int, exclude: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	q.collide_with_areas = false
	return world.direct_space_state.intersect_ray(q)
