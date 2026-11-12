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

## F4 window art, drawn by tools/art/window_art.py at 3x. The 9-slice margins below (left, top,
## right, bottom, in screen pixels) have to match the drawings, so update both together.
const DESK_TILE := preload("res://art/window/desk_tile.png")
const DESK_EDGE := preload("res://art/window/desk_edge.png")
const PAPER_TEXTURE := preload("res://art/window/paper.png")
const ID_CARD_TEXTURE := preload("res://art/window/id_card.png")
const MONITOR_TEXTURE := preload("res://art/window/monitor.png")
const SCANLINES_TEXTURE := preload("res://art/window/screen_scanlines.png")
const BUTTON_TEXTURE := preload("res://art/window/button.png")
const BUTTON_PRESSED_TEXTURE := preload("res://art/window/button_pressed.png")
const BUTTON_DISABLED_TEXTURE := preload("res://art/window/button_disabled.png")
const PAPER_SLICE := [6, 15, 18, 9]
const ID_CARD_SLICE := [6, 15, 9, 9]
const MONITOR_SLICE := [15, 15, 18, 27]
const BUTTON_SLICE := [6, 6, 9, 12]
## Every piece with a drop shadow draws it 3px past its rect, so layouts stay the same size.
const SHADOW := 3
## The button face is drawn a little under white so its highlight survives tinting.
const BUTTON_FACE := 240.0 / 255.0


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


## A 9-slice panel from one of the window textures. `content` is the inner padding (left, top,
## right, bottom); a shadowed piece draws its shadow outside the rect, past the right and bottom.
static func slice(texture: Texture2D, margins: Array, content: Array, shadow: bool = true, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.modulate_color = tint
	for side in 4:
		style.set_texture_margin(side, margins[side])
		style.set_content_margin(side, content[side])
	if shadow:
		style.expand_margin_right = SHADOW
		style.expand_margin_bottom = SHADOW
	return style


## A form on the desk. The ID card has a green band across the top, so its text starts lower.
static func paper_style(id_card: bool = false) -> StyleBoxTexture:
	if id_card:
		return slice(ID_CARD_TEXTURE, ID_CARD_SLICE, [6, 14, 6, 6])
	return slice(PAPER_TEXTURE, PAPER_SLICE, [6, 6, 6, 6])


## The ISMIS monitor's plastic bezel, with a deeper chin for the power light.
static func monitor_style() -> StyleBoxTexture:
	return slice(MONITOR_TEXTURE, MONITOR_SLICE, [15, 15, 15, 24])


## The ISMIS screen glass: the screen color with faint scanlines.
static func screen_style(pad: int = 10) -> StyleBoxTexture:
	var style := slice(SCANLINES_TEXTURE, [0, 0, 0, 0], [pad, pad, pad, pad], false)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return style


## The counter the window sits on: tiled wood with a lip along the top edge.
static func desk() -> Control:
	var desk_node := TextureRect.new()
	desk_node.texture = DESK_TILE
	desk_node.stretch_mode = TextureRect.STRETCH_TILE
	desk_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge := TextureRect.new()
	edge.texture = DESK_EDGE
	edge.stretch_mode = TextureRect.STRETCH_TILE
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.set_anchors_preset(Control.PRESET_TOP_WIDE)
	edge.offset_bottom = DESK_EDGE.get_height()
	desk_node.add_child(edge)
	return desk_node


## Tints the grey button art. Dividing by the face's grey keeps the face the exact color asked for.
static func _button_tint(color: Color) -> Color:
	return Color(color.r / BUTTON_FACE, color.g / BUTTON_FACE, color.b / BUTTON_FACE, color.a)


static func button(text: String, bg: Color = PAPER, fg: Color = INK, size: int = 22) -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_stylebox_override("normal", slice(BUTTON_TEXTURE, BUTTON_SLICE, [8, 8, 8, 10], true, _button_tint(bg)))
	node.add_theme_stylebox_override("hover", slice(BUTTON_TEXTURE, BUTTON_SLICE, [8, 8, 8, 10], true, _button_tint(bg.lightened(0.12))))
	# Pressed, the button sits where its shadow was, so the text moves with it.
	node.add_theme_stylebox_override("pressed", slice(BUTTON_PRESSED_TEXTURE, BUTTON_SLICE, [11, 11, 5, 7], true, _button_tint(bg.darkened(0.15))))
	node.add_theme_stylebox_override("disabled", slice(BUTTON_DISABLED_TEXTURE, BUTTON_SLICE, [8, 8, 8, 10]))
	node.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		node.add_theme_color_override(state, fg)
	node.add_theme_color_override("font_disabled_color", MUTED)
	node.pressed.connect(func() -> void: Sfx.play("click"))
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
