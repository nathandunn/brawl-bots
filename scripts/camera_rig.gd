class_name CameraRig
extends Node3D
## Orbit camera: drag to rotate (mouse or touch), wheel/pinch to zoom, and on-screen controls
## in the bottom-right corner - pan, rotate, tilt, zoom, and "Wide" to put the whole map back in
## view. Keys: arrows / WASD pan, Q E rotate, R F tilt, + - zoom, Home or 0 for wide. Every match
## starts on the wide view; it does not move on its own.

var yaw := 0.6
var pitch := 0.5
var dist := 27.0
var idle := 0.0
var auto_orbit := false  # the view stays where you put it
var _cam: Camera3D
var _dragging := false
var _touches := {}
var _pinch_d := 0.0
# optional focus (the winners' celebration): the rig glides to the point and the
# auto-zoom tightens; a user who is dragging or pinching keeps their own zoom
var _focus := Vector3(0, 1.0, 0)
var _focus_target := Vector3(0, 1.0, 0)
var _focus_dist := -1.0
var min_dist := 10.0
var max_dist := 70.0
var _rest_dist := 27.0  # the zoom the user last chose; the view returns to it after a celebration
## where the user has panned the view to (added to the focus); "Wide" clears it
var _pan := Vector3.ZERO
var _pan_limit := Vector2(16.0, 11.0)
## the wide view for the current map
var wide_yaw := 0.6
var wide_pitch := 0.82
var wide_dist := 38.0
## the on-screen buttons: which one is held down, for hold-to-repeat
var _held := ""
var _ui: CanvasLayer
var _pad: Control
var _shown := true
var _toggle: Button
var _box: Control

const PAN_SPEED := 9.0      # m/s at the wide zoom (scales with zoom)
const ROT_SPEED := 1.2      # rad/s
const TILT_SPEED := 0.8
const ZOOM_SPEED := 1.6     # x per second


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.keep_aspect = Camera3D.KEEP_WIDTH  # portrait phones see the whole arena too
	_cam.far = 300.0
	add_child(_cam)
	_build_controls()
	_apply()


## Fit the wide view to a map `half_x` by `half_z` metres from the centre each way.
func fit_map(half_x: float, half_z: float) -> void:
	var r := maxf(half_x, half_z * 1.35)
	wide_dist = clampf(r * 2.45, 14.0, max_dist)
	_pan_limit = Vector2(half_x, half_z)
	if min_dist >= 10.0:
		min_dist = minf(10.0, wide_dist * 0.3)


## Back to the whole map in view: centred, high, zoomed out. Called at the start of every match.
func go_wide() -> void:
	yaw = wide_yaw
	pitch = wide_pitch
	dist = wide_dist
	_rest_dist = wide_dist
	_pan = Vector3.ZERO
	_focus_target = Vector3(0, 1.0, 0)
	_focus = _focus_target
	_focus_dist = -1.0
	idle = 0.0
	_apply()


func _process(delta: float) -> void:
	idle += delta
	if auto_orbit and idle > 6.0:
		yaw += delta * 0.05
	_held_step(delta)
	if _box != null:
		# clear of the status line, which wraps to two lines on a narrow phone
		var vs := get_viewport().get_visible_rect().size
		_box.offset_bottom = -34.0 if vs.x > vs.y else -64.0
	_key_step(delta)
	var k := clampf(delta * 2.0, 0.0, 1.0)
	_focus = _focus.lerp(_focus_target, k)
	if _focus_dist > 0.0 and idle > 6.0:
		dist = lerpf(dist, _focus_dist, k)
	_apply()


func set_focus(point: Vector3, want_dist: float = -1.0) -> void:
	_focus_target = Vector3(point.x, 1.0, point.z)
	_focus_dist = want_dist


func clear_focus() -> void:
	if min_dist < 2.5:
		return   # the lineup holds its shot
	_focus_target = Vector3(0, 1.0, 0)
	_focus_dist = _rest_dist if absf(dist - _rest_dist) > 0.5 else -1.0


func _apply() -> void:
	pitch = clampf(pitch, 0.15, 1.45)
	dist = clampf(dist, min_dist, max_dist)
	_pan.x = clampf(_pan.x, -_pan_limit.x, _pan_limit.x)
	_pan.z = clampf(_pan.z, -_pan_limit.y, _pan_limit.y)
	var f := _focus + _pan
	var p := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	_cam.position = f + p
	_cam.look_at(f, Vector3.UP)


