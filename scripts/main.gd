extends Node3D
## Entry point. Builds the saloon, wires the HUD, runs matches; supports headless sims:
##   godot --headless --path . -- --sim=20 [--reddoc=Pincer --bluedoc=Rush] [--red=Snake --blue=Lawman] [--seed=1]
##   godot --headless --path . -- --league=10      every doctrine against every other, both ends
##   godot --headless --path . -- --presets=10     every personality preset against Balanced, both ends
## On the web the query string stands in for the flags (index.html?reddoc=Pincer&blue=Brawler).

var manager: MatchManager
var saloon: Saloon
var cam: CameraRig
var hud: Hud
var headless := false
var batch_left := 0
var batch_results: Array[Dictionary] = []
var _dump := false
var _restart := -1.0
var _base_seed := -1
var _league: Array = []        # queue of [reddoc, bluedoc, red, blue, n]
var _league_rows: Array = []
var _league_cur := {}
var _league_n := 0
var map_choice := "saloon"     # a map id, or "random"
var _sun: DirectionalLight3D
var _lamps: Array[OmniLight3D] = []
var _env: Environment
var blood: Blood
var _args := {}


func _ready() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_dump = args.has("dumpmen")
	headless = (DisplayServer.get_name() == "headless" or args.has("sim") or args.has("league") or args.has("presets")) and not args.has("ui")
	_args = args
	_build_lighting()
	manager = MatchManager.new()
	manager.world = self
	manager.headless = headless
	manager.stall_watch = _dump
	map_choice = String(args.get("map", "saloon"))
	var sfx := Sfx.new()
	add_child(sfx)
	manager.sfx = sfx
	blood = Blood.new()
	blood.headless = headless
	add_child(blood)
	manager.blood = blood
	_ensure_map(_resolve_map())
	manager.match_ended.connect(_on_match_ended)
	manager.celebration_finished.connect(_on_celebration_finished)
	add_child(manager)
	for k in [["reddoc", 0], ["bluedoc", 1]]:
		if args.has(k[0]) and TeamBrain.DOCTRINES.has(args[k[0]]):
			manager.doctrines[k[1]] = args[k[0]]
	for k in [["redf", 0], ["bluef", 1]]:
		if args.has(k[0]) and Roster.FACTIONS.has(args[k[0]]):
			manager.set_faction(k[1], args[k[0]])
	for k in [["red", 0], ["blue", 1]]:
		if args.has(k[0]):
			manager.team_presets[k[1]] = args[k[0]]
	for k in [["redn", 0], ["bluen", 1]]:
		if args.has(k[0]):
			manager.team_sizes[k[1]] = clampi(int(args[k[0]]), 1, MatchManager.MAX_TEAM)
	for k in [["redgrade", 0], ["bluegrade", 1]]:
		if args.has(k[0]) and Roster.GRADES.has(args[k[0]]):
			manager.team_grades[k[1]] = args[k[0]]
	# --redscript=path/to/file.rules (headless) or literal rules text with ; for newlines
	for k in [["redscript", 0], ["bluescript", 1]]:
		if args.has(k[0]):
			var src := String(args[k[0]])
			if FileAccess.file_exists(src):
				src = FileAccess.get_file_as_string(src)
			elif AiScript.PRESETS.has(src):
				src = String(AiScript.PRESETS[src])
			else:
				src = src.replace(";", "\n")
			var sc := AiScript.parse(src)
			if sc.errors.size() > 0:
				printerr("%s: %s" % [k[0], "\n".join(sc.errors)])
			manager.script_text[k[1]] = src
			manager.scripts[k[1]] = sc
	manager.refresh_identity()
	if args.has("seed"):
		_base_seed = int(args["seed"])
	if args.has("intents"):
		manager.show_intents = true

	if headless:
		set_sim_speed(float(args.get("speed", "12")))
		if args.has("league"):
			_league_n = int(args["league"])
			for a in TeamBrain.DOCTRINES:
				for b in TeamBrain.DOCTRINES:
					if a < b:
						_league.append([a, b, "Balanced", "Balanced"])
			# --pairs=Rush:Dig In,Bait:Rush  plays just those
			if args.has("pairs"):
				_league.clear()
				for pr in String(args["pairs"]).split(",", false):
					var ab := pr.split(":")
					_league.append([ab[0], ab[1], "Balanced", "Balanced"])
			_take_part(args)
			print("Doctrine league: %d pairings x %d matches a side" % [_league.size(), _league_n])
			_next_league()
			return
		if args.has("presets"):
			_league_n = int(args["presets"])
			for pr in Personality.ORDER:
				if pr != "Balanced" and pr != "Random":
					_league.append(["Adaptive", "Adaptive", pr, "Balanced"])
			_take_part(args)
			print("Preset league vs Balanced: %d presets x %d matches a side" % [_league.size(), _league_n])
			_next_league()
			return
		batch_left = maxi(int(args.get("sim", "5")), 1)
		print("Saloon Bots sim: %d matches, %s/%s vs %s/%s" % [batch_left, manager.doctrines[0], manager.team_presets[0], manager.doctrines[1], manager.team_presets[1]])
		_start_next()
		return

	_setup_ui_scale()
	cam = CameraRig.new()
	add_child(cam)
	if args.has("cam"):   # ?cam=10 starts the camera that close
		cam.dist = float(args["cam"])
		cam._rest_dist = cam.dist
	hud = Hud.new()
	add_child(hud)
	hud.setup(manager, map_choice)
	hud.map_changed.connect(func(m: String): map_choice = m)
	hud.new_match_requested.connect(func(): batch_left = 0; batch_results.clear(); _start_next())
	hud.batch_requested.connect(_run_batch)
	hud.speed_changed.connect(set_sim_speed)
	hud.pause_toggled.connect(func(p: bool): get_tree().paused = p)
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	cam.process_mode = Node.PROCESS_MODE_ALWAYS
	_start_next()
	if args.has("lineup"):
		_lineup()


