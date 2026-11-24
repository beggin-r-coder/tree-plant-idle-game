class_name HUD
extends CanvasLayer
## All 2D UI, built in code: stats bar, plant list, shop, milestone bar and
## "eco fact" popups that teach kids something at every milestone.

const PANEL_BG := Color(0.08, 0.2, 0.12, 0.82)
const CARD_BG := Color(1, 1, 1, 0.07)
const GOLD := Color(1.0, 0.86, 0.3)
const TOAST_TIME := 8.0

var _root: Control
var _coins_label: Label
var _cps_label: Label
var _trees_label: Label
var _co2_label: Label
var _stage_label: Label
var _milestone_label: Label
var _milestone_bar: ProgressBar
var _hint_label: Label

var _plant_cards: Array[PanelContainer] = []
var _plant_counts: Array[Label] = []
var _plant_bars: Array[ProgressBar] = []
var _plant_buttons: Array[Button] = []

var _click_title: Label
var _click_btn: Button
var _fert_title: Label
var _fert_btn: Button
var _machine_rows: Array[Control] = []
var _machine_titles: Array[Label] = []
var _machine_descs: Array[Label] = []
var _machine_btns: Array[Button] = []

var _toast: PanelContainer
var _toast_title: Label
var _toast_body: Label
var _toast_queue: Array[Dictionary] = []
var _toast_timer := 0.0
var _refresh_timer := 0.0
var _confirm: ConfirmationDialog


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_build_top_bar()
	_build_plants_panel()
	_build_shop_panel()
	_build_bottom()
	_build_toast()
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Start over?"
	_confirm.dialog_text = "This erases your forest and coins. Are you sure?"
	_confirm.confirmed.connect(GameState.reset_game)
	_root.add_child(_confirm)

	GameState.stage_changed.connect(_on_stage_changed)
	GameState.plant_unlocked.connect(_on_plant_unlocked)
	GameState.game_reset.connect(func() -> void: show_toast("A fresh start!", GameData.STAGES[0]["fact"]))
	_refresh()

	if GameState.total_trees == 0:
		var st: Dictionary = GameData.STAGES[0]
		show_toast(st["title"], st["fact"])
	if not GameState.offline_report.is_empty():
		var r := GameState.offline_report
		show_toast("Welcome back!", "While you were away (%s), your Auto-Planters grew %s trees and earned %s coins." % [
			_format_time(r["seconds"]), GameData.format_number(r["trees"]), GameData.format_number(r["coins"])])


# ------------------------------------------------------------------ building

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.25, 0.62, 0.3)
	btn.set_corner_radius_all(10)
	btn.set_content_margin_all(8)
	var hover := btn.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.32, 0.72, 0.36)
	var pressed := btn.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.2, 0.5, 0.25)
	var disabled := btn.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.35, 0.38, 0.36, 0.8)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_disabled_color", "Button", Color(0.8, 0.8, 0.8, 0.7))
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0.35)
	bar_bg.set_corner_radius_all(6)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.55, 0.9, 0.35)
	bar_fill.set_corner_radius_all(6)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	return t


