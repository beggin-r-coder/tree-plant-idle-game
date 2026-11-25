extends Node
## Global game state (autoload "GameState"): coins, plants, machines, upgrades,
## ecosystem stage, saving/loading and offline progress.
## The 3D world and HUD only *listen* to these signals, so the economy can be
## tested and rebalanced independently of the visuals.

signal coins_changed(coins: float)
signal clicked(plant_index: int)
signal trees_completed(plant_index: int, count: int, reward: float, by_machine: bool)
signal plant_unlocked(plant_index: int)
signal machine_changed(plant_index: int)
signal upgrades_changed
signal selected_changed(plant_index: int)
signal stage_changed(stage: int)
signal game_reset

const SAVE_PATH := "user://save.json"
const AUTOSAVE_INTERVAL := 10.0

var coins: float = 0.0
var total_trees: int = 0
var trees_per_type: Array[int] = []
var progress: Array[float] = []      ## current growth points of the growing tree per plant type
var unlocked: Array[bool] = []
var machine_level: Array[int] = []
var click_level: int = 0
var fert_level: int = 0
var stage: int = 0
var selected: int = 0
var lifetime_coins: float = 0.0
## Where every visible tree stands: flat list of (plant_index, x, z). Written by Forest.
var forest_layout := PackedFloat32Array()
## True once the intro cinematic has been watched (or skipped). Survives "Restart game".
var intro_seen := false
## Player setting: sound on/off. Survives "Restart game".
var sound_on := true

## Filled after loading if machines worked while the game was closed.
var offline_report: Dictionary = {}

var _autosave_timer := 0.0


func _ready() -> void:
	_reset_values()
	if not OS.get_cmdline_user_args().has("--fresh"):
		load_game()


func _reset_values() -> void:
	var n := GameData.PLANTS.size()
	coins = 0.0
	total_trees = 0
	click_level = 0
	fert_level = 0
	stage = 0
	selected = 0
	lifetime_coins = 0.0
	forest_layout = PackedFloat32Array()
	trees_per_type.clear()
	progress.clear()
	unlocked.clear()
	machine_level.clear()
	for i in n:
		trees_per_type.append(0)
		progress.append(0.0)
		unlocked.append(i == 0)
		machine_level.append(0)


func _process(delta: float) -> void:
	for i in GameData.PLANTS.size():
		if unlocked[i] and machine_level[i] > 0:
			_add_growth(i, machine_rate(i) * delta, true)
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()


# ---------------------------------------------------------------- formulas

func growth_needed(i: int) -> float:
	return GameData.PLANTS[i]["growth"]


func reward(i: int) -> float:
	return GameData.PLANTS[i]["reward"]


func growth_multiplier() -> float:
	return pow(GameData.FERT_MULT, fert_level)


func click_power() -> float:
	return 1.0 + click_level * 1.0 + floorf(click_level / 5.0) * 2.0


func click_upgrade_cost() -> float:
	return GameData.CLICK_BASE_COST * pow(GameData.CLICK_COST_GROWTH, click_level)


func fert_upgrade_cost() -> float:
	return GameData.FERT_BASE_COST * pow(GameData.FERT_COST_GROWTH, fert_level)


func unlock_cost(i: int) -> float:
	return GameData.PLANTS[i]["unlock_cost"]


func machine_cost(i: int) -> float:
	var base: float = GameData.PLANTS[i]["auto_cost"]
	return base * pow(GameData.AUTO_COST_GROWTH, machine_level[i])


## Growth points per second added by the machine (before fertilizer).
func machine_rate(i: int) -> float:
	var lvl := machine_level[i]
	if lvl <= 0:
		return 0.0
	var base: float = GameData.PLANTS[i]["auto_rate"]
	# Every 10 levels the machine doubles its speed: a classic idle-game milestone.
	return base * lvl * pow(2.0, floorf(lvl / 10.0))


func trees_per_second(i: int) -> float:
	return machine_rate(i) * growth_multiplier() / growth_needed(i)


func coins_per_second() -> float:
	var total := 0.0
	for i in GameData.PLANTS.size():
		total += trees_per_second(i) * reward(i)
	return total


func co2_per_year() -> float:
	var total := 0.0
	for i in GameData.PLANTS.size():
		var per_tree: float = GameData.PLANTS[i]["co2"]
		total += trees_per_type[i] * per_tree
	return total


func next_stage_trees() -> int:
	if stage + 1 >= GameData.STAGES.size():
		return -1
	return GameData.STAGES[stage + 1]["trees"]


# ---------------------------------------------------------------- actions

## Player clicked/tapped: grow the selected tree.
func click_grow() -> void:
	if not unlocked[selected]:
		selected = 0
	_add_growth(selected, click_power(), false)
	clicked.emit(selected)


func select_plant(i: int) -> void:
	if i >= 0 and i < unlocked.size() and unlocked[i] and i != selected:
		selected = i
		selected_changed.emit(i)


func try_unlock(i: int) -> bool:
	if unlocked[i] or coins < unlock_cost(i):
		return false
	_spend(unlock_cost(i))
	unlocked[i] = true
	plant_unlocked.emit(i)
	select_plant(i)
	return true


