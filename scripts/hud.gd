class_name Hud
extends CanvasLayer
## All UI in code: clock and team bars, controls, the running ticker of team calls, the setup
## overlay (doctrine + personality per team, a personality per man, sliders for Custom), and the
## results and batch overlays. Rows wrap and overlays shrink for a phone.

signal new_match_requested
signal batch_requested(n: int)
signal speed_changed(scale: float)
signal pause_toggled(paused: bool)

const TEAM_PRESETS: Array[String] = ["Balanced", "Gunslinger", "Sharpshooter", "Brawler", "Snake", "Lawman", "Coward", "Desperado", "Random", "Custom"]

var manager: MatchManager
var timer_label: Label
var team_labels: Array[Label] = []
var ticker: VBoxContainer
var status_label: Label
var setup_overlay: Control
var setup_scroll: ScrollContainer
var results_overlay: Control
var results_scroll: ScrollContainer
var results_box: VBoxContainer
var results_title: Label
var speed_buttons: Array[Button] = []
var setup_btn: Button
var results_btn: Button
var last_result := {}
var doc_pickers: Array[OptionButton] = []
var doc_help: Array[Label] = []
var preset_pickers: Array[OptionButton] = []
var preset_help: Array[Label] = []
var man_pickers := [[], []]
var sliders := [{}, {}]
var _updating := false
var _tick := 0.0
var _root: Control


func setup(m: MatchManager) -> void:
	manager = m
	manager.announced.connect(_on_announce)
	for t in 2:
		manager.custom[t] = Personality.preset("Balanced")
	var theme := Theme.new()
	theme.default_font_size = 16
	_root = Control.new()
	_root.theme = theme
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	var row1 := HFlowContainer.new()
	row1.add_theme_constant_override("h_separation", 14)
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(row1)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(84, 0)   # the page's Apps button sits here
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_child(gap)
	timer_label = Label.new()
	timer_label.add_theme_font_size_override("font_size", 26)
	timer_label.text = "2:00"
	row1.add_child(timer_label)
	for t in 2:
		var l := Label.new()
		l.add_theme_color_override("font_color", MatchManager.TEAM_COLORS[t].lightened(0.3))
		l.add_theme_font_size_override("font_size", 17)
		row1.add_child(l)
		team_labels.append(l)

	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("h_separation", 6)
	row2.add_theme_constant_override("v_separation", 4)
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(row2)
	var pause_btn := Button.new()
	pause_btn.text = "Pause"
	pause_btn.toggle_mode = true
	pause_btn.toggled.connect(func(on: bool): pause_btn.text = "Play" if on else "Pause"; pause_toggled.emit(on))
	row2.add_child(pause_btn)
	for s in [1, 2, 4, 8]:
		var b := Button.new()
		b.text = "%dx" % s
		b.toggle_mode = true
		b.button_pressed = (s == 1)
		b.pressed.connect(func(): set_speed_ui(float(s)); speed_changed.emit(float(s)))
		row2.add_child(b)
		speed_buttons.append(b)
	setup_btn = Button.new()
	setup_btn.text = "Teams / tactics"
	setup_btn.toggle_mode = true
	setup_btn.toggled.connect(func(on: bool): setup_overlay.visible = on; if on: results_overlay.visible = false)
	row2.add_child(setup_btn)
	var intents := Button.new()
	intents.text = "Show intents"
	intents.toggle_mode = true
	intents.tooltip_text = "Print what every man is doing over his head"
	intents.toggled.connect(func(on: bool): manager.set_show_intents(on))
	row2.add_child(intents)
	results_btn = Button.new()
	results_btn.text = "Last results"
	results_btn.disabled = true
	results_btn.pressed.connect(func(): if not last_result.is_empty(): _show_any(last_result))
	row2.add_child(results_btn)
	var new_btn := Button.new()
	new_btn.text = "New match"
	new_btn.pressed.connect(func(): _close_overlays(); new_match_requested.emit())
	row2.add_child(new_btn)
	for n in [10, 50]:
		var bb := Button.new()
		bb.text = "Batch x%d" % n
		bb.pressed.connect(func(): _close_overlays(); batch_requested.emit(n))
		row2.add_child(bb)
	var mute_btn := Button.new()
	mute_btn.text = "Sound on"
	mute_btn.toggle_mode = true
	mute_btn.toggled.connect(func(on: bool): Sfx.set_muted(on); mute_btn.text = "Sound off" if on else "Sound on")
	row2.add_child(mute_btn)

	ticker = VBoxContainer.new()
	ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticker.add_theme_constant_override("separation", 0)
	vbox.add_child(ticker)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(status_label)

	_build_setup()
	_build_results()
	get_tree().root.size_changed.connect(_relayout)
	_relayout()


