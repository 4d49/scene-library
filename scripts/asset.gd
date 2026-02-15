# Copyright (c) 2023-2026 Mansur Isaev and contributors - MIT License
# See `LICENSE.md` included in the source distribution for details.

extends RefCounted

# Represents an asset in the scene library
var id: int = -1
var uid: String = ""
var path: String = ""
var thumb: ImageTexture = null