func _panel(color: Color = PANEL_BG, radius: int = 14, margin: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _label(text: String, size: int = 17, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _build_top_bar() -> void:
	var bar := _panel()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 12
	bar.offset_right = -12
	bar.offset_top = 10
	_root.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 28)
	bar.add_child(h)
	var coins_box := VBoxContainer.new()
	coins_box.add_theme_constant_override("separation", -4)
	_coins_label = _label("0 coins", 30, GOLD)
	_cps_label = _label("0 / sec", 15, Color(1, 1, 1, 0.8))
	coins_box.add_child(_coins_label)
	coins_box.add_child(_cps_label)
	h.add_child(coins_box)
	_trees_label = _label("Trees: 0", 20)
	_co2_label = _label("CO2 cleaned: 0 kg/yr", 20, Color(0.75, 0.95, 1.0))
	_stage_label = _label("Barren Land", 22, Color(0.7, 1.0, 0.6))
	h.add_child(_trees_label)
	h.add_child(_co2_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	h.add_child(_stage_label)
	var reset := Button.new()
	reset.text = "Restart"
	reset.tooltip_text = "Erase progress and start a new forest"
	reset.pressed.connect(func() -> void: _confirm.popup_centered())
	h.add_child(reset)
	for c in h.get_children():
		if c is Label:
			(c as Label).size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _build_plants_panel() -> void:
	var panel := _panel()
	panel.anchor_top = 0
	panel.anchor_bottom = 1
	panel.offset_left = 12
	panel.offset_top = 92
	panel.offset_right = 292
	panel.offset_bottom = -110
	_root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	v.add_child(_label("Your Plants", 22, Color(0.8, 1.0, 0.7)))
	for i in GameData.PLANTS.size():
		var data: Dictionary = GameData.PLANTS[i]
		var card := _panel(CARD_BG, 10, 8)
		v.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		card.add_child(cv)
		var row := HBoxContainer.new()
		cv.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = TreeFactory.plant_color(data["id"])
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var name_label := _label("Lv%d  %s" % [i + 1, data["name"]], 17)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var count := _label("0", 16, Color(1, 1, 1, 0.8))
		row.add_child(count)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		bar.max_value = 1.0
		cv.add_child(bar)
		var btn := Button.new()
		btn.pressed.connect(_on_plant_button.bind(i))
		cv.add_child(btn)
		_plant_cards.append(card)
		_plant_counts.append(count)
		_plant_bars.append(bar)
		_plant_buttons.append(btn)


func _build_shop_panel() -> void:
	var panel := _panel()
	panel.anchor_left = 1
	panel.anchor_right = 1
	panel.anchor_bottom = 1
	panel.offset_left = -372
	panel.offset_right = -12
	panel.offset_top = 92
	panel.offset_bottom = -110
	_root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	v.add_child(_label("Shop", 22, Color(0.8, 1.0, 0.7)))

	var r1 := _shop_row(v)
	_click_title = r1[0]
	_click_btn = r1[2]
	(r1[1] as Label).text = "Each click grows trees faster."
	_click_btn.pressed.connect(func() -> void: GameState.try_buy_click_upgrade(); _refresh())
	var r2 := _shop_row(v)
	_fert_title = r2[0]
	_fert_btn = r2[2]
	(r2[1] as Label).text = "Natural compost: ALL trees grow +25% faster."
	_fert_btn.pressed.connect(func() -> void: GameState.try_buy_fert_upgrade(); _refresh())

	v.add_child(_label("Auto-Planters", 20, Color(0.8, 1.0, 0.7)))
	for i in GameData.PLANTS.size():
		var r := _shop_row(v)
		_machine_rows.append(r[3])
		_machine_titles.append(r[0])
		_machine_descs.append(r[1])
		_machine_btns.append(r[2])
		(r[2] as Button).pressed.connect(func() -> void: GameState.try_buy_machine(i); _refresh())


## Returns [title Label, description Label, Button, card].
func _shop_row(parent: Control) -> Array:
	var card := _panel(CARD_BG, 10, 8)
	parent.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	card.add_child(h)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	h.add_child(tv)
	var title := _label("", 16)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(170, 0)
	var desc := _label("", 13, Color(1, 1, 1, 0.75))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(170, 0)
	tv.add_child(title)
	tv.add_child(desc)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(100, 44)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(btn)
	return [title, desc, btn, card]


func _build_bottom() -> void:
	var panel := _panel()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1
	panel.anchor_bottom = 1
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -98
	panel.offset_bottom = -12
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	_hint_label = _label("", 18, Color(1, 1, 0.85))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_hint_label)
	_milestone_label = _label("", 15, Color(0.8, 1.0, 0.7))
	_milestone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_milestone_label)
	_milestone_bar = ProgressBar.new()
	_milestone_bar.show_percentage = false
	_milestone_bar.custom_minimum_size = Vector2(0, 14)
	_milestone_bar.max_value = 1.0
	v.add_child(_milestone_bar)


func _build_toast() -> void:
	_toast = _panel(Color(0.98, 0.96, 0.86, 0.96), 16, 16)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -290
	_toast.offset_right = 290
	_toast.offset_top = 96
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.visible = false
	_toast.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_toast_timer = 0.0)
	_root.add_child(_toast)
	var v := VBoxContainer.new()
	_toast.add_child(v)
	_toast_title = _label("", 24, Color(0.15, 0.45, 0.15))
	_toast_title.add_theme_constant_override("outline_size", 0)
	_toast_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_body = _label("", 17, Color(0.2, 0.2, 0.2))
	_toast_body.add_theme_constant_override("outline_size", 0)
	_toast_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_body.custom_minimum_size = Vector2(540, 0)
	var tap := _label("(tap to close)", 12, Color(0.4, 0.4, 0.4))
	tap.add_theme_constant_override("outline_size", 0)
	tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_toast_title)
	v.add_child(_toast_body)
	v.add_child(tap)


# ------------------------------------------------------------------ runtime

func show_toast(title: String, body: String) -> void:
	_toast_queue.append({"title": title, "body": body})
	if not _toast.visible:
		_next_toast()


func _next_toast() -> void:
	if _toast_queue.is_empty():
		_toast.visible = false
		return
	var t: Dictionary = _toast_queue.pop_front()
	_toast_title.text = t["title"]
	_toast_body.text = t["body"]
	_toast.visible = true
	_toast.modulate.a = 0.0
	_toast.scale = Vector2.ONE
	create_tween().tween_property(_toast, "modulate:a", 1.0, 0.3)
	_toast_timer = TOAST_TIME


