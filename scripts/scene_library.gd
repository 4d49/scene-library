# Copyright (c) 2023-2026 Mansur Isaev and contributors - MIT License
# See `LICENSE.md` included in the source distribution for details.

extends MarginContainer


signal collection_count_changed

signal library_unsaved
signal library_saved

signal collection_changed

signal open_asset_request(path: String)
signal inherit_asset_request(path: String)
signal show_in_file_system_request(path: String)
signal show_in_file_manager_request(path: String)
signal asset_display_mode_changed(display_mode: DisplayMode)


enum CollectionTabMenu {
	NEW,
	RENAME,
	DELETE,
}
enum LibraryMenu {
	NEW,
	OPEN,
	SAVE,
	SAVE_AS,
}
enum DisplayMode{
	THUMBNAILS,
	LIST,
}
enum SortMode {
	NAME,
	NAME_REVERSE,
}
enum AssetContextMenu {
	OPEN_ASSET,
	INHERIT_ASSET,
	COPY_PATH,
	COPY_UID,
	DELETE_ASSET,
	SHOW_IN_FILE_SYSTEM,
	SHOW_IN_FILE_MANAGER,
	REFRESH,
	MAX,
}


const Asset: GDScript = preload("asset.gd")
const AssetCollection: GDScript = preload("asset_collection.gd")
const AssetLibrary: GDScript = preload("asset_library.gd")


const EDITOR_SETTING_THUMBNAIL_MODE: String = "addons/scene_library/thumbnail/mode"
const EDITOR_SETTING_THUMBNAIL_GRID_SIZE: String = "addons/scene_library/thumbnail/grid_size"
const EDITOR_SETTING_THUMBNAIL_LIST_SIZE: String = "addons/scene_library/thumbnail/list_size"
const EDITOR_SETTING_SORT_MODE: String = "addons/scene_library/sort_mode"

const PROJECT_SETTING_CACHE_ENABLED: String = "addons/scene_library/cache/enabled"
const PROJECT_SETTING_CACHE_PATH: String = "addons/scene_library/cache/path"
const PROJECT_SETTING_CURRENT_LIBRARY_PATH: String = "addons/scene_library/library/current_library_path"


const THUMB_GRID_SIZE: int = 192
const THUMB_LIST_SIZE: int = 48


var _main_vbox: VBoxContainer = null

var _collec_hbox: HBoxContainer = null
var _collec_tab_bar: TabBar = null
var _collec_tab_add: Button = null
var _all_tabs_list: MenuButton = null
var _collec_option: MenuButton = null

var _main_container: PanelContainer = null
var _content_vbox: VBoxContainer = null

var _top_hbox: HBoxContainer = null
var _asset_filter_line: LineEdit = null
var _asset_sort_mode_btn: Button = null

var _mode_thumb_btn: Button = null
var _mode_list_btn: Button = null

var _item_list: ItemList = null

var _item_context_menu: PopupMenu = null
var _collec_context_menu: PopupMenu = null
var _open_dialog: ConfirmationDialog = null
var _save_dialog: ConfirmationDialog = null
var _rename_collec_window: ConfirmationDialog = null
var _create_collec_dialog: ConfirmationDialog = null
var _remove_collec_dialog: ConfirmationDialog = null

var _save_timer: Timer = null

var _thumb_grid_icon_size: int = 64
var _thumb_list_icon_size: int = 16

# INFO: May be required for debugging.
var _cache_enabled: bool = true
var _cache_path: String = "res://.godot/thumb_cache"

# Create thumbnail scene:
var _viewport: SubViewport = null

var _camera_2d: Camera2D = null

var _camera_3d: Camera3D = null
var _light_3d: DirectionalLight3D = null

var _asset_display_mode: DisplayMode = DisplayMode.THUMBNAILS
var _sort_mode: SortMode = SortMode.NAME

var _thumbnails: Dictionary[int, ImageTexture] = {}

var _mutex: Mutex = null
var _thread: Thread = null
var _thread_queue: Array[Dictionary] = []
var _thread_sem: Semaphore = null
var _thread_work: bool = true

var _saved: bool = true

var _curr_lib: AssetLibrary = null
var _curr_collec: AssetCollection = null


func _update_position_new_collection_btn() -> void:
	var tab_bar_total_width := float(_collec_tab_bar.get_theme_constant(&"h_separation"))
	for i: int in _collec_tab_bar.get_tab_count():
		tab_bar_total_width += _collec_tab_bar.get_tab_rect(i).size.x

	_collec_tab_bar.size = Vector2(minf(_collec_tab_bar.size.x, tab_bar_total_width), 0.0)
	_collec_tab_add.position.x = _collec_tab_bar.size.x

	_all_tabs_list.set_visible(_collec_tab_bar.get_offset_buttons_visible())


