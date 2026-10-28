class_name Hud
extends CanvasLayer
## All UI in code: clock and team bars, controls, the running ticker of team calls, the setup
## overlay (doctrine + personality per team, a personality per man, sliders for Custom), and the
## results and batch overlays. Rows wrap and overlays shrink for a phone.

signal new_match_requested
signal batch_requested(n: int)
signal speed_changed(scale: float)
signal pause_toggled(paused: bool)
signal map_changed(map_id: String)

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
var _team_boxes: Array[VBoxContainer] = []
var map_choice := "saloon"


func setup(m: MatchManager, map_id := "saloon") -> void:
	manager = m
	map_choice = map_id
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
		l.add_theme_color_override("font_color", manager.team_colors[t].lightened(0.3))
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

	_load_saved_scripts()
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
	content.add_child(_lbl("Any side against any side, on any map. Damage is the same for everyone - a Super dies to one good slug or one clean cut like anybody else; he is just faster, jumps further and thinks better. Pick each side's faction, character, grade, numbers and plan; give single men their own; or write the side's AI as rules.", 13))
	var mrow := HFlowContainer.new()
	mrow.add_theme_constant_override("h_separation", 10)
	content.add_child(mrow)
	mrow.add_child(_key("Map", 15))
	var mp := OptionButton.new()
	var ids: Array[String] = []
	for m in Saloon.MAPS:
		mp.add_item(String(Saloon.MAP_TITLES[m]))
		ids.append(m)
	mp.add_item("Random each match")
	ids.append("random")
	mp.select(maxi(ids.find(map_choice), 0))
	var mh := _lbl(String(Saloon.MAP_HELP.get(map_choice, "A different map every match")), 12, Color(0.8, 0.78, 0.72))
	mp.item_selected.connect(func(i: int):
		map_choice = ids[i]
		mh.text = String(Saloon.MAP_HELP.get(map_choice, "A different map every match"))
		map_changed.emit(map_choice))
	mrow.add_child(mp)
	content.add_child(mh)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 24)
	content.add_child(row)
	for t in 2:
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(340, 0)
		row.add_child(v)
		_team_boxes.append(v)
		_fill_team(t)
	var start := Button.new()
	start.text = "Start a match with these teams"
	start.add_theme_font_size_override("font_size", 18)
	start.pressed.connect(func(): _close_overlays(); new_match_requested.emit())
	content.add_child(start)


