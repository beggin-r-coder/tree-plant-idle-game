class_name HUD
extends CanvasLayer
## Clean, minimal portrait UI:
##   top    : coins pill (left), forest stats pill (right), next-milestone bar
##   bottom : tray with round plant buttons + a Shop button
##   sheets : slide-up shop, eco-fact cards

const INK := Color(0.13, 0.27, 0.18)
const MUTED := Color(0.4, 0.47, 0.42)
const GREEN := Color(0.3, 0.7, 0.42)
const CARD := Color(1, 1, 1, 0.9)
const TOAST_TIME := 7.0

var _root: Control
var _coins_label: Label
var _cps_label: Label
var _trees_label: Label
var _co2_label: Label
var _milestone_label: Label
var _milestone_bar: ProgressBar
var _hint: Label
var _chips: Array[PlantChip] = []
var _shop_badge: Control

var _overlay: ColorRect
var _sheet: PanelContainer
var _sheet_open := false
var _rows: Array[Dictionary] = []   ## {kind, index, row, title, desc, btn, price}

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
	_build_top()
	_build_tray()
	_build_toast()
	_build_sheet()
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Start over?"
	_confirm.dialog_text = "This erases your forest and coins."
	_confirm.confirmed.connect(GameState.reset_game)
	_root.add_child(_confirm)

	GameState.stage_changed.connect(_on_stage_changed)
	GameState.plant_unlocked.connect(_on_plant_unlocked)
	_refresh()

	if GameState.total_trees == 0:
		var st: Dictionary = GameData.STAGES[0]
		show_toast(st["title"], st["fact"])
	if not GameState.offline_report.is_empty():
		var r := GameState.offline_report
		show_toast("Welcome back!", "While you were away (%s), your drones grew %s trees and earned %s coins." % [
			_format_time(r["seconds"]), GameData.format_number(r["trees"]), GameData.format_number(r["coins"])])


# ------------------------------------------------------------------ helpers

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	var btn := _box(GREEN, 24, 10)
	btn.content_margin_left = 16
	btn.content_margin_right = 16
	var hover := _box(GREEN.lightened(0.08), 24, 10)
	var pressed := _box(GREEN.darkened(0.12), 24, 10)
	var disabled := _box(Color(0.82, 0.85, 0.83), 24, 10)
	for b in [hover, pressed, disabled]:
		b.content_margin_left = 16
		b.content_margin_right = 16
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.9))
	t.set_stylebox("background", "ProgressBar", _box(Color(0, 0, 0, 0.1), 4, 0))
	t.set_stylebox("fill", "ProgressBar", _box(GREEN, 4, 0))
	var grabber := _box(Color(0, 0, 0, 0.15), 4, 0)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	t.set_stylebox("scroll", "HScrollBar", StyleBoxEmpty.new())
	t.set_stylebox("grabber", "HScrollBar", StyleBoxEmpty.new())
	return t


func _box(color: Color, radius: int, margin: int, shadow: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	if shadow:
		sb.shadow_color = Color(0, 0, 0, 0.12)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 3)
	return sb


