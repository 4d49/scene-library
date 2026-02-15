# Copyright (c) 2023-2026 Mansur Isaev and contributors - MIT License
# See `LICENSE.md` included in the source distribution for details.

extends RefCounted


const Asset: GDScript = preload("asset.gd")


# Represents a collection in the scene library
var name: String = ""
var assets: Array[Asset] = []
