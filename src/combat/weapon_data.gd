class_name WeaponData
extends Resource
## Data-driven weapon definition. Duplicate a .tres in src/player/weapons/ to make
## a new gun. Behaviour-altering mods (Phase 3) hook into WeaponController.

@export var id: StringName = &"weapon"
@export var display_name: String = "Weapon"
@export_group("Firing")
@export var automatic: bool = true
@export var fire_rate: float = 10.0          ## shots per second
@export var energy_cost: float = 1.0
@export var pellets: int = 1
@export var spread_deg: float = 2.0
@export var bloom_per_shot_deg: float = 0.6  ## extra spread while sustaining fire
@export var bloom_max_deg: float = 5.0
@export_group("Projectile")
@export var damage: float = 12.0
@export var damage_kind: DamageInfo.Kind = DamageInfo.Kind.BULLET
@export var projectile_speed: float = 75.0
@export var projectile_range: float = 32.0
@export var projectile_length: float = 1.1
@export var projectile_width: float = 0.09
@export var pierce: int = 0
@export var knockback: float = 2.0
@export var poise_damage: float = 4.0
@export var crit_chance: float = 0.12
@export var crit_multiplier: float = 2.0
@export_group("Feel")
@export var color: Color = Color(0.3, 0.85, 1.0)
@export var shake: float = 0.06
@export var muzzle_size: float = 1.0
@export var recoil_push: float = 0.0          ## pushes the player back (m/s)
@export var fire_sfx: StringName = &"rifle_fire"