## A short label that never wraps (for grids and rows; wrapping labels in a grid get squeezed
## to nothing and stack their letters).
func _key(text: String, size := 14, color := Color(1, 0.85, 0.55)) -> Label:
	var l := _lbl(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _picker(items: Array, labels: Array, current: String, on_pick: Callable) -> OptionButton:
	var ob := OptionButton.new()
	for i in items.size():
		ob.add_item(String(labels[i]))
	ob.select(maxi(items.find(current), 0))
	ob.item_selected.connect(func(i: int): on_pick.call(items[i]))
	return ob


## (Re)build one side's panel - called again whenever its faction or size changes.
func _fill_team(t: int) -> void:
	var v: VBoxContainer = _team_boxes[t]
	for c in v.get_children():
		v.remove_child(c)
		c.queue_free()
	sliders[t] = {}
	manager.refresh_identity()
	var fac := manager.factions[t]
	var col: Color = manager.team_colors[t]
	v.add_child(_lbl("%s side - %s" % ["West" if t == 0 else "East", manager.team_names[t]], 18, col.lightened(0.3)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	v.add_child(grid)
	# faction
	grid.add_child(_key("Faction"))
	var fl: Array = []
	for f in Roster.FACTION_ORDER:
		fl.append(Roster.FACTIONS[f]["name"])
	grid.add_child(_picker(Roster.FACTION_ORDER, fl, fac, func(f):
		manager.set_faction(t, f)
		_fill_team.call_deferred(t)
		if t == 0 or manager.factions[0] == manager.factions[1]:
			_fill_team.call_deferred(1 - t)))
	# numbers
	grid.add_child(_key("Fighters"))
	var sb := SpinBox.new()
	sb.min_value = 1
	sb.max_value = MatchManager.MAX_TEAM
	sb.value = manager.team_sizes[t]
	sb.value_changed.connect(func(x: float):
		manager.team_sizes[t] = int(x)
		_fill_team.call_deferred(t))
	grid.add_child(sb)
	# character
	var kinds: Array = Roster.kinds_for(fac).duplicate()
	kinds.append("Random")
	kinds.append("Custom")
	grid.add_child(_key("Character"))
	grid.add_child(_picker(kinds, kinds, manager.team_presets[t], func(k):
		manager.team_presets[t] = k
		_fill_team.call_deferred(t)))
	# grade
	var gl: Array = []
	for g in Roster.GRADE_ORDER:
		gl.append(Roster.grade_name(g, fac))
	grid.add_child(_key("Grade"))
	grid.add_child(_picker(Roster.GRADE_ORDER, gl, manager.team_grades[t], func(g):
		manager.team_grades[t] = g
		_fill_team.call_deferred(t)))
	# weapon
	var wl: Array = []
	for w in Roster.WEAPON_CHOICES:
		wl.append(String(Roster.WEAPON_NAMES[w]))
	grid.add_child(_key("Weapon"))
	grid.add_child(_picker(Roster.WEAPON_CHOICES, wl, manager.team_weapons[t], func(w):
		manager.team_weapons[t] = w
		_fill_team.call_deferred(t)))
	# plan
	grid.add_child(_key("Plan"))
	grid.add_child(_picker(TeamBrain.DOCTRINES, TeamBrain.DOCTRINES, manager.doctrines[t], func(d):
		manager.doctrines[t] = d
		_fill_team.call_deferred(t)))
	var ab := Roster.abilities(manager.team_grades[t], manager.team_presets[t])
	var kh := String(Personality.PRESET_HELP.get(manager.team_presets[t], "Your own mix from the sliders below" if manager.team_presets[t] == "Custom" else ""))
	v.add_child(_lbl("%s. %s: speed %.2f, jump %.2f, smarts %.2f. %s" % [String(Roster.FACTIONS[fac]["blurb"]), Roster.grade_name(manager.team_grades[t], fac), ab["speed"], ab["jump"], ab["smarts"], kh], 12, Color(0.82, 0.8, 0.74)))
	v.add_child(_lbl("Weapon: " + String(Roster.WEAPON_HELP.get(manager.team_weapons[t], "")), 12, Color(0.82, 0.8, 0.74)))
	v.add_child(_lbl("Plan: " + String(TeamBrain.DOCTRINE_HELP.get(manager.doctrines[t], "")), 12, Color(0.82, 0.8, 0.74)))
	# AI script
	var srow := HFlowContainer.new()
	srow.add_theme_constant_override("h_separation", 8)
	v.add_child(srow)
	var eb := Button.new()
	eb.text = "Edit AI rules"
	eb.tooltip_text = "Write this side's AI as rules: 'when bleeding and hp < 40 -> rush nearest'"
	eb.pressed.connect(func(): _open_editor(t))
	srow.add_child(eb)
	var sc = manager.scripts[t]
	var stxt := "Built-in brain only" if sc == null or (sc as AiScript).rules.is_empty() else "Running %d rule%s" % [(sc as AiScript).rules.size(), "" if (sc as AiScript).rules.size() == 1 else "s"]
	srow.add_child(_key(stxt, 13, Color(0.6, 0.95, 0.6) if stxt.begins_with("Running") else Color(0.8, 0.78, 0.72)))
	# per man
	var n: int = manager.team_sizes[t]
	v.add_child(_lbl("Each man (Team = as above)", 14, Color(1, 0.85, 0.55)))
	var men := GridContainer.new()
	men.columns = 2
	v.add_child(men)
	var letter := String(Roster.FACTIONS[fac]["letter"])
	var mk: Array = [""]
	var ml: Array = ["Team character"]
	for k in Roster.kinds_for(fac):
		mk.append(k)
		ml.append(k)
	var mw: Array = Roster.WEAPON_CHOICES.duplicate()
	var mwl: Array = ["Team weapon"]
	for w in Roster.WEAPON_CHOICES:
		if w != "":
			mwl.append(String(Roster.WEAPON_NAMES[w]))
	var mg: Array = [""]
	var mgl: Array = ["Team grade"]
	for g in Roster.GRADE_ORDER:
		mg.append(g)
		mgl.append(Roster.grade_name(g, fac))
	for i in n:
		var ii := i
		var cell := HBoxContainer.new()
		cell.add_child(_key("%s%d" % [letter, i + 1], 13, col.lightened(0.3)))
		cell.add_child(_picker(mk, ml, String(manager.player_preset[t][i]), func(k): manager.player_preset[t][ii] = k))
		cell.add_child(_picker(mg, mgl, String(manager.player_grade[t][i]), func(g): manager.player_grade[t][ii] = g))
		cell.add_child(_picker(mw, mwl, String(manager.player_weapon[t][i]), func(w): manager.player_weapon[t][ii] = w))
		men.add_child(cell)
	# custom temperament
	v.add_child(_lbl("Custom temperament (dragging sets the side to Custom)", 13, Color(1, 0.85, 0.55)))
	var sg := GridContainer.new()
	sg.columns = 2
	v.add_child(sg)
	var base := Personality.preset(manager.team_presets[t]) if manager.team_presets[t] != "Custom" and manager.team_presets[t] != "Random" else (manager.custom[t] as Personality)
	if manager.team_presets[t] != "Custom":
		(manager.custom[t] as Personality).t = base.t.duplicate()
	for k in Personality.TRAITS:
		var kl := _key(k, 13, Color(0.92, 0.88, 0.8))
		kl.tooltip_text = String(Personality.TRAIT_HELP[k])
		kl.mouse_filter = Control.MOUSE_FILTER_STOP
		kl.custom_minimum_size = Vector2(90, 0)
		sg.add_child(kl)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.custom_minimum_size = Vector2(230, 22)
		sl.tooltip_text = String(Personality.TRAIT_HELP[k])
		sl.value = (manager.custom[t] as Personality).g(k)
		var key: String = k
		sl.value_changed.connect(func(val: float):
			(manager.custom[t] as Personality).t[key] = val
			manager.team_presets[t] = "Custom")
		sg.add_child(sl)
		sliders[t][k] = sl


# ---------------------------------------------------------------- the rule editor

var _editor_team := -1
var _gd_editor: Control
var _gd_text: TextEdit
var _gd_msg: Label


func _load_saved_scripts() -> void:
	if not OS.has_feature("web"):
		return
	for t in 2:
		var raw = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('brawlbots.rules.%d')||''}catch(e){return ''}})()" % t, true)
		if raw != null and String(raw).strip_edges() != "":
			_apply_script(t, String(raw), false)