# ---------------------------------------------------------------- overlays

func _overlay(title_text: String, on_close: Callable) -> Array:
	var ov := Control.new()
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.visible = false
	_root.add_child(ov)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.08, 0.06, 0.93)
	sb.border_color = Color(0.6, 0.45, 0.25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): ov.visible = false; on_close.call())
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return [ov, scroll, content, title]


func _lbl(text: String, size := 14, color := Color(0.92, 0.88, 0.8)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _build_setup() -> void:
	var parts := _overlay("Teams and tactics", func(): setup_btn.set_pressed_no_signal(false))
	setup_overlay = parts[0]
	setup_scroll = parts[1]
	var content: VBoxContainer = parts[2]
	content.add_child(_lbl("Every man has the same Colt (six rounds, 30 spare) and the same fists. What wins is the team's doctrine and each man's personality. Pick a doctrine and a personality for each side, or give single men their own. 'Custom' uses the sliders.", 13))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 24)
	content.add_child(row)
	for t in 2:
		row.add_child(_team_panel(t))
	var start := Button.new()
	start.text = "Start a match with these teams"
	start.add_theme_font_size_override("font_size", 18)
	start.pressed.connect(func(): _close_overlays(); new_match_requested.emit())
	content.add_child(start)


func _team_panel(t: int) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(380, 0)
	v.add_child(_lbl(MatchManager.TEAM_NAMES[t] + (" (west, swinging doors)" if t == 0 else " (east, back door)"), 18, MatchManager.TEAM_COLORS[t].lightened(0.3)))
	v.add_child(_lbl("Doctrine", 14, Color(1, 0.85, 0.55)))
	var dp := OptionButton.new()
	for d in TeamBrain.DOCTRINES:
		dp.add_item(d)
	dp.select(TeamBrain.DOCTRINES.find(manager.doctrines[t]))
	dp.item_selected.connect(func(i: int): manager.doctrines[t] = TeamBrain.DOCTRINES[i]; _refresh_help())
	v.add_child(dp)
	doc_pickers.append(dp)
	var dh := _lbl("", 12, Color(0.8, 0.78, 0.72))
	v.add_child(dh)
	doc_help.append(dh)
	v.add_child(_lbl("Team personality", 14, Color(1, 0.85, 0.55)))
	var pp := OptionButton.new()
	for pn in TEAM_PRESETS:
		pp.add_item(pn)
	pp.select(TEAM_PRESETS.find(manager.team_presets[t]))
	pp.item_selected.connect(func(i: int): manager.team_presets[t] = TEAM_PRESETS[i]; _refresh_help())
	v.add_child(pp)
	preset_pickers.append(pp)
	var ph := _lbl("", 12, Color(0.8, 0.78, 0.72))
	v.add_child(ph)
	preset_help.append(ph)
	v.add_child(_lbl("Each man (Team = follow the team)", 14, Color(1, 0.85, 0.55)))
	var men := HFlowContainer.new()
	men.add_theme_constant_override("h_separation", 4)
	v.add_child(men)
	for i in MatchManager.TEAM_SIZE:
		var mb := OptionButton.new()
		mb.add_item("%s%d: Team" % [MatchManager.TEAM_NAMES[t][0], i + 1])
		for pn in TEAM_PRESETS:
			mb.add_item("%s%d: %s" % [MatchManager.TEAM_NAMES[t][0], i + 1, pn])
		mb.item_selected.connect(func(k: int): manager.player_preset[t][i] = "" if k == 0 else TEAM_PRESETS[k - 1])
		men.add_child(mb)
		man_pickers[t].append(mb)
	v.add_child(_lbl("Custom personality (dragging sets the team to Custom)", 13, Color(1, 0.85, 0.55)))
	var grid := GridContainer.new()
	grid.columns = 2
	v.add_child(grid)
	for k in Personality.TRAITS:
		var kl := _lbl(k, 13)
		kl.tooltip_text = String(Personality.TRAIT_HELP[k])
		kl.mouse_filter = Control.MOUSE_FILTER_STOP
		kl.custom_minimum_size = Vector2(90, 0)
		grid.add_child(kl)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.custom_minimum_size = Vector2(230, 22)
		sl.tooltip_text = String(Personality.TRAIT_HELP[k])
		sl.value = (manager.custom[t] as Personality).g(k)
		var key: String = k
		sl.value_changed.connect(func(val: float):
			if _updating:
				return
			(manager.custom[t] as Personality).t[key] = val
			manager.team_presets[t] = "Custom"
			preset_pickers[t].select(TEAM_PRESETS.find("Custom"))
			_refresh_help())
		grid.add_child(sl)
		sliders[t][k] = sl
	_refresh_help.call_deferred()
	return v


