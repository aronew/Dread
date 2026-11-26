# Architecture

## Pattern: composition + autoload services + signal bus (not ECS)

Godot's scene tree is already a composition system, so a full ECS would fight the
engine. Instead the project uses three layers:

1. **Autoload services.** These are stateless or global systems that anything may call:

   | Autoload | Responsibility |
   |---|---|
   | `Events` | Global signal bus. HUD, PostFX and WaveDirector only *listen*. |
   | `Assets` | Asset registry. Resolves IDs to Blender scenes, PolyHaven materials or audio, and falls back to placeholders. |
   | `Vfx` | Every visual effect: particle presets (cached per color), decals (capped pool), damage numbers (pooled), slashes, shockwaves, afterimages. |
   | `Sfx` | Pooled one-shot audio with pitch jitter, distance falloff and anti-spam throttling. |
   | `Feel` | Hitstop, slow-mo, shake routing, zoom punch, gamepad rumble. |
   | `InputConfig` | All input bindings, declared in code. |

2. **Actors made of small components.** `Player` composes `HealthComponent`,
   `WeaponController`, `MeleeController` and `AbilityController`. `Enemy` composes
   `HealthComponent`, a `StateMachine` and a `NavigationAgent3D`. Each component
   exposes **hook arrays** (Callables) so Phase 3 mods can plug in without editing
   the component.

3. **Data resources.** `WeaponData` (`.tres`) defines guns. Enemy stats are exported
   on the scenes (`src/enemies/*.tscn`), so you tune them in the Inspector.

## Art decoupling: the `ActorVisual` contract

Gameplay code never touches meshes, bones or AnimationPlayers. It only calls:

```gdscript
visual.set_locomotion(velocity, max_speed)   # every physics tick
visual.set_aim(world_direction)              # upper body / facing
visual.play_action(&"melee" | &"telegraph" | &"attack" | &"stagger" | &"hit" | &"die" ...)
visual.set_charge(0..1, color)               # wind-up / weak-point glow
visual.flash(color)                          # hit flash
visual.get_socket(&"muzzle")                 # attachment points
```

There are two implementations:

- `assets/placeholders/*_visual.gd`: primitives with procedural animation (gait, recoil, blade swing, jaw snaps, bile sac swelling).
- `ImportedActorVisual`: wraps a Blender `.glb` with an AnimationPlayer. It maps logical actions to clip names and logical sockets to node names, using `assets/asset_manifest.gd`.

`Assets.create_actor_visual(id)` picks the imported model if the file exists and
falls back to the placeholder otherwise. Hit flash and wind-up glow use a
`material_overlay`, so they work on any mesh, including your imported ones.

## Combat data flow

```
Input ─► Player ─► WeaponController ─► Projectile (swept raycast) ─► Enemy.apply_damage(DamageInfo)
                └► MeleeController ─► Enemy.apply_damage / EnemyProjectile.reflect / finisher
                └► AbilityController ─► MicroRocket / Combat.explode()

Enemy.apply_damage ─► HealthComponent ─► (poise break) StateMachine → staggered
                   ├► Vfx (flash, numbers, gore, splats)  ├► Sfx  ├► Feel
                   └► Events.enemy_damaged / enemy_killed / hit_confirmed ─► HUD, PostFX, WaveDirector
```

Every hit is a `DamageInfo` (amount, kind, source, position, direction, knockback,
poise, crit, tags). That gives Phase 3 a single place to intercept or rewrite damage.

## Enemy AI

`EnemyStates` holds the shared **flow**: Idle → Chase → Telegraph (`Windup`) → Attack → Chase,
plus Staggered and Dead interrupts. Each archetype only overrides **hooks**:

| Hook | Swarmer | Spitter | Brute |
|---|---|---|---|
| `chase_step` | flank to a personal angle around the player | kite between 7.5 and 12 m, strafe, keep line of sight | plod forward |
| `can_attack` | in lunge range + line of sight | in range + line of sight + cooldown | slam range, or leap when the player kites past 9 m |
| `begin_telegraph` | red line + jaws open | lime aim line + bile sac swell | red circle (slam, or a leap target) + arms raised |
| `perform_attack` | lunge + bite | 3-glob fan | AoE slam / leap arc then slam |