func _apply_script(t: int, text: String, save: bool) -> AiScript:
	var sc := AiScript.parse(text)
	manager.script_text[t] = text
	manager.scripts[t] = sc if sc.errors.is_empty() and (sc.rules.size() > 0 or sc.trait_set.size() > 0 or sc.aim_mult != 1.0) else null
	if save and OS.has_feature("web"):
		JavaScriptBridge.eval("(function(){try{localStorage.setItem('brawlbots.rules.%d', %s)}catch(e){}})()" % [t, JSON.stringify(text)], true)
	return sc


func _open_editor(t: int) -> void:
	_editor_team = t
	var text: String = manager.script_text[t]
	if text.strip_edges() == "":
		text = String(AiScript.PRESETS["Built-in brain"])
	var title := "AI rules - %s" % manager.team_names[t]
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.brawlEditor && window.brawlEditor.open(%d, %s, %s, %s, %s)" % [t, JSON.stringify(title), JSON.stringify(text), JSON.stringify(AiScript.help_text()), JSON.stringify(AiScript.PRESETS), JSON.stringify(AiScript.vocab())], true)
		return
	# desktop / native: an editor drawn in Godot
	if _gd_editor == null:
		var parts := _overlay("AI rules", func(): _editor_team = -1)
		_gd_editor = parts[0]
		var c: VBoxContainer = parts[2]
		var prow := HFlowContainer.new()
		c.add_child(prow)
		prow.add_child(_key("Start from:", 13))
		var pp := OptionButton.new()
		for k in AiScript.PRESET_ORDER:
			pp.add_item(k)
		pp.item_selected.connect(func(i: int): _gd_text.text = String(AiScript.PRESETS[AiScript.PRESET_ORDER[i]]))
		prow.add_child(pp)
		prow.add_child(_key("Add an example:", 13))
		var ex := OptionButton.new()
		ex.add_item("(pick one)")
		for e in AiScript.EXAMPLES:
			ex.add_item(String(e[0]))
		ex.item_selected.connect(func(i: int):
			if i <= 0:
				return
			var line := String(AiScript.EXAMPLES[i - 1][1])
			var ln := _gd_text.get_caret_line()
			_gd_text.insert_line_at(ln, line)
			ex.select(0))
		prow.add_child(ex)
		_gd_text = TextEdit.new()
		_gd_text.custom_minimum_size = Vector2(620, 300)
		_gd_text.add_theme_font_size_override("font_size", 14)
		c.add_child(_gd_text)
		_gd_msg = _lbl("", 13, Color(1, 0.6, 0.5))
		c.add_child(_gd_msg)
		var brow := HFlowContainer.new()
		c.add_child(brow)
		var chk := Button.new()
		chk.text = "Check"
		chk.pressed.connect(func(): _gd_check(false))
		brow.add_child(chk)
		var ap := Button.new()
		ap.text = "Apply to this side"
		ap.pressed.connect(func(): _gd_check(true))
		brow.add_child(ap)
		var hl := _lbl(AiScript.help_text(), 11, Color(0.8, 0.8, 0.75))
		hl.autowrap_mode = TextServer.AUTOWRAP_OFF
		c.add_child(hl)
	_gd_text.text = text
	_gd_msg.text = ""
	setup_overlay.visible = false
	_gd_editor.visible = true


