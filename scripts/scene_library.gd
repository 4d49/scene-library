# Copyright (c) 2023 Mansur Isaev and contributors - MIT License
# See `LICENSE.md` included in the source distribution for details.

extends MarginContainer


class AssetItemList extends ItemList:
	func _create_drag_preview(files: PackedStringArray) -> Control:
		const MAX_ROWS = 6

		var vbox := VBoxContainer.new()
		var num_rows := mini(files.size(), MAX_ROWS)

		for i in num_rows:
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
		for i in get_selected_items():
			var asset: Dictionary = get_item_metadata(i)
			files.push_back(asset["path"])

		set_drag_preview(_create_drag_preview(files))

		return {"type": "files", "files": files}

	func _make_custom_tooltip(_for_text: String) -> Object:
		var item: int = get_item_at_position(get_local_mouse_position())
		if item < 0:
			return null

		var asset: Dictionary = get_item_metadata(item)
		if asset.is_empty():
			return null

		var vbox := VBoxContainer.new()

		var thumb_rect := TextureRect.new()
		thumb_rect.set_expand_mode(TextureRect.EXPAND_IGNORE_SIZE)
		thumb_rect.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
		thumb_rect.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
		thumb_rect.set_custom_minimum_size(Vector2i(THUMB_SIZE, THUMB_SIZE))
		thumb_rect.set_texture(asset["thumb"])
		vbox.add_child(thumb_rect)

		var label := Label.new()
		label.set_text(asset["path"])
		vbox.add_child(label)

		return vbox


signal library_changed

signal library_unsaved
signal library_saved

signal collection_changed

signal open_asset_request(path: String)
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
	COPY_PATH,
	COPY_UID,
	DELETE_ASSET,
	SHOW_IN_FILE_SYSTEM,
	SHOW_IN_FILE_MANAGER,
	MAX,
}


const NULL_LIBRARY: Dictionary = {}
const NULL_COLLECTION: Array[Dictionary] = []

const THUMB_SIZE = 256
const THUMB_SIZE_SMALL = 16

# INFO: Required to change parent panel style.
var _parent_container: PanelContainer = null

var _main_vbox: VBoxContainer = null

var _collec_hbox: HBoxContainer = null
var _collec_tab_bar: TabBar = null
var _collec_tab_add: Button = null
var _collec_option: MenuButton = null

var _main_container: PanelContainer = null
var _content_vbox: VBoxContainer = null

var _top_hbox: HBoxContainer = null
var _asset_filter_line: LineEdit = null
var _asset_sort_mode_btn: Button = null

var _mode_thumb_btn: Button = null
var _mode_list_btn: Button = null

var _item_list: ItemList = null

var _open_dialog: ConfirmationDialog = null
var _save_dialog: ConfirmationDialog = null

var _save_timer: Timer = null

# Create thumbnail scene:
var _viewport: SubViewport = null

var _camera_2d: Camera2D = null

var _camera_3d: Camera3D = null
var _light_3d: DirectionalLight3D = null

var _asset_display_mode: DisplayMode = DisplayMode.THUMBNAILS
var _sort_mode: SortMode = SortMode.NAME

var _thumbnails: Dictionary = {}

var _mutex: Mutex = null
var _thread: Thread = null
var _thread_queue: Array[Dictionary] = []
var _thread_sem: Semaphore = null
var _thread_work := true

# INFO: Use key-value pairs to store collections.
var _curr_lib: Dictionary = NULL_LIBRARY # {String: Array[Dictionary]}
var _curr_lib_path: String = "res://.godot/asset_palette.cfg"

var _curr_collec: Array[Dictionary] = NULL_COLLECTION
# INFO: Used to quickly find a value by UID.
# An asset's UID is used as the key, and a Dictionary is used as the value.
# Must be updated each time a new collection is assigned.
var _curr_collec_map: Dictionary = {} # {int: Dictionary}


func _get_parent_container() -> PanelContainer:
	var parent: Node = get_parent()
	while parent:
		if parent is PanelContainer:
			return parent

		parent = parent.get_parent()

	return null

func _update_position_new_collection_btn() -> void:
	var tab_bar_total_width := float(_collec_tab_bar.get_theme_constant(&"h_separation"))
	for i in _collec_tab_bar.get_tab_count():
		tab_bar_total_width += _collec_tab_bar.get_tab_rect(i).size.x

	_collec_tab_bar.size = Vector2(minf(_collec_tab_bar.size.x, tab_bar_total_width), 0.0)
	_collec_tab_add.position.x = _collec_tab_bar.size.x