## ?lineup=1 - one of each side stood still facing the camera, for looking at the costumes.
func _lineup() -> void:
	manager.running = false
	var picks: Array[Gunman] = [manager.gunmen[0], manager.gunmen[manager.team_sizes[0]]]
	for k in 2:
		var g: Gunman = picks[k]
		g.global_position = Vector3(-0.45 + 0.9 * k, 0.0, 3.0)
		g.rotation.y = PI
		if String(_args.get("lineup", "1")) == "2" and g.arm_r != null:
			# side on, gun up: for looking at the six-shooter
			g.rotation.y = PI * 0.5 if k == 0 else -PI * 0.5
			g.arm_r.rotation.x = 1.57
	cam.min_dist = 2.0
	cam.yaw = 0.25
	cam.pitch = 0.12
	cam.dist = 3.2
	cam.set_focus(Vector3(0, 1.3, 3.0), -1.0)
	cam._focus = cam._focus_target


func _setup_ui_scale() -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	var dpi := DisplayServer.screen_get_dpi()
	root.content_scale_factor = clampf(float(dpi) / 96.0, 1.0, 3.0)


## Game time faster WITHOUT coarser physics: raise the tick rate with the time scale.
func set_sim_speed(s: float) -> void:
	Engine.time_scale = s
	Engine.physics_ticks_per_second = int(round(60.0 * s))
	Engine.max_physics_steps_per_frame = maxi(8, int(s * 4.0))


func _build_lighting() -> void:
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-60, 25, 0)
	_sun.shadow_enabled = not headless
	add_child(_sun)
	var env := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment = _env
	add_child(env)


func _apply_lighting(e: Dictionary) -> void:
	_sun.light_color = e.get("sun", Color(1, 0.92, 0.8))
	_sun.light_energy = float(e.get("sun_e", 0.9))
	_env.background_color = e.get("bg", Color(0.1, 0.08, 0.07))
	_env.ambient_light_color = e.get("ambient", Color(0.75, 0.62, 0.5))
	_env.ambient_light_energy = float(e.get("ambient_e", 0.6))
	for l in _lamps:
		l.queue_free()
	_lamps.clear()
	if headless:
		return
	for p in e.get("lamps", []):
		var l := OmniLight3D.new()
		l.position = p
		l.light_color = e.get("lamp_c", Color(1.0, 0.78, 0.45))
		l.light_energy = 1.6
		l.omni_range = 14.0
		add_child(l)
		_lamps.append(l)