func _gd_check(apply: bool) -> void:
	var sc := AiScript.parse(_gd_text.text)
	if sc.errors.size() > 0:
		_gd_msg.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
		_gd_msg.text = "\n".join(sc.errors)
		return
	_gd_msg.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
	_gd_msg.text = "OK - %d rules%s" % [sc.rules.size(), "" if not apply else ", applied from the next match"]
	if apply:
		_apply_script(_editor_team, _gd_text.text, true)
		_gd_editor.visible = false
		setup_overlay.visible = true
		_fill_team(_editor_team)


## The web editor talks to us through a little queue on window.brawlEditor.
func _poll_web_editor() -> void:
	if not OS.has_feature("web"):
		return
	var raw = JavaScriptBridge.eval("window.brawlEditor ? window.brawlEditor.poll() : ''", true)
	if raw == null or String(raw) == "":
		return
	var msg = JSON.parse_string(String(raw))
	if typeof(msg) != TYPE_DICTIONARY:
		return
	var t := int(msg.get("team", 0))
	var text := String(msg.get("text", ""))
	var what := String(msg.get("action", ""))
	if what == "cancel":
		return
	var sc := AiScript.parse(text)
	var reply := {"ok": sc.errors.is_empty(), "errors": "\n".join(sc.errors), "summary": "OK - %d rules" % sc.rules.size(), "close": false}
	if what == "apply" and sc.errors.is_empty():
		_apply_script(t, text, true)
		reply["close"] = true
		reply["summary"] += ", applied from the next match"
		_fill_team(t)
	JavaScriptBridge.eval("window.brawlEditor.reply(%s)" % JSON.stringify(reply), true)


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
	status_label.text = "%s - %d %s %s (%s) vs %d %s %s (%s)" % [Saloon.MAP_TITLES.get(manager.saloon.map_id, ""), manager.team_sizes[0], Roster.grade_name(manager.team_grades[0], manager.factions[0]), manager.team_names[0], manager.doctrines[0], manager.team_sizes[1], Roster.grade_name(manager.team_grades[1], manager.factions[1]), manager.team_names[1], manager.doctrines[1]]


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
	var c: Color = Color(1, 0.9, 0.6) if team < 0 else manager.team_colors[team].lightened(0.35)
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
	_poll_web_editor()
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
		team_labels[t].text = "%s %d/%d  [%s]" % [manager.team_names[t], manager.alive_count(t), manager.team_sizes[t], plan]
		team_labels[t].add_theme_color_override("font_color", manager.team_colors[t].lightened(0.3))


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
	results_title.text = manager.team_wins[w] if w >= 0 else "A draw"
	if w >= 0:
		results_title.add_theme_color_override("font_color", manager.team_colors[w].lightened(0.35))
	results_box.add_child(_lbl("%s after %d:%02d. Standing %d-%d. First blood at %ds." % [String(res["reason"]).capitalize(), int(res["duration"]) / 60, int(res["duration"]) % 60, res["alive"][0], res["alive"][1], int(maxf(res["first_blood"], 0.0))], 14))
	for t in 2:
		var pl: Dictionary = res["plans"][t]
		var parts := PackedStringArray()
		for k in pl:
			if String(k) != "" and float(pl[k]) >= 1.0:
				parts.append("%s %ds" % [k, int(pl[k])])
		results_box.add_child(_lbl("%s - %s / %s. Plans: %s" % [manager.team_names[t], res["doctrines"][t], res["presets"][t], ", ".join(parts)], 13, manager.team_colors[t].lightened(0.35)))
	_next_row()
	var g := _grid(14)
	for h in ["Man", "Kind", "Grade", "Kills", "Died", "Shots", "Acc", "Avg aim", "Vital", "Melee", "Def", "Mostly", "Wounds", "Fate"]:
		_cell(g, h, Color(1, 0.85, 0.55))
	for m in res["men"]:
		var col: Color = manager.team_colors[int(m["team"])].lightened(0.35)
		_cell(g, String(m["name"]), col)
		_cell(g, String(m["preset"]))
		_cell(g, Roster.grade_name(String(m.get("grade", "Regular")), String(m.get("faction", "outlaws"))))
		_cell(g, str(m["kills"]))
		_cell(g, "-" if m["alive"] else "%d:%02d" % [int(m["died_at"]) / 60, int(m["died_at"]) % 60])
		_cell(g, str(m["shots"]))
		_cell(g, _pct(m["hits"], m["shots"]))
		_cell(g, "%.2fs" % (float(m["aim_sum"]) / maxf(float(m["shots"]), 1.0)))
		_cell(g, str(m["heads"]))
		_cell(g, "%d/%d" % [m["punch_hits"], m["punches"]])
		_cell(g, "%d/%d/%d" % [int(m.get("blocks", 0)), int(m.get("parries", 0)), int(m.get("dodges", 0))])
		_cell(g, _top_modes(m.get("modes", {})))
		_cell(g, _wound_text(m.get("wounds", [])))
		_cell(g, _fate(m))
	var tk := [0, 0]
	var td := [0, 0]
	for m in res["men"]:
		tk[int(m["team"])] += int(m["kills"])
		td[int(m["team"])] += 0 if m["alive"] else 1
	results_box.add_child(_lbl("Kills - deaths: %s %d-%d, %s %d-%d (deaths nobody is credited with: bled out from a stray wound, a fall)" % [manager.team_names[0], tk[0], td[0], manager.team_names[1], tk[1], td[1]], 13))
	_rules_fired(res["men"])
	results_box.add_child(_lbl("How it went", 15, Color(1, 0.85, 0.55)))
	for e in res["events"]:
		if not e[3]:
			continue
		var c: Color = manager.team_colors[int(e[1])].lightened(0.35)
		results_box.add_child(_lbl("%d:%02d  %s" % [int(e[0]) / 60, int(e[0]) % 60, e[2]], 12, c))
	results_overlay.visible = true


