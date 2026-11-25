class_name LevelMap
extends Node2D
## 16x16 metatile level renderer and deterministic pixel-level slope/collision query map.
## Strictly requires ContentRegistry ROM data for real rooms; supports synthetic room dicts for unit tests.

const Constants = preload("res://src/core/constants.gd")

var _room_id: int = -1
var _tileset_id: int = -1
var _width_screens: int = 0
var _height_screens: int = 0
var _width_metatiles: int = 0
var _height_metatiles: int = 0
var _width_px: int = 0
var _height_px: int = 0

var _metatile_grid: PackedInt32Array = PackedInt32Array()
var _tileset_metatiles: Array[Dictionary] = []
var _bg_chr_banks: PackedInt32Array = PackedInt32Array()
var _bg_palettes: Array[PackedColorArray] = []
var _doors: Array[Dictionary] = []
var _entities: Array[Dictionary] = []

var _room_image: Image = null
var _room_texture: ImageTexture = null
var _sprite: Sprite2D = null


func _ready() -> void:
	_ensure_sprite_node()


func _ensure_sprite_node() -> void:
	if _sprite != null:
		return
	_sprite = Sprite2D.new()
	_sprite.name = "MetatileLayer"
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func load_room(room_id: int) -> bool:
	if not ContentRegistry.require_initialized():
		return false
	if not ContentRegistry.has_room(room_id):
		push_error("LevelMap: Room %d not found in ContentRegistry." % room_id)
		return false

	var room_data: Dictionary = ContentRegistry.get_room_data(room_id)
	var ts_id: int = int(room_data.get("tileset_id", -1))
	if not ContentRegistry.has_tileset(ts_id):
		push_error("LevelMap: Tileset %d for room %d not found in ContentRegistry." % [ts_id, room_id])
		return false

	var ts_data: Dictionary = ContentRegistry.get_tileset_data(ts_id)
	if not load_from_dicts(room_data, ts_data):
		return false

	_rebuild_room_texture()
	return true


func load_from_dicts(room_data: Dictionary, tileset_data: Dictionary) -> bool:
	var w_mt: int = int(room_data.get("width_metatiles", 0))
	var h_mt: int = int(room_data.get("height_metatiles", 0))
	var raw_grid_var: Variant = room_data.get("metatiles", [])
	var raw_ts_var: Variant = tileset_data.get("metatiles", [])
	if w_mt <= 0 or h_mt <= 0 or not (raw_grid_var is Array) or not (raw_ts_var is Array):
		return false

	var raw_grid: Array = raw_grid_var as Array
	var raw_ts: Array = raw_ts_var as Array
	if raw_grid.size() < w_mt * h_mt or raw_ts.is_empty():
		return false

	_room_id = int(room_data.get("room_id", -1))
	_tileset_id = int(room_data.get("tileset_id", -1))
	_width_screens = maxi(1, int(room_data.get("width_screens", w_mt / Constants.ROOM_SCREEN_COLS)))
	_height_screens = maxi(1, int(room_data.get("height_screens", h_mt / Constants.ROOM_SCREEN_ROWS)))
	_width_metatiles = w_mt
	_height_metatiles = h_mt
	_width_px = w_mt * Constants.METATILE_SIZE
	_height_px = h_mt * Constants.METATILE_SIZE

	_metatile_grid.resize(w_mt * h_mt)
	for i: int in range(w_mt * h_mt):
		_metatile_grid[i] = int(raw_grid[i]) & 0xFF

	_tileset_metatiles.clear()
	for entry_var: Variant in raw_ts:
		if entry_var is Dictionary:
			_tileset_metatiles.append(entry_var as Dictionary)

	_bg_chr_banks.clear()
	var chr_var: Variant = room_data.get("bg_chr_banks", [])
	if chr_var is Array:
		for b_var: Variant in (chr_var as Array):
			_bg_chr_banks.append(int(b_var))

	_bg_palettes.clear()
	var pals_var: Variant = room_data.get("palettes", {})
	if pals_var is Dictionary:
		var pals_dict: Dictionary = pals_var as Dictionary
		for p_idx: int in range(4):
			var key: String = "bg_%d" % p_idx
			var idx_arr_var: Variant = pals_dict.get(key, [])
			var indices: PackedInt32Array = PackedInt32Array()
			if idx_arr_var is Array:
				for c_var: Variant in (idx_arr_var as Array):
					indices.append(int(c_var) & 0x3F)
			_bg_palettes.append(Constants.build_nes_subpalette(indices))

	_doors.clear()
	var doors_var: Variant = room_data.get("doors", [])
	if doors_var is Array:
		for d_var: Variant in (doors_var as Array):
			if d_var is Dictionary:
				_doors.append((d_var as Dictionary).duplicate(true))

	_entities.clear()
	var ents_var: Variant = room_data.get("entities", [])
	if ents_var is Array:
		for e_var: Variant in (ents_var as Array):
			if e_var is Dictionary:
				_entities.append((e_var as Dictionary).duplicate(true))

	return true


