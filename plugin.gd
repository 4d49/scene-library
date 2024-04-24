# Copyright (c) 2023-2024 Mansur Isaev and contributors - MIT License
# See `LICENSE.md` included in the source distribution for details.

@tool
extends EditorPlugin


var _editor : Control = null
var _button : Button = null

@warning_ignore("unsafe_method_access", "unsafe_property_access", "return_value_discarded")
func _enter_tree() -> void:
	_editor = load("res://addons/scene-library/scripts/scene_library.gd").new()
	_editor.library_saved.connect(_mark_saved)
	_editor.library_unsaved.connect(_mark_unsaved)
	_editor.open_asset_request.connect(_on_open_asset_request)
	_editor.show_in_file_system_request.connect(_on_show_in_file_system_request)
	_editor.show_in_file_manager_request.connect(_on_show_in_file_manager_request)
	_button = add_control_to_bottom_panel(_editor, "Scene Library")

	get_parent().connect(&"scene_saved", _editor.handle_scene_saved)
	get_editor_interface().get_file_system_dock().files_moved.connect(_editor.handle_file_moved)
	get_editor_interface().get_file_system_dock().file_removed.connect(_editor.handle_file_removed)


func _exit_tree() -> void:
	remove_control_from_bottom_panel(_editor)
	_editor.queue_free()


func _mark_saved() -> void:
	_button.set_text("Scene Library")


func _mark_unsaved() -> void:
	_button.set_text("Scene Library(*)")


func _on_open_asset_request(path: String) -> void:
	get_editor_interface().open_scene_from_path(path)


func _on_show_in_file_system_request(path: String) -> void:
	get_editor_interface().get_file_system_dock().navigate_to_path(path)


func _on_show_in_file_manager_request(path: String) -> void:
	var error := OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path), true)
	if error:
		push_warning(error_string(error))
