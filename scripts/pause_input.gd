extends Node

signal toggle_requested
signal employee_menu_requested


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and not event.is_echo():
		toggle_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("employee_menu") and not event.is_echo():
		employee_menu_requested.emit()
		get_viewport().set_input_as_handled()
