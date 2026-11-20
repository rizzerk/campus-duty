class_name LineStrip
extends PanelContainer
## The queue as a row of faces. Priority students (GRAD, PWD) can be clicked to call them early.
## The line is alive: faces bob while they wait, pull out a phone, fan themselves and sigh the
## longer it takes (LineChatter decides which), and cheer when the window is on a roll. Reduced
## motion keeps the tells and expressions but nothing moves.

signal face_clicked(index: int)

const FACE := 54.0
const MAX_FACES := 12
const HINT := "Click a GRAD or PWD face to call them out of turn"
const FLASH_SECONDS := 4.0
const BOB_PIXELS := 2.0
const BOB_SECONDS := 1.8
## What anchor_of returns right after a rebuild, until the containers have laid the new faces
## out (later that frame). A speech bubble keeps its place until the real spot is known.
const LAYING_OUT := Vector2(-INF, -INF)

var _faces: HBoxContainer
var _more: Label
var _hint: Label
var _flash_left: float = 0.0
var _cheer_left: float = 0.0
## One entry per face shown: { student, frame, tell, expression }.
var _shown: Array = []
var _minute: float = 0.0
var _patience: float = 100.0
var _laid_out: bool = true


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.box(Color("#cfdcd6"), 3, UiKit.INK, 0, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var title := UiKit.label("THE\nLINE", 20, UiKit.GREEN)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	_faces = HBoxContainer.new()
	_faces.add_theme_constant_override("separation", 8)
	row.add_child(_faces)
	_more = UiKit.label("", 20, UiKit.MUTED)
	_more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_more)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_hint = UiKit.wrapped(HINT, 16, UiKit.MUTED)
	_hint.custom_minimum_size.x = 200
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hint)


## A short alert where the hint usually is, like a rush wave arriving.
func flash(text: String) -> void:
	_hint.text = text
	_hint.add_theme_color_override("font_color", UiKit.RED)
	_flash_left = FLASH_SECONDS


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_hint.text = HINT
			_hint.add_theme_color_override("font_color", UiKit.MUTED)
	if _cheer_left > 0.0:
		_cheer_left -= delta
		if _cheer_left <= 0.0:
			_apply_moods()


func refresh(line: Array, patience: float, minute: float = 0.0) -> void:
	_minute = minute
	_patience = patience
	UiKit.clear(_faces)
	_shown.clear()
	for i in mini(line.size(), MAX_FACES):
		_faces.add_child(_make_face(line[i], i))
	_more.text = "+%d more" % (line.size() - MAX_FACES) if line.size() > MAX_FACES else ""
	_apply_moods()
	# The containers sort the new faces in deferred calls queued above; this one runs after them.
	_laid_out = false
	_finish_layout.call_deferred()


func _finish_layout() -> void:
	_laid_out = true


## Updates what each face is doing as time passes, without rebuilding the row.
func update_moods(patience: float, minute: float) -> void:
	_minute = minute
	_patience = patience
	_apply_moods()


## The whole line cheers for a moment: big smiles and a little bounce.
func cheer(seconds: float) -> void:
	_cheer_left = seconds
	_apply_moods()
	for i in _shown.size():
		var frame: Control = _shown[i]["frame"]
		get_tree().create_timer(0.05 * i).timeout.connect(func() -> void:
			if is_instance_valid(frame):
				Juice.punch(frame, 1.12, 0.25))


## The face at index says something: a small bounce so the eye finds who spoke.
func speak(index: int) -> void:
	if index >= 0 and index < _shown.size():
		Juice.punch(_shown[index]["frame"], 1.1, 0.2)


## How many faces are on screen (the rest are "+N more").
func shown_count() -> int:
	return _shown.size()


## The top middle of a student's face, in canvas coordinates, where a speech bubble points.
## Vector2.INF if they aren't among the faces on screen (called up, or behind "+N more"), and
## LAYING_OUT if the row was just rebuilt and isn't placed yet.
func anchor_of(student: Dictionary) -> Vector2:
	for entry: Dictionary in _shown:
		if is_same(entry["student"], student):
			if not _laid_out:
				return LAYING_OUT
			var holder := (entry["frame"] as Control).get_parent() as Control
			# Where the face rests, not where a shake has it this frame, so a bubble never jitters.
			var shake: Vector2 = get_meta("juice_home") - position if has_meta("juice_home") else Vector2.ZERO
			return holder.global_position + Vector2(holder.size.x / 2.0, 0.0) + shake
	return Vector2.INF


