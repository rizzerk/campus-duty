class_name Portrait
extends Control
## A student's face, stacked from layered parts. Resize this Control to scale the whole portrait.
## apply() is safe to call before the portrait is added to the tree.

const PORTRAIT_SCENE_PATH := "res://scenes/portrait/portrait.tscn"
const PARENT_OFFSET := Vector2(-0.38, 0.0)
const PARENT_SHADE := Color(0.82, 0.82, 0.82)

var _parts: Dictionary = {}
var _parent_portrait: Portrait = null


func apply(parts: Dictionary) -> void:
	_parts = parts
	$Body.texture = _load_part("body", PortraitGen.data()["body"])
	$Body.self_modulate = Color(parts["skin"])
	_apply_optional($Wrinkles, "wrinkles", parts.get("wrinkles", ""))
	_apply_optional($FacialHair, "facial_hair", parts.get("facial_hair", ""))
	$FacialHair.self_modulate = Color(parts["hair_color"])
	$Brows.self_modulate = Color(parts["brow_color"])
	$Hair.texture = _load_part("hair", parts["hair"])
	$Hair.self_modulate = Color(parts["hair_color"])
	$Clothes.texture = _load_part("clothes", parts["clothes"])
	$Clothes.self_modulate = Color(parts["clothes_color"])
	_apply_accessories(parts["accessories"], parts.get("accessory_colors", {}))
	set_expression(parts["expression"])
	_apply_parent(parts.get("parent", {}))


## Swaps only the face parts. Everything else stays as it is.
func set_expression(expression: String) -> void:
	var face: Dictionary = PortraitGen.data()["expressions"][expression]
	_parts["expression"] = expression
	$Eyes.texture = _load_part("eye", PortraitGen.eye_part(_parts["eye_style"], expression))
	$Eyes.visible = not PortraitGen.hides_eyes(_parts["accessories"])
	$Brows.texture = _load_part("brow", face["brow"])
	$Mouth.texture = _load_part("mouth", face["mouth"])


func _apply_optional(layer: TextureRect, slot: String, part_name: String) -> void:
	layer.visible = part_name != ""
	layer.texture = _load_part(slot, part_name) if layer.visible else null


func _apply_accessories(names: Array, colors: Dictionary) -> void:
	for old: Node in $Accessories.get_children():
		old.free()
	for accessory: String in names:
		var layer := TextureRect.new()
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		layer.texture = _load_part("accessory", accessory)
		layer.self_modulate = Color(colors.get(accessory, "#ffffff"))
		$Accessories.add_child(layer)


func _apply_parent(parent_parts: Dictionary) -> void:
	if parent_parts.is_empty():
		if _parent_portrait != null:
			_parent_portrait.free()
			_parent_portrait = null
		return
	if _parent_portrait == null:
		_parent_portrait = (load(PORTRAIT_SCENE_PATH) as PackedScene).instantiate()
		add_child(_parent_portrait)
		move_child(_parent_portrait, 0)
		_parent_portrait.anchor_left = PARENT_OFFSET.x
		_parent_portrait.anchor_right = 1.0 + PARENT_OFFSET.x
		_parent_portrait.anchor_top = PARENT_OFFSET.y
		_parent_portrait.anchor_bottom = 1.0 + PARENT_OFFSET.y
		_parent_portrait.modulate = PARENT_SHADE
	_parent_portrait.apply(parent_parts)


func _load_part(slot: String, part_name: String) -> Texture2D:
	return load(PortraitGen.part_path(slot, part_name))
