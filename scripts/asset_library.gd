# Copyright (c) 2023-2026 Mansur Isaev and contributors - MIT License
# See `LICENSE.md` included in the source distribution for details.

extends RefCounted


# Emitted when the asset library changes (collections added/removed)
signal changed


const Asset: GDScript = preload("asset.gd")
const AssetCollection: GDScript = preload("asset_collection.gd")


var _file_path: String = ""
var _collections: Array[AssetCollection] = []


# Gets the current library path.
func get_path() -> String:
	return _file_path

# Sets the current library path.
func set_path(path: String) -> void:
	_file_path = path


# Adds a new collection to the library.
func add_collection(collection: AssetCollection) -> void:
	assert(is_instance_valid(collection), "Invalid collection provided to add_collection")

	_collections.push_back(collection)
	changed.emit()


# Removes a collection from the library by index.
func remove_collection(index: int) -> void:
	_collections.remove_at(index)
	changed.emit()

# Removes a collection from the library by reference.
# The collection must exist in the library.
func erase_collection(collection: AssetCollection) -> void:
	_collections.remove_at(_collections.find(collection))
	changed.emit()


# Gets a collection by index.
# Returns the AssetCollection at the specified index.
func get_collection(index: int) -> AssetCollection:
	return _collections[index]


# Finds a collection by collection name.
# Returns the first AssetCollection with matching name, or null if not found.
func find_collection(collection_name: String) -> AssetCollection:
	for collection in _collections:
		if collection.get_name() == collection_name:
			return collection

	return null

# Checks if a collection with the given name exists.
func has_collection(collection_name: String) -> bool:
	return is_instance_valid(find_collection(collection_name))


# Gets all collections in the library.
func get_collections() -> Array[AssetCollection]:
	return _collections


# Gets the number of collections in the library.
func get_collection_count() -> int:
	return _collections.size()


# Checks if the library contains no collections.
func is_empty() -> bool:
	return _collections.is_empty()
