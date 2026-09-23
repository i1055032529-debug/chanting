@tool
extends StaticBody2D
## Picture, footprint, interaction and item mount are editable scene children.

@export var station_id := ""
@export var display_name := ""
@onready var marker: Marker2D = $InteractionPoint
@onready var caption: Label = $Caption
@onready var item: Sprite2D = $ItemMount/Item


func _ready() -> void:
	caption.text = display_name


func interaction_position() -> Vector2:
	return marker.global_position


func set_highlight(active: bool) -> void:
	caption.modulate = Color("ffe6a5") if active else Color("fff1d5")
	$InteractionPoint/Hint.visible = active


func show_item(visible_item: bool, used := false) -> void:
	item.visible = visible_item
	item.frame = 1 if used else 0
