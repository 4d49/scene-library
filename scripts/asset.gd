# Copyright (c) 2023-2026 Mansur Isaev and contributors - MIT License
# See `LICENSE.md` included in the source distribution for details.

## Represents a single asset in the scene library
## This class holds information about an asset including its ID, file path, and thumbnail

extends RefCounted


var _id: int = ResourceUID.INVALID_ID
var _path: String = ""
var _thumbnail: ImageTexture = null


func _init(id: int, path: String, thumbnail: ImageTexture) -> void:
	_id = id
	_path = path
	_thumbnail = thumbnail


## Returns the unique identifier of this asset
## The ID is used to uniquely identify this asset within the library
func get_id() -> int:
	return _id


## Returns the unique ID as a string representation
## This converts the internal integer ID to a string using ResourceUID.id_to_text()
func get_uid() -> String:
	return ResourceUID.id_to_text(_id)


## Sets the file path for this asset
## The new path will replace the current path
func set_path(path: String) -> void:
	_path = path

## Returns the file path of this asset
## This is the full path to the asset file in the filesystem
func get_path() -> String:
	return _path


## Returns the thumbnail image for this asset
## If no thumbnail was set, this will return null
func get_thumbnail() -> ImageTexture:
	return _thumbnail