**Poise** builds up from hits. When it breaks, the enemy is staggered and becomes finishable. The Brute
ignores poise until it drops below 35% HP ("CORE EXPOSED").

Movement uses a navmesh baked at runtime (`NavigationRegion3D.bake_navigation_mesh`)
plus cheap separation steering, so packs surround you instead of stacking.

## Feel pass (what makes combat land)

These came from frame-by-frame study of DreadHunter's official gameplay footage. The tuning lives in the files named.

| Area | How it works | Where |
|---|---|---|
| **Hit detection** | Bullets hit **top-down (2D)**: anything whose footprint circle they cross, at any height. What's under the cursor is what you hit. | `Projectile._process`, `seg_circle` |
| **Aim assist** | The enemy nearest the cursor (or inside a 7° cone; 16° on gamepad) becomes `aim_target`. Shots lead it, and rifle rounds gently home in (bullet magnetism). Pink brackets show the lock. | `Player._update_aim_target`, `WeaponController._fire`, `WeaponData.homing` |
| **Smoothness** | Player movement, aim and projectiles run at render rate (`_process`), not on the physics tick, so they're judder-free at any refresh rate. The camera updates last each frame. | `Player._process`, `IsoCamera.process_priority` |
| **Camera** | The look-ahead uses the mouse's *screen* offset, never its world point. That prevents the aim-drift feedback loop. | `IsoCamera._desired_look_ahead` |
| **Melee** | A buffered 3-hit combo: 0.2 s swings, chaining at 60% of the swing. Each swing auto-targets and lunges, and damage lands on an active frame (45 ms in). Gunfire can cancel the recovery; a slash cancels a dash. | `MeleeController.COMBO` |
| **Hit reactions** | White flash that holds briefly, squash flinch, knockback, and hit-stun that interrupts light enemies' wind-ups. Kills pop, then splat. | `Enemy.apply_damage`, `ActorVisual.squash` |
| **Dash** | 3 charges, 0.13 s at 36 m/s, buffered input, exit momentum, speed-lines. | `Player._start_dash` |

## Game feel checklist (where to tune)

| Feel | Where |
|---|---|
| Hitstop on hits, kills and finishers | `Feel.hitstop`, called from Melee, Enemy and Player |
| Directional camera kick + trauma shake | `IsoCamera.add_trauma` |
| Finisher slow-mo + zoom punch | `MeleeController._finisher` |
| Muzzle flash, light flicker, recoil animation | `WeaponController._fire` |
| Hit flash, damage numbers (crit / melee / explosion colors), gore + glowing goo decals | `Enemy._hit_feedback`, `Vfx` |
| Dash afterimages, thruster flare, shockwave | `Player._try_dash` |
| Chromatic aberration + red vignette on damage, low-HP pulse | `PostFX` |
| Crosshair bloom and hit / kill / crit markers | `HUD.Crosshair` |

## Phase 2 plan (dungeon + lock-in)

- `DungeonGenerator` places room templates on a grid (Start, 3–5 Arenas, Boss) and connects them with corridors. It reuses `TestArena`'s modular builders (walls, cover, corruption) parameterized per room.
- `ArenaRoom` adds an `Area3D` trigger. On entry it closes the laser barriers (the sealed-door piece already exists), runs waves through `WaveDirector.spawn_enemy()`, then opens the barriers and drops loot when cleared.
- The navmesh is baked once per dungeon after generation (already async-capable).

## Phase 3 plan (loot + mods)

The hooks are already in place:

| Mod | Hook |
|---|---|
| Split Shot | `WeaponController.shot_modifiers`: append extra shot dictionaries |
| Ricochet Rounds | `WeaponController.projectile_hit_hooks`: on a world hit, spawn a reflected projectile |
| Vampiric Melee | `MeleeController.hit_hooks`: heal per hit |
| Explosive Dash | `Player.dashed(from, to)`: `Combat.explode` along the path |
