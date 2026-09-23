extends Node

signal toggle_requested


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and not event.is_echo():
		toggle_requested.emit()
		get_viewport().set_input_as_handled()