@warning_ignore("narrowing_conversion", "return_value_discarded", "unsafe_method_access")
func _enter_tree() -> void:
	_parent_container = _get_parent_container()

	self.add_theme_constant_override(&"margin_left", -get_theme_stylebox(&"BottomPanel", &"EditorStyles").get_margin(SIDE_LEFT))
	self.add_theme_constant_override(&"margin_right", -get_theme_stylebox(&"BottomPanel", &"EditorStyles").get_margin(SIDE_RIGHT))
	self.add_theme_constant_override(&"margin_top", -get_theme_stylebox(&"BottomPanel", &"EditorStyles").get_margin(SIDE_TOP))

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
	_collec_tab_bar.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	_collec_tab_bar.set_max_tab_width(256) # TODO: Make this parameter receive global editor settings.
	_collec_tab_bar.set_theme_type_variation(&"TabContainer")
	_collec_tab_bar.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"DebuggerPanel", &"EditorStyles"))
	_collec_tab_bar.set_select_with_rmb(true)
	_collec_tab_bar.add_tab("[null]")
	_collec_tab_bar.set_tab_disabled(0, true)
	_collec_tab_bar.set_tab_close_display_policy(TabBar.CLOSE_BUTTON_SHOW_NEVER)
	_collec_tab_bar.tab_changed.connect(_on_collection_tab_changed)
	_collec_tab_bar.tab_close_pressed.connect(_on_collection_tab_close_pressed)
	_collec_tab_bar.tab_rmb_clicked.connect(_on_collection_tab_rmb_clicked)
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

	_collec_option = MenuButton.new()
	_collec_option.set_flat(true)
	_collec_option.set_button_icon(get_theme_icon(&"GuiTabMenuHl", &"EditorIcons"))
	_collec_option.add_theme_color_override(&"icon_normal_color", Color(0.6, 0.6, 0.6, 0.8))
	_collec_hbox.add_child(_collec_option)

	var popup: PopupMenu = _collec_option.get_popup()
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
	_mode_thumb_btn.set_pressed(true)
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
	_item_list.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	_item_list.set_mouse_filter(Control.MOUSE_FILTER_PASS)
	_item_list.set_focus_mode(Control.FOCUS_CLICK)
	_item_list.set_select_mode(ItemList.SELECT_MULTI)
	_item_list.set_max_columns(0)
	_item_list.set_same_column_width(true)
	_item_list.set_icon_mode(ItemList.ICON_MODE_TOP)
	_item_list.set_fixed_column_width(64 * 3 * 0.5)
	_item_list.set_max_text_lines(2)
	_item_list.set_fixed_icon_size(Vector2i(64, 64))
	_item_list.item_clicked.connect(_on_item_list_item_clicked)
	_item_list.item_activated.connect(_on_item_list_item_activated)
	_content_vbox.add_child(_item_list)

	_open_dialog = _create_file_dialog(true)
	_open_dialog.set_title("Open Asset Library")
	_open_dialog.connect(&"file_selected", load_library)
	self.add_child(_open_dialog)

	_save_dialog = _create_file_dialog(false)
	_save_dialog.set_title("Save Asset Library As...")
	#_save_dialog.set_current_path("new_library.cfg") # Condition "!is_inside_tree()" is true.
	_save_dialog.connect(&"file_selected", save_library)
	self.add_child(_save_dialog)

	_save_timer = Timer.new()
	_save_timer.set_one_shot(true)
	_save_timer.set_wait_time(10.0) # Save unsaved data every 10 seconds.
	_save_timer.timeout.connect(_on_save_timer_timeout)
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
	_viewport.set_size(Vector2i(THUMB_SIZE, THUMB_SIZE))
	_viewport.set_disable_input(true)
	_viewport.set_transparent_background(true)
	# TODO: Replace "magic" values with values from ProjectSettings.
	_viewport.set_msaa_3d(Viewport.MSAA_8X)
	_viewport.set_screen_space_aa(Viewport.SCREEN_SPACE_AA_FXAA)
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

	library_changed.connect(update_tabs)
	library_changed.connect(_emit_unsaved)

	collection_changed.connect(update_item_list)
	collection_changed.connect(_save_timer.start)
	collection_changed.connect(_emit_unsaved)
	asset_display_mode_changed.connect(_on_asset_display_mode_changed)

	load_default_library()


func _exit_tree() -> void:
	_mutex.lock()
	_thread_work = false
	_mutex.unlock()

	_thread_sem.post()
	if _thread.is_started():
		_thread.wait_to_finish()

@warning_ignore("unsafe_method_access")
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not _item_list.get_rect().has_point(at_position):
		return false

	if not data is Dictionary or data.get("type") != "files":
		return false

	if _curr_lib.is_read_only() or _curr_collec.is_read_only():
		return false

	var files: PackedStringArray = data["files"]
	var rec_ext: PackedStringArray = ResourceLoader.get_recognized_extensions_for_type("PackedScene")

	for file in files:
		var extension: String = file.get_extension().to_lower()
		if not rec_ext.has(extension):
			return false

		if has_asset_path(file) or not ResourceLoader.exists(file, "PackedScene"):
			return false

	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary:
		var files: PackedStringArray = data["files"]

		for path in files:
			create_asset(path)


func set_current_library(library: Dictionary) -> void:
	if is_same(_curr_lib, library):
		return

	_curr_lib = library
	library_changed.emit()

