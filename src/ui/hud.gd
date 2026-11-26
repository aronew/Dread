class_name HUD
extends CanvasLayer
## Combat HUD, drawn procedurally (no textures needed). Purely event-driven:
## listens to the Events bus and never references gameplay nodes directly.

const RED := Color(1.0, 0.16, 0.22)
const RED_DARK := Color(0.25, 0.03, 0.06, 0.85)
const CYAN := Color(0.3, 0.88, 1.0)
const PANEL := Color(0.03, 0.06, 0.08, 0.78)
const EDGE := Color(0.25, 0.95, 0.85, 0.85)
const ORANGE := Color(1.0, 0.6, 0.2)

var font: FontVariation
var health_bar: HealthBar
var energy_bar: EnergyBar
var abilities: AbilityRow
var weapons: WeaponPanel
var crosshair: Crosshair
var combo: ComboMeter
var wave_label: Label
var announce_label: Label
var hint_label: Label
var debug_label: Label
var death_panel: Control

var _wave: int = 0
var _hostiles: int = 0
var _announce_tw: Tween


func _ready() -> void:
	layer = 10
	font = FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.7
	font.spacing_glyph = 1

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	health_bar = HealthBar.new(font)
	_anchor(health_bar, root, Control.PRESET_BOTTOM_LEFT, Vector2(36, -150), Vector2(470, 64))
	energy_bar = EnergyBar.new(font)
	_anchor(energy_bar, root, Control.PRESET_BOTTOM_LEFT, Vector2(36, -86), Vector2(470, 30))
	abilities = AbilityRow.new(font)
	_anchor(abilities, root, Control.PRESET_BOTTOM_LEFT, Vector2(520, -150), Vector2(300, 110))
	weapons = WeaponPanel.new(font)
	_anchor(weapons, root, Control.PRESET_BOTTOM_RIGHT, Vector2(-420, -170), Vector2(390, 140))
	combo = ComboMeter.new(font)
	_anchor(combo, root, Control.PRESET_CENTER_RIGHT, Vector2(-300, -120), Vector2(270, 120))

	wave_label = _label(root, 30, Color(1, 1, 1, 0.9))
	_place(wave_label, Vector2(0.5, 0.0), Rect2(-400, 22, 800, 40))
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	announce_label = _label(root, 64, Color.WHITE)
	_place(announce_label, Vector2(0.5, 0.5), Rect2(-700, -330, 1400, 90))
	announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_label.modulate.a = 0.0
	announce_label.pivot_offset = Vector2(700, 45)

	hint_label = _label(root, 19, Color(0.8, 0.95, 1.0, 0.85))
	_place(hint_label, Vector2(0.5, 1.0), Rect2(-900, -40, 1800, 30))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.text = "WASD move   ·   MOUSE aim   ·   LMB fire   ·   RMB / F blade (refills energy, finishes glowing enemies)   ·   SPACE dash   ·   Q rockets   ·   E nova   ·   1/2 weapons"

	debug_label = _label(root, 15, Color(0.6, 0.8, 0.85, 0.6))
	_place(debug_label, Vector2(0.0, 0.0), Rect2(20, 14, 900, 24))
	debug_label.text = "F1 swarm · F2 spitter · F3 hulk · F5 god · F6 kill all · F7 slow-mo · F8 graphics · M music · R restart"

	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)

	death_panel = _build_death_panel(root)

	Events.player_health_changed.connect(health_bar.set_value)
	Events.player_damaged.connect(func(_a, _d): health_bar.hurt())
	Events.player_energy_changed.connect(energy_bar.set_value)
	Events.player_dash_charges_changed.connect(abilities.set_dash)
	Events.ability_cooldown_changed.connect(abilities.set_cooldown)
	Events.weapon_switched.connect(weapons.set_active)
	Events.weapon_fired.connect(func(_w): crosshair.kick())
	Events.hit_confirmed.connect(crosshair.hit)
	Events.aim_target_changed.connect(crosshair.set_target)
	Events.enemy_killed.connect(func(_e, info): combo.add_kill(info))
	Events.finisher_performed.connect(func(_e): combo.add_bonus(3))
	Events.wave_started.connect(_on_wave_started)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.wave_cleared.connect(_on_wave_cleared)
	Events.announce.connect(announce)
	Events.player_died.connect(_on_player_died)
	weapons.font = font

	var tw := hint_label.create_tween()
	tw.tween_interval(14.0)
	tw.tween_property(hint_label, "modulate:a", 0.0, 2.0)