func _process(delta: float) -> void:
	if _toast.visible:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_next_toast()
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.1
		_refresh()


func _refresh() -> void:
	var gs := GameState
	_coins_label.text = "%s coins" % GameData.format_number(gs.coins)
	_cps_label.text = "+%s coins / sec from machines" % GameData.format_number(gs.coins_per_second())
	_trees_label.text = "Trees planted: %s" % GameData.format_number(gs.total_trees)
	_co2_label.text = "CO2 cleaned: ~%s kg/year" % GameData.format_number(gs.co2_per_year())
	_stage_label.text = "Ecosystem: %s" % GameData.STAGES[gs.stage]["name"]

	var sel_name: String = GameData.PLANTS[gs.selected]["name"]
	_hint_label.text = "Click anywhere to help your %s grow!  (+%s per click)" % [sel_name, GameData.format_number(gs.click_power() * gs.growth_multiplier())]
	var next := gs.next_stage_trees()
	if next < 0:
		_milestone_label.text = "Every milestone reached! Your ecosystem is complete."
		_milestone_bar.value = 1.0
	else:
		var prev: int = GameData.STAGES[gs.stage]["trees"]
		var next_name: String = GameData.STAGES[gs.stage + 1]["name"]
		_milestone_label.text = "Next milestone: %s  (%d / %d trees)" % [next_name, gs.total_trees, next]
		_milestone_bar.value = clampf(float(gs.total_trees - prev) / float(next - prev), 0.0, 1.0)

	for i in GameData.PLANTS.size():
		var data: Dictionary = GameData.PLANTS[i]
		var unlocked: bool = gs.unlocked[i]
		var btn := _plant_buttons[i]
		_plant_bars[i].visible = unlocked
		_plant_counts[i].text = "x%s" % GameData.format_number(gs.trees_per_type[i]) if unlocked else ""
		if unlocked:
			_plant_bars[i].value = gs.progress[i] / gs.growth_needed(i)
			var selected := gs.selected == i
			btn.text = "Growing (+%s each)" % GameData.format_number(gs.reward(i)) if selected else "Grow this (+%s each)" % GameData.format_number(gs.reward(i))
			btn.disabled = selected
		else:
			btn.text = "Unlock: %s coins" % GameData.format_number(data["unlock_cost"])
			btn.disabled = gs.coins < gs.unlock_cost(i)
		var sb := _plant_cards[i].get_theme_stylebox("panel") as StyleBoxFlat
		sb.bg_color = Color(1, 0.95, 0.5, 0.22) if gs.selected == i else CARD_BG

	_click_title.text = "Watering Can  Lv %d" % gs.click_level
	_click_btn.text = "%s" % GameData.format_number(gs.click_upgrade_cost())
	_click_btn.disabled = gs.coins < gs.click_upgrade_cost()
	_fert_title.text = "Compost  Lv %d" % gs.fert_level
	_fert_btn.text = "%s" % GameData.format_number(gs.fert_upgrade_cost())
	_fert_btn.disabled = gs.coins < gs.fert_upgrade_cost()

	for i in GameData.PLANTS.size():
		var data: Dictionary = GameData.PLANTS[i]
		var lvl: int = gs.machine_level[i]
		_machine_rows[i].visible = gs.unlocked[i]
		_machine_titles[i].text = "%s Planter  Lv %d" % [data["name"], lvl]
		if lvl == 0:
			_machine_descs[i].text = "Plants %s trees for you, even while you're away!" % data["name"]
		else:
			_machine_descs[i].text = "%s trees/min  (x2 speed every 10 levels)" % _fmt_rate(gs.trees_per_second(i) * 60.0)
		_machine_btns[i].text = ("Buy\n%s" if lvl == 0 else "Upgrade\n%s") % GameData.format_number(gs.machine_cost(i))
		_machine_btns[i].disabled = gs.coins < gs.machine_cost(i)


func _fmt_rate(v: float) -> String:
	if v < 10.0:
		return "%.1f" % v
	return GameData.format_number(v)


func _format_time(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%dh %dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm" % (s / 60)
	return "%ds" % s


# ------------------------------------------------------------------ events

func _on_plant_button(i: int) -> void:
	if GameState.unlocked[i]:
		GameState.select_plant(i)
	else:
		GameState.try_unlock(i)
	_refresh()


func _on_plant_unlocked(i: int) -> void:
	var data: Dictionary = GameData.PLANTS[i]
	show_toast("New plant: %s!" % data["name"], data["fact"])


func _on_stage_changed(stage: int) -> void:
	var st: Dictionary = GameData.STAGES[stage]
	show_toast(st["title"], st["fact"])