func _make_face(student: Dictionary, index: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var tag_text := ""
	var tag_color := UiKit.GOLD
	if student["priority"] == "grad":
		tag_text = "GRAD"
	elif student["priority"] == "pwd":
		tag_text = "PWD"
		tag_color = Color("#7fb3e0")
	elif student.get("mood", "") == "angry":
		tag_text = "BACK"
		tag_color = Color("#f08a7a")
	var tag := UiKit.label(tag_text, 14, UiKit.INK)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if tag_text != "":
		tag.add_theme_stylebox_override("normal", UiKit.box(tag_color, 2))
	box.add_child(tag)
	var parts: Dictionary = student["portrait"].duplicate(true)
	parts["expression"] = _expression(student, "")
	var frame := UiKit.portrait_frame(parts, FACE, UiKit.INK, Color("#9fd0e8"), 2)
	# Sized now, not at the next layout pass, so a bounce right away scales from the middle.
	frame.size = frame.custom_minimum_size
	if student["priority"] != "":
		frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		frame.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				face_clicked.emit(index))
	# The frame sits in a plain holder so it can bob without the box laying it out again.
	var holder := Control.new()
	holder.custom_minimum_size = frame.custom_minimum_size
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.add_child(frame)
	var tell := LineTell.new()
	holder.add_child(tell)
	box.add_child(holder)
	_shown.append({ "student": student, "frame": frame, "tell": tell, "expression": parts["expression"], "index": index })
	return box


func _expression(student: Dictionary, idle: String) -> String:
	if student.get("mood", "") == "angry":
		return "angry"
	if _cheer_left > 0.0:
		return "delighted"
	if idle == "sigh" or _patience < LineChatter.setting("sigh_patience"):
		return "annoyed"
	return student["portrait"].get("expression", "neutral")


func _apply_moods() -> void:
	var moving := Settings.motion_allowed()
	for entry: Dictionary in _shown:
		var student: Dictionary = entry["student"]
		var idle := "" if _cheer_left > 0.0 else LineChatter.idle_state(student, _minute, _patience)
		var tell: LineTell = entry["tell"]
		tell.show_kind(idle, moving)
		var expression := _expression(student, idle)
		if expression != entry["expression"]:
			entry["expression"] = expression
			UiKit.frame_portrait(entry["frame"]).set_expression(expression)
		_set_bob(entry["frame"], moving, int(entry["index"]))


## Each face bobs gently, out of step with its neighbors. Reduced motion stops it in place.
func _set_bob(frame: Control, moving: bool, index: int) -> void:
	var bob: Variant = frame.get_meta("bob") if frame.has_meta("bob") else null
	var running: bool = bob is Tween and bob.is_valid()
	if moving == running:
		return
	if not moving:
		bob.kill()
		frame.remove_meta("bob")
		frame.position = Vector2.ZERO
		return
	var tween := frame.create_tween().set_loops()
	# Each face rests a different moment between bobs, so neighbors drift out of step.
	tween.tween_interval(0.0001 + fmod(index * 0.37, BOB_SECONDS / 2.0))
	tween.tween_property(frame, "position:y", -BOB_PIXELS, BOB_SECONDS / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(frame, "position:y", 0.0, BOB_SECONDS / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	frame.set_meta("bob", tween)


## A small drawn prop next to a waiting face: a phone, a paper fan or a sigh puff. Placeholder
## shapes until the line art has them. Moves (the fan sways, the puff drifts up) only when motion
## is allowed.
class LineTell:
	extends Control

	var kind: String = ""
	var _tween: Tween

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(58, 58)

	func show_kind(next: String, moving: bool) -> void:
		var animating := _tween != null and _tween.is_valid()
		if next == kind and animating == (moving and kind != "" and kind != "phone"):
			return
		kind = next
		if animating:
			_tween.kill()
		rotation = 0.0
		modulate.a = 1.0
		position = Vector2.ZERO
		queue_redraw()
		if not moving or kind == "" or kind == "phone":
			return
		_tween = create_tween().set_loops()
		if kind == "fan":
			pivot_offset = Vector2(6, 50)
			_tween.tween_property(self, "rotation", 0.25, 0.3).set_trans(Tween.TRANS_SINE)
			_tween.tween_property(self, "rotation", -0.15, 0.3).set_trans(Tween.TRANS_SINE)
		else:
			_tween.tween_property(self, "position:y", -6.0, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_tween.parallel().tween_property(self, "modulate:a", 0.0, 1.4)
			_tween.tween_property(self, "position:y", 0.0, 0.0)
			_tween.tween_property(self, "modulate:a", 1.0, 0.0)
			_tween.tween_interval(0.6)

	func _draw() -> void:
		match kind:
			"phone":
				draw_rect(Rect2(42, 34, 11, 17), UiKit.INK)
				draw_rect(Rect2(44, 36, 7, 11), Color("#cfeaff"))
			"fan":
				var points := PackedVector2Array([Vector2(6, 50)])
				for step in 7:
					var angle := deg_to_rad(-150.0 + step * 20.0)
					points.append(Vector2(6, 50) + Vector2(cos(angle), sin(angle)) * 16.0)
				draw_colored_polygon(points, UiKit.GOLD)
				draw_polyline(points + PackedVector2Array([points[0]]), UiKit.INK, 1.5)
			"sigh":
				# Outlined, so the puff reads on the pale strip and the light-blue face backing.
				for puff: Array in [[Vector2(48, 6), 6.0], [Vector2(55, 2), 4.0], [Vector2(42, 12), 2.5]]:
					draw_circle(puff[0], puff[1] + 1.5, UiKit.INK)
				for puff: Array in [[Vector2(48, 6), 6.0], [Vector2(55, 2), 4.0], [Vector2(42, 12), 2.5]]:
					draw_circle(puff[0], puff[1], UiKit.CREAM)
