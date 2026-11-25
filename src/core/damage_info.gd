class_name DamageInfo
extends RefCounted
## One packet of damage. Everything that hurts something builds one of these, so
## mods (Phase 3) can intercept / rewrite hits in a single place.

enum Kind { BULLET, PLASMA, MELEE, EXPLOSION, CORROSIVE, FINISHER }

var amount: float = 0.0
var kind: Kind = Kind.BULLET
var source: Node = null                ## who dealt it (player / enemy)
var position: Vector3 = Vector3.ZERO   ## world-space impact point
var direction: Vector3 = Vector3.ZERO  ## normalized travel direction of the hit
var knockback: float = 0.0             ## impulse in m/s applied along direction
var poise_damage: float = 0.0          ## stagger buildup
var is_crit: bool = false
var tags: PackedStringArray = []       ## free-form (e.g. "ricochet", "reflected") for mods


static func make(p_amount: float, p_kind: Kind, p_source: Node, p_pos: Vector3, p_dir: Vector3) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = p_amount
	d.kind = p_kind
	d.source = p_source
	d.position = p_pos
	d.direction = p_dir.normalized() if p_dir.length_squared() > 0.0001 else Vector3.ZERO
	return d


func is_melee() -> bool:
	return kind == Kind.MELEE or kind == Kind.FINISHER