func _rebuild_room_texture() -> void:
	if not ContentRegistry.is_ready() or _bg_chr_banks.size() < 4 or _bg_palettes.size() < 4:
		return

	var chr_rgba_banks: Array[PackedByteArray] = []
	for slot: int in range(4):
		var bank_img: Image = ContentRegistry.get_chr_bank_image(_bg_chr_banks[slot])
		if bank_img == null or bank_img.is_empty():
			return
		chr_rgba_banks.append(bank_img.get_data())

	_room_image = Image.create(_width_px, _height_px, false, Image.FORMAT_RGBA8)
	var out_rgba: PackedByteArray = PackedByteArray()
	out_rgba.resize(_width_px * _height_px * 4)

	for my: int in range(_height_metatiles):
		for mx: int in range(_width_metatiles):
			var mt_id: int = _metatile_grid[my * _width_metatiles + mx]
			_stamp_metatile_into_buffer(mt_id, mx, my, chr_rgba_banks, out_rgba)

	_room_image = Image.create_from_data(_width_px, _height_px, false, Image.FORMAT_RGBA8, out_rgba)
	_room_texture = ImageTexture.create_from_image(_room_image)
	_ensure_sprite_node()
	_sprite.texture = _room_texture


func _stamp_metatile_into_buffer(
	mt_id: int,
	mx: int,
	my: int,
	chr_rgba_banks: Array[PackedByteArray],
	out_rgba: PackedByteArray
) -> void:
	if mt_id < 0 or mt_id >= _tileset_metatiles.size():
		return
	var mt: Dictionary = _tileset_metatiles[mt_id]
	var pal_idx: int = clampi(int(mt.get("palette", 0)), 0, 3)
	var palette: PackedColorArray = _bg_palettes[pal_idx]
	var corner_tiles: PackedInt32Array = PackedInt32Array([
		int(mt.get("tl", 0)),
		int(mt.get("tr", 0)),
		int(mt.get("bl", 0)),
		int(mt.get("br", 0)),
	])

	var base_px: int = mx * Constants.METATILE_SIZE
	var base_py: int = my * Constants.METATILE_SIZE
	for q: int in range(4):
		var tile_id: int = corner_tiles[q] & 0xFF
		var bank_slot: int = (tile_id >> 6) & 0x03
		var local_tile: int = tile_id & 0x3F
		var src_bytes: PackedByteArray = chr_rgba_banks[bank_slot]
		var tile_x0: int = (local_tile % 8) * Constants.TILE_SIZE
		var tile_y0: int = (local_tile / 8) * Constants.TILE_SIZE
		var dst_qx: int = base_px + (q & 1) * Constants.TILE_SIZE
		var dst_qy: int = base_py + ((q >> 1) & 1) * Constants.TILE_SIZE

		for py: int in range(Constants.TILE_SIZE):
			var src_row_off: int = ((tile_y0 + py) * Constants.CHR_1K_BANK_SHEET_WIDTH + tile_x0) * 4
			var dst_row_off: int = ((dst_qy + py) * _width_px + dst_qx) * 4
			for px: int in range(Constants.TILE_SIZE):
				var gray: int = src_bytes[src_row_off + px * 4]
				var color_idx: int = clampi((gray + 42) / 85, 0, 3)
				var col: Color = palette[color_idx]
				var dst_off: int = dst_row_off + px * 4
				out_rgba[dst_off] = clampi(int(round(col.r * 255.0)), 0, 255)
				out_rgba[dst_off + 1] = clampi(int(round(col.g * 255.0)), 0, 255)
				out_rgba[dst_off + 2] = clampi(int(round(col.b * 255.0)), 0, 255)
				out_rgba[dst_off + 3] = 255


