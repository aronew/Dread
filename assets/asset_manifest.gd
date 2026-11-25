extends RefCounted
## ============================================================================
##  ASSET MANIFEST — the single place art is wired into the game.
## ============================================================================
##  Gameplay code only ever asks for an ID (e.g. Assets.create_actor_visual(&"swarmer")).
##  This file maps IDs to real files. If a file does not exist yet, the
##  procedural placeholder is used automatically, so the game always runs.
##
##  To swap in your own art:
##   * Characters: export a .glb from Blender into the "scene" path below, fill in
##     "anims" (logical action -> clip name) and "sockets" (logical socket -> node /
##     BoneAttachment3D name). See docs/ASSET_PIPELINE.md.
##   * Materials: drop a PolyHaven texture set into the "polyhaven" folder below
##     (e.g. assets/textures/polyhaven/floor_metal/metal_plate_diff_2k.jpg ...).
##   * Audio: drop rifle_fire.wav/.ogg into assets/audio/sfx/ (same basename as the ID).
## ============================================================================

const ACTORS := {
	&"player": {
		"scene": "res://assets/models/player/exo_suit.glb",
		"placeholder": "res://assets/placeholders/exo_suit_visual.gd",
		"scale": 1.0,
		"yaw_offset_deg": 180.0,
		"run_speed_ref": 8.5,
		"anims": {
			"idle": "Idle", "run": "Run", "shoot": "Shoot", "melee": "Slash",
			"dash": "Dash", "ability": "Ability", "hit": "Hit", "die": "Death",
		},
		"sockets": {"muzzle": "Muzzle", "blade_tip": "BladeTip", "rocket_pod": "RocketPod", "thruster": "Thruster"},
	},
	&"swarmer": {
		"scene": "res://assets/models/enemies/hatch_runner.glb",
		"placeholder": "res://assets/placeholders/swarmer_visual.gd",
		"scale": 1.0,
		"yaw_offset_deg": 180.0,
		"anims": {"idle": "Idle", "run": "Run", "telegraph": "Windup", "attack": "Lunge", "stagger": "Stagger", "hit": "Hit", "die": "Death"},
		"sockets": {"mouth": "Mouth"},
	},
	&"spitter": {
		"scene": "res://assets/models/enemies/bloom_spitter.glb",
		"placeholder": "res://assets/placeholders/spitter_visual.gd",
		"scale": 1.0,
		"yaw_offset_deg": 180.0,
		"anims": {"idle": "Idle", "run": "Walk", "telegraph": "Charge", "attack": "Spit", "stagger": "Stagger", "hit": "Hit", "die": "Death"},
		"sockets": {"mouth": "Mouth"},
	},
	&"brute": {
		"scene": "res://assets/models/enemies/tusk_hulk.glb",
		"placeholder": "res://assets/placeholders/brute_visual.gd",
		"scale": 1.0,
		"yaw_offset_deg": 180.0,
		"anims": {"idle": "Idle", "run": "Walk", "telegraph": "SlamWindup", "attack": "Slam", "stagger": "Stagger", "hit": "Hit", "die": "Death"},
		"sockets": {"mouth": "Mouth", "slam": "SlamPoint"},
	},
}

## Surface materials. "polyhaven" = folder scanned for *_diff_*, *_nor_gl_*, *_rough_*,
## *_metal_*, *_arm_*, *_ao_* maps. "fallback" = procedural material id in MaterialFactory.
const MATERIALS := {
	&"floor_metal": {"polyhaven": "res://assets/textures/polyhaven/floor_metal/", "uv_scale": 0.25, "triplanar": true, "fallback": &"floor_metal"},
	&"wall_panel": {"polyhaven": "res://assets/textures/polyhaven/wall_panel/", "uv_scale": 0.35, "triplanar": true, "fallback": &"wall_panel"},
	&"wall_trim": {"polyhaven": "", "fallback": &"wall_trim"},
	&"pillar": {"polyhaven": "res://assets/textures/polyhaven/pillar/", "uv_scale": 0.5, "triplanar": true, "fallback": &"pillar"},
	&"crate": {"polyhaven": "res://assets/textures/polyhaven/crate/", "uv_scale": 0.6, "triplanar": true, "fallback": &"crate"},
	&"corruption": {"polyhaven": "", "fallback": &"corruption"},
	&"neon_cyan": {"polyhaven": "", "fallback": &"neon_cyan"},
	&"neon_magenta": {"polyhaven": "", "fallback": &"neon_magenta"},
	&"floor_pad": {"polyhaven": "", "fallback": &"floor_pad"},
}

## Props: optional Blender scenes. Placeholder geometry is built by the arena if missing.
const PROPS := {
	&"pillar": "res://assets/models/props/pillar.glb",
	&"crate": "res://assets/models/props/crate.glb",
	&"wall_segment": "res://assets/models/props/wall_segment.glb",
	&"barrier_door": "res://assets/models/props/barrier_door.glb",
}

## SFX: id -> base path without extension (.wav / .ogg / .mp3 are tried in order).
const SFX_DIR := "res://assets/audio/sfx/"
const SFX := [
	&"rifle_fire", &"shotgun_fire", &"dry_fire", &"bullet_impact", &"flesh_hit", &"crit_hit",
	&"melee_swing", &"melee_hit", &"finisher", &"dash", &"rocket_launch", &"explosion",
	&"nova", &"enemy_die", &"enemy_spit", &"spit_impact", &"brute_roar", &"brute_slam",
	&"swarmer_screech", &"player_hurt", &"pickup_health", &"pickup_energy", &"spawn_portal",
	&"wave_start", &"wave_clear", &"weapon_switch", &"stagger",
]