func get_current_library() -> Dictionary:
	return _curr_lib


func set_current_library_path(path: String) -> void:
	if is_same(_curr_lib_path, path):
		return

	_curr_lib_path = path

func get_current_library_path() -> String:
	return _curr_lib_path


func has_collection(c_name: String) -> bool:
	return _curr_lib.has(c_name)


func create_collection(c_name: String) -> void:
	assert(not has_collection(c_name), "Collection with this name already exists.")

	var new_collection: Array[Dictionary] = []
	_curr_lib[c_name] = new_collection
	library_changed.emit()
	# Switch to the last tab.
	_collec_tab_bar.set_current_tab(_collec_tab_bar.get_tab_count() - 1)


func remove_collection(c_name: String) -> void:
	if _curr_lib.erase(c_name):
		library_changed.emit()


func get_collection(c_name: String) -> Array[Dictionary]:
	return _curr_lib[c_name]


func rename_collection(old_name: String, new_name: String) -> void:
	assert(new_name, "New name is empty.")
	if not has_collection(old_name):
		return

	var collection: Array[Dictionary] = _curr_lib[old_name]
	if _curr_lib.erase(old_name):
		_curr_lib[new_name] = collection
		library_changed.emit()




func _create_asset(id: int, uid: String, path: String) -> Dictionary:
	var asset: Dictionary = {"id": id, "uid": uid, "path": path}
	assign_thumbnail(asset)

	return asset

func create_asset(path: String) -> void:
	assert(ResourceLoader.exists(path, "PackedScene"), "There is no recognised resource for the specified path.")
	assert(not has_asset_path(path), "The current collection already contains an asset with the same path")

	var id: int = ResourceLoader.get_resource_uid(path)
	var new_asset: Dictionary = _create_asset(id, ResourceUID.id_to_text(id), path)

	_curr_collec.push_back(new_asset)
	_curr_collec_map[id] = new_asset

	collection_changed.emit()


func remove_asset(id: int) -> void:
	if not _curr_collec_map.erase(id):
		return

	for i in _curr_collec.size():
		if _curr_collec[i]["id"] == id:
			_curr_collec.remove_at(i)
			collection_changed.emit()
			return

func remove_asset_path(path: String) -> void:
	return remove_asset(ResourceLoader.get_resource_uid(path))



@warning_ignore("unsafe_method_access")
func _sort_collection(collection: Array[Dictionary], sort_mode: SortMode) -> void:
	# TODO: Needed to check the "null" collection.
	# In the future, this code should be replaced.
	if collection.is_read_only():
		return

	if sort_mode == SortMode.NAME:
		collection.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["path"].get_file() < b["path"].get_file()
		)
	else: # Reverse sorting.
		collection.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["path"].get_file() > b["path"].get_file()
		)

func _update_collection_map() -> void:
	_curr_collec_map.clear()

	for asset in _curr_collec:
		_curr_collec_map[asset["id"]] = asset

	_curr_collec.assign(_curr_collec_map.values())
	_sort_collection(_curr_collec, _sort_mode)

func set_current_collection(collection: Array[Dictionary]) -> void:
	if is_same(_curr_collec, collection):
		return

	_curr_collec = collection
	_update_collection_map()

	collection_changed.emit()

func get_current_collection() -> Array[Dictionary]:
	return _curr_collec


func has_asset(id: int) -> bool:
	return _curr_collec_map.has(id)

func has_asset_path(path: String) -> bool:
	return has_asset(ResourceLoader.get_resource_uid(path))


func update_tabs() -> void:
	var is_valid: bool = not _curr_lib.is_read_only() and not _curr_lib.is_empty()

	_asset_filter_line.set_editable(is_valid)
	_collec_tab_add.set_disabled(_curr_lib.is_read_only())
	_asset_sort_mode_btn.set_disabled(not is_valid)
	_mode_thumb_btn.set_disabled(not is_valid)
	_mode_list_btn.set_disabled(not is_valid)

	if _curr_lib.size():
		_collec_tab_bar.set_tab_count(_curr_lib.size())
		_collec_tab_bar.set_tab_close_display_policy(TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY)

		var index: int = 0
		for c_name: String in _curr_lib:
			_collec_tab_bar.set_tab_title(index, c_name)
			_collec_tab_bar.set_tab_disabled(index, false)

			var collec: Array[Dictionary] = _curr_lib[c_name]
			_collec_tab_bar.set_tab_metadata(index, collec)

			index += 1

	else:
		_collec_tab_bar.set_tab_count(1)
		_collec_tab_bar.set_tab_close_display_policy(TabBar.CLOSE_BUTTON_SHOW_NEVER)
		_collec_tab_bar.set_tab_title(0, "[null]")
		_collec_tab_bar.set_tab_disabled(0, true)

		_collec_tab_bar.set_tab_metadata(0, NULL_COLLECTION)

	# WARNING: Metadata must always be of type Array[Dictionary]!
	# Every time when we update the tabs, we try to assign a new collection.
	# This is necessary to create an actual list of assets.
	var collection: Array[Dictionary] = _collec_tab_bar.get_tab_metadata(_collec_tab_bar.get_current_tab())
	set_current_collection(collection)

	# INFO: Required to recalculate position of the "new collection" button.
	_collec_tab_bar.size_flags_changed.emit()