## Which lines of each side's script actually decided things, and how often.
func _rules_fired(men: Array) -> void:
	for t in 2:
		var tot := {}
		for m in men:
			if int(m["team"]) != t:
				continue
			var r: Dictionary = m.get("rules", {})
			for k in r:
				tot[k] = int(tot.get(k, 0)) + int(r[k])
		if tot.is_empty():
			continue
		results_box.add_child(_lbl("%s's rules that decided (times):" % manager.team_names[t], 14, manager.team_colors[t].lightened(0.35)))
		var ks := tot.keys()
		ks.sort_custom(func(a, b): return int(String(a).split(":")[0].substr(1)) < int(String(b).split(":")[0].substr(1)))
		for k in ks:
			results_box.add_child(_lbl("   %5d  %s" % [tot[k], k], 12))


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
		"head_blunt": how = "skull broken"
		"fall": how = "fell to his death"
		"bruise": how = "beaten down"
		"": how = "killed"
		_: how = "shot in the %s" % String(MatchManager.PART_NAMES.get(dp, dp))
	var dh := String(m.get("death_how", ""))
	if dh == "blade" and dp != "bled out":
		how = "cut down (%s)" % String(MatchManager.PART_NAMES.get(dp, dp))
	elif dh == "star" and dp != "bled out":
		how = "star in the %s" % String(MatchManager.PART_NAMES.get(dp, dp))
	elif dh == "blunt" and dp != "head_blunt":
		how = "beaten down"
	elif dh == "bottle":
		how = "brained with a bottle"
	elif dh == "lasso":
		how = "roped off the balcony"
	elif dh == "knife":
		how = "knifed (%s)" % String(MatchManager.PART_NAMES.get(dp, dp))
	elif dh == "chair":
		how = "laid out with a chair"
	elif dh == "kick":
		how = "kicked to death"
	elif dh == "throw":
		how = "thrown down and finished"
	if bool(m.get("fell", false)) and dp != "fall":
		how += ", and over the rail"
	var by := " by %s" % String(m["killed_by"]) if dp != "bled out" else " (wound from %s)" % String(m["killed_by"])
	return "%s%s at %ds" % [how, by, int(m["died_at"])]


