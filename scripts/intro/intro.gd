extends Node3D
## Intro cinematic (~75 s): a green island is slowly destroyed (deforestation,
## factory smoke, traffic, poisoned air and water, struggling lungs, animals
## leaving, an earthquake, a tsunami and storms), then a single sapling and a
## message of hope lead into the game. Fully procedural, skippable.
##
## Dev flags (after `--`): --shots=DIR saves screenshots at key moments and quits;
## --finish-at=T presses Skip at T seconds.

const MAIN_SCENE := "res://scenes/main.tscn"
const SHOT_TIMES := [4.0, 11.0, 18.0, 25.5, 33.0, 40.0, 45.0, 50.6, 59.0, 68.0, 77.0]

var world: IntroWorld
var env: Environment
var sun: DirectionalLight3D
var rig: Node3D
var cam: Camera3D
var synth: IntroSynth

var _ui: Control
var _haze: ColorRect
var _dim: ColorRect
var _lungs: LungsView
var _flash: ColorRect
var _fade: ColorRect
var _caption: Label
var _caption_tw: Tween
var _day_label: Label
var _aqi: AqiMeter
var _skip: Button
var _cta: Button
var _hope_tag: Label
var _planet_label: Label

var day := 1.0
var _t := 0.0
var _events: Array = []        ## [time, Callable], sorted
var _next_event := 0
var _shake := 0.0
var _shake_until := 0.0
var _finishing := false
var _shots_dir := ""
var _next_shot := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots_dir = a.substr(8)
		if a.begins_with("--finish-at="):
			at(float(a.substr(12)), _finish)
	_build_environment()
	world = IntroWorld.new()
	add_child(world)
	world.build()
	world.build_hope_set()
	_build_camera()
	_build_ui()
	synth = IntroSynth.new()
	add_child(synth)
	_build_timeline()


# ------------------------------------------------------------------ setup

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.8, 0.98)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.85)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


func _build_camera() -> void:
	rig = Node3D.new()
	rig.rotation_degrees.y = 45.0
	add_child(rig)
	var tilt := Node3D.new()
	tilt.rotation_degrees.x = -35.264
	rig.add_child(tilt)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = 24.0
	cam.position = Vector3(0, 0, 70)
	cam.far = 200.0
	tilt.add_child(cam)
	cam.make_current()
	rig.position = world.uv_point(0, 3)


func _label(size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)

	_haze = _rect(Color(0.45, 0.38, 0.28, 0.0))
	_ui.add_child(_haze)
	_dim = _rect(Color(0.03, 0.03, 0.04, 0.0))
	_ui.add_child(_dim)
	_lungs = LungsView.new()
	_lungs.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lungs.offset_top = 120
	_lungs.offset_bottom = -260
	_lungs.modulate.a = 0.0
	_ui.add_child(_lungs)

	# Cinematic letterbox bars
	for top in [true, false]:
		var bar := _rect(Color(0, 0, 0, 0.92))
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			bar.offset_bottom = 120
		else:
			bar.offset_top = -120
		_ui.add_child(bar)

	_day_label = _label(30)
	_day_label.position = Vector2(28, 34)
	_ui.add_child(_day_label)
	var sub := _label(14, Color(1, 1, 1, 0.6))
	sub.text = "PLANET EARTH"
	sub.position = Vector2(30, 76)
	_ui.add_child(sub)
	_planet_label = sub
	_aqi = AqiMeter.new()
	_aqi.anchor_left = 1.0
	_aqi.anchor_right = 1.0
	_aqi.offset_left = -258
	_aqi.offset_right = -28
	_aqi.offset_top = 14
	_aqi.offset_bottom = 112
	_aqi.value = 22.0
	_ui.add_child(_aqi)

	_caption = _label(34)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_left = 40
	_caption.offset_right = -40
	_caption.offset_top = -330
	_caption.offset_bottom = -150
	_caption.modulate.a = 0.0
	_ui.add_child(_caption)

	_hope_tag = _label(20, Color(1, 0.95, 0.75))
	_hope_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hope_tag.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hope_tag.offset_top = 170
	_hope_tag.offset_bottom = 210
	_hope_tag.modulate.a = 0.0
	_ui.add_child(_hope_tag)

	_flash = _rect(Color(1, 1, 1, 0.0))
	_ui.add_child(_flash)
	_fade = _rect(Color(0, 0, 0, 1.0))
	_ui.add_child(_fade)

	_cta = Button.new()
	_cta.text = "Plant the first tree"
	_cta.add_theme_font_size_override("font_size", 28)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.3, 0.7, 0.42) if state != "pressed" else Color(0.25, 0.6, 0.36)
		if state == "hover":
			sb.bg_color = Color(0.36, 0.76, 0.48)
		sb.set_corner_radius_all(36)
		sb.content_margin_left = 40
		sb.content_margin_right = 40
		sb.content_margin_top = 18
		sb.content_margin_bottom = 18
		sb.shadow_color = Color(0.3, 0.8, 0.45, 0.35)
		sb.shadow_size = 18
		_cta.add_theme_stylebox_override(state, sb)
	_cta.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_cta.anchor_left = 0.5
	_cta.anchor_right = 0.5
	_cta.anchor_top = 1.0
	_cta.anchor_bottom = 1.0
	_cta.offset_left = -200
	_cta.offset_right = 200
	_cta.offset_top = -250
	_cta.offset_bottom = -170
	_cta.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cta.visible = false
	_cta.pressed.connect(_finish)
	_ui.add_child(_cta)

	_skip = Button.new()
	_skip.text = "Skip  >"
	_skip.flat = true
	_skip.add_theme_font_size_override("font_size", 20)
	_skip.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_skip.add_theme_color_override("font_hover_color", Color.WHITE)
	_skip.anchor_left = 1.0
	_skip.anchor_right = 1.0
	_skip.anchor_top = 1.0
	_skip.anchor_bottom = 1.0
	_skip.offset_left = -140
	_skip.offset_right = -20
	_skip.offset_top = -86
	_skip.offset_bottom = -36
	_skip.pressed.connect(_finish)
	_ui.add_child(_skip)