func _refresh_help() -> void:
	for t in doc_help.size():
		doc_help[t].text = String(TeamBrain.DOCTRINE_HELP.get(manager.doctrines[t], ""))
		var pn := manager.team_presets[t]
		preset_help[t].text = "Your own mix from the sliders below" if pn == "Custom" else String(Personality.PRESET_HELP.get(pn, ""))
		# show the preset's numbers on the sliders so Custom starts from something sensible
		if pn != "Custom" and pn != "Random" and t < sliders.size() and not sliders[t].is_empty():
			_updating = true
			var p := Personality.preset(pn)
			(manager.custom[t] as Personality).t = p.t.duplicate()
			for k in Personality.TRAITS:
				sliders[t][k].value = p.g(k)
			_updating = false


func _build_results() -> void:
	var parts := _overlay("Results", func(): pass)
	results_overlay = parts[0]
	results_scroll = parts[1]
	results_box = parts[2]
	results_title = parts[3]


func on_match_started() -> void:
	results_overlay.visible = false
	for c in ticker.get_children():
		c.queue_free()
	status_label.text = "%s (%s) vs %s (%s)" % [manager.doctrines[0], manager.team_presets[0], manager.doctrines[1], manager.team_presets[1]]


func _close_overlays() -> void:
	setup_overlay.visible = false
	results_overlay.visible = false
	setup_btn.set_pressed_no_signal(false)


func _relayout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var w := vs.x
	var h := vs.y
	setup_scroll.custom_minimum_size = Vector2(minf(840.0, w - 40.0), minf(640.0, h - 120.0))
	var rc: Control = results_overlay.get_child(0)
	if w > h:
		rc.anchor_left = 0.42
		rc.anchor_top = 0.0
		rc.offset_top = 96.0
		results_scroll.custom_minimum_size = Vector2(minf(720.0, w * 0.58 - 40.0), minf(600.0, h - 210.0))
	else:
		rc.anchor_left = 0.0
		rc.anchor_top = 0.38
		rc.offset_top = 0.0
		results_scroll.custom_minimum_size = Vector2(minf(900.0, w - 30.0), minf(640.0, h * 0.62 - 90.0))


func set_speed_ui(s: float) -> void:
	for b in speed_buttons:
		b.set_pressed_no_signal(b.text == "%dx" % int(s))


func set_status(text: String) -> void:
	status_label.text = text