func get_filtered_collection_by_assets_name(filter: String) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = _curr_collec.filter(func(asset: Dictionary) -> bool:
		var path: String = asset["path"]
		return filter.is_subsequence_ofn(path.get_file())
	)
	return filtered


func update_item_list() -> void:
	var collec: Array[Dictionary] = get_filtered_collection_by_assets_name(_asset_filter_line.get_text())
	_item_list.set_item_count(collec.size())

	var is_list_mode: bool = _asset_display_mode == DisplayMode.LIST

	for i in collec.size():
		var asset: Dictionary = collec[i]
		var path: String = asset["path"]

		_item_list.set_item_text(i, path.get_file().get_basename())
		_item_list.set_item_icon(i, asset["thumb_small"] if is_list_mode else asset["thumb"])
		# NOTE: This tooltip will be hidden because used the custom tooltip.
		_item_list.set_item_tooltip(i, path)
		_item_list.set_item_metadata(i, asset)




func set_asset_display_mode(display_mode: DisplayMode) -> void:
	if is_same(_asset_display_mode, display_mode):
		return

	_asset_display_mode = display_mode
	asset_display_mode_changed.emit(display_mode)

func get_asset_display_mode() -> DisplayMode:
	return _asset_display_mode


func set_sort_mode(sort_mode: SortMode) -> void:
	if is_same(_sort_mode, sort_mode):
		return

	_sort_mode = sort_mode
	_sort_collection(_curr_collec, sort_mode)

	collection_changed.emit()

func get_sort_mode() -> SortMode:
	return _sort_mode



@warning_ignore("return_value_discarded")
func show_create_collection_dialog() -> AcceptDialog:
	var window := AcceptDialog.new()
	window.set_size(Vector2i.ZERO)
	window.set_title("Create New Collection")
	window.add_cancel_button("Cancel")
	window.set_flag(Window.FLAG_RESIZE_DISABLED, true)
	window.focus_exited.connect(window.queue_free)
	self.add_child(window)

	var ok_button: Button = window.get_ok_button()
	ok_button.set_text("Create")
	ok_button.set_disabled(true)

	var vbox := VBoxContainer.new()
	window.add_child(vbox)

	var label := Label.new()
	label.set_text("New Collection Name:")
	vbox.add_child(label)

	var line_edit := LineEdit.new()
	window.register_text_enter(line_edit)
	line_edit.set_text("new_collection")
	line_edit.select_all()

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

	window.confirmed.connect(func() -> void:
		var new_collec_name: String = line_edit.get_text()
		create_collection(new_collec_name)
	)
	window.popup_centered(Vector2i(300, 0))
	line_edit.grab_focus()

	return window




func _deserialize_asset(asset: Dictionary) -> Dictionary:
	var uid: String = asset.get("uid", "")
	var path: String = asset.get("path", "")

	var id: int = ResourceUID.text_to_id(uid)

	# TODO: Add error handling.
	if id >= 0 and ResourceUID.has_id(id): # If the UID is valid.
		path = ResourceUID.get_id_path(id)
	# If the UID is wrong, try to load the asset by the path.
	# It also checks whether the file extension is valid.
	elif ResourceLoader.exists(path, "PackedScene") and path.get_extension().to_lower() in ResourceLoader.get_recognized_extensions_for_type("PackedScene"):
		id = ResourceLoader.get_resource_uid(path)
		uid = ResourceUID.get_id_path(id)
	# Invalid assset.
	else:
		return {}

	return _create_asset(id, uid, path)

func _load_cfg(path: String) -> Dictionary:
	var config := ConfigFile.new()

	var error := config.load(path)
	assert(error == OK, error_string(error))

	var library: Dictionary = {}

	for key in config.get_section_keys(""):
		var collection: Array[Dictionary] = config.get_value("", key)

		for i in collection.size():
			var asset: Dictionary = collection[i]
			collection[i] = _deserialize_asset(asset)

		library[key] = collection

	return library

func _json_deserialize_collection(collection: Array) -> Array[Dictionary]:
	# A dictionary is needed to avoid creating duplicates.
	var asset_map: Dictionary = {}

	for asset: Dictionary in collection:
		var deserialized_asset: Dictionary = _deserialize_asset(asset)
		if deserialized_asset.is_empty(): # Skip invalid asset.
			continue

		asset_map[deserialized_asset["uid"]] = deserialized_asset

	var validated_collection: Array[Dictionary] = []
	validated_collection.assign(asset_map.values())

	return validated_collection