func get_room_id() -> int:
	return _room_id


func get_tileset_id() -> int:
	return _tileset_id


func get_width_metatiles() -> int:
	return _width_metatiles


func get_height_metatiles() -> int:
	return _height_metatiles


func get_width_pixels() -> int:
	return _width_px


func get_height_pixels() -> int:
	return _height_px


func get_room_texture() -> ImageTexture:
	return _room_texture


func get_doors() -> Array[Dictionary]:
	return _doors.duplicate(true)


func get_entities() -> Array[Dictionary]:
	return _entities.duplicate(true)


func get_metatile_id(mx: int, my: int) -> int:
	if mx < 0 or mx >= _width_metatiles or my < 0 or my >= _height_metatiles:
		return -1
	return _metatile_grid[my * _width_metatiles + mx]


func get_metatile_def(mx: int, my: int) -> Dictionary:
	var mt_id: int = get_metatile_id(mx, my)
	if mt_id < 0 or mt_id >= _tileset_metatiles.size():
		return {}
	return _tileset_metatiles[mt_id]


func get_collision_at_tile(mx: int, my: int) -> int:
	# Out-of-bounds horizontal walls clamp to SOLID; above ceiling is AIR; below bottom is AIR (pit)
	if mx < 0 or mx >= _width_metatiles:
		return Constants.TileCollision.SOLID
	if my < 0 or my >= _height_metatiles:
		return Constants.TileCollision.AIR
	var mt_def: Dictionary = get_metatile_def(mx, my)
	if mt_def.is_empty():
		return Constants.TileCollision.AIR
	return int(mt_def.get("collision", Constants.TileCollision.AIR))


func get_nes_collision_at_tile(mx: int, my: int) -> int:
	if mx < 0 or mx >= _width_metatiles or my < 0 or my >= _height_metatiles:
		return 0
	var mt_def: Dictionary = get_metatile_def(mx, my)
	if mt_def.is_empty():
		return 0
	return int(mt_def.get("nes_collision", 0))


func get_collision_at_pixel(px: int, py: int) -> int:
	var mx: int = int(floor(float(px) / float(Constants.METATILE_SIZE)))
	var my: int = int(floor(float(py) / float(Constants.METATILE_SIZE)))
	return get_collision_at_tile(mx, my)


func is_water_at_pixel(px: int, py: int) -> bool:
	var mx: int = int(floor(float(px) / float(Constants.METATILE_SIZE)))
	var my: int = int(floor(float(py) / float(Constants.METATILE_SIZE)))
	if mx < 0 or mx >= _width_metatiles or my < 0 or my >= _height_metatiles:
		return false
	var col_type: int = get_collision_at_tile(mx, my)
	if col_type == Constants.TileCollision.WATER:
		return true
	return (get_nes_collision_at_tile(mx, my) & 0x80) != 0


func is_hazard_at_pixel(px: int, py: int) -> bool:
	return get_collision_at_pixel(px, py) == Constants.TileCollision.SPIKE_HAZARD


static func is_full_solid_collision(col_type: int) -> bool:
	return (
		col_type == Constants.TileCollision.SOLID
		or col_type == Constants.TileCollision.BREAKABLE_STAR
		or col_type == Constants.TileCollision.BOMB_BLOCK
		or col_type == Constants.TileCollision.SPIKE_HAZARD
	)


static func is_slope_collision(col_type: int) -> bool:
	return (
		col_type == Constants.TileCollision.SLOPE_45_UP
		or col_type == Constants.TileCollision.SLOPE_45_DOWN
		or col_type == Constants.TileCollision.SLOPE_26_UP_L
		or col_type == Constants.TileCollision.SLOPE_26_UP_H
		or col_type == Constants.TileCollision.SLOPE_26_DOWN_L
		or col_type == Constants.TileCollision.SLOPE_26_DOWN_H
	)


