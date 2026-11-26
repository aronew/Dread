extends Node
## Global signal bus. Systems talk through here instead of holding references to
## each other (HUD never touches the Player directly, the WaveDirector never touches
## the HUD, etc). Keep payloads small and typed.

# --- Player ---------------------------------------------------------------
signal player_spawned(player: Node3D)
signal player_health_changed(current: float, maximum: float)
signal player_energy_changed(current: float, maximum: float)
signal player_damaged(amount: float, from_direction: Vector3)
signal player_died
signal player_dash_charges_changed(charges: int, max_charges: int, recharge_ratio: float)
signal ability_cooldown_changed(slot: StringName, ratio: float)  # ratio: 0 = ready, 1 = just used
signal weapon_switched(index: int, weapon: Resource)
signal weapon_fired(weapon: Resource)
signal aim_target_changed(target: Node3D)

# --- Combat ---------------------------------------------------------------
signal enemy_spawned(enemy: Node3D)
signal enemy_damaged(enemy: Node3D, info: DamageInfo)
signal enemy_staggered(enemy: Node3D)
signal enemy_killed(enemy: Node3D, info: DamageInfo)
signal finisher_performed(enemy: Node3D)
signal hit_confirmed(is_kill: bool, is_crit: bool)

# --- Flow -----------------------------------------------------------------
signal wave_started(wave_number: int, enemy_count: int)
signal wave_cleared(wave_number: int)
signal combo_changed(count: int, tier_name: String)
signal announce(text: String, color: Color)
