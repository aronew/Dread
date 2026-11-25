# Asset pipeline: Blender + PolyHaven → Dread

Every piece of art is wired through **one file**: `assets/asset_manifest.gd`.
Gameplay code only asks for IDs (`&"player"`, `&"swarmer"`, `&"floor_metal"`, `&"rifle_fire"`).
If a referenced file doesn't exist, the procedural placeholder is used, so the game
always runs while you replace art one piece at a time.

After swapping anything, run `godot --path . -- --showcase` to see the player and all
three enemies lined up idle under game lighting.

---

## 1. Characters (Blender → `.glb`)

### Modeling conventions

- **Units:** 1 Blender unit = 1 m. Reference heights: exo-suit ≈ 2.3 m, Hatch Runner ≈ 1.2 m (on all fours), Bloom Spitter ≈ 2.4 m, Tusk Hulk ≈ 3.5 m.
- **Origin** at the feet, centered.
- **Facing:** model facing Blender **−Y** (the default "front"). After the glTF export it faces +Z in Godot, so the manifest's `"yaw_offset_deg": 180` turns it to Godot's forward (−Z). If your model ends up backwards, set it to `0`.
- **Gameplay-relevant silhouettes:** keep the yellow mask faces and glowing sacs or cores readable from a ~50° top-down view. That's the camera angle.

### Animations

Name the Blender actions to match the manifest's `"anims"` map (or edit the map):

| Logical action | Player clip | Enemy clip | Notes |
|---|---|---|---|
| `idle` | `Idle` | `Idle` | loop |
| `run` | `Run` | `Run` / `Walk` | loop; playback speed scales with move speed (`run_speed_ref`) |
| `shoot` | `Shoot` | – | short additive-feeling recoil |
| `melee` | `Slash` | – | stretched to the swing duration (0.18 s) |
| `dash` | `Dash` | – | |
| `ability` | `Ability` | – | |
| `telegraph` | – | `Windup` / `Charge` / `SlamWindup` | stretched to the telegraph time |
| `attack` | – | `Lunge` / `Spit` / `Slam` | |
| `stagger` | – | `Stagger` | |
| `hit` | `Hit` | `Hit` | |
| `die` | `Death` | `Death` | |

Looping: add `-loop` to the clip name in Blender (e.g. `Run-loop`), or set Loop in
Godot's Advanced Import Settings. Then reference that exact name in the manifest.

**Export:** File → Export → glTF 2.0 (.glb). Format: glb. Include: Selected Objects.
Transform: **+Y Up** checked. Animation: Actions, and "Always Sample Animations".
Materials: Export. Emission strength carries over, so glowing parts bloom in-game.

### Sockets (attachment points)

Create **Empties**, parent them to the right bone (Bone parenting), and name them:

| Actor | Socket name | Used for |
|---|---|---|
| player | `Muzzle` | projectile spawn, muzzle flash, muzzle light. Point the empty's −Z down the barrel. |
| player | `BladeTip` | blade effects |
| player | `RocketPod` | micro-rocket launch point |
| player | `Thruster` | dash effects |
| enemies | `Mouth` | spit origin / bite point |
| brute | `SlamPoint` | slam impact point |

Godot imports bone-parented empties as nodes under a `BoneAttachment3D`, so they follow the animation.

### Drop-in locations (already referenced by the manifest)

```
assets/models/player/exo_suit.glb
assets/models/enemies/hatch_runner.glb      (swarmer)
assets/models/enemies/bloom_spitter.glb     (spitter)
assets/models/enemies/tusk_hulk.glb         (brute)
```

Collision capsules live on the enemy/player scenes (`src/enemies/*.tscn`,
`src/player/player.tscn`). Resize them there if your silhouettes differ.

---

## 2. Surfaces (PolyHaven textures)

1. On polyhaven.com → Textures, download a set as **2K, JPG**. You need at least the **Diffuse** map and the **GL** normal map (*nor_gl*, not *nor_dx*). Rough, Metal, AO, or the packed **ARM** map are optional.
2. Unzip into a folder named after the material ID:

```
assets/textures/polyhaven/floor_metal/   e.g. a metal-plate / diamond-plate set
assets/textures/polyhaven/wall_panel/    e.g. painted metal panels
assets/textures/polyhaven/pillar/
assets/textures/polyhaven/crate/
```

The loader (`MaterialFactory.from_polyhaven`) detects maps by filename
(`_diff`, `_nor_gl`, `_rough`, `_metal`, `_arm`, `_ao`) and builds a
`StandardMaterial3D` with **world-space triplanar mapping**, so it tiles seamlessly
on procedurally sized geometry. Adjust tiling with `"uv_scale"` in the manifest.

Materials not backed by textures (`corruption`, `neon_*`, `floor_pad`) are shader-driven on purpose. Their look is in `assets/shaders/`.

**Optional: PolyHaven HDRI for reflections.** Pick an indoor or industrial HDRI and
assign it as the Environment's Sky in `scenes/main.tscn`. Keep **Background = Custom
Color** (so the void stays dark), and set **Reflected Light = Sky** to get believable
reflections on metal.

---

## 3. Props (Blender)

Optional replacements, referenced by `assets/asset_manifest.gd` → `PROPS`:

| ID | File | Footprint |
|---|---|---|
| `pillar` | `assets/models/props/pillar.glb` | 2.2 × 2.2 m, ~2 m tall (low cover, so it doesn't hide the player) |
| `crate` | `assets/models/props/crate.glb` | 1.5 × 1.5 m, 1.1 m tall |
| `wall_segment` | `assets/models/props/wall_segment.glb` | 4 m wide, 4.4 m tall, 0.8 m deep. Its front faces local +Z (toward the arena). |

Wall collision is generated by code. **Pillars and crates need their own collision:**
name the collision mesh with the `-colonly` suffix in Blender (a Godot import hint) so
it becomes a StaticBody on physics layer 1 ("world").

---

## 4. Audio

Placeholder SFX are generated by `tools/gen_sfx.py` into `assets/audio/sfx/`.
To replace one, drop a file with the **same basename** (`rifle_fire.wav`,
`.ogg` or `.mp3`; the first one found wins). The full ID list is in
`asset_manifest.gd → SFX`. Playback goes through the SFX bus (compressor +
master limiter), so mixed levels stay consistent.

---

## 5. Adding a new enemy

1. Write a placeholder visual in `assets/placeholders/` (extend `ActorVisual`) or skip straight to a `.glb`.
2. Add an entry to `ACTORS` in the manifest.
3. Create `src/enemies/<name>.gd` extending `Enemy` and override the hooks you need (see `docs/ARCHITECTURE.md`).
4. Create `src/enemies/<name>.tscn` (copy `swarmer.tscn`, change the script, `visual_id`, stats and capsule).
5. Register it in `WaveDirector.SCENES`.