func _on_announce(text: String, team: int) -> void:
	var c: Color = Color(1, 0.9, 0.6) if team < 0 else MatchManager.TEAM_COLORS[team].lightened(0.35)
	var t := manager.elapsed
	var l := _lbl("%d:%02d  %s" % [int(t) / 60, int(t) % 60, text], 13, c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticker.add_child(l)
	while ticker.get_child_count() > 5:
		var old := ticker.get_child(0)
		ticker.remove_child(old)
		old.queue_free()


# ---------------------------------------------------------------- live

func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or manager == null:
		return
	_tick = 0.2
	if manager.sudden_death:
		timer_label.text = "SUDDEN DEATH +%d" % int(manager.sudden_t)
		timer_label.add_theme_color_override("font_color", Color(1, 0.4, 0.3))
	else:
		var tl := maxf(manager.time_left, 0.0)
		timer_label.text = "%d:%02d" % [int(tl) / 60, int(tl) % 60]
		timer_label.add_theme_color_override("font_color", Color(1, 0.5, 0.4) if tl < 25.0 else Color(1, 0.95, 0.85))
	for t in 2:
		var b: TeamBrain = manager.brains[t] if manager.brains.size() > t else null
		var plan := ""
		if b != null:
			plan = b.plan + ((" / " + b.phase) if b.phase != "" and b.phase != "hold" else "")
		team_labels[t].text = "%s %d/5  [%s]" % [MatchManager.TEAM_NAMES[t], manager.alive_count(t), plan]


# ---------------------------------------------------------------- results

func _clear_results() -> void:
	for c in results_box.get_children():
		results_box.remove_child(c)
		c.queue_free()


func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 2)
	results_box.add_child(g)
	return g


func _cell(g: GridContainer, text: String, color := Color(0.92, 0.88, 0.8), size := 13) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	g.add_child(l)


static func _pct(a: int, b: int) -> String:
	return "%d%%" % int(round(100.0 * a / b)) if b > 0 else "-"


func _next_row() -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	var same := Button.new()
	same.text = "Next match - same teams"
	same.pressed.connect(func(): _close_overlays(); new_match_requested.emit())
	row.add_child(same)
	var change := Button.new()
	change.text = "Change teams first"
	change.pressed.connect(func(): results_overlay.visible = false; setup_btn.button_pressed = true)
	row.add_child(change)
	results_box.add_child(row)


func _show_any(r: Dictionary) -> void:
	if r.has("text"):
		show_batch(r)
	else:
		show_result(r)


func show_result(res: Dictionary) -> void:
	last_result = res
	results_btn.disabled = false
	_clear_results()
	setup_overlay.visible = false
	setup_btn.set_pressed_no_signal(false)
	var w: int = res["winner"]
	results_title.text = ("%s wins" % res["winner_name"]) if w >= 0 else "A draw"
	if w >= 0:
		results_title.add_theme_color_override("font_color", MatchManager.TEAM_COLORS[w].lightened(0.35))
	results_box.add_child(_lbl("%s after %d:%02d. Standing %d-%d. First blood at %ds." % [String(res["reason"]).capitalize(), int(res["duration"]) / 60, int(res["duration"]) % 60, res["alive"][0], res["alive"][1], int(maxf(res["first_blood"], 0.0))], 14))
	for t in 2:
		var pl: Dictionary = res["plans"][t]
		var parts := PackedStringArray()
		for k in pl:
			if String(k) != "" and float(pl[k]) >= 1.0:
				parts.append("%s %ds" % [k, int(pl[k])])
		results_box.add_child(_lbl("%s - %s / %s. Plans: %s" % [MatchManager.TEAM_NAMES[t], res["doctrines"][t], res["presets"][t], ", ".join(parts)], 13, MatchManager.TEAM_COLORS[t].lightened(0.35)))
	_next_row()
	var g := _grid(11)
	for h in ["Man", "Kind", "Kills", "Shots", "Acc", "Avg aim", "Vital", "Fists", "Mostly", "Wounds", "Fate"]:
		_cell(g, h, Color(1, 0.85, 0.55))
	for m in res["men"]:
		var col: Color = MatchManager.TEAM_COLORS[int(m["team"])].lightened(0.35)
		_cell(g, String(m["name"]), col)
		_cell(g, String(m["preset"]))
		_cell(g, str(m["kills"]))
		_cell(g, "%d/18" % int(m["shots"]))
		_cell(g, _pct(m["hits"], m["shots"]))
		_cell(g, "%.2fs" % (float(m["aim_sum"]) / maxf(float(m["shots"]), 1.0)))
		_cell(g, str(m["heads"]))
		_cell(g, "%d/%d" % [m["punch_hits"], m["punches"]])
		_cell(g, _top_modes(m.get("modes", {})))
		_cell(g, _wound_text(m.get("wounds", [])))
		_cell(g, _fate(m))
	results_box.add_child(_lbl("How it went", 15, Color(1, 0.85, 0.55)))
	for e in res["events"]:
		if not e[3]:
			continue
		var c: Color = MatchManager.TEAM_COLORS[int(e[1])].lightened(0.35)
		results_box.add_child(_lbl("%d:%02d  %s" % [int(e[0]) / 60, int(e[0]) % 60, e[2]], 12, c))
	results_overlay.visible = true