func show_batch(summary: Dictionary) -> void:
	last_result = summary
	results_btn.disabled = false
	_clear_results()
	var d: Dictionary = summary["data"]
	results_title.text = "Batch of %d" % d["matches"]
	results_title.remove_theme_color_override("font_color")
	var tn: Array = d.get("team_names", manager.team_names)
	results_box.add_child(_lbl("%s (%s / %s) won %d, %s (%s / %s) won %d, %d drawn. Average match %ds, first blood at %ds." % [tn[0], d["doctrines"][0], d["presets"][0], d["wins"][0], tn[1], d["doctrines"][1], d["presets"][1], d["wins"][1], d["draws"], int(d["avg_duration"]), int(d["first_blood"])], 14))
	var rs := PackedStringArray()
	for k in d["reasons"]:
		rs.append("%s %d" % [k, d["reasons"][k]])
	results_box.add_child(_lbl("Endings: " + ", ".join(rs), 13))
	_next_row()
	var g := _grid(3)
	for h in ["", String(tn[0]), String(tn[1])]:
		_cell(g, h, Color(1, 0.85, 0.55))
	var rows := [["Kills", "kills"], ["Deaths", "team_deaths"], ["Shots", "shots"], ["Hits", "hits"], ["Head shots", "heads"], ["Hits on men in cover", "deny"], ["Hits from the balcony", "high"], ["Fist kills", "fist_kills"], ["Tables flipped", "flips"]]
	for r in rows:
		_cell(g, r[0])
		for t in 2:
			_cell(g, str(int(d.get(r[1], [0, 0])[t])))
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
		results_box.add_child(_lbl("%s time in each plan: %s" % [manager.team_names[t], ", ".join(parts)], 13, manager.team_colors[t].lightened(0.35)))
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
		results_box.add_child(_lbl("%s: %s" % [manager.team_names[t], _top_modes_all(d.get("modes", [{}, {}])[t])], 13, manager.team_colors[t].lightened(0.35)))
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
	var pg := _grid(6)
	for h in ["Kind", "Men", "Kills/man", "Deaths/man", "Survived", "Acc"]:
		_cell(pg, h, Color(1, 0.85, 0.55))
	for k in d["by_preset"]:
		var b: Dictionary = d["by_preset"][k]
		_cell(pg, String(k))
		_cell(pg, str(b["n"]))
		_cell(pg, "%.2f" % (float(b["kills"]) / maxf(b["n"], 1)))
		_cell(pg, "%.2f" % (float(b["deaths"]) / maxf(b["n"], 1)))
		_cell(pg, _pct(int(b["n"]) - int(b["deaths"]), int(b["n"])))
		_cell(pg, _pct(int(b["hits"]), int(b["shots"])))
	results_overlay.visible = true
