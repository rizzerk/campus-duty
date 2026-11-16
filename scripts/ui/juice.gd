class_name Juice
extends RefCounted
## Game feel in one place: shake, punch, flashes, pop text, slides, banners, a heartbeat, hit stop
## and confetti. All tween based, nothing per frame,
## and none of it takes input, so the player can act during any effect. Every function reads
## Settings: reduced motion drops shake and movement, screen shake off drops shake. Each returns
## the Tween it started, or null when the settings (or a node that isn't in the tree) skip it.
## Starting an effect stops the same effect still running on that node, so they never stack.

## True while a hit stop has the game slowed, so two can't overlap.
static var _stopping: bool = false


## Jolts a node around where it sits, then puts it back exactly there. For impacts: a wrong call,
## a stamp landing. Never use it on the paper the player is reading (2 px at most there).
## axis scales the jolt per direction: Vector2(0, 1) shakes only up and down, for a bar that
## spans the screen and would show the wall at its ends.
static func shake(node: Control, strength: float = 6.0, duration: float = 0.3, axis: Vector2 = Vector2(1.0, 0.4)) -> Tween:
	if not _ready_for(node) or not Settings.shake_allowed():
		return null
	var home: Vector2 = node.get_meta("juice_home") if node.has_meta("juice_home") else node.position
	_stop(node, "juice_shake")
	node.set_meta("juice_home", home)
	node.position = home
	var tween := node.create_tween()
	var steps := 6
	for i in steps:
		# Each jolt is smaller than the last, so it settles instead of stopping dead.
		var fade := 1.0 - float(i) / steps
		var offset := Vector2(strength * axis.x * fade * (1.0 if i % 2 == 0 else -1.0), strength * axis.y * fade * (1.0 if i % 3 == 0 else -1.0))
		tween.tween_property(node, "position", home + offset, duration / (steps + 1))
	tween.tween_property(node, "position", home, duration / (steps + 1))
	tween.finished.connect(func() -> void:
		if is_instance_valid(node):
			node.remove_meta("juice_home"))
	node.set_meta("juice_shake", tween)
	return tween


## Scales a node up from its center and lets it spring back to normal size. For a stamp landing,
## a button, a number that changed.
static func punch(node: Control, amount: float = 1.15, duration: float = 0.12) -> Tween:
	if not _ready_for(node) or not Settings.motion_allowed():
		return null
	_stop(node, "juice_punch")
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2.ONE * amount
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	node.set_meta("juice_punch", tween)
	return tween


## Tints a node with color and fades back to its normal look. Not motion, so reduced motion keeps
## it, only shorter.
static func flash(node: CanvasItem, color: Color, duration: float = 0.25) -> Tween:
	if not _ready_for(node):
		return null
	_stop(node, "juice_flash")
	var base: Color = node.get_meta("juice_flash_base") if node.has_meta("juice_flash_base") else node.modulate
	node.set_meta("juice_flash_base", base)
	node.modulate = color
	var tween := node.create_tween()
	tween.tween_property(node, "modulate", base, _calm(duration))
	tween.finished.connect(func() -> void:
		if is_instance_valid(node):
			node.remove_meta("juice_flash_base"))
	node.set_meta("juice_flash", tween)
	return tween


## A see-through wash of color over the whole of parent that fades out and frees itself. For a
## right (green) or wrong (red) call. Clicks go straight through it.
static func screen_flash(parent: Control, color: Color, duration: float = 0.25) -> Tween:
	if not _ready_for(parent):
		return null
	# The last wash may already have freed itself: check it's alive before asking what it is.
	var old: Variant = parent.get_meta("juice_wash") if parent.has_meta("juice_wash") else null
	if old != null and is_instance_valid(old) and old is ColorRect:
		old.queue_free()
	var wash := ColorRect.new()
	wash.color = color
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(wash)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.set_meta("juice_wash", wash)
	var tween := wash.create_tween()
	tween.tween_property(wash, "modulate:a", 0.0, _calm(duration))
	tween.finished.connect(func() -> void:
		if is_instance_valid(parent) and parent.get_meta("juice_wash", null) == wash:
			parent.remove_meta("juice_wash")
		wash.queue_free())
	return tween