func _panel(color: Color = CARD, radius: int = 24, margin: int = 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(color, radius, margin, true))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _label(text: String, size: int, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _hbox(sep: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _vbox(sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


# ------------------------------------------------------------------ building

func _build_top() -> void:
	# Coins (top-left)
	var coins := _panel(CARD, 28, 12)
	coins.position = Vector2(20, 24)
	coins.offset_left = 20
	coins.offset_top = 24
	coins.add_theme_stylebox_override("panel", _box(CARD, 28, 12, true))
	_root.add_child(coins)
	var ch := _hbox(10)
	coins.add_child(ch)
	ch.add_child(UIIcon.make("coin", 40))
	var cv := _vbox(-6)
	_coins_label = _label("0", 32)
	_cps_label = _label("", 15, MUTED)
	cv.add_child(_coins_label)
	cv.add_child(_cps_label)
	ch.add_child(cv)
	coins.custom_minimum_size = Vector2(190, 0)

	# Forest stats (top-right)
	var stats := _panel(CARD, 28, 12)
	stats.anchor_left = 1.0
	stats.anchor_right = 1.0
	stats.offset_right = -20
	stats.offset_left = -20
	stats.offset_top = 24
	stats.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.add_child(stats)
	var sv := _vbox(2)
	stats.add_child(sv)
	var r1 := _hbox(8)
	r1.add_child(UIIcon.make("leaf", 22))
	_trees_label = _label("0 trees", 19)
	r1.add_child(_trees_label)
	var r2 := _hbox(8)
	r2.add_child(UIIcon.make("cloud", 22))
	_co2_label = _label("0 kg CO2/yr", 15, MUTED)
	r2.add_child(_co2_label)
	sv.add_child(r1)
	sv.add_child(r2)

	# Next milestone (centered under the pills)
	var ms := _vbox(6)
	ms.anchor_left = 0.5
	ms.anchor_right = 0.5
	ms.offset_left = -170
	ms.offset_right = 170
	ms.offset_top = 112
	ms.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(ms)
	_milestone_label = _label("", 16, Color(1, 1, 1))
	_milestone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_milestone_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	_milestone_label.add_theme_constant_override("shadow_offset_y", 1)
	_milestone_label.add_theme_constant_override("shadow_outline_size", 3)
	_milestone_bar = ProgressBar.new()
	_milestone_bar.show_percentage = false
	_milestone_bar.custom_minimum_size = Vector2(0, 6)
	_milestone_bar.max_value = 1.0
	_milestone_bar.add_theme_stylebox_override("background", _box(Color(1, 1, 1, 0.45), 3, 0))
	_milestone_bar.add_theme_stylebox_override("fill", _box(Color(1, 1, 1, 0.95), 3, 0))
	_milestone_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ms.add_child(_milestone_label)
	ms.add_child(_milestone_bar)


func _build_tray() -> void:
	var tray := PanelContainer.new()
	var sb := _box(CARD, 0, 10, true)
	sb.corner_radius_top_left = 32
	sb.corner_radius_top_right = 32
	sb.content_margin_bottom = 22
	sb.content_margin_left = 12
	sb.content_margin_right = 16
	tray.add_theme_stylebox_override("panel", sb)
	tray.mouse_filter = Control.MOUSE_FILTER_STOP
	tray.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(tray)
	var h := _hbox(10)
	tray.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 108)
	h.add_child(scroll)
	var chips := _hbox(0)
	scroll.add_child(chips)
	for i in GameData.PLANTS.size():
		var data: Dictionary = GameData.PLANTS[i]
		var chip := PlantChip.new()
		chip.index = i
		chip.level = i + 1
		chip.label = data["short"]
		chip.color = TreeFactory.plant_color(data["id"])
		chip.pressed.connect(_on_chip)
		chips.add_child(chip)
		_chips.append(chip)

	# Round shop button
	var shop := Button.new()
	shop.custom_minimum_size = Vector2(76, 76)
	shop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state in ["normal", "hover", "pressed"]:
		var b := _box(GREEN if state != "pressed" else GREEN.darkened(0.12), 38, 0)
		shop.add_theme_stylebox_override(state, b)
	shop.pressed.connect(open_shop)
	h.add_child(shop)
	var icon := UIIcon.make("bag", 34)
	icon.size = Vector2(34, 34)
	icon.position = Vector2(21, 19)
	shop.add_child(icon)
	_shop_badge = Panel.new()
	_shop_badge.add_theme_stylebox_override("panel", _box(Color(1.0, 0.45, 0.35), 8, 0))
	_shop_badge.size = Vector2(16, 16)
	_shop_badge.position = Vector2(56, 4)
	_shop_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop.add_child(_shop_badge)

	_hint = _label("Tap anywhere to grow", 18, Color.WHITE)
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	_hint.add_theme_constant_override("shadow_outline_size", 4)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -190
	_hint.offset_bottom = -160
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hint)


func _build_toast() -> void:
	_toast = _panel(Color(1, 1, 1, 0.97), 24, 18)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_top = 156
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.visible = false
	_toast.gui_input.connect(_on_toast_input)
	_root.add_child(_toast)
	var v := _vbox(6)
	_toast.add_child(v)
	var th := _hbox(10)
	th.add_child(UIIcon.make("leaf", 26))
	_toast_title = _label("", 23, INK)
	_toast_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(_toast_title)
	_toast_body = _label("", 18, MUTED)
	_toast_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_body.custom_minimum_size = Vector2(560, 0)
	v.add_child(th)
	v.add_child(_toast_body)


func _build_sheet() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.3)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	_overlay.gui_input.connect(_on_overlay_input)
	_root.add_child(_overlay)

	_sheet = PanelContainer.new()
	var sb := _box(Color(0.97, 0.98, 0.97), 0, 22, true)
	sb.corner_radius_top_left = 32
	sb.corner_radius_top_right = 32
	sb.content_margin_bottom = 30
	_sheet.add_theme_stylebox_override("panel", sb)
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.anchor_left = 0
	_sheet.anchor_right = 1
	_sheet.anchor_top = 1
	_sheet.anchor_bottom = 1
	_sheet.offset_top = 0
	_sheet.offset_bottom = 0
	_sheet.visible = false
	_root.add_child(_sheet)
	var v := _vbox(12)
	_sheet.add_child(v)
	var header := _hbox(8)
	var title := _label("Shop", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.custom_minimum_size = Vector2(48, 48)
	for state in ["normal", "hover", "pressed"]:
		close.add_theme_stylebox_override(state, _box(Color(0, 0, 0, 0.06 if state == "normal" else 0.1), 24, 0))
	var x := UIIcon.make("close", 22, MUTED)
	x.position = Vector2(13, 13)
	close.add_child(x)
	close.pressed.connect(close_shop)
	header.add_child(close)
	v.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 620)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var list := _vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	list.add_child(_section("Upgrades"))
	_add_row(list, "click", 0, "drop", Color.WHITE)
	_add_row(list, "fert", 0, "sprout", Color.WHITE)
	list.add_child(_section("Planter Drones"))
	for i in GameData.PLANTS.size():
		_add_row(list, "drone", i, "drone", TreeFactory.plant_color(GameData.PLANTS[i]["id"]))
	var restart := Button.new()
	restart.text = "Restart game"
	restart.flat = true
	restart.add_theme_color_override("font_color", MUTED)
	restart.add_theme_color_override("font_hover_color", INK)
	restart.add_theme_font_size_override("font_size", 16)
	restart.pressed.connect(func() -> void: _confirm.popup_centered())
	var intro := Button.new()
	intro.text = "Watch intro"
	intro.flat = true
	intro.add_theme_color_override("font_color", MUTED)
	intro.add_theme_color_override("font_hover_color", INK)
	intro.add_theme_font_size_override("font_size", 16)
	intro.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/intro.tscn"))
	var extras := _hbox(24)
	extras.mouse_filter = Control.MOUSE_FILTER_PASS
	extras.alignment = BoxContainer.ALIGNMENT_CENTER
	extras.add_child(intro)
	extras.add_child(restart)
	list.add_child(extras)