func _json_deserialize_library(data: Dictionary) -> Dictionary:
	var deserialized: Dictionary = {}

	for key: String in data:
		var value: Variant = data[key]
		if value is Array:
			var collection: Array[Dictionary] = _json_deserialize_collection(value)
			deserialized[key] = collection

	return deserialized

func _load_json(path: String) -> Dictionary:
	var library: Dictionary = NULL_LIBRARY
	var json := JSON.new()

	var error := json.parse(FileAccess.get_file_as_string(path))
	assert(error == OK, error_string(error))

	var data: Variant = json.get_data()
	if data is Dictionary:
		library = _json_deserialize_library(data)

	return library

func load_library(path: String) -> void:
	var library: Dictionary = {}

	if FileAccess.file_exists(path):
		var extension: String = path.get_extension()
		assert(extension == "cfg" or extension == "json", "Invalid extension.")

		if extension == "cfg":
			library = _load_cfg(path)
		elif extension == "json":
			library = _load_json(path)

	set_current_library(library)
	set_current_library_path(path)


func load_default_library() -> void:
	# TODO: Add an option to set up a custom path.
	load_library("res://.godot/scene_library.cfg")




func _serialize_asset(asset: Dictionary) -> Dictionary:
	return {"uid": asset["uid"], "path": asset["path"]}

func _cfg_serialize_collection(collection: Array[Dictionary]) -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	@warning_ignore("return_value_discarded")
	serialized.resize(collection.size())

	for i in serialized.size():
		serialized[i] = _serialize_asset(collection[i])

	return serialized

func _cfg_save_library(path: String) -> void:
	var config := ConfigFile.new()

	for key: String in _curr_lib:
		config.set_value("", key, _cfg_serialize_collection(_curr_lib[key]))

	var error := config.save(path)
	assert(error == OK, error_string(error))

func _json_serialize_collection(collection: Array[Dictionary]) -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	@warning_ignore("return_value_discarded")
	serialized.resize(collection.size())

	for i in serialized.size():
		serialized[i] = _serialize_asset(collection[i])

	return serialized

func _json_seserialize_library(library: Dictionary) -> Dictionary:
	var serialized: Dictionary = {}

	for key: String in library:
		serialized[key] = _json_serialize_collection(library[key])

	return serialized

func _json_save_library(path: String) -> void:
	var data: Dictionary = _json_seserialize_library(_curr_lib)

	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(FileAccess.get_open_error() == OK, error_string(FileAccess.get_open_error()))

	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func save_library(path: String) -> void:
	var extension: String = path.get_extension()
	if extension == "cfg":
		_cfg_save_library(path)
	elif extension == "json":
		_json_save_library(path)
	else:
		return

	library_saved.emit()



@warning_ignore("unsafe_method_access")
func _calculate_node_rect(node: Node) -> Rect2:
	var rect := Rect2()
	if node is Node2D and node.is_visible():
		# HACK: This works only in editor.
		rect = node.get_global_transform() * node.call(&"_edit_get_rect")

	for i: int in node.get_child_count():
		rect = rect.merge(_calculate_node_rect(node.get_child(i)))

	return rect

@warning_ignore("unsafe_method_access")
func _calculate_node_aabb(node: Node) -> AABB:
	var aabb := AABB()

	# NOTE: If the node is not MeshInstance3D, the AABB is not calculated correctly.
	# The camera may have incorrect distances to objects in the scene.
	if node is MeshInstance3D and node.is_visible():
		aabb = node.get_aabb() * node.get_global_transform()

	for i: int in node.get_child_count():
		aabb = aabb.merge(_calculate_node_aabb(node.get_child(i)))

	return aabb


func _focus_camera_on_node_2d(node: Node) -> void:
	var rect: Rect2 = _calculate_node_rect(node)
	_camera_2d.set_position(rect.get_center())

	var zoom_ratio: float = THUMB_SIZE / maxf(rect.size.x, rect.size.y)
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
	return ProjectSettings.globalize_path("res://.godot/thumb_cache")

func _get_thumb_cache_path(path: String) -> String:
	return _get_thumb_cache_dir().path_join(path.md5_text()) + ".png"

func _save_thumb_to_disk(id: int, image: Image) -> void:
	if not DirAccess.dir_exists_absolute(_get_thumb_cache_dir()):
		var error := DirAccess.make_dir_absolute(_get_thumb_cache_dir())
		assert(error == OK, error_string(error))

	var error := image.save_png(_get_thumb_cache_path(ResourceUID.get_id_path(id)))
	assert(error == OK, error_string(error))