# ---------------------------------------------------------------- moving the view

## Pan along the ground, relative to where the camera is looking (up = away from you).
func pan(right: float, fwd: float) -> void:
	var r := Vector3(cos(yaw), 0, -sin(yaw))
	var f := Vector3(-sin(yaw), 0, -cos(yaw))
	_pan += r * right + f * fwd
	idle = 0.0


func zoom(factor: float) -> void:
	dist *= factor
	dist = clampf(dist, min_dist, max_dist)
	_rest_dist = dist
	_focus_dist = -1.0
	idle = 0.0


func _act(a: String, delta: float) -> void:
	var ps := PAN_SPEED * delta * (dist / maxf(wide_dist, 1.0) * 0.8 + 0.2)
	match a:
		"left": pan(-ps, 0.0)
		"right": pan(ps, 0.0)
		"up": pan(0.0, ps)
		"down": pan(0.0, -ps)
		"rotl": yaw += ROT_SPEED * delta
		"rotr": yaw -= ROT_SPEED * delta
		"tiltup": pitch += TILT_SPEED * delta
		"tiltdn": pitch -= TILT_SPEED * delta
		"in": zoom(pow(ZOOM_SPEED, -delta))
		"out": zoom(pow(ZOOM_SPEED, delta))
	idle = 0.0


func _held_step(delta: float) -> void:
	if _held != "":
		_act(_held, delta)


func _key_step(delta: float) -> void:
	# keys only when no text field has focus (the rule editor)
	var fo := get_viewport().gui_get_focus_owner()
	if fo is TextEdit or fo is LineEdit:
		return
	var keys := {
		"left": [KEY_LEFT, KEY_A], "right": [KEY_RIGHT, KEY_D], "up": [KEY_UP, KEY_W], "down": [KEY_DOWN, KEY_S],
		"rotl": [KEY_Q], "rotr": [KEY_E], "tiltup": [KEY_R], "tiltdn": [KEY_F],
		"in": [KEY_EQUAL, KEY_KP_ADD], "out": [KEY_MINUS, KEY_KP_SUBTRACT],
	}
	for a in keys:
		for kc in keys[a]:
			if Input.is_physical_key_pressed(kc):
				_act(a, delta)
				break
	if Input.is_physical_key_pressed(KEY_HOME) or Input.is_physical_key_pressed(KEY_0):
		go_wide()


# ---------------------------------------------------------------- the on-screen controls

func _build_controls() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 1
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_right = -10.0
	box.offset_bottom = -34.0
	_box = box
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 4)
	root.add_child(box)
	_pad = VBoxContainer.new()
	_pad.add_theme_constant_override("separation", 4)
	box.add_child(_pad)
	# pan: a cross with Wide in the middle
	var cross := GridContainer.new()
	cross.columns = 3
	cross.add_theme_constant_override("h_separation", 4)
	cross.add_theme_constant_override("v_separation", 4)
	_pad.add_child(cross)
	for cell in [["", ""], ["", "up"], ["", ""], ["", "left"], ["Wide", "wide"], ["", "right"], ["", ""], ["", "down"], ["", ""]]:
		if cell[1] == "":
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(46, 40)
			sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cross.add_child(sp)
		else:
			cross.add_child(_btn(cell[0], cell[1], "Pan" if cell[1] != "wide" else "Whole map in view (Home)"))
	# rotate, tilt, zoom
	var row := GridContainer.new()
	row.columns = 3
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	_pad.add_child(row)
	row.add_child(_btn("", "rotl", "Rotate left (Q)"))
	row.add_child(_btn("Tilt", "tiltup", "Look down from higher (R)"))
	row.add_child(_btn("", "rotr", "Rotate right (E)"))
	row.add_child(_btn("-", "out", "Zoom out (-)"))
	row.add_child(_btn("Tilt", "tiltdn", "Lower the camera (F)"))
	row.add_child(_btn("+", "in", "Zoom in (+)"))
	_toggle = Button.new()
	_toggle.text = "Hide view controls"
	_toggle.add_theme_font_size_override("font_size", 13)
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	_toggle.pressed.connect(func():
		_shown = not _shown
		_pad.visible = _shown
		_toggle.text = "Hide view controls" if _shown else "View controls")
	box.add_child(_toggle)