func _section(text: String) -> Label:
	var l := _label(text.to_upper(), 14, MUTED)
	return l


func _add_row(parent: Control, kind: String, index: int, icon_kind: String, icon_tint: Color) -> void:
	var row := _panel(Color.WHITE, 20, 12)
	row.add_theme_stylebox_override("panel", _box(Color.WHITE, 20, 12))
	parent.add_child(row)
	var h := _hbox(14)
	row.add_child(h)
	var icon_bg := PanelContainer.new()
	icon_bg.add_theme_stylebox_override("panel", _box(Color(0.92, 0.96, 0.92), 26, 8))
	icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_bg.add_child(UIIcon.make(icon_kind, 36, icon_tint))
	h.add_child(icon_bg)
	var tv := _vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label("", 20)
	var desc := _label("", 15, MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(title)
	tv.add_child(desc)
	h.add_child(tv)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(130, 52)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bh := _hbox(6)
	bh.set_anchors_preset(Control.PRESET_FULL_RECT)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_child(UIIcon.make("coin", 22))
	var price := _label("", 19, Color.WHITE)
	bh.add_child(price)
	btn.add_child(bh)
	btn.pressed.connect(_on_buy.bind(kind, index))
	h.add_child(btn)
	_rows.append({"kind": kind, "index": index, "row": row, "title": title, "desc": desc, "btn": btn, "price": price, "content": bh})


# ------------------------------------------------------------------ shop sheet

func open_shop() -> void:
	if _sheet_open:
		return
	_sheet_open = true
	_refresh()
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	_sheet.visible = true
	var h := _sheet.get_combined_minimum_size().y
	_sheet.offset_top = 0
	_sheet.offset_bottom = h
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_overlay, "modulate:a", 1.0, 0.2)
	tw.tween_property(_sheet, "offset_top", -h, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_sheet, "offset_bottom", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func close_shop() -> void:
	if not _sheet_open:
		return
	_sheet_open = false
	var h := _sheet.size.y
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_overlay, "modulate:a", 0.0, 0.2)
	tw.tween_property(_sheet, "offset_top", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_sheet, "offset_bottom", h, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(_hide_sheet)


func _hide_sheet() -> void:
	_overlay.visible = false
	_sheet.visible = false


func _on_overlay_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and not (e as InputEventMouseButton).pressed:
		close_shop()


# ------------------------------------------------------------------ toasts

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
	_toast.offset_top = 140
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_toast, "modulate:a", 1.0, 0.25)
	tw.tween_property(_toast, "offset_top", 156.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toast_timer = TOAST_TIME


func _on_toast_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and not (e as InputEventMouseButton).pressed:
		_toast_timer = 0.0


# ------------------------------------------------------------------ refresh

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
	_coins_label.text = GameData.format_number(gs.coins)
	var cps := gs.coins_per_second()
	_cps_label.text = "+%s / sec" % GameData.format_number(cps) if cps > 0.0 else "coins"
	_trees_label.text = "%s trees" % GameData.format_number(gs.total_trees)
	_co2_label.text = "%s kg CO2 / yr" % GameData.format_number(gs.co2_per_year())

	var next := gs.next_stage_trees()
	if next < 0:
		_milestone_label.text = "%s  ·  every milestone reached" % GameData.STAGES[gs.stage]["name"]
		_milestone_bar.value = 1.0
	else:
		var prev: int = GameData.STAGES[gs.stage]["trees"]
		_milestone_label.text = "Next: %s  ·  %d / %d" % [GameData.STAGES[gs.stage + 1]["name"], gs.total_trees, next]
		_milestone_bar.value = clampf(float(gs.total_trees - prev) / float(next - prev), 0.0, 1.0)

	_hint.visible = gs.total_trees < 8
	_hint.text = "Tap anywhere to grow your %s" % GameData.PLANTS[gs.selected]["name"]

	for i in _chips.size():
		var unlocked: bool = gs.unlocked[i]
		_chips[i].set_state(gs.progress[i] / gs.growth_needed(i), gs.selected == i, not unlocked,
				gs.coins >= gs.unlock_cost(i), GameData.format_number(gs.unlock_cost(i)))

	var any_affordable := false
	for r in _rows:
		var kind: String = r["kind"]
		var i: int = r["index"]
		var title: Label = r["title"]
		var desc: Label = r["desc"]
		var btn: Button = r["btn"]
		var price: Label = r["price"]
		var cost := 0.0
		match kind:
			"click":
				cost = gs.click_upgrade_cost()
				title.text = "Watering Can  ·  Lv %d" % gs.click_level
				desc.text = "+%s growth per tap" % GameData.format_number(gs.click_power())
			"fert":
				cost = gs.fert_upgrade_cost()
				title.text = "Compost  ·  Lv %d" % gs.fert_level
				desc.text = "All trees grow 25% faster"
			"drone":
				var data: Dictionary = GameData.PLANTS[i]
				var lvl: int = gs.machine_level[i]
				(r["row"] as Control).visible = gs.unlocked[i]
				cost = gs.machine_cost(i)
				title.text = "%s Drone%s" % [data["short"], ("  ·  Lv %d" % lvl) if lvl > 0 else ""]
				if lvl == 0:
					desc.text = "Grows %s for you, even when you're away" % data["name"]
				else:
					desc.text = "%s trees / min" % _fmt_rate(gs.trees_per_second(i) * 60.0)
				if not gs.unlocked[i]:
					continue
		price.text = GameData.format_number(cost)
		var can := gs.coins >= cost
		btn.disabled = not can
		(r["content"] as Control).modulate.a = 1.0 if can else 0.6
		any_affordable = any_affordable or can
	_shop_badge.visible = any_affordable


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

func _on_chip(i: int) -> void:
	if GameState.unlocked[i]:
		GameState.select_plant(i)
	elif not GameState.try_unlock(i):
		show_toast("%s is locked" % GameData.PLANTS[i]["name"], "Collect %s coins to plant it." % GameData.format_number(GameState.unlock_cost(i)))
	_refresh()


func _on_buy(kind: String, i: int) -> void:
	match kind:
		"click": GameState.try_buy_click_upgrade()
		"fert": GameState.try_buy_fert_upgrade()
		"drone": GameState.try_buy_machine(i)
	_refresh()


func _on_plant_unlocked(i: int) -> void:
	var data: Dictionary = GameData.PLANTS[i]
	show_toast("New plant: %s" % data["name"], data["fact"])


func _on_stage_changed(stage: int) -> void:
	var st: Dictionary = GameData.STAGES[stage]
	show_toast(st["title"], st["fact"])