func _resolve_map() -> String:
	if map_choice == "random" or not Saloon.MAPS.has(map_choice):
		return Saloon.MAPS[randi() % Saloon.MAPS.size()] if map_choice == "random" else "saloon"
	return map_choice


## Build the arena for `id` unless it's already standing.
func _ensure_map(id: String) -> void:
	if saloon != null and saloon.map_id == id:
		return
	if saloon != null:
		manager.clear()
		remove_child(saloon)
		saloon.queue_free()
	saloon = Saloon.new()
	add_child(saloon)
	saloon.build(id)
	manager.saloon = saloon
	blood.saloon = saloon
	blood.clear()
	_apply_lighting(saloon.env)


func _parse_args(list: PackedStringArray) -> Dictionary:
	var d := {}
	for a in list:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if OS.has_feature("web"):
		var raw = JavaScriptBridge.eval("window.location.search.slice(1)", true)
		if raw != null:
			for pair in String(raw).split("&", false):
				var kv := pair.split("=", true, 1)
				if kv[0] != "":
					d[kv[0].uri_decode()] = (kv[1].uri_decode() if kv.size() > 1 else "1")
	return d


func _start_next() -> void:
	_restart = -1.0
	if hud != null:
		hud.on_match_started()
	var s := -1
	if _base_seed >= 0:
		s = _base_seed + manager.match_index
	_ensure_map(_resolve_map())
	manager.start_match(s)


func _run_batch(n: int) -> void:
	batch_left = n
	batch_results.clear()
	set_sim_speed(10.0)
	if hud != null:
		hud.set_speed_ui(10.0)
	_start_next()


func _process(delta: float) -> void:
	if _restart > 0.0:
		_restart -= delta
		if _restart <= 0.0:
			_start_next()
	if cam != null and not manager.running and _restart < 0.0 and not manager.result.is_empty() and manager.result["winner"] >= 0:
		var c := Vector3.ZERO
		var n := 0
		for g in manager.gunmen:
			if g.alive and g.celebrating:
				c += g.global_position
				n += 1
		if n > 0:
			cam.set_focus(c / n, 14.0)
	elif cam != null:
		cam.clear_focus()


func _on_match_ended(res: Dictionary) -> void:
	if not _league_cur.is_empty():
		_league_record(res)
		return
	if batch_left > 0:
		batch_left -= 1
		batch_results.append(res)
		if headless and _dump:
			for t in 2:
				var a := {"shots": 0, "hits": 0, "aim": 0.0, "fan": 0, "mv": 0, "sup": 0.0, "sig": 0.0, "d": 0.0, "kills": 0}
				for m in res["men"]:
					if int(m["team"]) != t: continue
					a["shots"] += int(m["shots"]); a["hits"] += int(m["hits"]); a["aim"] += float(m["aim_sum"])
					a["fan"] += int(m.get("fan", 0)); a["mv"] += int(m.get("mv", 0)); a["sup"] += float(m.get("sup", 0.0)); a["sig"] += float(m.get("sig", 0.0)); a["d"] += float(m.get("dsum", 0.0)); a["kills"] += int(m["kills"])
				print("DUMP t%d %s" % [t, JSON.stringify(a)])
		if headless:
			print("  match %d: %s by %s in %ds (alive %d-%d) plans R=%s B=%s" % [res["match"], res["winner_name"], res["reason"], int(res["duration"]), res["alive"][0], res["alive"][1], _plans_str(res["plans"][0]), _plans_str(res["plans"][1])])
		if batch_left > 0:
			if hud != null:
				hud.set_status("Batch: %d done, %d to go..." % [batch_results.size(), batch_left])
			_restart = 0.05
			return
		var summary := Stats.summarize(batch_results)
		if headless:
			print(summary["text"])
			print("SUMMARY " + JSON.stringify(summary["data"]))
			get_tree().quit()
			return
		hud.show_batch(summary)
		set_sim_speed(1.0)
		hud.set_speed_ui(1.0)
		return
	if hud != null:
		hud.set_status("%s - %s" % [manager.team_wins[res["winner"]] if res["winner"] >= 0 else "Draw", res["reason"]])
		if res["winner"] < 0:
			get_tree().create_timer(1.5).timeout.connect(func(): _on_celebration_finished(res["match"]))