func _btn(text: String, action: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(46, 40)
	b.add_theme_font_size_override("font_size", 20 if text.length() <= 2 else 13)
	var ic := _icon(action)
	if ic != null:
		b.icon = ic
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP if text != "" else VERTICAL_ALIGNMENT_CENTER
		b.expand_icon = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.06, 0.62)
	sb.set_corner_radius_all(6)
	sb.border_color = Color(0.6, 0.45, 0.25, 0.7)
	sb.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", sb)
	var sh := sb.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.25, 0.18, 0.1, 0.8)
	b.add_theme_stylebox_override("hover", sh)
	var sp := sb.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.45, 0.32, 0.15, 0.9)
	b.add_theme_stylebox_override("pressed", sp)
	if action == "wide":
		b.pressed.connect(go_wide)
	else:
		b.button_down.connect(func(): _held = action; _act(action, 0.06))
		b.button_up.connect(func(): if _held == action: _held = "")
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom(0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom(1.1)
	elif event is InputEventMouseMotion and _dragging:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT or Input.is_key_pressed(KEY_SHIFT):
			# right-drag (or shift-drag) pans
			var k := dist * 0.0016
			pan(-event.relative.x * k, event.relative.y * k)
		else:
			yaw -= event.relative.x * 0.006
			pitch += event.relative.y * 0.006
		idle = 0.0
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			var pts := _touches.values()
			_pinch_d = pts[0].distance_to(pts[1])
	elif event is InputEventScreenDrag:
		var prev: Vector2 = _touches.get(event.index, event.position)
		_touches[event.index] = event.position
		if _touches.size() == 1:
			yaw -= event.relative.x * 0.008
			pitch += event.relative.y * 0.008
		elif _touches.size() == 2:
			var pts := _touches.values()
			var d: float = pts[0].distance_to(pts[1])
			if _pinch_d > 0.0:
				zoom(_pinch_d / maxf(d, 1.0))
			_pinch_d = d
			# two fingers moving together pan
			var mv: Vector2 = (event.position - prev) * 0.5
			var k := dist * 0.0016
			pan(-mv.x * k, mv.y * k)
		idle = 0.0



## Arrow icons drawn into a little image (the web font has no arrow glyphs).
func _icon(action: String) -> Texture2D:
	var n := 22
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Color(1.0, 0.92, 0.78)
	var c := (n - 1) * 0.5
	match action:
		"up", "down", "left", "right", "tiltup", "tiltdn":
			var dir := {"up": Vector2(0, -1), "tiltup": Vector2(0, -1), "down": Vector2(0, 1), "tiltdn": Vector2(0, 1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}[action] as Vector2
			var small := action.begins_with("tilt")
			var tip := Vector2(c, c) + dir * (5.0 if small else 8.0)
			var side := Vector2(-dir.y, dir.x)
			var base := Vector2(c, c) - dir * (3.0 if small else 6.0)
			var hw := 5.0 if small else 8.0
			var tri := PackedVector2Array([tip, base + side * hw, base - side * hw])
			for y in n:
				for x in n:
					if Geometry2D.is_point_in_polygon(Vector2(x, y), tri):
						img.set_pixel(x, y, col)
		"rotl", "rotr":
			# a three-quarter ring with an arrowhead at its end
			var r0 := 5.5
			var r1 := 8.5
			for y in n:
				for x in n:
					var v := Vector2(x - c, y - c)
					var d := v.length()
					var a := fposmod(atan2(v.y, v.x) * (1.0 if action == "rotr" else -1.0), TAU)
					if d >= r0 and d <= r1 and a > 0.9:
						img.set_pixel(x, y, col)
			var end_a := 0.9
			var sgn := 1.0 if action == "rotr" else -1.0
			var p := Vector2(cos(end_a), sin(end_a) * sgn) * 7.0 + Vector2(c, c)
			var tang := Vector2(sin(end_a), -cos(end_a) * sgn)
			var rad := Vector2(cos(end_a), sin(end_a) * sgn)
			var tri := PackedVector2Array([p + tang * 5.0, p + rad * 5.5, p - rad * 5.5])
			for y in n:
				for x in n:
					if Geometry2D.is_point_in_polygon(Vector2(x, y), tri):
						img.set_pixel(x, y, col)
		_:
			return null
	return ImageTexture.create_from_image(img)