## A word or number that pops up at `at` (in parent's coordinates), drifts up and fades. With
## reduced motion it only fades. A new pop replaces the one still showing, so words never overlap.
static func pop_text(parent: Control, text: String, color: Color, at: Vector2, size: int = 30) -> Tween:
	if not _ready_for(parent):
		return null
	var old: Variant = parent.get_meta("juice_pop") if parent.has_meta("juice_pop") else null
	if old != null and is_instance_valid(old) and old is Label:
		old.queue_free()
	var label := UiKit.label(text, size, color)
	parent.set_meta("juice_pop", label)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_outline_color", UiKit.INK)
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	label.reset_size()
	label.position = at - Vector2(label.size.x / 2.0, label.size.y)
	var tween := label.create_tween().set_parallel()
	if Settings.motion_allowed():
		label.pivot_offset = label.size / 2.0
		label.scale = Vector2.ONE * 0.6
		tween.tween_property(label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(label, "position:y", label.position.y - 36.0, 0.7).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.45)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(parent) and parent.get_meta("juice_pop", null) == label:
			parent.remove_meta("juice_pop")
		label.queue_free())
	return tween


## Brings a node in from offset back to where it sits, overshooting a touch. For a student
## arriving at the window. With reduced motion it simply appears in place.
static func slide_in(node: Control, offset: Vector2, duration: float = 0.35) -> Tween:
	if not _ready_for(node) or not Settings.motion_allowed():
		return null
	var home: Vector2 = node.get_meta("juice_home") if node.has_meta("juice_home") else node.position
	_stop(node, "juice_shake")
	_stop(node, "juice_slide")
	node.set_meta("juice_home", home)
	node.position = home + offset
	var tween := node.create_tween()
	tween.tween_property(node, "position", home, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		if is_instance_valid(node):
			node.remove_meta("juice_home"))
	node.set_meta("juice_slide", tween)
	return tween


## A beat every period seconds until stop_heartbeat: on_beat runs (play the sound there), and the
## node swells and settles, or with reduced motion only brightens. Settings are read on each beat,
## so changing them in the pause menu applies at once. Starting it again replaces the old one.
static func heartbeat(node: Control, period: float, on_beat: Callable) -> Tween:
	if not _ready_for(node):
		return null
	stop_heartbeat(node)
	var beat := func() -> void:
		if not is_instance_valid(node):
			return
		on_beat.call()
		if Settings.motion_allowed():
			punch(node, 1.1, period * 0.3)
		else:
			flash(node, Color(1.6, 1.6, 1.6), period * 0.2)
	var tween := node.create_tween().set_loops()
	tween.tween_callback(beat)
	tween.tween_interval(period)
	node.set_meta("juice_heartbeat", tween)
	return tween


static func stop_heartbeat(node: Control) -> void:
	if node == null or not is_instance_valid(node) or not node.has_meta("juice_heartbeat"):
		return
	_stop(node, "juice_heartbeat")
	_stop(node, "juice_punch")
	_stop(node, "juice_flash")
	node.scale = Vector2.ONE
	if node.has_meta("juice_flash_base"):
		node.modulate = node.get_meta("juice_flash_base")
		node.remove_meta("juice_flash_base")


