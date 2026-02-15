# Copyright (c) 2023-2026 Mansur Isaev and contributors - MIT License
# See `LICENSE.md` included in the source distribution for details.

extends RefCounted


signal changed


const Asset: GDScript = preload("asset.gd")


# Represents a collection in the scene library
var _name: String = ""


var assets: Array[Asset] = []


func set_name(name: String) -> void:
	if _name != name:
		_name = name
		changed.emit()

func get_name() -> String:
	return _name
