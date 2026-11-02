class_name UiKit
extends RefCounted
## Shared look from the mockups: USC green, gold, cream cards with thick dark borders and hard
## shadows. Screens build their widgets through these helpers so they all match.

const INK := Color("#1d2a22")
const GREEN := Color("#1f5a3d")
const GREEN_DARK := Color("#143d29")
const GOLD := Color("#e0b23a")
const GOLD_DARK := Color("#8a6410")
const GOLD_PALE := Color("#fff6d9")
const CREAM := Color("#fbfaf4")
const PAPER := Color("#f3efe2")
const MINT := Color("#dfe7e4")
const MUTED := Color("#55604f")
const SOFT := Color("#9fb0aa")
const RED := Color("#b8382a")
const RED_PALE := Color("#fbe3df")
const OK := Color("#2f7d46")
const BLUE := Color("#3b6ea5")
const DISABLED := Color("#c9cfcb")
const MONO_FONT := preload("res://fonts/JetBrainsMono.ttf")
const PORTRAIT_SCENE := preload("res://scenes/portrait/portrait.tscn")


## Empties a container right away. queue_free alone leaves the old children in place until the end
## of the frame, so a container briefly holds old and new together, grows, and never shrinks back.
static func clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


static func box(bg: Color, border: int = 4, border_color: Color = INK, shadow: int = 0, pad: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border_color
	style.set_border_width_all(border)
	style.set_content_margin_all(pad)
	if shadow > 0:
		style.shadow_color = INK
		style.shadow_size = 1
		style.shadow_offset = Vector2(shadow, shadow)
	return style


static func card(bg: Color = CREAM, pad: int = 12, shadow: int = 5, border: int = 4) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box(bg, border, INK, shadow, pad))
	return panel


static func label(text: String, size: int = 20, color: Color = INK, mono: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if mono:
		node.add_theme_font_override("font", MONO_FONT)
	return node


static func wrapped(text: String, size: int = 20, color: Color = INK) -> Label:
	var node := label(text, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node


static func button(text: String, bg: Color = PAPER, fg: Color = INK, size: int = 22) -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_stylebox_override("normal", box(bg, 4, INK, 4, 8))
	node.add_theme_stylebox_override("hover", box(bg.lightened(0.12), 4, INK, 4, 8))
	node.add_theme_stylebox_override("pressed", box(bg.darkened(0.15), 4, INK, 1, 8))
	node.add_theme_stylebox_override("disabled", box(DISABLED, 4, SOFT, 0, 8))
	node.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		node.add_theme_color_override(state, fg)
	node.add_theme_color_override("font_disabled_color", MUTED)
	return node


## A bordered square showing a portrait cropped to head and shoulders.
static func portrait_frame(parts: Dictionary, inner: float, border_color: Color = GOLD, fill: Color = GREEN, border: int = 3) -> Panel:
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", box(fill, border, border_color))
	frame.custom_minimum_size = Vector2.ONE * (inner + border * 2)
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	var crop := Control.new()
	crop.clip_contents = true
	crop.position = Vector2.ONE * border
	crop.size = Vector2.ONE * inner
	crop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(crop)
	var portrait: Portrait = PORTRAIT_SCENE.instantiate()
	crop.add_child(portrait)
	portrait.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var width := inner * 1.08
	portrait.position = Vector2((inner - width) / 2.0, -inner * 0.125)
	portrait.size = Vector2(width, width * 1228.0 / 1024.0)
	portrait.apply(parts.duplicate(true))
	frame.set_meta("portrait", portrait)
	return frame


static func frame_portrait(frame: Panel) -> Portrait:
	return frame.get_meta("portrait")