## A banner that drops in from above parent's top edge to at_y, holds, and goes back up. For a
## rush wave. With reduced motion it appears at at_y and fades. A new banner replaces the old.
static func banner(parent: Control, text: String, color: Color, at_y: float, hold: float = 1.4) -> Tween:
	if not _ready_for(parent):
		return null
	var old: Variant = parent.get_meta("juice_banner") if parent.has_meta("juice_banner") else null
	if old != null and is_instance_valid(old) and old is Control:
		old.queue_free()
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UiKit.box(UiKit.INK, 4, color, 4, 12))
	var label := UiKit.label(text, 28, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)
	parent.add_child(card)
	parent.set_meta("juice_banner", card)
	card.reset_size()
	card.position = Vector2((parent.size.x - card.size.x) / 2.0, at_y)
	var tween := card.create_tween()
	if Settings.motion_allowed():
		card.position.y = -card.size.y - 8.0
		tween.tween_property(card, "position:y", at_y, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_interval(hold)
		tween.tween_property(card, "position:y", -card.size.y - 8.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		tween.tween_interval(hold + 0.3)
		tween.tween_property(card, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func() -> void:
		if is_instance_valid(parent) and parent.get_meta("juice_banner", null) == card:
			parent.remove_meta("juice_banner")
		card.queue_free())
	return tween


## Freezes the game for a blink (at most 0.06 s) so an impact lands, then lets it run on. Skipped
## with reduced motion, and while another hit stop is still going. Returns whether it ran.
static func hit_stop(node: Node, seconds: float = 0.05) -> bool:
	if _stopping or node == null or not is_instance_valid(node) or not node.is_inside_tree() or not Settings.motion_allowed():
		return false
	_stopping = true
	Engine.time_scale = 0.05
	# The timer ignores the time scale it just set, and runs while paused, so the game always
	# comes back to full speed.
	node.get_tree().create_timer(minf(seconds, 0.06), true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0
		_stopping = false)
	return true


## A one-shot burst of at most 40 paper bits at `at` in parent, freed when done. For three stars.
## Skipped with reduced motion.
static func confetti(parent: Control, at: Vector2, amount: int = 36) -> CPUParticles2D:
	if not _ready_for(parent) or not Settings.motion_allowed():
		return null
	var bits := CPUParticles2D.new()
	bits.amount = clampi(amount, 1, 40)
	bits.one_shot = true
	bits.explosiveness = 0.9
	bits.lifetime = 1.2
	bits.direction = Vector2.UP
	# Gentle enough to stay on screen when it starts near the top (it peaks about 60 px up).
	bits.spread = 110.0
	bits.gravity = Vector2(0.0, 700.0)
	bits.initial_velocity_min = 150.0
	bits.initial_velocity_max = 290.0
	bits.angular_velocity_min = -360.0
	bits.angular_velocity_max = 360.0
	bits.scale_amount_min = 4.0
	bits.scale_amount_max = 7.0
	var colors := Gradient.new()
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colors.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75])
	colors.colors = PackedColorArray([UiKit.GOLD, UiKit.OK_BRIGHT, UiKit.CREAM, UiKit.RED_BRIGHT])
	bits.color_initial_ramp = colors
	bits.position = at
	parent.add_child(bits)
	bits.finished.connect(bits.queue_free)
	bits.emitting = true
	return bits


## Ends any shake, punch or slide on node at once and puts it back where and how big it was, so another
## tween (say, the papers sliding away) can move it without a fight.
static func settle(node: Control) -> void:
	if node == null or not is_instance_valid(node):
		return
	_stop(node, "juice_shake")
	_stop(node, "juice_punch")
	_stop(node, "juice_slide")
	if node.has_meta("juice_home"):
		node.position = node.get_meta("juice_home")
		node.remove_meta("juice_home")
	node.scale = Vector2.ONE


static func _ready_for(node: CanvasItem) -> bool:
	return node != null and is_instance_valid(node) and node.is_inside_tree()


## Kills the tween stored under key on node, if one is still running.
static func _stop(node: Node, key: String) -> void:
	if node.has_meta(key):
		var old: Variant = node.get_meta(key)
		if old is Tween and old.is_valid():
			old.kill()
		node.remove_meta(key)


## Reduced motion keeps color changes but makes them brief.
static func _calm(duration: float) -> float:
	return minf(duration, 0.12) if not Settings.motion_allowed() else duration