# ------------------------------------------------------------------ timeline helpers

func at(time: float, fn: Callable) -> void:
	_events.append([time, fn])


func say(text: String, hold: float) -> void:
	if _caption_tw:
		_caption_tw.kill()
	_caption.text = text
	_caption.visible_ratio = 0.0
	_caption.modulate.a = 1.0
	_caption_tw = create_tween()
	_caption_tw.tween_property(_caption, "visible_ratio", 1.0, clampf(text.length() * 0.035, 0.6, 2.2))
	_caption_tw.tween_interval(hold)
	_caption_tw.tween_property(_caption, "modulate:a", 0.0, 0.7)


func ease_to(obj: Object, prop: String, value: Variant, duration: float) -> void:
	create_tween().tween_property(obj, prop, value, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func shot(u: float, v: float, size: float, duration: float) -> void:
	ease_to(rig, "position", world.uv_point(u, v), duration)
	ease_to(cam, "size", size, duration)


func shake(strength: float, duration: float) -> void:
	_shake = strength
	_shake_until = _t + duration


func flash(alpha: float, duration: float = 0.5) -> void:
	_flash.color.a = alpha
	ease_to(_flash, "color:a", 0.0, duration)


func lightning(u: float, v: float) -> void:
	world.lightning_bolt(Vector2(u, v))
	flash(0.75, 0.6)
	synth.thunder()


func _build_timeline() -> void:
	# 1. A green, living Earth
	at(0.0, func() -> void:
		ease_to(_fade, "color:a", 0.0, 2.5)
		ease_to(synth, "master", 0.9, 3.0)
		ease_to(synth, "pad", 0.8, 3.0)
		synth.birds = 1.2
		ease_to(cam, "size", 28.0, 7.0))
	at(0.8, func() -> void: say("Once, our Earth was green and full of life.", 4.0))

	# 2. Deforestation
	at(6.5, func() -> void:
		say("But every day, we took a little more.", 4.2)
		world.cut_forest(0.8, 6.0)
		world.fade_green(0.1, 7.0)
		ease_to(self, "day", 365.0, 6.5)
		ease_to(_aqi, "value", 48.0, 6.0)
		ease_to(synth, "birds", 0.3, 6.0)
		ease_to(synth, "dark", 0.25, 6.0))

	# 3. Factories and smoke
	at(13.0, func() -> void:
		shot(1.0, -10.0, 22.0, 2.5)
		world.build_factories(2.4)
		say("Factories rose, and smoke filled the sky.", 4.5)
		ease_to(synth, "hum", 0.7, 3.0)
		ease_to(synth, "birds", 0.0, 3.0)
		ease_to(synth, "dark", 0.5, 6.0)
		ease_to(env, "background_color", Color(0.62, 0.6, 0.55), 6.0)
		ease_to(_haze, "color:a", 0.22, 6.0)
		ease_to(sun, "light_color", Color(1.0, 0.85, 0.65), 6.0)
		ease_to(self, "day", 1200.0, 7.0)
		ease_to(_aqi, "value", 172.0, 6.5))

	# 4. Traffic, poisoned air and water
	at(20.0, func() -> void:
		shot(-2.0, 7.0, 22.0, 2.5)
		world.start_traffic()
		say("Cars crowded every road. The air and water turned to poison.", 5.0)
		world.spread_poison(15.0, 8.0)
		ease_to(_haze, "color", Color(0.42, 0.42, 0.22, 0.38), 7.0)
		ease_to(env, "background_color", Color(0.55, 0.52, 0.4), 7.0)
		ease_to(sun, "light_energy", 0.65, 7.0)
		ease_to(synth, "wind", 0.3, 4.0)
		ease_to(self, "day", 2000.0, 8.0)
		ease_to(_aqi, "value", 318.0, 7.0))

	# 5. Struggling lungs
	at(28.0, func() -> void:
		ease_to(_dim, "color:a", 0.72, 1.2)
		ease_to(_lungs, "modulate:a", 1.0, 1.2)
		say("Every breath became harder.", 3.0)
		ease_to(_lungs, "health", 0.12, 8.0)
		ease_to(synth, "heart", 0.85, 2.0)
		synth.heart_bpm = 72.0
		ease_to(synth, "heart_bpm", 112.0, 8.0)
		ease_to(synth, "hum", 0.25, 2.0)
		ease_to(self, "day", 2600.0, 8.0)
		ease_to(_aqi, "value", 462.0, 8.0))
	at(31.0, func() -> void: _lungs.cough = 1.0)
	at(32.4, func() -> void: say("Today, 9 out of 10 people on Earth breathe polluted air.", 3.6))
	at(34.6, func() -> void: _lungs.cough = 1.0)
	at(35.6, func() -> void: _lungs.cough = 0.8)
	at(36.6, func() -> void:
		ease_to(_dim, "color:a", 0.0, 1.0)
		ease_to(_lungs, "modulate:a", 0.0, 1.0)
		ease_to(synth, "heart", 0.0, 2.5))

	# 6. Animals lose their homes
	at(37.2, func() -> void:
		shot(0.0, 3.0, 30.0, 2.0)
		world.animals_leave(4.5)
		say("Animals and birds had nowhere left to live.", 4.3)
		ease_to(synth, "dark", 0.8, 4.0)
		ease_to(synth, "hum", 0.5, 3.0)
		ease_to(self, "day", 3000.0, 5.5))

	# 7. Earthquake
	at(43.0, func() -> void:
		say("Then the Earth shook...", 3.0)
		shake(1.0, 3.6)
		world.earthquake()
		synth.rumble = 1.0
		ease_to(synth, "rumble", 0.0, 4.5)
		ease_to(synth, "hum", 0.0, 2.0)
		flash(0.25, 0.4))

	# 8. Tsunami and storms
	at(47.5, func() -> void:
		shot(0.0, -3.0, 40.0, 2.0)
		say("...the oceans rose up, and storms grew stronger.", 5.0)
		world.tsunami(6.5)
		world.storm(true)
		ease_to(synth, "rain", 0.55, 2.0)
		ease_to(synth, "wind", 0.7, 3.0)
		synth.rumble = 0.5
		ease_to(synth, "rumble", 0.0, 6.0)
		ease_to(env, "background_color", Color(0.3, 0.32, 0.34), 3.0)
		ease_to(_haze, "color", Color(0.2, 0.22, 0.26, 0.35), 3.0)
		ease_to(sun, "light_energy", 0.35, 3.0)
		ease_to(self, "day", 3500.0, 7.0))
	at(48.6, func() -> void: lightning(-5.0, -8.0))
	at(50.4, func() -> void: lightning(6.0, 4.0))
	at(52.2, func() -> void: lightning(-2.0, 10.0))
	at(53.9, func() -> void: lightning(4.0, -14.0))

	# 9. Darkness
	at(55.5, func() -> void:
		shot(0.0, 2.0, 34.0, 4.0)
		say("Day 3,650.\nIs this the future we want?", 5.2)
		ease_to(_aqi, "value", 999.0, 4.0)
		ease_to(self, "day", 3650.0, 3.0)
		ease_to(sun, "light_energy", 0.12, 4.0)
		ease_to(env, "ambient_light_energy", 0.2, 4.0)
		ease_to(env, "background_color", Color(0.12, 0.12, 0.14), 4.0)
		ease_to(_haze, "color", Color(0.05, 0.05, 0.07, 0.45), 4.0)
		ease_to(synth, "rain", 0.25, 3.0)
		ease_to(synth, "wind", 0.35, 3.0)
		ease_to(synth, "pad", 0.35, 3.0)
		synth.heart_bpm = 48.0
		ease_to(synth, "heart", 0.6, 2.0))
	at(57.8, func() -> void: lightning(-6.0, 6.0))

	# 10. Silence
	at(62.0, func() -> void:
		ease_to(_fade, "color:a", 1.0, 2.0)
		ease_to(synth, "rain", 0.0, 2.0)
		ease_to(synth, "wind", 0.0, 2.0)
		ease_to(synth, "heart", 0.0, 2.0)
		ease_to(synth, "pad", 0.0, 2.0))

	# 11. Hope
	at(64.5, func() -> void:
		world.storm(false)
		for c in world.get_children():
			if c != world.hope_set and c is Node3D:
				(c as Node3D).visible = false
		world.hope_set.visible = true
		rig.position = world.hope_set.position
		cam.size = 6.5
		env.background_color = Color(0.05, 0.07, 0.08)
		env.ambient_light_energy = 0.35
		sun.light_energy = 0.4
		sun.light_color = Color(1.0, 0.92, 0.75)
		_haze.color.a = 0.0
		_day_label.modulate.a = 0.0
		_planet_label.modulate.a = 0.0
		_aqi.modulate.a = 0.0
		ease_to(_fade, "color:a", 0.0, 2.5)
		synth.dark = 0.0
		ease_to(synth, "pad", 0.6, 3.0)
		synth.chime())
	at(65.8, func() -> void: say("But it's not too late.", 3.4))
	at(70.0, func() -> void:
		say("Every tree you plant helps heal our Earth.", 4.0)
		var sap := world.hope_set.get_node("Sapling") as Node3D
		ease_to(sap, "scale", Vector3.ONE * 1.6, 4.0)
		ease_to(cam, "size", 5.4, 6.0))
	at(75.2, func() -> void:
		_skip.visible = false
		_hope_tag.text = "Let's bring nature back, together."
		ease_to(_hope_tag, "modulate:a", 1.0, 1.0)
		_cta.visible = true
		_cta.modulate.a = 0.0
		ease_to(_cta, "modulate:a", 1.0, 0.8)
		synth.chime())
	_events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


# ------------------------------------------------------------------ runtime

func _process(delta: float) -> void:
	_t += delta
	while _next_event < _events.size() and _t >= float(_events[_next_event][0]):
		var fn: Callable = _events[_next_event][1]
		_next_event += 1
		fn.call()
	_day_label.text = "DAY %s" % _commas(int(day))
	# Camera shake
	if _t < _shake_until:
		cam.h_offset = randf_range(-1.0, 1.0) * _shake * 0.45
		cam.v_offset = randf_range(-1.0, 1.0) * _shake * 0.3
	else:
		cam.h_offset = lerpf(cam.h_offset, 0.0, 0.3)
		cam.v_offset = lerpf(cam.v_offset, 0.0, 0.3)
	if _shots_dir != "" and _next_shot < SHOT_TIMES.size() and _t >= float(SHOT_TIMES[_next_shot]):
		_take_shot("%s/intro_%02d.png" % [_shots_dir, _next_shot])
		_next_shot += 1
		if _next_shot >= SHOT_TIMES.size():
			await get_tree().create_timer(0.5).timeout
			get_tree().quit()


func _take_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("intro shot: ", path)


func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_finish()


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	_skip.visible = false
	GameState.intro_seen = true
	GameState.save_game()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_fade, "color:a", 1.0, 0.8)
	tw.tween_property(synth, "master", 0.0, 0.8)
	tw.chain().tween_callback(func() -> void: get_tree().change_scene_to_file(MAIN_SCENE))
