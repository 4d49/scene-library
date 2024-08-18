# Copyright (c) 2023-2024 Mansur Isaev and contributors - MIT License
# See `LICENSE.md` included in the source distribution for details.

@tool
extends EditorPlugin


const SceneLibrary = preload("res://addons/scene-library/scripts/scene_library.gd")

const BUTTON_NAME: String = "Scene Library"


var _editor: SceneLibrary = null
var _button: Button = null


func _enter_tree() -> void:
	_editor = SceneLibrary.new()
	_button = add_control_to_bottom_panel(_editor, BUTTON_NAME)
	_editor.open_asset_request.connect(_on_open_asset_request)
	_editor.show_in_file_system_request.connect(_on_show_in_file_system_request)
	_editor.show_in_file_manager_request.connect(_on_show_in_file_manager_request)
	_editor.library_saved.connect(_on_library_saved)
	_editor.library_unsaved.connect(_on_library_unsaved)

	get_parent().connect(&"scene_saved", _editor.handle_scene_saved)
	EditorInterface.get_file_system_dock().files_moved.connect(_editor.handle_file_moved)
	EditorInterface.get_file_system_dock().file_removed.connect(_editor.handle_file_removed)


func _exit_tree() -> void:
	remove_control_from_bottom_panel(_editor)
	_editor.queue_free()


func _save_external_data() -> void:
	if _editor.is_saved():
		return

	var library_path: String = _editor.get_current_library_path()
	if library_path.is_empty():
		return

	_editor.save_library(library_path)


func _on_library_saved() -> void:
	_button.set_text(BUTTON_NAME)

func _on_library_unsaved() -> void:
	_button.set_text(BUTTON_NAME + "(*)")


func _on_open_asset_request(path: String) -> void:
	EditorInterface.open_scene_from_path(path)


func _on_show_in_file_system_request(path: String) -> void:
	EditorInterface.get_file_system_dock().navigate_to_path(path)


func _on_show_in_file_manager_request(path: String) -> void:
	var error := OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path), true)
	if error:
		push_warning(error_string(error))