@warning_ignore("return_value_discarded")
func _thread_process() -> void:
	var semaphore := Semaphore.new()

	var preview_frame_started := func() -> void:
		_viewport.set_update_mode(SubViewport.UPDATE_ONCE)
		RenderingServer.request_frame_drawn_callback(semaphore.post)

	while _thread_work:
		if _thread_queue.is_empty():
			_thread_sem.wait()
		else:
			_mutex.lock()
			var item: Dictionary = _thread_queue.pop_front()
			_mutex.unlock()

			var path: String = ResourceUID.get_id_path(item["id"])
			if not ResourceLoader.exists(path, "PackedScene"):
				continue

			var packed_scene: PackedScene = ResourceLoader.load(path, "PackedScene")
			if not packed_scene.can_instantiate():
				continue

			var instance: Node = packed_scene.instantiate()
			# BUG: https://github.com/godotengine/godot/issues/79637
			instance.ready.connect(semaphore.post, Object.CONNECT_DEFERRED)
			_viewport.call_deferred(&"add_child", instance)
			semaphore.wait()

			if instance is Node2D:
				_camera_2d.set_enabled(true)
				_camera_3d.set_current(false)

				_focus_camera_on_node_2d(instance)
			else:
				_camera_2d.set_enabled(false)
				_camera_3d.set_current(true)

				_focus_camera_on_node_3d(instance)

			RenderingServer.frame_pre_draw.connect(preview_frame_started, Object.CONNECT_DEFERRED | Object.CONNECT_ONE_SHOT)
			semaphore.wait()

			var image: Image = _viewport.get_texture().get_image()
			image.resize(THUMB_SIZE, THUMB_SIZE, Image.INTERPOLATE_LANCZOS)

			var thumb: Dictionary = item["thumb"]

			var thumb_large: ImageTexture = thumb["large"]
			thumb_large.changed.connect(semaphore.post, Object.CONNECT_DEFERRED | Object.CONNECT_ONE_SHOT)
			thumb_large.update(image)
			semaphore.wait()

			_save_thumb_to_disk(item["id"], image)

			image = _viewport.get_texture().get_image()
			image.resize(THUMB_SIZE_SMALL, THUMB_SIZE_SMALL, Image.INTERPOLATE_LANCZOS)

			var thumb_small: ImageTexture = thumb["small"]
			thumb_small.changed.connect(semaphore.post, Object.CONNECT_DEFERRED | Object.CONNECT_ONE_SHOT)
			thumb_small.update(image)
			semaphore.wait()

			instance.tree_exited.connect(semaphore.post)
			instance.queue_free()
			semaphore.wait()

			# Otherwise it crashes sometimes.
			RenderingServer.frame_pre_draw.connect(semaphore.post, Object.CONNECT_DEFERRED | Object.CONNECT_ONE_SHOT)
			semaphore.wait()

func _queue_update_thumbnail(id: int) -> void:
	if _thumbnails.has(id):
		_mutex.lock()
		var thumb: Dictionary = _thumbnails[id]
		_thread_queue.push_back({"id": id, "thumb": thumb})
		_mutex.unlock()

		_thread_sem.post()


func _get_thumbnail(asset: Dictionary) -> Dictionary:
	var id: int = asset["id"]
	if _thumbnails.has(id):
		return _thumbnails[id]

	var new_thumb: Dictionary = {}
	_thumbnails[id] = new_thumb

	var cache_path: String = _get_thumb_cache_path(asset["path"])
	if FileAccess.file_exists(cache_path):
		var image := Image.load_from_file(cache_path)
		new_thumb["large"] = ImageTexture.create_from_image(image)

		image.resize(THUMB_SIZE_SMALL, THUMB_SIZE_SMALL, Image.INTERPOLATE_LANCZOS)
		new_thumb["small"] = ImageTexture.create_from_image(image)

	else:
		# TODO: Add placeholder thumbnail.
		new_thumb["large"] = ImageTexture.create_from_image(Image.create(THUMB_SIZE, THUMB_SIZE, false, Image.FORMAT_RGBA8))
		new_thumb["small"] = ImageTexture.create_from_image(Image.create(THUMB_SIZE_SMALL, THUMB_SIZE_SMALL, false, Image.FORMAT_RGBA8))

		_queue_update_thumbnail(id)

	new_thumb.make_read_only()
	return new_thumb

func assign_thumbnail(asset: Dictionary) -> void:
	var thumb: Dictionary = _get_thumbnail(asset)

	asset["thumb"] = thumb["large"]
	asset["thumb_small"] = thumb["small"]


func handle_scene_saved(path: String) -> void:
	# INFO: When we save a scene, we try to update the asset thumbnail.
	# The "_queue_update_thumbnail" method will not create new thumbnails if they have not been previously created.
	_queue_update_thumbnail(ResourceLoader.get_resource_uid(path))


func handle_file_moved(old_file: String, new_file: String) -> void:
	var id: int = ResourceLoader.get_resource_uid(new_file)
	if not _thumbnails.has(id):
		return

	for key: String in _curr_lib:
		var collec: Array[Dictionary] = _curr_lib[key]

		for asset in collec:
			if asset["path"] == old_file:
				asset["path"] = new_file
				break

	collection_changed.emit()