func _top_modes(md: Dictionary) -> String:
	var tot := 0.0
	for k in md:
		tot += float(md[k])
	var ks := md.keys()
	ks.sort_custom(func(a, b): return float(md[a]) > float(md[b]))
	var parts := PackedStringArray()
	for i in mini(3, ks.size()):
		parts.append("%s %d%%" % [ks[i], int(round(100.0 * float(md[ks[i]]) / maxf(tot, 1.0)))])
	return ", ".join(parts)


func _top_modes_all(md: Dictionary) -> String:
	var tot := 0.0
	for k in md:
		tot += float(md[k])
	var ks := md.keys()
	ks.sort_custom(func(a, b): return float(md[a]) > float(md[b]))
	var parts := PackedStringArray()
	for k in ks:
		parts.append("%s %d%%" % [k, int(round(100.0 * float(md[k]) / maxf(tot, 1.0)))])
	return ", ".join(parts)


func _wound_text(w: Array) -> String:
	if w.is_empty():
		return "-"
	var parts := PackedStringArray()
	for x in w:
		parts.append(String(MatchManager.PART_NAMES.get(x, x)))
	return ", ".join(parts)


func _fate(m: Dictionary) -> String:
	if m["alive"]:
		return "standing, %d hp" % int(m["hp"])
	var dp := String(m.get("death_part", ""))
	var how := ""
	match dp:
		"head": how = "shot through the head"
		"heart": how = "shot through the heart"
		"bled out": how = "bled out from a gut shot"
		"fists": how = "beaten to death"
		"": how = "killed"
		_: how = "shot in the %s" % String(MatchManager.PART_NAMES.get(dp, dp))
	var by := " by %s" % String(m["killed_by"]) if dp != "bled out" else " (%s's bullet)" % String(m["killed_by"])
	return "%s%s at %ds" % [how, by, int(m["died_at"])]


