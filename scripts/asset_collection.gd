# Copyright (c) 2023-2026 Mansur Isaev and contributors - MIT License
# See `LICENSE.md` included in the source distribution for details.

## A collection of assets that can be managed and organized.
## This class provides functionality to store, retrieve, and manipulate
## a list of Asset objects with various utility methods.

extends RefCounted

## Emitted when the asset collection changes (added/removed assets or name changed).
signal changed


const Asset: GDScript = preload("asset.gd")


var _name: String = ""
var _assets: Array[Asset] = []


## Sets the name of this asset collection.
## Emits the changed signal if the name actually changes.
func set_name(name: String) -> void:
	if _name != name:
		_name = name
		changed.emit()

## Returns the name of this asset collection.
func get_name() -> String:
	return _name

## Returns all assets in this collection.
func get_assets() -> Array[Asset]:
	return _assets

## Returns the number of assets in this collection.
func get_size() -> int:
	return _assets.size()

## Adds an asset to this collection.
func add_asset(asset: Asset) -> void:
	assert(is_instance_valid(asset), "Asset must be a valid instance")
	assert(not has_asset_id(asset.get_id()), "Asset with this ID already exists in collection")

	_assets.push_back(asset)
	changed.emit()

## Removes an asset from this collection by index.
## Emits the changed signal after removal.
func remove_asset(index: int) -> void:
	_assets.remove_at(index)
	changed.emit()

## Gets an asset from this collection by index.
func get_asset(index: int) -> Asset:
	return _assets[index]

## Finds and returns an asset by its unique ID.
## Returns null if no asset with the given ID is found.
func find_asset_by_id(asset_id: int) -> Asset:
	for asset: Asset in _assets:
		if asset.get_id() == asset_id:
			return asset

	return null

## Finds and returns an asset by its file path.
## Returns null if no asset with the given path is found.
func find_asset_by_path(asset_path: String) -> Asset:
	for asset: Asset in _assets:
		if asset.get_path() == asset_path:
			return asset

	return null

## Checks if an asset with the given ID exists in this collection.
func has_asset_id(asset_id: int) -> bool:
	return is_instance_valid(find_asset_by_id(asset_id))

## Checks if an asset with the given path exists in this collection.
func has_asset_path(asset_path: String) -> bool:
	return is_instance_valid(find_asset_by_path(asset_path))

## Removes an asset from this collection by its unique ID.
## Returns true if an asset was removed, false if not found.
func erase_asset_by_id(asset_id: int) -> bool:
	for i: int in _assets.size():
		if _assets[i].get_id() == asset_id:
			remove_asset(i)
			return true

	return false

## Removes an asset from this collection by its file path.
## Returns true if an asset was removed, false if not found.
func erase_asset_by_path(asset_path: String) -> bool:
	for i: int in _assets.size():
		if _assets[i].get_path() == asset_path:
			remove_asset(i)
			return true

	return false

## Checks if this collection is empty (contains no assets).
func is_empty() -> bool:
	return _assets.is_empty()

## Sorts the assets in this collection using a custom comparator function.
## Emits the changed signal after sorting.
func sort(comparator: Callable) -> void:
	_assets.sort_custom(comparator)
	changed.emit()