func try_buy_machine(i: int) -> bool:
	if not unlocked[i] or coins < machine_cost(i):
		return false
	_spend(machine_cost(i))
	machine_level[i] += 1
	machine_changed.emit(i)
	return true


func try_buy_click_upgrade() -> bool:
	if coins < click_upgrade_cost():
		return false
	_spend(click_upgrade_cost())
	click_level += 1
	upgrades_changed.emit()
	return true


func try_buy_fert_upgrade() -> bool:
	if coins < fert_upgrade_cost():
		return false
	_spend(fert_upgrade_cost())
	fert_level += 1
	upgrades_changed.emit()
	return true


func add_coins(amount: float) -> void:
	coins += amount
	lifetime_coins += maxf(amount, 0.0)
	coins_changed.emit(coins)


func reset_game() -> void:
	_reset_values()
	offline_report = {}
	save_game()
	game_reset.emit()
	coins_changed.emit(coins)


# ---------------------------------------------------------------- internals

func _spend(amount: float) -> void:
	coins -= amount
	coins_changed.emit(coins)


func _add_growth(i: int, amount: float, by_machine: bool) -> void:
	progress[i] += amount * growth_multiplier()
	var need := growth_needed(i)
	if progress[i] < need:
		return
	var count := int(floor(progress[i] / need))
	progress[i] -= count * need
	_complete_trees(i, count, by_machine, true)


func _complete_trees(i: int, count: int, by_machine: bool, emit: bool) -> void:
	var earned := reward(i) * count
	trees_per_type[i] += count
	total_trees += count
	coins += earned
	lifetime_coins += earned
	if emit:
		trees_completed.emit(i, count, earned, by_machine)
		coins_changed.emit(coins)
	_check_stage(emit)


func _check_stage(emit: bool) -> void:
	while stage + 1 < GameData.STAGES.size() and total_trees >= int(GameData.STAGES[stage + 1]["trees"]):
		stage += 1
		if emit:
			stage_changed.emit(stage)


# ---------------------------------------------------------------- save / load

func save_game() -> void:
	var data := {
		"version": 1,
		"coins": coins,
		"total_trees": total_trees,
		"trees_per_type": trees_per_type,
		"progress": progress,
		"unlocked": unlocked,
		"machine_level": machine_level,
		"click_level": click_level,
		"fert_level": fert_level,
		"stage": stage,
		"selected": selected,
		"lifetime_coins": lifetime_coins,
		"forest_layout": Array(forest_layout),
		"intro_seen": intro_seen,
		"sound_on": sound_on,
		"time": Time.get_unix_time_from_system(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	coins = float(d.get("coins", 0.0))
	total_trees = int(d.get("total_trees", 0))
	click_level = int(d.get("click_level", 0))
	fert_level = int(d.get("fert_level", 0))
	stage = int(d.get("stage", 0))
	selected = int(d.get("selected", 0))
	lifetime_coins = float(d.get("lifetime_coins", 0.0))
	intro_seen = bool(d.get("intro_seen", false))
	sound_on = bool(d.get("sound_on", true))
	_load_array(d.get("trees_per_type", []), trees_per_type, TYPE_INT)
	_load_array(d.get("progress", []), progress, TYPE_FLOAT)
	_load_array(d.get("unlocked", []), unlocked, TYPE_BOOL)
	_load_array(d.get("machine_level", []), machine_level, TYPE_INT)
	var layout: Variant = d.get("forest_layout", [])
	if typeof(layout) == TYPE_ARRAY:
		forest_layout = PackedFloat32Array(layout as Array)
	unlocked[0] = true
	if not unlocked[selected]:
		selected = 0
	_apply_offline_progress(float(d.get("time", 0.0)))


func _load_array(src: Variant, dst: Array, type: int) -> void:
	if typeof(src) != TYPE_ARRAY:
		return
	var arr: Array = src
	for i in mini(arr.size(), dst.size()):
		match type:
			TYPE_INT: dst[i] = int(arr[i])
			TYPE_FLOAT: dst[i] = float(arr[i])
			TYPE_BOOL: dst[i] = bool(arr[i])


func _apply_offline_progress(saved_time: float) -> void:
	if saved_time <= 0.0:
		return
	var elapsed := clampf(Time.get_unix_time_from_system() - saved_time, 0.0, GameData.OFFLINE_CAP_SECONDS)
	if elapsed < 30.0:
		return
	var trees := 0
	var earned := 0.0
	for i in GameData.PLANTS.size():
		if not unlocked[i] or machine_level[i] <= 0:
			continue
		progress[i] += machine_rate(i) * growth_multiplier() * elapsed
		var count := int(floor(progress[i] / growth_needed(i)))
		if count > 0:
			progress[i] -= count * growth_needed(i)
			earned += reward(i) * count
			trees += count
			_complete_trees(i, count, true, false)
	if trees > 0:
		offline_report = {"seconds": elapsed, "trees": trees, "coins": earned}
