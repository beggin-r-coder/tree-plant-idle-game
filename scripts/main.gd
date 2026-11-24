extends Node3D
## Entry point: sets up lighting, the world, the camera and the HUD, and turns
## clicks/taps into tree growth.
##
## Dev command-line flags (after `--`):
##   --fresh     start without loading the save file
##   --autotest  fast-forward through every milestone (for testing visuals)
##   --shot=PATH save a screenshot to PATH (after the autotest, or after 2.5s) and quit

var world: World
var cam: IsoCamera
var hud: HUD
var env: Environment
var sun: DirectionalLight3D


func _ready() -> void:
	_build_environment()
	world = World.new()
	world.name = "World"
	add_child(world)
	world.build()
	cam = IsoCamera.new()
	cam.name = "IsoCamera"
	add_child(cam)
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	GameState.stage_changed.connect(_on_stage_changed)
	GameState.game_reset.connect(func() -> void: env.background_color = GameData.STAGES[0]["sky"])
	if OS.get_cmdline_user_args().has("--autotest"):
		_run_autotest()
	elif _shot_path() != "":
		await get_tree().create_timer(2.5).timeout
		await _save_shot()
		get_tree().quit()


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = GameData.STAGES[GameState.stage]["sky"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.85)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


func _on_stage_changed(stage: int) -> void:
	create_tween().tween_property(env, "background_color", GameData.STAGES[stage]["sky"], 2.0)


func _unhandled_input(event: InputEvent) -> void:
	var press_pos := Vector2.INF
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			press_pos = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			press_pos = st.position
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_SPACE:
			GameState.click_grow()
			return
	if press_pos == Vector2.INF:
		return
	# Clicking a plantation plot switches to that plant; anywhere else just grows.
	var ground: Variant = cam.screen_to_ground(press_pos)
	if ground != null:
		var z := world.zone_at(ground)
		if z != null:
			if not z.is_unlocked():
				var data: Dictionary = GameData.PLANTS[z.plant_index]
				hud.show_toast("%s is locked" % data["name"], "Save up %s coins and unlock it from the plants list on the left." % GameData.format_number(data["unlock_cost"]))
				return
			GameState.select_plant(z.plant_index)
	GameState.click_grow()


# ------------------------------------------------------------------ dev tools

func _run_autotest() -> void:
	print("[autotest] starting")
	GameState.add_coins(5.0)
	for k in 15:
		GameState.click_grow()
	GameState.add_coins(1e7)
	for i in GameData.PLANTS.size():
		GameState.try_unlock(i)
		GameState.try_buy_machine(i)
		GameState.try_buy_machine(i)
	GameState.try_buy_click_upgrade()
	GameState.try_buy_fert_upgrade()
	for target in [5, 20, 50, 100, 200, 400, 800]:
		await get_tree().create_timer(0.6).timeout
		var i := randi() % GameData.PLANTS.size()
		while GameState.total_trees < target:
			GameState._add_growth(i, GameState.growth_needed(i) * 7.0 / GameState.growth_multiplier(), true)
			i = (i + 1) % GameData.PLANTS.size()
		print("[autotest] stage=%d trees=%d coins=%.0f" % [GameState.stage, GameState.total_trees, GameState.coins])
	await get_tree().create_timer(4.0).timeout
	GameState.save_game()
	print("[autotest] animals=%d features=%s" % [world.animals_root.get_child_count(), str(world.features.keys())])
	await _save_shot()
	print("[autotest] done")
	get_tree().quit()


func _shot_path() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			return a.substr(7)
	return ""


func _save_shot() -> void:
	var shot := _shot_path()
	if shot == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot)
	print("screenshot saved: ", shot)
