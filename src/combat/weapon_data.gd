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
@export var bloom_per_shot_deg: float = 0.0  ## extra spread while sustaining fire
@export var bloom_max_deg: float = 0.0
@export_group("Projectile")
@export var damage: float = 12.0
@export var damage_kind: DamageInfo.Kind = DamageInfo.Kind.BULLET
@export var projectile_speed: float = 75.0
@export var projectile_range: float = 32.0
@export var projectile_length: float = 1.1
@export var projectile_width: float = 0.09
@export var pierce: int = 0
@export var hit_radius: float = 0.3          ## top-down collision radius (generous = feels accurate)
@export var homing: float = 0.0              ## bullet magnetism turn rate (rad/s) toward the aim-assist target
@export var homing_cone_deg: float = 25.0    ## only steer when the target is within this angle
@export var lead_factor: float = 0.8         ## how much to lead moving aim-assist targets (0..1)
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
