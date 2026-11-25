extends Node3D
## Entry point: sets up lighting, the world, the camera and the HUD, and turns
## taps into tree growth.
##
## Dev command-line flags (after `--`):
##   --fresh     start without loading the save file (this also replays the intro, if enabled)
##   --no-intro  skip the intro cinematic (it is currently disabled: GameData.INTRO_ENABLED)
##   --autotest  fast-forward through every milestone (for testing visuals)
##   --shot=PATH save a screenshot to PATH (after the autotest, or after 2.5s) and quit
##   --until=N   stop the autotest at N trees
##   --showcase  trigger the golden butterfly, flying coins and confetti before the screenshot
##   --shop      open the shop before taking the screenshot
##   --zoom=N    start with camera size N (bigger = further away)

var world: World
var cam: IsoCamera
var hud: HUD
var env: Environment
var sun: DirectionalLight3D
var audio: GameAudio
var bonus: GoldenBonus


func _ready() -> void:
	# First launch: play the intro cinematic first.
	var args := OS.get_cmdline_user_args()
	var dev_run := args.has("--autotest") or args.has("--no-intro") or _shot_path() != ""
	if GameData.INTRO_ENABLED and not GameState.intro_seen and not dev_run:
		get_tree().change_scene_to_file.call_deferred("res://scenes/intro.tscn")
		return
	_build_environment()
	world = World.new()
	world.name = "World"
	add_child(world)
	world.build()
	cam = IsoCamera.new()
	cam.name = "IsoCamera"
	add_child(cam)
	cam.focus(world.forest.center + Terrain.TOWARD * -3.0)
	cam.tapped.connect(_on_tap)
	audio = GameAudio.new()
	audio.name = "Audio"
	add_child(audio)
	bonus = GoldenBonus.new()
	bonus.name = "GoldenBonus"
	bonus.world = world
	add_child(bonus)
	bonus.collected.connect(_on_bonus)
	hud = HUD.new()
	hud.name = "HUD"
	hud.camera = cam.camera
	hud.audio = audio
	add_child(hud)
	world.forest.tree_grown.connect(_on_tree_grown)
	GameState.clicked.connect(_on_clicked)
	GameState.selected_changed.connect(func(i: int) -> void: cam.glide_to(world.forest.sapling_position(i), true))
	GameState.stage_changed.connect(_on_stage_changed)
	GameState.game_reset.connect(func() -> void: get_tree().reload_current_scene())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zoom="):
			cam._target_size = float(a.substr(7))
			cam.camera.size = cam._target_size
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


func _on_tap(pos: Vector2) -> void:
	if bonus.try_collect(pos, cam.camera):
		return
	GameState.click_grow()


func _on_clicked(i: int) -> void:
	# The "pop" rises in pitch as the sapling grows: you can hear it getting close.
	var p := clampf(GameState.progress[i] / GameState.growth_needed(i), 0.0, 1.0)
	audio.play("pop", 0.85 + p * 0.6 + randf_range(-0.03, 0.03), -4.0)
	Input.vibrate_handheld(8)


func _on_tree_grown(i: int, pos: Vector3, earned: float) -> void:
	var selected := i == GameState.selected
	# Drones can finish trees many times a second, so keep their sounds/coins light.
	audio.play("grow", randf_range(0.95, 1.08), 0.0 if selected else -10.0, 0.08 if selected else 0.6)
	if selected or cam.is_on_screen(pos):
		hud.fly_coins(pos, earned)
	if selected:
		Input.vibrate_handheld(25)
		# Follow the forest edge: if the next sapling is off-screen, glide to it.
		var next := world.forest.sapling_position(i)
		if next != Vector3.INF and not cam.is_on_screen(next):
			cam.glide_to(next)


func _on_bonus(amount: float, at: Vector3) -> void:
	audio.play("bonus")
	hud.fly_coins(at, amount * 1000.0)
	hud.show_toast("Golden butterfly!  +%s coins" % GameData.format_number(amount), bonus.next_fact())


func _on_stage_changed(stage: int) -> void:
	create_tween().tween_property(env, "background_color", GameData.STAGES[stage]["sky"], 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_SPACE:
			GameState.click_grow()


# ------------------------------------------------------------------ dev tools

func _run_autotest() -> void:
	print("[autotest] starting")
	GameState.add_coins(5.0)
	for k in 15:
		GameState.click_grow()
	await get_tree().create_timer(1.0).timeout
	GameState.add_coins(1e7)
	for i in GameData.PLANTS.size():
		GameState.try_unlock(i)
		GameState.try_buy_machine(i)
		GameState.try_buy_machine(i)
	GameState.try_buy_click_upgrade()
	GameState.try_buy_fert_upgrade()
	var until := 100000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--until="):
			until = int(a.substr(8))
	for target in [5, 20, 50, 100, 200, 400, 800]:
		target = mini(target, until)
		await get_tree().create_timer(0.6).timeout
		var i := randi() % GameData.PLANTS.size()
		while GameState.total_trees < target:
			GameState._add_growth(i, GameState.growth_needed(i) * 3.0 / GameState.growth_multiplier(), true)
			i = (i + 1) % GameData.PLANTS.size()
		if target >= until:
			print("[autotest] stopped at %d trees" % GameState.total_trees)
			break
		print("[autotest] stage=%d trees=%d visible=%d coins=%.0f" % [GameState.stage, GameState.total_trees, world.forest.total_visible(), GameState.coins])
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
	if OS.get_cmdline_user_args().has("--showcase"):
		# Trigger the "juice" so a screenshot can show it: golden butterfly, flying coins, confetti.
		bonus._timer = 0.0
		await get_tree().create_timer(2.5).timeout
		hud.confetti()
		for k in 3:
			GameState.click_grow()
		hud.fly_coins(world.forest.sapling_position(GameState.selected), 500.0)
		await get_tree().create_timer(0.45).timeout
	if OS.get_cmdline_user_args().has("--shop"):
		hud.open_shop()
		await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot)
	print("screenshot saved: ", shot)