func _ready() -> void:
	_cache_enabled = get_or_create_project_setting(PROJECT_SETTING_CACHE_ENABLED, true)
	_cache_path = get_or_create_project_setting(PROJECT_SETTING_CACHE_PATH, "res://.godot/thumb_cache")

	_asset_display_mode = get_or_create_editor_setting(EDITOR_SETTING_THUMBNAIL_MODE, DisplayMode.THUMBNAILS)

	_thumb_grid_icon_size = get_or_create_editor_setting(EDITOR_SETTING_THUMBNAIL_GRID_SIZE, 64)
	_thumb_list_icon_size = get_or_create_editor_setting(EDITOR_SETTING_THUMBNAIL_LIST_SIZE, 16)

	_sort_mode = get_or_create_editor_setting(EDITOR_SETTING_SORT_MODE, SortMode.NAME)

	self.add_theme_constant_override(&"margin_left", -get_theme_stylebox(&"BottomPanel", &"EditorStyles").get_margin(SIDE_LEFT))
	self.add_theme_constant_override(&"margin_right", -get_theme_stylebox(&"BottomPanel", &"EditorStyles").get_margin(SIDE_RIGHT))
	self.add_theme_constant_override(&"margin_top", -get_theme_stylebox(&"BottomPanel", &"EditorStyles").get_margin(SIDE_TOP))

	self.set_custom_minimum_size(Vector2(0.0, 180.0))

	# INFO: Required to create a tab pseudo-container background.
	var tabbar_background := Panel.new()
	tabbar_background.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"tabbar_background", &"TabContainer"))
	self.add_child(tabbar_background)

	_main_vbox = VBoxContainer.new()
	_main_vbox.add_theme_constant_override(&"separation", 0)
	self.add_child(_main_vbox)

	_collec_hbox = HBoxContainer.new()
	_collec_hbox.add_theme_constant_override(&"separation", 0)
	# INFO: Required to calculate the position of the "new" button.
	_collec_hbox.sort_children.connect(_update_position_new_collection_btn)
	_main_vbox.add_child(_collec_hbox)

	_collec_tab_bar = TabBar.new()
	_collec_tab_bar.set_auto_translate(false)
	_collec_tab_bar.set_drag_to_rearrange_enabled(true)
	_collec_tab_bar.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	_collec_tab_bar.set_max_tab_width(256) # TODO: Make this parameter receive global editor settings.
	_collec_tab_bar.set_theme_type_variation(&"TabContainer")
	_collec_tab_bar.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"DebuggerPanel", &"EditorStyles"))
	_collec_tab_bar.set_select_with_rmb(true)
	_collec_tab_bar.add_tab("[null]")
	_collec_tab_bar.set_tab_disabled(0, true)
	_collec_tab_bar.set_tab_close_display_policy(TabBar.CLOSE_BUTTON_SHOW_NEVER)
	_collec_tab_bar.tab_selected.connect(_on_collection_tab_changed)
	_collec_tab_bar.tab_close_pressed.connect(_on_collection_tab_close_pressed)
	_collec_tab_bar.tab_rmb_clicked.connect(_on_collection_tab_rmb_clicked)
	_collec_tab_bar.active_tab_rearranged.connect(_on_collection_tab_rearranged)
	_collec_hbox.add_child(_collec_tab_bar)

	_collec_tab_add = Button.new()
	_collec_tab_add.set_flat(true)
	_collec_tab_add.set_disabled(true)
	_collec_tab_add.set_tooltip_text("Add a new Collection.")
	_collec_tab_add.set_button_icon(get_theme_icon(&"Add", &"EditorIcons"))
	_collec_tab_add.add_theme_color_override(&"icon_normal_color", Color(0.6, 0.6, 0.6, 0.8))
	_collec_tab_add.set_h_size_flags(Control.SIZE_SHRINK_END)
	_collec_tab_add.pressed.connect(show_create_collection_dialog)
	_collec_hbox.add_child(_collec_tab_add)

	_all_tabs_list = MenuButton.new()
	_all_tabs_list.hide()
	_all_tabs_list.set_tooltip_text("List all tabs.")
	_all_tabs_list.set_button_icon(get_theme_icon(&"GuiOptionArrow", &"EditorIcons"))
	_all_tabs_list.add_theme_color_override(&"icon_normal_color", Color(0.6, 0.6, 0.6, 0.8))
	_collec_hbox.add_child(_all_tabs_list)

	var popup: PopupMenu = _all_tabs_list.get_popup()
	popup.index_pressed.connect(_collec_tab_bar.set_current_tab)

	_collec_option = MenuButton.new()
	_collec_option.set_flat(true)
	_collec_option.set_button_icon(get_theme_icon(&"GuiTabMenuHl", &"EditorIcons"))
	_collec_option.add_theme_color_override(&"icon_normal_color", Color(0.6, 0.6, 0.6, 0.8))
	_collec_hbox.add_child(_collec_option)

	popup = _collec_option.get_popup()
	popup.add_item("New Library", LibraryMenu.NEW)
	popup.add_item("Open Library", LibraryMenu.OPEN)
	popup.add_separator()
	popup.add_item("Save Library", LibraryMenu.SAVE)
	popup.add_item("Save Library As...", LibraryMenu.SAVE_AS)
	popup.id_pressed.connect(_on_collection_option_id_pressed)

	_main_container = PanelContainer.new()
	_main_container.set_mouse_filter(Control.MOUSE_FILTER_IGNORE)
	_main_container.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	_main_container.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"DebuggerPanel", &"EditorStyles"))
	_main_vbox.add_child(_main_container)

	_content_vbox = VBoxContainer.new()
	_main_container.add_child(_content_vbox)

	_top_hbox = HBoxContainer.new()
	_content_vbox.add_child(_top_hbox)

	_asset_filter_line = LineEdit.new()
	_asset_filter_line.set_placeholder("Filter assets")
	_asset_filter_line.set_clear_button_enabled(true)
	_asset_filter_line.set_right_icon(get_theme_icon(&"Search", &"EditorIcons"))
	_asset_filter_line.set_editable(false) # The value will be changed when the collection is changed.
	_asset_filter_line.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	_asset_filter_line.text_changed.connect(_on_filter_assets_text_changed)
	_top_hbox.add_child(_asset_filter_line)

	_asset_sort_mode_btn = Button.new()
	_asset_sort_mode_btn.set_disabled(true)
	_asset_sort_mode_btn.set_tooltip_text("Toggle alphabetical sorting of assets")
	_asset_sort_mode_btn.set_flat(true)
	_asset_sort_mode_btn.set_toggle_mode(true)
	_asset_sort_mode_btn.set_button_icon(get_theme_icon(&"Sort", &"EditorIcons"))
	_asset_sort_mode_btn.toggled.connect(_sort_assets_button_toggled)
	_top_hbox.add_child(_asset_sort_mode_btn)

	_top_hbox.add_child(VSeparator.new())

	var button_group := ButtonGroup.new()

	_mode_thumb_btn = Button.new()
	_mode_thumb_btn.set_flat(true)
	_mode_thumb_btn.set_disabled(true)
	_mode_thumb_btn.set_tooltip_text("View items as a grid of thumbnails.")
	_mode_thumb_btn.set_toggle_mode(true)
	_mode_thumb_btn.set_button_icon(get_theme_icon(&"FileThumbnail", &"EditorIcons"))
	_mode_thumb_btn.set_button_group(button_group)
	_mode_thumb_btn.pressed.connect(set_asset_display_mode.bind(DisplayMode.THUMBNAILS))
	_top_hbox.add_child(_mode_thumb_btn)

	_mode_list_btn = Button.new()
	_mode_list_btn.set_flat(true)
	_mode_list_btn.set_disabled(true)
	_mode_list_btn.set_tooltip_text("View items as a list.")
	_mode_list_btn.set_toggle_mode(true)
	_mode_list_btn.set_button_icon(get_theme_icon(&"FileList", &"EditorIcons"))
	_mode_list_btn.set_button_group(button_group)
	_mode_list_btn.pressed.connect(set_asset_display_mode.bind(DisplayMode.LIST))
	_top_hbox.add_child(_mode_list_btn)

	_item_list = AssetItemList.new()
	_item_list.set_focus_mode(Control.FOCUS_CLICK)
	_item_list.set_max_columns(0)
	_item_list.set_mouse_filter(Control.MOUSE_FILTER_PASS)
	_item_list.set_same_column_width(true)
	_item_list.set_select_mode(ItemList.SELECT_MULTI)
	_item_list.set_texture_filter(CanvasItem.TEXTURE_FILTER_LINEAR)
	_item_list.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	_item_list.gui_input.connect(_on_item_list_gui_input)
	_item_list.item_clicked.connect(_on_item_list_item_clicked)
	_item_list.item_activated.connect(_on_item_list_item_activated)
	_content_vbox.add_child(_item_list)

	_open_dialog = _create_file_dialog(true)
	_open_dialog.set_title("Open Asset Library")
	_open_dialog.connect(&"file_selected", load_library)
	self.add_child(_open_dialog)

	_save_dialog = _create_file_dialog(false)
	_save_dialog.set_title("Save Asset Library As...")
	_save_dialog.connect(&"file_selected", save_library)
	self.add_child(_save_dialog)

	_save_timer = Timer.new()
	_save_timer.set_one_shot(true)
	_save_timer.set_wait_time(10.0) # Save unsaved data every 10 seconds.
	_save_timer.timeout.connect(_on_save_timer_timeout)
	library_unsaved.connect(_save_timer.start)
	self.add_child(_save_timer)

	var world_2d := World2D.new()

	var world_3d := World3D.new()
	# TODO: Add a feature to change Environment.
	world_3d.set_environment(get_viewport().get_world_3d().get_environment())

	_viewport = SubViewport.new()
	_viewport.set_world_2d(world_2d)
	_viewport.set_world_3d(world_3d)
	_viewport.set_update_mode(SubViewport.UPDATE_DISABLED) # We'll update the frame manually.
	_viewport.set_debug_draw(Viewport.DEBUG_DRAW_DISABLE_LOD) # This is necessary to avoid visual glitches.
	_viewport.set_process_mode(Node.PROCESS_MODE_DISABLED) # Needs to disable animations.
	_viewport.set_size(Vector2i(THUMB_GRID_SIZE, THUMB_GRID_SIZE))
	_viewport.set_disable_input(true)
	_viewport.set_transparent_background(true)
	_viewport.set_physics_object_picking(false)
	_viewport.set_default_canvas_item_texture_filter(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter"))
	_viewport.set_default_canvas_item_texture_repeat(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_repeat"))
	_viewport.set_fsr_sharpness(ProjectSettings.get_setting("rendering/scaling_3d/fsr_sharpness"))
	_viewport.set_msaa_2d(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d"))
	_viewport.set_msaa_3d(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d"))
	_viewport.set_positional_shadow_atlas_16_bits(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_16_bits"))
	_viewport.set_positional_shadow_atlas_quadrant_subdiv(0, ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_quadrant_0_subdiv"))
	_viewport.set_positional_shadow_atlas_quadrant_subdiv(1, ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_quadrant_1_subdiv"))
	_viewport.set_positional_shadow_atlas_quadrant_subdiv(2, ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_quadrant_2_subdiv"))
	_viewport.set_positional_shadow_atlas_quadrant_subdiv(3, ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_quadrant_3_subdiv"))
	_viewport.set_positional_shadow_atlas_size(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_size"))
	_viewport.set_scaling_3d_mode(ProjectSettings.get_setting("rendering/scaling_3d/mode"))
	_viewport.set_scaling_3d_scale(ProjectSettings.get_setting("rendering/scaling_3d/scale"))
	_viewport.set_screen_space_aa(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa"))
	_viewport.set_texture_mipmap_bias(ProjectSettings.get_setting("rendering/textures/default_filters/texture_mipmap_bias"))
	self.add_child(_viewport)

	_camera_2d = Camera2D.new()
	_camera_2d.set_enabled(false)
	_viewport.add_child(_camera_2d)

	# TODO: Add a feature to set lighting.
	_light_3d = DirectionalLight3D.new()
	_light_3d.set_shadow_mode(DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	_light_3d.set_bake_mode(Light3D.BAKE_STATIC)
	_light_3d.set_shadow(true)
	_light_3d.basis *= Basis(Vector3.UP, deg_to_rad(45.0))
	_light_3d.basis *= Basis(Vector3.LEFT, deg_to_rad(65.0))
	_viewport.add_child(_light_3d)

	_camera_3d = Camera3D.new()
	_camera_3d.set_current(false)
	_camera_3d.set_fov(22.5)
	_viewport.add_child(_camera_3d)

	# Multithreading starts here.
	_mutex = Mutex.new()
	_thread_sem = Semaphore.new()
	_thread = Thread.new()
	_thread.start(_thread_process)

	collection_count_changed.connect(update_tabs)

	collection_changed.connect(update_item_list)
	asset_display_mode_changed.connect(_update_asset_display_mode)

	load_library(get_or_create_project_setting(PROJECT_SETTING_CURRENT_LIBRARY_PATH, "res://addons/scene-library/scene_library.cfg"))

	collection_changed.connect(_collec_tab_bar.size_flags_changed.emit)

	_update_asset_display_mode(_asset_display_mode)


func _exit_tree() -> void:
	_mutex.lock()
	_thread_work = false
	_mutex.unlock()

	_thread_sem.post()
	if _thread.is_started():
		_thread.wait_to_finish()

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not _item_list.get_rect().has_point(at_position):
		return false

	if not data is Dictionary or data.get("type") != "files":
		return false

	if not is_instance_valid(_curr_lib) or not is_instance_valid(_curr_collec):
		return false

	var files: PackedStringArray = data["files"]
	var rec_ext: PackedStringArray = ResourceLoader.get_recognized_extensions_for_type("PackedScene")

	for file: String in files:
		var extension: String = file.get_extension().to_lower()
		if not rec_ext.has(extension):
			return false

		if _curr_collec.has_asset_path(file) or not is_valid_scene_file(file):
			return false

	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary:
		var files: PackedStringArray = data["files"]

		for path: String in files:
			create_asset(path)


## Retrieves or creates an editor setting with a default value.
## If the setting doesn't exist, it's initialized with the default value.
## Returns the current value of the setting
func get_or_create_editor_setting(setting_name: String, default_value: Variant) -> Variant:
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	if not editor_settings.has_setting(setting_name):
		editor_settings.set_setting(setting_name, default_value)
		editor_settings.set_initial_value(setting_name, default_value, false)

	return editor_settings.get_setting(setting_name)

## Retrieves or creates an editor setting with a default value.
## If the setting doesn't exist, it's initialized with the default value.
## Returns the current value of the setting
func get_or_create_project_setting(setting_name: String, default_value: Variant) -> Variant:
	if not ProjectSettings.has_setting(setting_name):
		ProjectSettings.set_setting(setting_name, default_value)
		ProjectSettings.set_initial_value(setting_name, default_value)

	return ProjectSettings.get_setting(setting_name, default_value)

## Set editor setting value
func set_editor_setting(setting_name: String, value: Variant) -> void:
	EditorInterface.get_editor_settings().set_setting(setting_name, value)

## Set project setting value.
func set_project_setting(setting_name: String, value: Variant) -> void:
	ProjectSettings.set_setting(setting_name, value)


func mark_saved() -> void:
	library_saved.emit()
	_saved = true

func mark_unsaved() -> void:
	library_unsaved.emit()
	_saved = false

func is_saved() -> bool:
	return _saved


func set_current_library(library: AssetLibrary) -> void:
	if is_same(_curr_lib, library):
		return

	_curr_lib = library
	update_tabs()
	# Switch to the first tab.
	_collec_tab_bar.set_current_tab(0)

func get_current_library() -> AssetLibrary:
	return _curr_lib


func has_collection(collection_name: String) -> bool:
	if is_instance_valid(_curr_lib):
		return _curr_lib.has_collection(collection_name)

	return false


func create_collection(collection_name: String) -> void:
	assert(not has_collection(collection_name), "Collection with this name already exists.")

	var collection: AssetCollection = AssetCollection.new()
	collection.set_name(collection_name)
	_curr_lib.add_collection(collection)

	collection_count_changed.emit()
	mark_unsaved()

	# Switch to the last tab.
	_collec_tab_bar.set_current_tab(_collec_tab_bar.get_tab_count() - 1)


func remove_collection(index: int) -> void:
	_curr_lib.remove_collection(index)

	collection_count_changed.emit()
	mark_unsaved()

	# Swith to the prev tab.
	_collec_tab_bar.set_current_tab(_collec_tab_bar.get_current_tab())


func show_remove_collection_dialog(index: int) -> void:
	if _curr_lib.get_collection(index).is_empty():
		return remove_collection(index)

	if is_instance_valid(_remove_collec_dialog):
		_remove_collec_dialog.queue_free()

	_remove_collec_dialog = ConfirmationDialog.new()
	_remove_collec_dialog.set_size(Vector2i.ZERO)
	_remove_collec_dialog.set_flag(Window.FLAG_RESIZE_DISABLED, true)
	_remove_collec_dialog.set_ok_button_text("Remove")
	_remove_collec_dialog.set_text("Are you sure you want to delete this collection? (Cannot be undone.)")
	_remove_collec_dialog.canceled.connect(_remove_collec_dialog.queue_free)
	_remove_collec_dialog.close_requested.connect(_remove_collec_dialog.queue_free)
	_remove_collec_dialog.confirmed.connect(remove_collection.bind(index))
	self.add_child(_remove_collec_dialog)

	_remove_collec_dialog.popup_centered(Vector2i(300, 0))


func _queue_has_id(id: int) -> bool:
	_mutex.lock()

	for item: Dictionary in _thread_queue:
		if item.id == id:
			_mutex.unlock()
			return true

	_mutex.unlock()
	return false

func _queue_update_thumbnail(id: int) -> void:
	if not _thumbnails.has(id) or _queue_has_id(id):
		return

	_mutex.lock()
	var queue_item: Dictionary[StringName, Variant] = {&"id": id, &"thumb": _thumbnails[id]}
	_thread_queue.push_back(queue_item)
	_mutex.unlock()

	_thread_sem.post()

func _get_or_create_thumbnail(id: int, path: String) -> ImageTexture:
	var thumb: ImageTexture = _thumbnails.get(id, null)
	if is_instance_valid(thumb):
		return thumb

	var cache_path: String = _get_thumb_cache_path(path)
	if _cache_enabled and FileAccess.file_exists(cache_path):
		thumb = ImageTexture.create_from_image(Image.load_from_file(cache_path))
		_thumbnails[id] = thumb
	else:
		const THUMB_PLACEHOLDER_PATH: String = "res://addons/scene-library/icons/thumb_placeholder.svg"

		var thumb_placeholder_path: String = ProjectSettings.globalize_path(THUMB_PLACEHOLDER_PATH)
		thumb = ImageTexture.create_from_image(Image.load_from_file(thumb_placeholder_path))
		_thumbnails[id] = thumb

		_queue_update_thumbnail(id)

	return thumb

func _create_asset(id: int, uid: String, path: String) -> Asset:
	var asset: Asset = Asset.new()
	asset.id = id
	asset.uid = uid
	asset.path = path
	asset.thumb = _get_or_create_thumbnail(id, path)

	return asset


static func is_valid_scene_file(path: String) -> bool:
	const TYPE_HINT: String = "PackedScene"

	if not ResourceLoader.exists(path, TYPE_HINT):
		return false

	var valid_extensions := ResourceLoader.get_recognized_extensions_for_type(TYPE_HINT)
	return path.get_extension().to_lower() in valid_extensions



static func get_or_create_valid_uid(path: String) -> int:
	var id: int = ResourceLoader.get_resource_uid(path)
	if id == ResourceUID.INVALID_ID:
		id = ResourceUID.create_id()
		ResourceUID.add_id(id, path)

	return id


func create_asset(path: String) -> void:
	assert(is_valid_scene_file(path), "PackedScene file was not found or has an invalid extension.")

	var id: int = get_or_create_valid_uid(path)
	var asset: Asset = _create_asset(id, ResourceUID.id_to_text(id), path)
	_curr_collec.add_asset(asset)

	collection_changed.emit()
	mark_unsaved()


func remove_asset(id: int) -> bool:
	if not _curr_collec.erase_asset_by_id(id):
		return false

	collection_changed.emit()
	mark_unsaved()

	return true


func set_current_collection(collection: AssetCollection) -> void:
	if is_same(_curr_collec, collection):
		return

	_curr_collec = collection

	_item_list.deselect_all()
	collection_changed.emit()

func get_current_collection() -> AssetCollection:
	return _curr_collec


func update_tabs() -> void:
	var is_valid: bool = is_instance_valid(_curr_lib)

	_asset_filter_line.set_editable(is_valid)
	_collec_tab_add.set_disabled(not is_valid)
	_asset_sort_mode_btn.set_disabled(not is_valid)
	_mode_thumb_btn.set_disabled(not is_valid)
	_mode_list_btn.set_disabled(not is_valid)

	if is_valid and _curr_lib.get_collection_count():
		_collec_tab_bar.set_tab_count(_curr_lib.get_collection_count())
		_collec_tab_bar.set_tab_close_display_policy(TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY)

		var popup: PopupMenu = _all_tabs_list.get_popup()
		popup.set_item_count(_curr_lib.get_collection_count())

		for i: int in _curr_lib.get_collection_count():
			var collection: AssetCollection = _curr_lib.get_collection(i)
			_collec_tab_bar.set_tab_title(i, collection.get_name())
			_collec_tab_bar.set_tab_disabled(i, false)
			_collec_tab_bar.set_tab_metadata(i, collection)

			popup.set_item_text(i, collection.get_name())
	else:
		_collec_tab_bar.set_tab_count(1)
		_collec_tab_bar.set_tab_close_display_policy(TabBar.CLOSE_BUTTON_SHOW_NEVER)
		_collec_tab_bar.set_tab_title(0, "[null]")
		_collec_tab_bar.set_tab_disabled(0, true)
		_collec_tab_bar.set_tab_metadata(0, null)

	# INFO: Required to recalculate position of the "new collection" button.
	_collec_tab_bar.size_flags_changed.emit()


func update_item_list() -> void:
	_item_list.set_item_count(_curr_collec.get_size())

	var filter: String = _asset_filter_line.get_text()

	var index: int = 0
	for asset: Asset in _curr_collec.get_assets():
		var path: String = asset.path
		if not filter.is_subsequence_ofn(path.get_file()):
			continue

		_item_list.set_item_text(index, path.get_file().get_basename())
		_item_list.set_item_icon(index, asset.thumb)
		# NOTE: This tooltip will be hidden because used the custom tooltip.
		_item_list.set_item_tooltip(index, path)
		_item_list.set_item_metadata(index, asset)

		index += 1

	_item_list.set_item_count(index)


func set_asset_display_mode(display_mode: DisplayMode) -> void:
	if is_same(_asset_display_mode, display_mode):
		return

	_asset_display_mode = display_mode
	set_editor_setting(EDITOR_SETTING_THUMBNAIL_MODE, display_mode)

	asset_display_mode_changed.emit(display_mode)

func get_asset_display_mode() -> DisplayMode:
	return _asset_display_mode


static func sort_asset_ascending(a: Asset, b: Asset) -> bool:
	return a.path.get_file() < b.path.get_file()

static func sort_asset_descending(a: Asset, b: Asset) -> bool:
	return a.path.get_file() > b.path.get_file()


func set_sort_mode(sort_mode: SortMode) -> void:
	if is_same(_sort_mode, sort_mode):
		return

	if sort_mode == SortMode.NAME:
		_curr_collec.sort(sort_asset_ascending)
	else:
		_curr_collec.sort(sort_asset_descending)

	_sort_mode = sort_mode
	set_editor_setting(EDITOR_SETTING_SORT_MODE, sort_mode)
	collection_changed.emit()

func get_sort_mode() -> SortMode:
	return _sort_mode


func show_create_collection_dialog() -> AcceptDialog:
	if is_instance_valid(_create_collec_dialog):
		_create_collec_dialog.queue_free()

	_create_collec_dialog = ConfirmationDialog.new()
	_create_collec_dialog.set_size(Vector2i.ZERO)
	_create_collec_dialog.set_title("Create New Collection")
	_create_collec_dialog.set_flag(Window.FLAG_RESIZE_DISABLED, true)
	_create_collec_dialog.get_label().hide() # Faced with the fact that the "panel" is drawn from the Label.
	_create_collec_dialog.close_requested.connect(_create_collec_dialog.queue_free)
	_create_collec_dialog.canceled.connect(_create_collec_dialog.queue_free)

	var ok_button: Button = _create_collec_dialog.get_ok_button()
	ok_button.set_text("Create")
	ok_button.set_disabled(true)

	var vbox := VBoxContainer.new()
	_create_collec_dialog.add_child(vbox)

	var label := Label.new()
	label.set_text("New Collection Name:")
	vbox.add_child(label)

	var line_edit := LineEdit.new()
	line_edit.set_text("new_collection")
	line_edit.select_all()
	line_edit.call_deferred(&"grab_focus")

	# INFO: Disables the ability to create a collection and set a tooltip.
	line_edit.text_changed.connect(func(c_name: String) -> void:
		if c_name.is_empty():
			line_edit.set_tooltip_text("Collection name is empty.")
		elif has_collection(c_name):
			line_edit.set_tooltip_text("Collection with this name already exists.")
		else:
			line_edit.set_tooltip_text("")

		ok_button.set_disabled(c_name.is_empty() or has_collection(c_name))
		line_edit.set_right_icon(get_theme_icon(&"StatusError", &"EditorIcons") if ok_button.is_disabled() else null)
	)
	line_edit.text_changed.emit(line_edit.get_text()) # Required for status updates.
	vbox.add_child(line_edit)

	self.add_child(_create_collec_dialog)
	_create_collec_dialog.register_text_enter(line_edit)
	_create_collec_dialog.confirmed.connect(func() -> void:
		var new_collec_name: String = line_edit.get_text()
		create_collection(new_collec_name)
	)
	_create_collec_dialog.popup_centered(Vector2i(300, 0))

	return _create_collec_dialog



func _serialize_asset(asset: Asset) -> Dictionary:
	return {"uid": asset.uid, "path": asset.path}

func _serialize_assets(assets: Array[Asset]) -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	serialized.resize(assets.size())

	for i: int in assets.size():
		serialized[i] = _serialize_asset(assets[i])

	return serialized

func _serialize_collection(collection: AssetCollection) -> Dictionary:
	return {
		"name": collection.get_name(),
		"assets": _serialize_assets(collection.get_assets()),
	}

func _serialize_library(library: AssetLibrary) -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	serialized.resize(library.get_collection_count())

	for i: int in library.get_collection_count():
		serialized[i] = _serialize_collection(library.get_collection(i))

	return serialized


func _cfg_save_library(library: AssetLibrary, path: String) -> void:
	var serialized: Array[Dictionary] = _serialize_library(library)

	var config := ConfigFile.new()
	config.set_value("", "library", serialized)

	var error := config.save(path)
	assert(error == OK, error_string(error))

func _json_save_library(library: AssetLibrary, path: String) -> void:
	var serialized: Array[Dictionary] = _serialize_library(library)

	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(FileAccess.get_open_error() == OK, error_string(FileAccess.get_open_error()))

	file.store_string(JSON.stringify(serialized, "\t"))
	file.close()

func save_library(path: String) -> void:
	var extension: String = path.get_extension()
	assert(extension == "cfg" or extension == "json", "Invalid extension.")

	if extension == "cfg":
		_cfg_save_library(_curr_lib, path)
	elif extension == "json":
		_json_save_library(_curr_lib, path)
	else:
		return

	mark_saved()


func _deserialize_asset(asset: Dictionary) -> Asset:
	var uid: String = asset.get("uid", "")
	var path: String = asset.get("path", "")

	var id: int = ResourceUID.text_to_id(uid)

	# TODO: Add error handling.
	if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id): # If the UID is valid.
		path = ResourceUID.get_id_path(id)
	# If the UID is wrong, try to load the asset by the path.
	# It also checks whether the file extension is valid.
	elif is_valid_scene_file(path):
		id = ResourceLoader.get_resource_uid(path)
		uid = ResourceUID.id_to_text(id)

		if not ResourceUID.has_id(id):
			ResourceUID.add_id(id, path)
	# Invalid asset.
	else:
		return null

	return _create_asset(id, uid, path)

func _deserialize_assets(assets: Array) -> Array[Asset]:
	var deserialized: Array[Asset] = []

	for asset: Dictionary in assets:
		var deserialized_asset: Asset = _deserialize_asset(asset)
		if is_instance_valid(deserialized_asset):
			deserialized.push_back(deserialized_asset)

	return deserialized

func _deserialize_collection(collection: Dictionary) -> AssetCollection:
	var deserialized: AssetCollection = AssetCollection.new()
	deserialized.set_name(collection.name)

	for asset: Asset in _deserialize_assets(collection.assets):
		deserialized.add_asset(asset)

	return deserialized

func _deserialize_library(library: Array) -> AssetLibrary:
	var deserialized: AssetLibrary = AssetLibrary.new()

	for i: int in library.size():
		deserialized.add_collection(_deserialize_collection(library[i]))

	return deserialized


func _load_cfg(path: String) -> AssetLibrary:
	var config := ConfigFile.new()

	var error := config.load(path)
	assert(error == OK, error_string(error))

	var data: Variant = config.get_value("", "library")
	if data is Array:
		return _deserialize_library(data)

	return null

func _load_json(path: String) -> AssetLibrary:
	var json := JSON.new()

	var error := json.parse(FileAccess.get_file_as_string(path))
	assert(error == OK, error_string(error))

	var data: Variant = json.get_data()
	if data is Array:
		return _deserialize_library(data)

	return null

func load_library(path: String) -> void:
	var library: AssetLibrary = null

	if FileAccess.file_exists(path):
		var extension: String = path.get_extension()
		assert(extension == "cfg" or extension == "json", "Invalid extension.")

		if extension == "cfg":
			library = _load_cfg(path)
		elif extension == "json":
			library = _load_json(path)

	if not is_instance_valid(library):
		return

	library.set_path(path)
	set_current_library(library)
	set_project_setting(PROJECT_SETTING_CURRENT_LIBRARY_PATH, path)


func _calculate_node_rect(node: Node) -> Rect2:
	var rect := Rect2()

	if node is Node2D and node.is_visible():
		# HACK: This works only in editor.
		rect = node.get_global_transform() * node.call(&"_edit_get_rect")

	for i: int in node.get_child_count(true):
		rect = rect.merge(_calculate_node_rect(node.get_child(i, true)))

	return rect

func _calculate_node_aabb(node: Node) -> AABB:
	var aabb := AABB()

	if node is Node3D and not node.is_visible():
		return aabb
	# NOTE: If the node is not MeshInstance3D, the AABB is not calculated correctly.
	# The camera may have incorrect distances to objects in the scene.
	elif node is MeshInstance3D:
		aabb = node.get_global_transform() * node.get_aabb()

	for i: int in node.get_child_count(true):
		aabb = aabb.merge(_calculate_node_aabb(node.get_child(i, true)))

	return aabb


func _focus_camera_on_node_2d(node: Node) -> void:
	var rect: Rect2 = _calculate_node_rect(node)
	_camera_2d.set_position(rect.get_center())

	var zoom_ratio: float = THUMB_GRID_SIZE / maxf(rect.size.x, rect.size.y)
	_camera_2d.set_zoom(Vector2(zoom_ratio, zoom_ratio))

func _focus_camera_on_node_3d(node: Node) -> void:
	var transform := Transform3D.IDENTITY
	# TODO: Add a feature to configure the rotation of the camera.
	transform.basis *= Basis(Vector3.UP, deg_to_rad(40.0))
	transform.basis *= Basis(Vector3.LEFT, deg_to_rad(22.5))

	var aabb: AABB = _calculate_node_aabb(node)
	var distance: float = aabb.get_longest_axis_size() / tan(deg_to_rad(_camera_3d.get_fov()) * 0.5)

	transform.origin = transform * (Vector3.BACK * distance) + aabb.get_center()

	_camera_3d.set_global_transform(transform.orthonormalized())


func _get_thumb_cache_dir() -> String:
	return ProjectSettings.globalize_path(_cache_path)

func _get_thumb_cache_path(path: String) -> String:
	return _get_thumb_cache_dir().path_join(path.md5_text()) + ".png"

func _save_thumb_to_disk(id: int, image: Image) -> void:
	if not DirAccess.dir_exists_absolute(_get_thumb_cache_dir()):
		var error := DirAccess.make_dir_absolute(_get_thumb_cache_dir())
		assert(error == OK, error_string(error))

	var error := image.save_png(_get_thumb_cache_path(ResourceUID.get_id_path(id)))
	assert(error == OK, error_string(error))

func _create_thumb(item: Dictionary[StringName, Variant], callback: Callable) -> void:
	var path: String = ResourceUID.get_id_path(item.id)
	if not is_valid_scene_file(path):
		return callback.call()

	var packed_scene := ResourceLoader.load(path, "PackedScene") as PackedScene
	# INFO: Could be null if, for example, the dependencies are broken.
	if not is_instance_valid(packed_scene) or not packed_scene.can_instantiate():
		return callback.call()

	var instance: Node = packed_scene.instantiate()

	_viewport.call_deferred(&"add_child", instance)
	await instance.ready

	if instance is Node2D:
		_camera_3d.set_current(false)
		_camera_2d.set_enabled(true)
		_focus_camera_on_node_2d(instance)
	else:
		_camera_2d.set_enabled(false)
		_camera_3d.set_current(true)
		_focus_camera_on_node_3d(instance)

	await RenderingServer.frame_pre_draw
	_viewport.set_update_mode(SubViewport.UPDATE_ONCE)

	await RenderingServer.frame_post_draw

	var image: Image = _viewport.get_texture().get_image()
	image.resize(THUMB_GRID_SIZE, THUMB_GRID_SIZE, Image.INTERPOLATE_LANCZOS)

	var thumb: ImageTexture = item.thumb
	thumb.update(image)

	if _cache_enabled:
		_save_thumb_to_disk(item.id, image)

	instance.call_deferred(&"free")
	await instance.tree_exited

	callback.call()

func _thread_process() -> void:
	var semaphore := Semaphore.new()

	while _thread_work:
		if _thread_queue.is_empty():
			_thread_sem.wait()
		else:
			_mutex.lock()
			var item: Dictionary[StringName, Variant] = _thread_queue.pop_front()
			_mutex.unlock()

			# This ensures that this method will be executed in the main thread.
			call_deferred_thread_group(&"_create_thumb", item, semaphore.post)
			semaphore.wait()




func handle_scene_saved(path: String) -> void:
	# INFO: When we save a scene, we try to update the asset thumbnail.
	# The "_queue_update_thumbnail" method will not create new thumbnails if they have not been previously created.
	_queue_update_thumbnail(ResourceLoader.get_resource_uid(path))


func handle_file_moved(old_file: String, new_file: String) -> void:
	if not _thumbnails.has(ResourceLoader.get_resource_uid(new_file)):
		return

	# TODO: Следует переместить логику в AssetLibrary.
	for collection: AssetCollection in _curr_lib.get_collections():
		var asset: Asset = collection.find_asset_by_path(old_file)
		if is_instance_valid(asset):
			asset.path = new_file

	collection_changed.emit()


func handle_file_removed(file: String) -> void:
	# TODO: Need to add Dictionary for asset path.
	# Because we can't use UID for deleted files.
	# And we have to go through all collections and assets.
	var removed: int = 0
	for collection: AssetCollection in _curr_lib.get_collections():
		if collection.erase_asset_by_path(file):
			removed += 1

	if removed:
		collection_changed.emit()




func _on_collection_tab_changed(tab: int) -> void:
	set_current_collection(_collec_tab_bar.get_tab_metadata(tab))


func _on_collection_tab_close_pressed(tab: int) -> void:
	show_remove_collection_dialog(tab)


func _on_collection_tab_rmb_clicked(tab: int) -> void:
	var collection: AssetCollection = _collec_tab_bar.get_tab_metadata(tab)
	if is_instance_valid(_collec_context_menu):
		_collec_context_menu.queue_free()

	_collec_context_menu = PopupMenu.new()
	_collec_context_menu.id_pressed.connect(func(option: CollectionTabMenu) -> void:
		match option:
			CollectionTabMenu.NEW:
				show_create_collection_dialog()
			CollectionTabMenu.RENAME:
				if is_instance_valid(_rename_collec_window):
					_rename_collec_window.queue_free()

				_rename_collec_window = ConfirmationDialog.new()
				_rename_collec_window.set_size(Vector2i.ZERO)
				_rename_collec_window.set_title("Rename Collection")
				_rename_collec_window.set_flag(Window.FLAG_RESIZE_DISABLED, true)
				_rename_collec_window.get_label().hide()
				_rename_collec_window.canceled.connect(_rename_collec_window.queue_free)
				_rename_collec_window.close_requested.connect(_rename_collec_window.queue_free)

				var ok_button: Button = _rename_collec_window.get_ok_button()
				ok_button.set_text("OK")
				ok_button.set_disabled(true)

				var vbox := VBoxContainer.new()
				_rename_collec_window.add_child(vbox)

				var label := Label.new()
				label.set_text("Change Collection Name:")
				vbox.add_child(label)

				var line_edit := LineEdit.new()
				line_edit.set_select_all_on_focus(true)
				line_edit.set_text(collection.get_name())
				_rename_collec_window.register_text_enter(line_edit)

				# INFO: Disables the ability to create a collection and set a tooltip.
				line_edit.text_changed.connect(func(new_name: String) -> void:
					var is_valid := false

					if new_name.is_empty():
						line_edit.set_tooltip_text("Collection name is empty.")
					elif has_collection(new_name):
						line_edit.set_tooltip_text("Collection with this name already exists.")
					else:
						line_edit.set_tooltip_text("")
						is_valid = true

					ok_button.set_disabled(not is_valid)
					line_edit.set_right_icon(null if is_valid else get_theme_icon(&"StatusError", &"EditorIcons"))
				)
				line_edit.text_changed.emit(line_edit.get_text()) # Required for update status.
				vbox.add_child(line_edit)

				_rename_collec_window.confirmed.connect(func() -> void:
					collection.set_name(line_edit.get_text())
					_collec_tab_bar.set_tab_title(tab, line_edit.get_text())
					mark_unsaved()
				)

				self.add_child(_rename_collec_window)
				_rename_collec_window.popup_centered(Vector2i(300, 0))
				line_edit.grab_focus()
			CollectionTabMenu.DELETE:
				show_remove_collection_dialog(tab)
		)
	self.add_child(_collec_context_menu)

	if is_instance_valid(collection):
		_collec_context_menu.add_item("New Collection", CollectionTabMenu.NEW)
		_collec_context_menu.add_separator()
		_collec_context_menu.add_item("Rename Collection", CollectionTabMenu.RENAME)
		_collec_context_menu.add_item("Delete Collection", CollectionTabMenu.DELETE)
	else:
		_collec_context_menu.add_item("New Collection", CollectionTabMenu.NEW)

	_collec_context_menu.popup(Rect2i(get_screen_position() + get_local_mouse_position(), Vector2i.ZERO))


# FIXME: Требуется новая имплементация.
func _on_collection_tab_rearranged(_to_idx: int) -> void:
	pass


func _create_file_dialog(open: bool) -> ConfirmationDialog:
	var dialog: ConfirmationDialog = null

	if Engine.is_editor_hint(): # Works only in the editor.
		var editor_file_dialog: EditorFileDialog = ClassDB.instantiate(&"EditorFileDialog")
		editor_file_dialog.set_access(EditorFileDialog.ACCESS_FILESYSTEM)
		editor_file_dialog.set_file_mode(EditorFileDialog.FILE_MODE_OPEN_FILE if open else EditorFileDialog.FILE_MODE_SAVE_FILE)
		editor_file_dialog.add_filter("*.cfg", "Config File")
		editor_file_dialog.add_filter("*.json", "JSON File")
		dialog = editor_file_dialog
	else:
		var file_dialog := FileDialog.new()
		file_dialog.set_access(FileDialog.ACCESS_FILESYSTEM)
		file_dialog.set_file_mode(FileDialog.FILE_MODE_OPEN_FILE if open else FileDialog.FILE_MODE_SAVE_FILE)
		file_dialog.add_filter("*.cfg", "Config File")
		file_dialog.add_filter("*.json", "JSON File")
		dialog = file_dialog

	dialog.set_exclusive(true)

	return dialog

func _popup_file_dialog(window: Window) -> void:
	window.popup_centered_clamped(Vector2(1050, 700) * DisplayServer.screen_get_scale(), 0.8)

func _on_collection_option_id_pressed(option: LibraryMenu) -> void:
	match option:
		# TODO: Add a feature to check if the current library is saved.
		LibraryMenu.NEW:
			set_current_library(AssetLibrary.new())

		LibraryMenu.OPEN:
			_popup_file_dialog(_open_dialog)

		LibraryMenu.SAVE when _curr_lib.get_path():
			save_library(_curr_lib.get_path())

		LibraryMenu.SAVE, LibraryMenu.SAVE_AS:
			_popup_file_dialog(_save_dialog)


func _on_filter_assets_text_changed(_filter: String) -> void:
	update_item_list()


func _sort_assets_button_toggled(reverse: bool) -> void:
	set_sort_mode(SortMode.NAME_REVERSE if reverse else SortMode.NAME)


func _update_thumb_icon_size(display_mode: DisplayMode) -> void:
	if display_mode == DisplayMode.THUMBNAILS:
		_item_list.set_fixed_column_width(_thumb_grid_icon_size * 1.5)
		_item_list.set_fixed_icon_size(Vector2i(_thumb_grid_icon_size, _thumb_grid_icon_size))
	else:
		_item_list.set_fixed_column_width(0)
		_item_list.set_fixed_icon_size(Vector2i(_thumb_list_icon_size, _thumb_list_icon_size))

func _update_asset_display_mode(display_mode: DisplayMode) -> void:
	if display_mode == DisplayMode.THUMBNAILS:
		_item_list.set_max_columns(0)
		_item_list.set_icon_mode(ItemList.ICON_MODE_TOP)
		_item_list.set_max_text_lines(2)

		_mode_thumb_btn.set_pressed_no_signal(true)
	else:
		_item_list.set_max_columns(0)
		_item_list.set_icon_mode(ItemList.ICON_MODE_LEFT)
		_item_list.set_max_text_lines(1)

		_mode_list_btn.set_pressed_no_signal(true)

	for i: int in _item_list.get_item_count():
		var asset: Asset = _item_list.get_item_metadata(i)
		_item_list.set_item_icon(i, asset.thumb)

	_update_thumb_icon_size(display_mode)


func _set_thumb_grid_icon_size(icon_size: int) -> void:
	icon_size = clampi(icon_size, THUMB_LIST_SIZE, THUMB_GRID_SIZE)
	if _thumb_grid_icon_size == icon_size:
		return

	_thumb_grid_icon_size = icon_size
	set_editor_setting(EDITOR_SETTING_THUMBNAIL_GRID_SIZE, icon_size)

	_update_thumb_icon_size(_asset_display_mode)

func _set_thumb_list_icon_size(icon_size: int) -> void:
	const ICON_MIN_SIZE = 16

	icon_size = clampi(icon_size, ICON_MIN_SIZE, THUMB_LIST_SIZE)
	if _thumb_list_icon_size == icon_size:
		return

	_thumb_list_icon_size = icon_size
	set_editor_setting(EDITOR_SETTING_THUMBNAIL_LIST_SIZE, icon_size)

	_update_thumb_icon_size(_asset_display_mode)


func _on_item_list_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed() and event.is_command_or_control_pressed():
		const ICON_GRID_STEP = 8
		const ICON_LIST_STEP = 4

		match event.get_button_index():
			MOUSE_BUTTON_WHEEL_UP:
				if _asset_display_mode == DisplayMode.THUMBNAILS:
					_set_thumb_grid_icon_size(_thumb_grid_icon_size + ICON_GRID_STEP)
				else:
					_set_thumb_list_icon_size(_thumb_list_icon_size + ICON_LIST_STEP)

			MOUSE_BUTTON_WHEEL_DOWN:
				if _asset_display_mode == DisplayMode.THUMBNAILS:
					_set_thumb_grid_icon_size(_thumb_grid_icon_size - ICON_GRID_STEP)
				else:
					_set_thumb_list_icon_size(_thumb_list_icon_size - ICON_LIST_STEP)

			_:
				return

		accept_event()

func _on_item_list_item_clicked(index: int, at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return

	_item_list.select(index, false)
	var selected_assets: PackedInt32Array = _item_list.get_selected_items()

	if is_instance_valid(_item_context_menu):
		_item_context_menu.queue_free()

	_item_context_menu = PopupMenu.new()
	_item_context_menu.id_pressed.connect(func(option: AssetContextMenu) -> void:
		var asset: Asset = _item_list.get_item_metadata(selected_assets[0])

		match option:
			AssetContextMenu.OPEN_ASSET:
				open_asset_request.emit(asset.path)
			AssetContextMenu.INHERIT_ASSET:
				inherit_asset_request.emit(asset.path)
			AssetContextMenu.COPY_PATH:
				DisplayServer.clipboard_set(asset.path)
			AssetContextMenu.COPY_UID:
				DisplayServer.clipboard_set(asset.uid)
			# BUG: If we first perform an asset search and then delete them,
			# the assets will be deleted with incorrect indices.
			AssetContextMenu.DELETE_ASSET:
				if selected_assets.size() == 1:
					_curr_collec.remove_asset(selected_assets[0])
				else:
					selected_assets.reverse()

					for i: int in selected_assets:
						_curr_collec.remove_asset(i)

				collection_changed.emit()
				mark_unsaved()
			AssetContextMenu.SHOW_IN_FILE_SYSTEM:
				show_in_file_system_request.emit(asset.path)
			AssetContextMenu.SHOW_IN_FILE_MANAGER:
				show_in_file_manager_request.emit(asset.path)
			AssetContextMenu.REFRESH:
				for i: int in selected_assets:
					asset = _item_list.get_item_metadata(i)
					_queue_update_thumbnail(asset.id)
		)
	self.add_child(_item_context_menu)

	if selected_assets.size() == 1: # If only one asset is selected.
		_item_context_menu.add_item("Open Scene", AssetContextMenu.OPEN_ASSET)
		_item_context_menu.set_item_icon(-1, get_theme_icon(&"Load", &"EditorIcons"))
		_item_context_menu.add_item("New Inherited Scene", AssetContextMenu.INHERIT_ASSET)
		_item_context_menu.set_item_icon(-1, get_theme_icon(&"CreateNewSceneFrom", &"EditorIcons"))
		_item_context_menu.add_separator()
		_item_context_menu.add_item("Copy Path", AssetContextMenu.COPY_PATH)
		_item_context_menu.set_item_icon(-1, get_theme_icon(&"ActionCopy", &"EditorIcons"))
		_item_context_menu.add_item("Copy UID", AssetContextMenu.COPY_UID)
		_item_context_menu.set_item_icon(-1, get_theme_icon(&"Instance", &"EditorIcons"))
		_item_context_menu.add_item("Delete", AssetContextMenu.DELETE_ASSET)
		_item_context_menu.set_item_icon(-1, get_theme_icon(&"Remove", &"EditorIcons"))
		_item_context_menu.add_separator()
		_item_context_menu.add_item("Show in FileSystem", AssetContextMenu.SHOW_IN_FILE_SYSTEM)
		_item_context_menu.set_item_icon(-1, get_theme_icon(&"Filesystem", &"EditorIcons"))
		_item_context_menu.add_item("Show in File Manager", AssetContextMenu.SHOW_IN_FILE_MANAGER)
		_item_context_menu.set_item_icon(-1, get_theme_icon(&"Folder", &"EditorIcons"))
		_item_context_menu.add_separator()
		_item_context_menu.add_item("Refresh", AssetContextMenu.REFRESH)
		_item_context_menu.set_item_icon(-1, get_theme_icon(&"Reload", &"EditorIcons"))
	else: # If many assets are selected.
		_item_context_menu.add_item("Delete", AssetContextMenu.DELETE_ASSET)
		_item_context_menu.set_item_icon(_item_context_menu.get_item_index(AssetContextMenu.DELETE_ASSET), get_theme_icon(&"Remove", &"EditorIcons"))
		_item_context_menu.add_item("Refresh", AssetContextMenu.REFRESH)
		_item_context_menu.set_item_icon(-1, get_theme_icon(&"Reload", &"EditorIcons"))

	_item_context_menu.popup(Rect2i(_item_list.get_screen_position() + at_position, Vector2i.ZERO))


func _on_item_list_item_activated(index: int) -> void:
	var asset: Asset = _item_list.get_item_metadata(index)
	open_asset_request.emit(asset.path)


func _on_save_timer_timeout() -> void:
	if not is_instance_valid(_curr_lib) or _curr_lib.get_path().is_empty():
		return

	save_library(_curr_lib.get_path())




class AssetItemList extends ItemList:
	func _gui_input(event: InputEvent) -> void:
		if event.is_action_pressed(&"ui_text_select_all"):
			for i: int in get_item_count():
				select(i, false)

			accept_event()

	func _create_drag_preview(files: PackedStringArray) -> Control:
		const MAX_ROWS = 6

		var vbox := VBoxContainer.new()
		var num_rows := mini(files.size(), MAX_ROWS)

		for i: int in num_rows:
			var hbox := HBoxContainer.new()
			vbox.add_child(hbox)

			var icon := TextureRect.new()
			icon.set_texture(get_theme_icon(&"File", &"EditorIcons"))
			icon.set_stretch_mode(TextureRect.STRETCH_KEEP_CENTERED)
			icon.set_size(Vector2(16.0, 16.0))
			hbox.add_child(icon)

			var label := Label.new()
			label.set_text(files[i].get_file().get_basename())
			hbox.add_child(label)

		if files.size() > num_rows:
			var label := Label.new()
			label.set_text("%d more files" % int(files.size() - num_rows))
			vbox.add_child(label)

		return vbox

	func _get_drag_data(at_position: Vector2) -> Variant:
		var item: int = get_item_at_position(at_position)
		if item < 0:
			return null

		var files := PackedStringArray()
		for i: int in get_selected_items():
			var asset: Asset = get_item_metadata(i)
			files.push_back(asset.path)

		set_drag_preview(_create_drag_preview(files))

		return {"type": "files", "files": files}

	func _make_custom_tooltip(_for_text: String) -> Object:
		var item: int = get_item_at_position(get_local_mouse_position())
		if item < 0:
			return null

		var asset: Asset = get_item_metadata(item)
		if not is_instance_valid(asset):
			return null

		var vbox := VBoxContainer.new()

		var thumb_rect := TextureRect.new()
		thumb_rect.set_expand_mode(TextureRect.EXPAND_IGNORE_SIZE)
		thumb_rect.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
		thumb_rect.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
		thumb_rect.set_custom_minimum_size(Vector2(THUMB_GRID_SIZE, THUMB_GRID_SIZE))
		thumb_rect.set_texture(asset.thumb)
		vbox.add_child(thumb_rect)

		var label := Label.new()
		label.set_text(asset.path)
		vbox.add_child(label)

		return vbox
