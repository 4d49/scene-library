# Copyright (c) 2023-2025 Mansur Isaev and contributors - MIT License
# See `LICENSE.md` included in the source distribution for details.

@tool
extends EditorPlugin


const SceneLibrary = preload("res://addons/scene-library/scripts/scene_library.gd")

const DOCK_NAME: String = "Scene Library"


var _editor: SceneLibrary = null
var _dock: EditorDock = null


func _enter_tree() -> void:
	_editor = SceneLibrary.new()
	_dock = EditorDock.new()
	_dock.name = DOCK_NAME
	_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	_dock.add_child(_editor)
	add_dock(_dock)
	_editor.open_asset_request.connect(_on_open_asset_request)
	_editor.inherit_asset_request.connect(_on_inherit_asset_request)
	_editor.show_in_file_system_request.connect(_on_show_in_file_system_request)
	_editor.show_in_file_manager_request.connect(_on_show_in_file_manager_request)
	_editor.library_saved.connect(_on_library_saved)
	_editor.library_unsaved.connect(_on_library_unsaved)

	get_parent().connect(&"scene_saved", _editor.handle_scene_saved)
	EditorInterface.get_file_system_dock().files_moved.connect(_editor.handle_file_moved)
	EditorInterface.get_file_system_dock().file_removed.connect(_editor.handle_file_removed)


func _exit_tree() -> void:
	remove_dock(_dock)
	_dock.queue_free()


func _save_external_data() -> void:
	if _editor.is_saved():
		return

	# TODO: Should move the logic inside the class.
	var library := _editor.get_current_library()
	if not is_instance_valid(library) or library.get_path().is_empty():
		return

	_editor.save_library(library.get_path())


func _on_library_saved() -> void:
	_dock.name = DOCK_NAME

func _on_library_unsaved() -> void:
	_dock.name = DOCK_NAME + "(*)"


func _on_open_asset_request(path: String) -> void:
	EditorInterface.open_scene_from_path(path)

func _on_inherit_asset_request(path: String) -> void:
	EditorInterface.open_scene_from_path(path, true)

func _on_show_in_file_system_request(path: String) -> void:
	EditorInterface.get_file_system_dock().navigate_to_path(path)


func _on_show_in_file_manager_request(path: String) -> void:
	var error := OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path), true)
	if error:
		push_warning(error_string(error))
