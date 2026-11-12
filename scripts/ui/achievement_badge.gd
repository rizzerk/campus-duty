class_name AchievementBadge
extends RefCounted
## Drawn badges for achievements until there is pixel art for each one.


## The square badge for an achievement: gold when unlocked, grey when not. A hidden one shows "?".
static func make(item: Dictionary, is_open: bool, size: float = 64.0) -> Control:
	var panel := PanelContainer.new()
	var fill := UiKit.GOLD if is_open else UiKit.DISABLED
	var edge := UiKit.GOLD_DARK if is_open else UiKit.SOFT
	panel.add_theme_stylebox_override("panel", UiKit.box(fill, 4, edge, 3 if is_open else 0))
	panel.custom_minimum_size = Vector2(size, size)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var secret: bool = item.get("hidden", false) and not is_open
	var text := UiKit.label("?" if secret else str(item.get("badge", "")), int(size * 0.42), UiKit.INK if is_open else UiKit.MUTED)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(text)
	return panel