static func get_local_surface_y(col_type: int, local_x: int) -> int:
	var lx: int = clampi(local_x, 0, 15)
	match col_type:
		Constants.TileCollision.SOLID, Constants.TileCollision.ONE_WAY, Constants.TileCollision.BREAKABLE_STAR, Constants.TileCollision.BOMB_BLOCK, Constants.TileCollision.SPIKE_HAZARD:
			return 0
		Constants.TileCollision.SLOPE_45_UP:
			return 15 - lx
		Constants.TileCollision.SLOPE_45_DOWN:
			return lx
		Constants.TileCollision.SLOPE_26_UP_L:
			return 15 - (lx >> 1)
		Constants.TileCollision.SLOPE_26_UP_H:
			return 7 - (lx >> 1)
		Constants.TileCollision.SLOPE_26_DOWN_L:
			return lx >> 1
		Constants.TileCollision.SLOPE_26_DOWN_H:
			return 8 + (lx >> 1)
		_:
			return -1


func get_floor_surface_y(px: int, my: int, allow_one_way: bool = true) -> int:
	var mx: int = int(floor(float(px) / float(Constants.METATILE_SIZE)))
	if mx < 0 or mx >= _width_metatiles or my < 0 or my >= _height_metatiles:
		return -1
	var col_type: int = get_collision_at_tile(mx, my)
	if col_type == Constants.TileCollision.ONE_WAY and not allow_one_way:
		return -1
	var local_y: int = get_local_surface_y(col_type, px & 0x0F)
	if local_y < 0:
		return -1
	return my * Constants.METATILE_SIZE + local_y


func is_point_solid(px: int, py: int) -> bool:
	var mx: int = int(floor(float(px) / float(Constants.METATILE_SIZE)))
	var my: int = int(floor(float(py) / float(Constants.METATILE_SIZE)))
	var col_type: int = get_collision_at_tile(mx, my)
	if is_full_solid_collision(col_type):
		return true
	if is_slope_collision(col_type):
		var surface_y: int = get_floor_surface_y(px, my, false)
		return surface_y >= 0 and py >= surface_y
	return false


func break_metatile_at(mx: int, my: int) -> bool:
	if mx < 0 or mx >= _width_metatiles or my < 0 or my >= _height_metatiles:
		return false
	var col_type: int = get_collision_at_tile(mx, my)
	if col_type != Constants.TileCollision.BREAKABLE_STAR and col_type != Constants.TileCollision.BOMB_BLOCK:
		return false

	_metatile_grid[my * _width_metatiles + mx] = 0
	if _room_image != null and _room_texture != null and ContentRegistry.is_ready() and _bg_chr_banks.size() >= 4 and _bg_palettes.size() >= 4:
		var chr_rgba_banks: Array[PackedByteArray] = []
		for slot: int in range(4):
			var bank_img: Image = ContentRegistry.get_chr_bank_image(_bg_chr_banks[slot])
			if bank_img == null:
				return true
			chr_rgba_banks.append(bank_img.get_data())
		var buf: PackedByteArray = _room_image.get_data()
		_stamp_metatile_into_buffer(0, mx, my, chr_rgba_banks, buf)
		_room_image.set_data(_width_px, _height_px, false, Image.FORMAT_RGBA8, buf)
		_room_texture.update(_room_image)
	return true


func find_door_at_pixel(px: float, py: float) -> Dictionary:
	for door: Dictionary in _doors:
		var src_scr: int = int(door.get("src_screen", 0))
		var src_x: int = int(door.get("src_x", 0))
		var src_y: int = int(door.get("src_y", 0))
		var door_cx: float = float((src_scr * Constants.ROOM_SCREEN_COLS + src_x) * Constants.METATILE_SIZE + 8)
		var door_cy: float = float(src_y * Constants.METATILE_SIZE + 8)
		if absf(px - door_cx) <= 10.0 and absf(py - door_cy) <= 14.0:
			return door.duplicate(true)
	return {}