func _anchor(c: Control, parent: Control, preset: Control.LayoutPreset, offset: Vector2, size: Vector2) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	c.set_anchors_preset(preset)
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + size.x
	c.offset_bottom = offset.y + size.y


## Anchor a control to a single point (0..1 on each axis) and give it a rect relative to it.
func _place(c: Control, anchor: Vector2, rect: Rect2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = rect.position.x
	c.offset_top = rect.position.y
	c.offset_right = rect.end.x
	c.offset_bottom = rect.end.y


func _label(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override(&"outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func announce(text: String, color: Color) -> void:
	if _announce_tw and _announce_tw.is_valid():
		_announce_tw.kill()
	announce_label.text = text
	announce_label.add_theme_color_override(&"font_color", color)
	announce_label.modulate.a = 1.0
	announce_label.scale = Vector2(1.5, 1.5)
	_announce_tw = announce_label.create_tween()
	_announce_tw.tween_property(announce_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_announce_tw.tween_interval(1.4)
	_announce_tw.tween_property(announce_label, "modulate:a", 0.0, 0.5)


func _on_wave_started(n: int, count: int) -> void:
	_wave = n
	_hostiles = count
	_refresh_wave()


func _on_enemy_killed(_e: Node3D, _info: DamageInfo) -> void:
	_hostiles = maxi(_hostiles - 1, 0)
	_refresh_wave()


func _on_wave_cleared(_w: int) -> void:
	_hostiles = 0
	_refresh_wave()


func _refresh_wave() -> void:
	wave_label.text = "WAVE %d   ·   %d HOSTILES" % [_wave, _hostiles] if _hostiles > 0 else ("WAVE %d CLEARED" % _wave if _wave > 0 else "")


func _build_death_panel(root: Control) -> Control:
	var panel := ColorRect.new()
	panel.color = Color(0.15, 0.0, 0.02, 0.0)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	root.add_child(panel)
	var title := _label(panel, 96, RED)
	_place(title, Vector2(0.5, 0.5), Rect2(-600, -110, 1200, 120))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "SUIT FAILURE"
	var sub := _label(panel, 30, Color(1, 1, 1, 0.85))
	_place(sub, Vector2(0.5, 0.5), Rect2(-600, 20, 1200, 40))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.text = "PRESS  R  TO REDEPLOY"
	return panel


func _on_player_died() -> void:
	death_panel.visible = true
	death_panel.modulate.a = 0.0
	var tw := death_panel.create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(death_panel, "modulate:a", 1.0, 0.8)
	tw.parallel().tween_property(death_panel, "color:a", 0.55, 0.8)


# =============================================================================
#  Widgets
# =============================================================================

class HealthBar extends Control:
	const SEGMENTS := 10
	var font: Font
	var value: float = 100.0
	var maximum: float = 100.0
	var ghost: float = 100.0
	var _ghost_delay: float = 0.0
	var _hurt: float = 0.0

	func _init(f: Font) -> void:
		font = f

	func set_value(c: float, m: float) -> void:
		if c < value:
			_ghost_delay = 0.45
		else:
			ghost = maxf(ghost, c)
		value = c
		maximum = m
		queue_redraw()

	func hurt() -> void:
		_hurt = 1.0

	func _process(delta: float) -> void:
		_ghost_delay -= delta
		if _ghost_delay <= 0.0 and ghost > value:
			ghost = move_toward(ghost, value, maximum * delta * 0.9)
		_hurt = move_toward(_hurt, 0.0, delta * 3.0)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := 38.0
		var y := 20.0
		var slant := 10.0
		# frame
		var frame := PackedVector2Array([Vector2(0, y - 6), Vector2(w + 6, y - 6), Vector2(w + 6 - slant, y + h + 6), Vector2(-slant, y + h + 6)])
		draw_colored_polygon(frame, HUD.PANEL)
		draw_polyline(frame + PackedVector2Array([frame[0]]), HUD.EDGE, 2.0, true)
		var gap := 5.0
		var seg_w := (w - gap * (SEGMENTS - 1)) / SEGMENTS
		var ratio := value / maxf(maximum, 1.0)
		var ghost_ratio := ghost / maxf(maximum, 1.0)
		var low := ratio < 0.3
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		for i in SEGMENTS:
			var x0 := i * (seg_w + gap) + 4.0
			var poly := _seg(x0, y, seg_w - 2.0, h, slant)
			draw_colored_polygon(poly, HUD.RED_DARK)
			var seg_lo := float(i) / SEGMENTS
			var seg_hi := float(i + 1) / SEGMENTS
			var g := clampf((ghost_ratio - seg_lo) / (seg_hi - seg_lo), 0.0, 1.0)
			if g > 0.0:
				draw_colored_polygon(_seg(x0, y, (seg_w - 2.0) * g, h, slant), Color(1, 0.9, 0.85, 0.75))
			var f := clampf((ratio - seg_lo) / (seg_hi - seg_lo), 0.0, 1.0)
			if f > 0.0:
				var col := HUD.RED.lerp(Color(1, 0.6, 0.5), _hurt * 0.6)
				if low:
					col = col.lerp(Color(1, 1, 1), pulse * 0.35)
				draw_colored_polygon(_seg(x0, y, (seg_w - 2.0) * f, h, slant), col)
				draw_colored_polygon(_seg(x0, y, (seg_w - 2.0) * f, h * 0.3, slant * 0.3), Color(1, 1, 1, 0.22))
		draw_string(font, Vector2(4, 12), "HULL INTEGRITY", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.95, 1.0, 0.8))
		draw_string(font, Vector2(w - 70, 12), "%d" % ceili(value), HORIZONTAL_ALIGNMENT_RIGHT, 70, 18, HUD.RED.lightened(0.3))

	func _seg(x: float, y: float, w: float, h: float, slant: float) -> PackedVector2Array:
		return PackedVector2Array([Vector2(x + slant, y), Vector2(x + slant + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


class EnergyBar extends Control:
	var font: Font
	var value: float = 100.0
	var maximum: float = 100.0
	var _flash: float = 0.0

	func _init(f: Font) -> void:
		font = f

	func set_value(c: float, m: float) -> void:
		if c > value + 0.5:
			_flash = 1.0
		value = c
		maximum = m

	func _process(delta: float) -> void:
		_flash = move_toward(_flash, 0.0, delta * 4.0)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := 14.0
		var y := 8.0
		var r := value / maxf(maximum, 1.0)
		var frame := PackedVector2Array([Vector2(0, y - 3), Vector2(w, y - 3), Vector2(w - 6, y + h + 3), Vector2(-6, y + h + 3)])
		draw_colored_polygon(frame, HUD.PANEL)
		var empty := r < 0.15
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.015)
		var col := HUD.CYAN.lerp(Color.WHITE, _flash * 0.6)
		if empty:
			col = col.lerp(Color(1, 0.3, 0.3), pulse)
		var fw := (w - 10.0) * r
		draw_colored_polygon(PackedVector2Array([Vector2(4, y), Vector2(4 + fw, y), Vector2(fw - 2, y + h), Vector2(-2, y + h)]), col)
		for i in range(1, 10):
			var x := 4.0 + (w - 10.0) * i / 10.0
			draw_line(Vector2(x, y), Vector2(x - 6, y + h), Color(0, 0, 0, 0.45), 2.0)
		draw_string(font, Vector2(w - 120, y + h + 20), "ENERGY  %d" % int(value), HORIZONTAL_ALIGNMENT_RIGHT, 120, 15, col)
		if empty:
			draw_string(font, Vector2(4, y + h + 20), "LOW ENERGY · USE BLADE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.5, 0.5, 0.5 + pulse * 0.5))


class AbilityRow extends Control:
	var font: Font
	var cd := {&"q": 0.0, &"e": 0.0}
	var dash_charges: int = 2
	var dash_max: int = 2
	var dash_recharge: float = 0.0
	var _ready_flash := {&"q": 0.0, &"e": 0.0}

	func _init(f: Font) -> void:
		font = f

	func set_cooldown(slot: StringName, ratio: float) -> void:
		if cd.get(slot, 0.0) > 0.0 and ratio <= 0.0:
			_ready_flash[slot] = 1.0
		cd[slot] = ratio

	func set_dash(charges: int, max_charges: int, recharge: float) -> void:
		dash_charges = charges
		dash_max = max_charges
		dash_recharge = recharge

	func _process(delta: float) -> void:
		for k in _ready_flash:
			_ready_flash[k] = move_toward(_ready_flash[k], 0.0, delta * 2.5)
		queue_redraw()

	func _draw() -> void:
		_slot(Vector2(40, 52), &"q", "Q", "ROCKETS", Color(1.0, 0.55, 0.2))
		_slot(Vector2(130, 52), &"e", "E", "NOVA", Color(0.55, 0.6, 1.0))
		# dash pips
		for i in dash_max:
			var c := Vector2(205 + i * 30, 52)
			var pts := PackedVector2Array([c + Vector2(0, -12), c + Vector2(12, 0), c + Vector2(0, 12), c + Vector2(-12, 0)])
			draw_colored_polygon(pts, HUD.PANEL)
			if i < dash_charges:
				draw_colored_polygon(pts, Color(0.35, 0.65, 1.0))
			elif i == dash_charges:
				var s := dash_recharge
				var p2 := PackedVector2Array([c + Vector2(0, -12) * s, c + Vector2(12, 0) * s, c + Vector2(0, 12) * s, c + Vector2(-12, 0) * s])
				draw_colored_polygon(p2, Color(0.35, 0.65, 1.0, 0.5))
			draw_polyline(pts + PackedVector2Array([pts[0]]), HUD.EDGE, 1.5, true)
		draw_string(font, Vector2(190, 92), "DASH", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.9, 1.0, 0.75))

	func _slot(c: Vector2, slot: StringName, key: String, label: String, color: Color) -> void:
		var r := 34.0
		var ratio: float = cd[slot]
		var hex := PackedVector2Array()
		for i in 6:
			var a := TAU * i / 6.0 + PI / 6.0
			hex.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(hex, HUD.PANEL)
		if ratio <= 0.0:
			var inner := PackedVector2Array()
			for p in hex:
				inner.append(c + (p - c) * 0.82)
			draw_colored_polygon(inner, Color(color, 0.35 + _ready_flash[slot] * 0.5))
		else:
			# cooldown sweep
			var pts := PackedVector2Array([c])
			var steps := 24
			for i in steps + 1:
				var a := -PI * 0.5 + TAU * (1.0 - ratio) * i / steps
				pts.append(c + Vector2(cos(a), sin(a)) * r * 0.8)
			if pts.size() > 2:
				draw_colored_polygon(pts, Color(color, 0.25))
		draw_polyline(hex + PackedVector2Array([hex[0]]), color if ratio <= 0.0 else Color(0.4, 0.5, 0.55), 2.5, true)
		draw_string(font, c + Vector2(-30, 9), key, HORIZONTAL_ALIGNMENT_CENTER, 60, 26, Color.WHITE if ratio <= 0.0 else Color(1, 1, 1, 0.4))
		draw_string(font, c + Vector2(-40, r + 20), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color(0.8, 0.9, 1.0, 0.75))


class WeaponPanel extends Control:
	var font: Font
	var active: int = 0
	var names: Array[String] = ["M-7 PULSE RIFLE", "VX PLASMA SCATTERGUN"]
	var costs: Array[float] = [1.0, 6.0]
	var colors: Array[Color] = [Color(0.3, 0.85, 1.0), Color(1.0, 0.3, 0.8)]
	var _pop: float = 0.0

	func _init(f: Font) -> void:
		font = f

	func set_active(index: int, weapon: Resource) -> void:
		active = index
		if weapon and index < names.size():
			names[index] = weapon.display_name
			costs[index] = weapon.energy_cost
			colors[index] = weapon.color
		_pop = 1.0

	func _process(delta: float) -> void:
		_pop = move_toward(_pop, 0.0, delta * 4.0)
		queue_redraw()

	func _draw() -> void:
		for i in names.size():
			var is_active := i == active
			var y := 12.0 + i * 62.0
			var x := 0.0 if is_active else 40.0
			var w := size.x - x
			var h := 52.0 if is_active else 44.0
			if is_active:
				x -= _pop * 16.0
			var poly := PackedVector2Array([Vector2(x + 14, y), Vector2(x + w, y), Vector2(x + w - 14, y + h), Vector2(x, y + h)])
			draw_colored_polygon(poly, Color(colors[i], 0.22) if is_active else HUD.PANEL)
			draw_polyline(poly + PackedVector2Array([poly[0]]), colors[i] if is_active else Color(0.35, 0.45, 0.5, 0.8), 2.0 if is_active else 1.2, true)
			draw_string(font, Vector2(x + 26, y + h * 0.5 + 7), "%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.9 if is_active else 0.45))
			draw_string(font, Vector2(x + 56, y + h * 0.5 + 7), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 19 if is_active else 16, Color(1, 1, 1, 1.0 if is_active else 0.5))
			draw_string(font, Vector2(x + w - 90, y + h * 0.5 + 7), "%d EN" % int(costs[i]), HORIZONTAL_ALIGNMENT_RIGHT, 70, 15, Color(colors[i], 0.9 if is_active else 0.4))


class ComboMeter extends Control:
	const TIERS := [[3, "BRUTAL"], [8, "SAVAGE"], [15, "MERCILESS"], [25, "DREADFUL"], [40, "APEX HUNTER"]]
	var font: Font
	var count: int = 0
	var timer: float = 0.0
	var window: float = 3.2
	var _pop: float = 0.0

	func _init(f: Font) -> void:
		font = f

	func add_kill(_info) -> void:
		count += 1
		timer = window
		_pop = 1.0
		Events.combo_changed.emit(count, tier())

	func add_bonus(n: int) -> void:
		count += n
		timer = window
		_pop = 1.0

	func tier() -> String:
		var t := ""
		for row in TIERS:
			if count >= row[0]:
				t = row[1]
		return t

	func _process(delta: float) -> void:
		if count > 0:
			timer -= delta
			if timer <= 0.0:
				count = 0
		_pop = move_toward(_pop, 0.0, delta * 5.0)
		queue_redraw()

	func _draw() -> void:
		if count < 2:
			return
		var s := 1.0 + _pop * 0.35
		var col := Color(1.0, 0.85, 0.3).lerp(Color(1.0, 0.25, 0.35), clampf(count / 30.0, 0.0, 1.0))
		draw_set_transform(Vector2(size.x, 50), 0.0, Vector2(s, s))
		draw_string(font, Vector2(-260, 0), "x%d" % count, HORIZONTAL_ALIGNMENT_RIGHT, 250, 56, col)
		draw_set_transform(Vector2.ZERO)
		var t := tier()
		if t != "":
			draw_string(font, Vector2(0, 84), t, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 10, 24, Color(col, 0.9))
		var bar_w := (size.x - 20) * clampf(timer / window, 0.0, 1.0)
		draw_rect(Rect2(size.x - 10 - bar_w, 96, bar_w, 4), Color(col, 0.8))


class Crosshair extends Control:
	var _spread: float = 0.0
	var _hit: float = 0.0
	var _kill: float = 0.0
	var _crit: bool = false
	var _target: Node3D = null
	var _lock: float = 0.0

	func set_target(t: Node3D) -> void:
		_target = t
		_lock = 0.0

	func _ready() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN if not OS.has_feature("headless") else Input.MOUSE_MODE_VISIBLE

	func kick() -> void:
		_spread = minf(_spread + 5.0, 16.0)

	func hit(is_kill: bool, is_crit: bool) -> void:
		_hit = 1.0
		_crit = is_crit
		if is_kill:
			_kill = 1.0

	func _process(delta: float) -> void:
		_spread = move_toward(_spread, 0.0, delta * 40.0)
		_hit = move_toward(_hit, 0.0, delta * 6.0)
		_kill = move_toward(_kill, 0.0, delta * 3.5)
		_lock = move_toward(_lock, 1.0, delta * 9.0)
		queue_redraw()

	## Corner brackets that snap onto the aim-assist target.
	func _draw_lock() -> void:
		if _target == null or not is_instance_valid(_target) or _target.is_dead():
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var r: float = float(_target.radius)
		var world := _target.global_position + Vector3.UP * (0.5 + r * 0.6)
		if cam.is_position_behind(world):
			return
		var c := cam.unproject_position(world)
		var half := (22.0 + r * 16.0) * lerpf(1.8, 1.0, _lock)
		var leg := 9.0
		var col := Color(1.0, 0.3, 0.55, 0.9 * _lock)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner := c + Vector2(sx * half, sy * half)
				draw_line(corner, corner - Vector2(sx * leg, 0), col, 2.5)
				draw_line(corner, corner - Vector2(0, sy * leg), col, 2.5)

	func _draw() -> void:
		_draw_lock()
		var m := get_local_mouse_position()
		# bots/cutscenes aim without a mouse: put the reticle where they aim
		var pl := Combat.get_player(get_tree())
		if pl and pl.aim_override != Vector3.INF:
			var cam := get_viewport().get_camera_3d()
			if cam:
				m = cam.unproject_position(pl.aim_point)
		var col := HUD.CYAN
		var gap := 10.0 + _spread
		var len := 10.0
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(m + d * gap, m + d * (gap + len), Color(0, 0, 0, 0.6), 5.0)
			draw_line(m + d * gap, m + d * (gap + len), col, 2.5)
		draw_circle(m, 2.5, col)
		draw_arc(m, 26.0 + _spread, 0, TAU, 32, Color(col, 0.25), 1.5, true)
		if _hit > 0.0:
			var hc := Color(1.0, 0.85, 0.2) if _crit else Color.WHITE
			if _kill > 0.0:
				hc = Color(1.0, 0.2, 0.25)
			hc.a = maxf(_hit, _kill)
			var r0 := 8.0 + (1.0 - _hit) * 6.0
			var r1 := r0 + 10.0
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var n: Vector2 = d.normalized()
				draw_line(m + n * r0, m + n * r1, hc, 3.0)