func show_batch(summary: Dictionary) -> void:
	last_result = summary
	results_btn.disabled = false
	_clear_results()
	var d: Dictionary = summary["data"]
	results_title.text = "Batch of %d" % d["matches"]
	results_title.remove_theme_color_override("font_color")
	results_box.add_child(_lbl("Red (%s / %s) won %d, Blue (%s / %s) won %d, %d drawn. Average match %ds, first blood at %ds." % [d["doctrines"][0], d["presets"][0], d["wins"][0], d["doctrines"][1], d["presets"][1], d["wins"][1], d["draws"], int(d["avg_duration"]), int(d["first_blood"])], 14))
	var rs := PackedStringArray()
	for k in d["reasons"]:
		rs.append("%s %d" % [k, d["reasons"][k]])
	results_box.add_child(_lbl("Endings: " + ", ".join(rs), 13))
	_next_row()
	var g := _grid(3)
	for h in ["", "Red", "Blue"]:
		_cell(g, h, Color(1, 0.85, 0.55))
	var rows := [["Kills", "kills"], ["Shots", "shots"], ["Hits", "hits"], ["Head shots", "heads"], ["Hits on men in cover", "deny"], ["Hits from the balcony", "high"], ["Fist kills", "fist_kills"], ["Tables flipped", "flips"]]
	for r in rows:
		_cell(g, r[0])
		for t in 2:
			_cell(g, str(int(d[r[1]][t])))
	_cell(g, "Accuracy")
	for t in 2:
		_cell(g, _pct(int(d["hits"][t]), int(d["shots"][t])))
	for t in 2:
		var pl: Dictionary = d["plans"][t]
		var tot := 0.0
		for k in pl:
			tot += float(pl[k])
		var parts := PackedStringArray()
		for k in pl:
			parts.append("%s %d%%" % [k, int(100.0 * float(pl[k]) / maxf(tot, 1.0))])
		results_box.add_child(_lbl("%s time in each plan: %s" % [MatchManager.TEAM_NAMES[t], ", ".join(parts)], 13, MatchManager.TEAM_COLORS[t].lightened(0.35)))
	results_box.add_child(_lbl("Hit rate by time spent aiming (hits / shots)", 15, Color(1, 0.85, 0.55)))
	var ag := _grid(5)
	for hh in ["Range", "Snap <0.3s", "Quick 0.3-0.7s", "Steady 0.7-1.2s", "Careful >1.2s"]:
		_cell(ag, hh, Color(1, 0.85, 0.55))
	var ar: Array = d.get("aimr", [])
	for rb in 3:
		_cell(ag, ["Close <7 m", "Middle 7-14 m", "Long >14 m"][rb])
		for b in 4:
			var c: Array = ar[rb * 4 + b] if ar.size() > rb * 4 + b else [0, 0]
			_cell(ag, "%s of %d" % [_pct(int(c[1]), int(c[0])), int(c[0])])
	results_box.add_child(_lbl("Time in each mode", 15, Color(1, 0.85, 0.55)))
	var me: Array = d.get("mode_events", [{}, {}])
	for t in 2:
		results_box.add_child(_lbl("%s: %s" % [MatchManager.TEAM_NAMES[t], _top_modes_all(d.get("modes", [{}, {}])[t])], 13, MatchManager.TEAM_COLORS[t].lightened(0.35)))
		var ev: Dictionary = me[t] if me.size() > t else {}
		var n := maxf(float(d["matches"]), 1.0)
		results_box.add_child(_lbl("   per match: %.1f cowered, %.1f hid, %.1f flanks, %.1f rushes, %.1f men ran dry, %.1f jams (%.1f knocked by a punch), %.1f slipped in blood" % [float(ev.get("cowers", 0)) / n, float(ev.get("hides", 0)) / n, float(ev.get("flanks", 0)) / n, float(ev.get("rushes", 0)) / n, float(ev.get("dry", 0)) / n, float(ev.get("jams", 0)) / n, float(ev.get("gun_knocks", 0)) / n, float(ev.get("slips", 0)) / n], 12))
	var deaths: Dictionary = d.get("deaths", {})
	if not deaths.is_empty():
		var dps := PackedStringArray()
		for k in deaths:
			dps.append("%s %d" % [k, deaths[k]])
		results_box.add_child(_lbl("How men died: " + ", ".join(dps), 13))
	results_box.add_child(_lbl("By personality", 15, Color(1, 0.85, 0.55)))
	var pg := _grid(5)
	for h in ["Kind", "Men", "Kills/man", "Survived", "Acc"]:
		_cell(pg, h, Color(1, 0.85, 0.55))
	for k in d["by_preset"]:
		var b: Dictionary = d["by_preset"][k]
		_cell(pg, String(k))
		_cell(pg, str(b["n"]))
		_cell(pg, "%.2f" % (float(b["kills"]) / maxf(b["n"], 1)))
		_cell(pg, _pct(int(b["n"]) - int(b["deaths"]), int(b["n"])))
		_cell(pg, _pct(int(b["hits"]), int(b["shots"])))
	results_overlay.visible = true