func handle_file_removed(file: String) -> void:
	# TODO: Need to add Dictionary for asset path.
	# Because we can't use UID for deleted files.
	# And we have to go through all collections and assets.
	var removed: int = 0
	for key: String in _curr_lib:
		var collec: Array[Dictionary] = _curr_lib[key]

		for i in collec.size():
			var asset: Dictionary = collec[i]

			if asset["path"] == file:
				collec.remove_at(i)
				removed |= int(collec == _curr_collec)
				break

	if removed:
		collection_changed.emit()




func _on_collection_tab_changed(tab: int) -> void:
	var collection: Array[Dictionary] = _collec_tab_bar.get_tab_metadata(tab)
	set_current_collection(collection)


func _on_collection_tab_close_pressed(tab: int) -> void:
	var index := int(0)
	for key: String in _curr_lib:
		if index == tab:
			return remove_collection(key)

		index += 1


@warning_ignore("return_value_discarded")
func _on_collection_tab_rmb_clicked(tab: int) -> void:
	var collection: Array[Dictionary] = _collec_tab_bar.get_tab_metadata(tab)

	var popup := PopupMenu.new()
	popup.id_pressed.connect(func(option: CollectionTabMenu) -> void:
		match option:
			CollectionTabMenu.NEW:
				show_create_collection_dialog()

			CollectionTabMenu.RENAME:
				var old_name: String = _collec_tab_bar.get_tab_title(_collec_tab_bar.get_current_tab())

				var rename_collec_window := AcceptDialog.new()
				rename_collec_window.set_size(Vector2i.ZERO)
				rename_collec_window.set_title("Rename Collection")
				rename_collec_window.add_cancel_button("Cancel")
				rename_collec_window.set_flag(Window.FLAG_RESIZE_DISABLED, true)
				rename_collec_window.focus_exited.connect(rename_collec_window.queue_free)
				self.add_child(rename_collec_window)

				var ok_button: Button = rename_collec_window.get_ok_button()
				ok_button.set_text("OK")
				ok_button.set_disabled(true)

				var vbox := VBoxContainer.new()
				rename_collec_window.add_child(vbox)

				var label := Label.new()
				label.set_text("Change Collection Name:")
				vbox.add_child(label)

				var line_edit := LineEdit.new()
				line_edit.set_select_all_on_focus(true)
				line_edit.set_text(old_name)
				rename_collec_window.register_text_enter(line_edit)

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

				rename_collec_window.confirmed.connect(func() -> void:
					rename_collection(old_name, line_edit.get_text())
				)
				rename_collec_window.popup_centered(Vector2i(300, 0))
				line_edit.grab_focus()

			CollectionTabMenu.DELETE:
				var collection_name: String = _collec_tab_bar.get_tab_title(_collec_tab_bar.get_current_tab())
				remove_collection(collection_name)
		)
	popup.focus_exited.connect(popup.queue_free)
	self.add_child(popup)

	if collection.is_read_only(): # If "null" collection.
		# BUG: You can't see it because the tab is disabled.
		popup.add_item("New Collection", CollectionTabMenu.NEW)
	else:
		popup.add_item("New Collection", CollectionTabMenu.NEW)
		popup.add_separator()
		popup.add_item("Rename Collection", CollectionTabMenu.RENAME)
		popup.add_item("Delete Collection", CollectionTabMenu.DELETE)

	popup.popup(Rect2i(get_screen_position() + get_local_mouse_position(), Vector2i.ZERO))


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

	@warning_ignore("return_value_discarded")
	dialog.set_exclusive(true)

	return dialog

func _popup_file_dialog(window: Window) -> void:
	window.popup_centered_clamped(Vector2(1050, 700) * DisplayServer.screen_get_scale(), 0.8)

@warning_ignore("return_value_discarded")
func _on_collection_option_id_pressed(option: LibraryMenu) -> void:
	match option:
		# TODO: Add a feature to check if the current library is saved.
		LibraryMenu.NEW:
			var new_library: Dictionary = {}
			set_current_library(new_library)

			_curr_lib_path = ""

		LibraryMenu.OPEN:
			_popup_file_dialog(_open_dialog)

		LibraryMenu.SAVE:
			if _curr_lib_path.is_empty():
				_on_collection_option_id_pressed(LibraryMenu.SAVE_AS)
			else:
				save_library(_curr_lib_path)

		LibraryMenu.SAVE_AS:
			_popup_file_dialog(_save_dialog)


func _on_filter_assets_text_changed(_filter: String) -> void:
	update_item_list()


func _sort_assets_button_toggled(reverse: bool) -> void:
	set_sort_mode(SortMode.NAME_REVERSE if reverse else SortMode.NAME)