func _on_celebration_finished(idx: int) -> void:
	if hud == null or batch_left > 0 or idx != manager.match_index or manager.running:
		return
	hud.show_result(manager.result)


func _plans_str(pl: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in pl:
		if String(k) != "" and float(pl[k]) >= 1.0:
			parts.append("%s:%d" % [k, int(pl[k])])
	return ",".join(parts)


# ---------------------------------------------------------------- leagues (headless)

## --part=i/m keeps every m-th pairing starting at i, so a league can be split over processes.
func _take_part(args: Dictionary) -> void:
	if not args.has("part"):
		return
	var pm := String(args["part"]).split("/")
	var keep: Array = []
	for k in _league.size():
		if k % int(pm[1]) == int(pm[0]):
			keep.append(_league[k])
	_league = keep


func _next_league() -> void:
	if _league.is_empty():
		_league_report()
		get_tree().quit()
		return
	var row: Array = _league.pop_front()
	_league_cur = {"row": row, "games": 0, "wins_a": 0, "wins_b": 0, "draws": 0, "dur": 0.0, "decisions": 0, "sudden": 0}
	_league_play()


func _league_play() -> void:
	var row: Array = _league_cur["row"]
	var g: int = _league_cur["games"]
	# play the pairing from both ends of the room so the map can't favour one
	var swap := g % 2 == 1
	manager.doctrines[0] = row[1] if swap else row[0]
	manager.doctrines[1] = row[0] if swap else row[1]
	manager.team_presets[0] = row[3] if swap else row[2]
	manager.team_presets[1] = row[2] if swap else row[3]
	_league_cur["swap"] = swap
	var s := (_base_seed if _base_seed >= 0 else 1000) + manager.match_index
	_restart = -1.0
	manager.start_match(s)


func _league_record(res: Dictionary) -> void:
	var swap: bool = _league_cur["swap"]
	_league_cur["games"] += 1
	_league_cur["dur"] += float(res["duration"])
	if String(res["reason"]).begins_with("decision"):
		_league_cur["decisions"] += 1
	if res["sudden_death"]:
		_league_cur["sudden"] += 1
	var w: int = res["winner"]
	if w < 0:
		_league_cur["draws"] += 1
	elif (w == 0) != swap:
		_league_cur["wins_a"] += 1
	else:
		_league_cur["wins_b"] += 1
	if _league_cur["games"] >= _league_n * 2:
		var row: Array = _league_cur["row"]
		var n: int = _league_cur["games"]
		var a_name := String(row[0]) if row[0] != row[1] else String(row[2])
		var b_name := String(row[1]) if row[0] != row[1] else String(row[3])
		var line := "%-12s vs %-12s  %2d-%2d (%d draws)  avg %3ds  decisions %d  sudden %d" % [a_name, b_name, _league_cur["wins_a"], _league_cur["wins_b"], _league_cur["draws"], int(_league_cur["dur"] / n), _league_cur["decisions"], _league_cur["sudden"]]
		print(line)
		_league_rows.append({"a": a_name, "b": b_name, "wa": _league_cur["wins_a"], "wb": _league_cur["wins_b"], "d": _league_cur["draws"], "n": n})
		_league_cur = {}
		call_deferred("_next_league")
		return
	call_deferred("_league_play")


func _league_report() -> void:
	var tot := {}
	for r in _league_rows:
		for side in [["a", "wa"], ["b", "wb"]]:
			var k := String(r[side[0]])
			var t: Dictionary = tot.get(k, {"w": 0, "n": 0})
			t["w"] += int(r[side[1]])
			t["n"] += int(r["n"])
			tot[k] = t
	print("--- totals (win % over all its games, draws count as losses)")
	for k in tot:
		print("  %-12s %3d%%  (%d/%d)" % [k, int(100.0 * tot[k]["w"] / maxf(tot[k]["n"], 1)), tot[k]["w"], tot[k]["n"]])
	print("LEAGUE " + JSON.stringify(_league_rows))