@warning_ignore("return_value_discarded")
func _on_item_list_item_clicked(index: int, at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return

	_item_list.select(index, false)
	var selected_assets: PackedInt32Array = _item_list.get_selected_items()

	var popup := PopupMenu.new()
	popup.connect(&"focus_exited", popup.queue_free)
	popup.connect(&"id_pressed", func(option: AssetContextMenu) -> void:
		match option:
			AssetContextMenu.OPEN_ASSET:
				var asset: Dictionary = _item_list.get_item_metadata(selected_assets[0])
				open_asset_request.emit(asset["path"])

			AssetContextMenu.COPY_PATH:
				var asset: Dictionary = _item_list.get_item_metadata(selected_assets[0])
				DisplayServer.clipboard_set(asset["path"])

			AssetContextMenu.COPY_UID:
				var asset: Dictionary = _item_list.get_item_metadata(selected_assets[0])
				DisplayServer.clipboard_set(asset["uid"])

			AssetContextMenu.DELETE_ASSET:
				for i in selected_assets:
					_curr_collec.erase(_item_list.get_item_metadata(i))

				_update_collection_map()

				_item_list.deselect_all()
				collection_changed.emit()

			AssetContextMenu.SHOW_IN_FILE_SYSTEM:
				var asset: Dictionary = _item_list.get_item_metadata(selected_assets[0])
				show_in_file_system_request.emit(asset["path"])

			AssetContextMenu.SHOW_IN_FILE_MANAGER:
				var asset: Dictionary = _item_list.get_item_metadata(selected_assets[0])
				show_in_file_manager_request.emit(asset["path"])
		)
	self.add_child(popup)

	if selected_assets.size() == 1: # If only one asset is selected.
		popup.add_item("Open", AssetContextMenu.OPEN_ASSET)
		popup.set_item_icon(popup.get_item_index(AssetContextMenu.OPEN_ASSET), get_theme_icon(&"Load", &"EditorIcons"))
		popup.add_separator()
		popup.add_item("Copy Path", AssetContextMenu.COPY_PATH)
		popup.set_item_icon(popup.get_item_index(AssetContextMenu.COPY_PATH), get_theme_icon(&"ActionCopy", &"EditorIcons"))
		popup.add_item("Copy UID", AssetContextMenu.COPY_UID)
		popup.set_item_icon(popup.get_item_index(AssetContextMenu.COPY_UID), get_theme_icon(&"Instance", &"EditorIcons"))
		popup.add_item("Delete", AssetContextMenu.DELETE_ASSET)
		popup.set_item_icon(popup.get_item_index(AssetContextMenu.DELETE_ASSET), get_theme_icon(&"Remove", &"EditorIcons"))
		popup.add_separator()
		popup.add_item("Show in FileSystem", AssetContextMenu.SHOW_IN_FILE_SYSTEM)
		popup.set_item_icon(popup.get_item_index(AssetContextMenu.SHOW_IN_FILE_SYSTEM), get_theme_icon(&"Filesystem", &"EditorIcons"))
		popup.add_item("Show in File Manager", AssetContextMenu.SHOW_IN_FILE_MANAGER)
		popup.set_item_icon(popup.get_item_index(AssetContextMenu.SHOW_IN_FILE_MANAGER), get_theme_icon(&"Folder", &"EditorIcons"))
	else: # If many assets are selected.
		popup.add_item("Delete", AssetContextMenu.DELETE_ASSET)
		popup.set_item_icon(popup.get_item_index(AssetContextMenu.DELETE_ASSET), get_theme_icon(&"Remove", &"EditorIcons"))

	popup.popup(Rect2i(_item_list.get_screen_position() + at_position, Vector2i.ZERO))


func _on_item_list_item_activated(index: int) -> void:
	var asset: Dictionary = _item_list.get_item_metadata(index)
	open_asset_request.emit(asset["path"])


func _on_asset_display_mode_changed(display_mode: DisplayMode) -> void:
	# TODO: Add a feature to resize icons.
	const ICON_SIZE = 64

	if display_mode == DisplayMode.THUMBNAILS:
		_item_list.set_max_columns(0)
		_item_list.set_icon_mode(ItemList.ICON_MODE_TOP)
		_item_list.set_max_text_lines(2)
		_item_list.set_fixed_column_width(int(ICON_SIZE * 3 * 0.5))
		_item_list.set_fixed_icon_size(Vector2i(ICON_SIZE, ICON_SIZE))

		for i in _item_list.get_item_count():
			var asset: Dictionary = _item_list.get_item_metadata(i)
			_item_list.set_item_icon(i, asset["thumb"])
	else:
		_item_list.set_max_columns(0)
		_item_list.set_icon_mode(ItemList.ICON_MODE_LEFT)
		_item_list.set_max_text_lines(1)
		_item_list.set_fixed_column_width(int(ICON_SIZE * 3.5))
		_item_list.set_fixed_icon_size(Vector2i(THUMB_SIZE_SMALL, THUMB_SIZE_SMALL))

		for i in _item_list.get_item_count():
			var asset: Dictionary = _item_list.get_item_metadata(i)
			_item_list.set_item_icon(i, asset["thumb_small"])


func _emit_unsaved() -> void:
	if _curr_lib_path.is_empty():
		library_unsaved.emit()


func _on_save_timer_timeout() -> void:
	if _curr_lib_path.is_empty():
		return

	save_library(_curr_lib_path)
