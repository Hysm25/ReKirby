extends Node
## Central repository for runtime-extracted ROM assets, palettes, metatiles, and audio tables.
## Strictly refuses gameplay initialization if ROM data has not been ingested into user://nes_data/.

const Constants = preload("res://src/core/constants.gd")

var _initialized: bool = false
var _manifest: Dictionary = {}
var _chr_1k_images: Array[Image] = []
var _chr_1k_textures: Array[ImageTexture] = []
var _palettes: Dictionary = {}
var _metatiles: Dictionary = {}
var _rooms: Dictionary = {}
var _audio_tables: Dictionary = {}
var _metasprites: Dictionary = {}
var _sprite_tex_cache: Dictionary = {}
var _metasprite_cache: Dictionary = {}


func is_ready() -> bool:
	return _initialized


func clear() -> void:
	_initialized = false
	_manifest = {}
	_chr_1k_images.clear()
	_chr_1k_textures.clear()
	_palettes.clear()
	_metatiles.clear()
	_rooms.clear()
	_audio_tables.clear()
	_metasprites.clear()
	_sprite_tex_cache.clear()
	_metasprite_cache.clear()


func require_initialized() -> bool:
	if not _initialized:
		push_error("ContentRegistry: Access denied — ROM assets are not ingested into user://nes_data/.")
		return false
	return true


static func _normalize_int_keyed_dict(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in raw.keys():
		var int_key: int = int(key)
		out[int_key] = raw[key]
	return out


func populate_from_extraction(
	manifest: Dictionary,
	chr_1k_images: Array[Image],
	palettes: Dictionary,
	metatiles: Dictionary,
	rooms: Dictionary,
	audio_tables: Dictionary,
	metasprites: Dictionary = {}
) -> void:
	if chr_1k_images.size() != Constants.EXPECTED_CHR_BANKS_1K:
		push_error("ContentRegistry: Expected %d 1KB CHR banks, received %d." % [Constants.EXPECTED_CHR_BANKS_1K, chr_1k_images.size()])
		clear()
		return

	_manifest = manifest.duplicate(true)
	_chr_1k_images = chr_1k_images.duplicate()
	_chr_1k_textures.clear()
	for img: Image in _chr_1k_images:
		_chr_1k_textures.append(ImageTexture.create_from_image(img))

	_palettes = palettes.duplicate(true)
	_metatiles = _normalize_int_keyed_dict(metatiles.duplicate(true))
	_rooms = _normalize_int_keyed_dict(rooms.duplicate(true))
	_audio_tables = audio_tables.duplicate(true)
	_metasprites = metasprites.duplicate(true)
	_initialized = true


func load_from_user_data(
	manifest_path: String = Constants.MANIFEST_PATH,
	chr_banks_dir: String = Constants.CHR_BANKS_DIR,
	palettes_path: String = Constants.PALETTES_PATH,
	world1_path: String = "",
	audio_path: String = ""
) -> bool:
	clear()
	var resolved_world1_path: String = world1_path
	if resolved_world1_path.is_empty():
		resolved_world1_path = manifest_path.get_base_dir().path_join("world1_data.json")
	var resolved_audio_path: String = audio_path
	if resolved_audio_path.is_empty():
		resolved_audio_path = manifest_path.get_base_dir().path_join("audio_data.json")

	if not FileAccess.file_exists(manifest_path):
		return false
	if not FileAccess.file_exists(palettes_path):
		return false
	if not FileAccess.file_exists(resolved_world1_path):
		return false
	if not FileAccess.file_exists(resolved_audio_path):
		return false

	var manifest_text: String = FileAccess.get_file_as_string(manifest_path)
	var manifest_parsed: Variant = JSON.parse_string(manifest_text)
	if not (manifest_parsed is Dictionary):
		return false
	var manifest: Dictionary = manifest_parsed as Dictionary

	if int(manifest.get("format_version", 0)) != Constants.EXTRACTION_FORMAT_VERSION:
		return false
	if int(manifest.get("prg_crc32", 0)) != Constants.ROM_PRG_CRC32:
		return false
	if int(manifest.get("chr_crc32", 0)) != Constants.ROM_CHR_CRC32:
		return false
	if String(manifest.get("prg_sha256", "")) != Constants.ROM_PRG_SHA256:
		return false
	if String(manifest.get("chr_sha256", "")) != Constants.ROM_CHR_SHA256:
		return false

	var palettes_text: String = FileAccess.get_file_as_string(palettes_path)
	var palettes_parsed: Variant = JSON.parse_string(palettes_text)
	if not (palettes_parsed is Dictionary):
		return false
	var palettes: Dictionary = palettes_parsed as Dictionary

	var world1_text: String = FileAccess.get_file_as_string(resolved_world1_path)
	var world1_parsed: Variant = JSON.parse_string(world1_text)
	if not (world1_parsed is Dictionary):
		return false
	var world1_data: Dictionary = world1_parsed as Dictionary
	if int(world1_data.get("format_version", 0)) != Constants.EXTRACTION_FORMAT_VERSION:
		return false

	var audio_text: String = FileAccess.get_file_as_string(resolved_audio_path)
	var audio_parsed: Variant = JSON.parse_string(audio_text)
	if not (audio_parsed is Dictionary):
		return false
	var audio_data: Dictionary = audio_parsed as Dictionary
	if int(audio_data.get("format_version", 0)) != Constants.EXTRACTION_FORMAT_VERSION:
		return false
	var tilesets_var: Variant = world1_data.get("tilesets", {})
	var rooms_var: Variant = world1_data.get("rooms", {})
	if not (tilesets_var is Dictionary) or not (rooms_var is Dictionary):
		return false
	var tilesets: Dictionary = tilesets_var as Dictionary
	var rooms: Dictionary = rooms_var as Dictionary
	if tilesets.is_empty() or rooms.is_empty():
		return false
	var metasprites_var: Variant = world1_data.get("metasprites", {})
	var metasprites: Dictionary = metasprites_var as Dictionary if (metasprites_var is Dictionary) else {}

	var loaded_1k_images: Array[Image] = []
	for bank_8k: int in range(Constants.EXPECTED_CHR_BANKS_8K):
		var sheet_path: String = "%s/chr_8k_%02d.png" % [chr_banks_dir, bank_8k]
		if not FileAccess.file_exists(sheet_path):
			return false
		var sheet_img: Image = Image.load_from_file(sheet_path)
		if sheet_img == null or sheet_img.is_empty():
			return false
		if sheet_img.get_width() != Constants.CHR_1K_BANK_SHEET_WIDTH * 8 or sheet_img.get_height() != Constants.CHR_1K_BANK_SHEET_HEIGHT:
			return false
		for slot: int in range(8):
			var slice_rect: Rect2i = Rect2i(
				slot * Constants.CHR_1K_BANK_SHEET_WIDTH,
				0,
				Constants.CHR_1K_BANK_SHEET_WIDTH,
				Constants.CHR_1K_BANK_SHEET_HEIGHT
			)
			var bank_1k_img: Image = sheet_img.get_region(slice_rect)
			loaded_1k_images.append(bank_1k_img)

	populate_from_extraction(manifest, loaded_1k_images, palettes, tilesets, rooms, audio_data, metasprites)
	return _initialized


func get_manifest() -> Dictionary:
	if not require_initialized():
		return {}
	return _manifest.duplicate(true)


func get_chr_1k_bank_count() -> int:
	if not _initialized:
		return 0
	return _chr_1k_images.size()


func get_chr_bank_image(bank_1k_index: int) -> Image:
	if not require_initialized():
		return null
	if bank_1k_index < 0 or bank_1k_index >= _chr_1k_images.size():
		push_error("ContentRegistry: 1KB CHR bank index out of bounds: %d" % bank_1k_index)
		return null
	return _chr_1k_images[bank_1k_index]


func get_chr_bank_texture(bank_1k_index: int) -> ImageTexture:
	if not require_initialized():
		return null
	if bank_1k_index < 0 or bank_1k_index >= _chr_1k_textures.size():
		push_error("ContentRegistry: 1KB CHR texture index out of bounds: %d" % bank_1k_index)
		return null
	return _chr_1k_textures[bank_1k_index]


func get_palette_indices(palette_key: String) -> PackedInt32Array:
	if not require_initialized():
		return PackedInt32Array()
	if not _palettes.has(palette_key):
		return PackedInt32Array()
	var raw_variant: Variant = _palettes[palette_key]
	if not (raw_variant is Array):
		return PackedInt32Array()
	var raw_arr: Array = raw_variant as Array
	var out: PackedInt32Array = PackedInt32Array()
	for entry: Variant in raw_arr:
		out.append(int(entry) & 0x3F)
	return out


func get_palette_colors(palette_key: String) -> PackedColorArray:
	var indices: PackedInt32Array = get_palette_indices(palette_key)
	if indices.is_empty():
		return PackedColorArray()
	return Constants.build_nes_subpalette(indices)


func has_room(room_id: int) -> bool:
	return _initialized and _rooms.has(room_id)


func get_room_ids() -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	if not require_initialized():
		return ids
	for key: Variant in _rooms.keys():
		ids.append(int(key))
	ids.sort()
	return ids


func get_room_data(room_id: int) -> Dictionary:
	if not require_initialized():
		return {}
	if not _rooms.has(room_id):
		return {}
	return (_rooms[room_id] as Dictionary).duplicate(true)


func has_tileset(tileset_id: int) -> bool:
	return _initialized and _metatiles.has(tileset_id)


func get_tileset_ids() -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	if not require_initialized():
		return ids
	for key: Variant in _metatiles.keys():
		ids.append(int(key))
	ids.sort()
	return ids


func get_tileset_data(tileset_id: int) -> Dictionary:
	if not require_initialized():
		return {}
	if not _metatiles.has(tileset_id):
		return {}
	return (_metatiles[tileset_id] as Dictionary).duplicate(true)


func get_metatile(tileset_id: int, metatile_id: int) -> Dictionary:
	if not require_initialized():
		return {}
	if not _metatiles.has(tileset_id):
		return {}
	var ts_dict: Dictionary = _metatiles[tileset_id] as Dictionary
	var mts_var: Variant = ts_dict.get("metatiles", [])
	if not (mts_var is Array):
		return {}
	var mts: Array = mts_var as Array
	if metatile_id < 0 or metatile_id >= mts.size():
		return {}
	return (mts[metatile_id] as Dictionary).duplicate(true)


func get_audio_tables() -> Dictionary:
	if not require_initialized():
		return {}
	return _audio_tables


func has_music_track(track_id: int) -> bool:
	if not _initialized:
		return false
	var tracks_var: Variant = _audio_tables.get("tracks", {})
	if not (tracks_var is Dictionary):
		return false
	return (tracks_var as Dictionary).has(str(track_id))


func get_music_track(track_id: int) -> Dictionary:
	if not has_music_track(track_id):
		return {}
	var tracks_dict: Dictionary = _audio_tables.get("tracks", {}) as Dictionary
	return (tracks_dict[str(track_id)] as Dictionary).duplicate(true)


func has_sfx_track(sfx_id: int) -> bool:
	if not _initialized:
		return false
	var sfx_var: Variant = _audio_tables.get("sfx", {})
	if not (sfx_var is Dictionary):
		return false
	return (sfx_var as Dictionary).has(str(sfx_id))


func get_sfx_track(sfx_id: int) -> Dictionary:
	if not has_sfx_track(sfx_id):
		return {}
	var sfx_dict: Dictionary = _audio_tables.get("sfx", {}) as Dictionary
	return (sfx_dict[str(sfx_id)] as Dictionary).duplicate(true)


func get_dpcm_sample_bytes(addr_reg: int, len_reg: int) -> PackedByteArray:
	if not require_initialized():
		return PackedByteArray()
	var dpcm_var: Variant = _audio_tables.get("dpcm_samples", {})
	if not (dpcm_var is Dictionary):
		return PackedByteArray()
	var key: String = "%d_%d" % [addr_reg & 0xFF, len_reg & 0xFF]
	var dpcm_dict: Dictionary = dpcm_var as Dictionary
	if not dpcm_dict.has(key):
		return PackedByteArray()
	var entry: Dictionary = dpcm_dict[key] as Dictionary
	var raw_arr: Array = entry.get("bytes", []) as Array
	var out: PackedByteArray = PackedByteArray()
	out.resize(raw_arr.size())
	for i: int in range(raw_arr.size()):
		out[i] = int(raw_arr[i]) & 0xFF
	return out


func build_rom_sprite_texture(
	bank_1k: int,
	tile_ids: PackedInt32Array,
	width_tiles: int,
	height_tiles: int,
	palette_key: String,
	fallback_palette_key: String = "kirby_default"
) -> ImageTexture:
	if not _initialized:
		return null
	var cache_key: String = "%d_%s_%s_%dx%d" % [bank_1k, str(tile_ids), palette_key, width_tiles, height_tiles]
	if _sprite_tex_cache.has(cache_key):
		return _sprite_tex_cache[cache_key] as ImageTexture

	var bank_img: Image = get_chr_bank_image(bank_1k)
	if bank_img == null or bank_img.is_empty():
		return null
	var pal: PackedColorArray = get_palette_colors(palette_key)
	if pal.size() < 4:
		pal = get_palette_colors(fallback_palette_key)
	if pal.size() < 4:
		return null

	var img_w: int = maxi(1, width_tiles) * Constants.TILE_SIZE
	var img_h: int = maxi(1, height_tiles) * Constants.TILE_SIZE
	var src_rgba: PackedByteArray = bank_img.get_data()
	var out_rgba: PackedByteArray = PackedByteArray()
	out_rgba.resize(img_w * img_h * 4)

	var tile_count: int = mini(tile_ids.size(), width_tiles * height_tiles)
	for slot: int in range(tile_count):
		var spec: int = tile_ids[slot]
		var local_tile: int = spec & 0x3F
		var flip_h: bool = (spec & Constants.OAM_FLIP_H) != 0
		var flip_v: bool = (spec & Constants.OAM_FLIP_V) != 0
		var tx0: int = (local_tile % 8) * Constants.TILE_SIZE
		var ty0: int = (local_tile / 8) * Constants.TILE_SIZE
		var dst_tx: int = (slot % width_tiles) * Constants.TILE_SIZE
		var dst_ty: int = (slot / width_tiles) * Constants.TILE_SIZE
		for py: int in range(Constants.TILE_SIZE):
			var src_py: int = (Constants.TILE_SIZE - 1 - py) if flip_v else py
			var src_row: int = ((ty0 + src_py) * Constants.CHR_1K_BANK_SHEET_WIDTH + tx0) * 4
			var dst_row: int = ((dst_ty + py) * img_w + dst_tx) * 4
			for px: int in range(Constants.TILE_SIZE):
				var src_px: int = (Constants.TILE_SIZE - 1 - px) if flip_h else px
				var gray: int = src_rgba[src_row + src_px * 4]
				var c_idx: int = clampi((gray + 42) / 85, 0, 3)
				var dst_off: int = dst_row + px * 4
				if c_idx == 0:
					out_rgba[dst_off] = 0
					out_rgba[dst_off + 1] = 0
					out_rgba[dst_off + 2] = 0
					out_rgba[dst_off + 3] = 0
				else:
					var col: Color = pal[c_idx]
					out_rgba[dst_off] = clampi(int(round(col.r * 255.0)), 0, 255)
					out_rgba[dst_off + 1] = clampi(int(round(col.g * 255.0)), 0, 255)
					out_rgba[dst_off + 2] = clampi(int(round(col.b * 255.0)), 0, 255)
					out_rgba[dst_off + 3] = 255

	var img: Image = Image.create_from_data(img_w, img_h, false, Image.FORMAT_RGBA8, out_rgba)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_sprite_tex_cache[cache_key] = tex
	return tex


func get_metasprites() -> Dictionary:
	if not _initialized:
		return {}
	return _metasprites


func get_actor_metasprite_frames(actor_id: int) -> Array:
	if not _initialized:
		return []
	var actors_var: Variant = _metasprites.get("actors", {})
	if not (actors_var is Dictionary):
		return []
	var actors_dict: Dictionary = actors_var as Dictionary
	var key: String = str(actor_id)
	if not actors_dict.has(key):
		return []
	var entry: Dictionary = actors_dict[key] as Dictionary
	var frames_var: Variant = entry.get("frames", [])
	return frames_var as Array if (frames_var is Array) else []


func get_kirby_metasprite_frame(table_key: String, frame_idx: int) -> Dictionary:
	if not _initialized:
		return {}
	var tbls_var: Variant = _metasprites.get("kirby_tables", {})
	if not (tbls_var is Dictionary):
		return {}
	var tbls: Dictionary = tbls_var as Dictionary
	if not tbls.has(table_key):
		return {}
	var frames_arr: Array = tbls[table_key] as Array
	if frame_idx < 0 or frame_idx >= frames_arr.size():
		return {}
	return frames_arr[frame_idx] as Dictionary


func get_effect_metasprite_frame(table_key: String, frame_idx: int) -> Dictionary:
	if not _initialized:
		return {}
	var tbls_var: Variant = _metasprites.get("effect_tables", {})
	if not (tbls_var is Dictionary):
		return {}
	var tbls: Dictionary = tbls_var as Dictionary
	if not tbls.has(table_key):
		return {}
	var frames_arr: Array = tbls[table_key] as Array
	if frame_idx < 0 or frame_idx >= frames_arr.size():
		return {}
	return frames_arr[frame_idx] as Dictionary


static func _palette_list_signature(palettes: Array[PackedColorArray]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for pal: PackedColorArray in palettes:
		for c_idx: int in range(1, mini(4, pal.size())):
			var col: Color = pal[c_idx]
			parts.append("%02x%02x%02x" % [
				clampi(int(round(col.r * 255.0)), 0, 255),
				clampi(int(round(col.g * 255.0)), 0, 255),
				clampi(int(round(col.b * 255.0)), 0, 255),
			])
	return "".join(parts)


func get_room_sprite_palettes(room_id: int) -> Array[PackedColorArray]:
	var sp0: PackedColorArray = get_palette_colors("kirby_default")
	var sp1: PackedColorArray = get_palette_colors("hud_sp_star")
	var sp2: PackedColorArray = get_palette_colors("room_%d_sp_2" % room_id) if room_id >= 0 else get_palette_colors("hud_sp_fire")
	var sp3: PackedColorArray = get_palette_colors("room_%d_sp_3" % room_id) if room_id >= 0 else get_palette_colors("hud_sp_beam")
	if sp1.size() < 4:
		sp1 = sp0
	if sp2.size() < 4:
		sp2 = get_palette_colors("hud_sp_fire")
	if sp3.size() < 4:
		sp3 = get_palette_colors("hud_sp_beam")
	return [sp0, sp1, sp2, sp3]


func build_rom_metasprite(
	frame_spec: Dictionary,
	palettes: Array[PackedColorArray],
	r0_fallback: int = Constants.CHR_BANK_KIRBY_DEFAULT,
	r1_bank: int = 154,
	common_odd_bank: int = Constants.CHR_BANK_STAR_EFFECTS
) -> Dictionary:
	if not _initialized or frame_spec.is_empty() or palettes.is_empty():
		return {}
	var sprites_var: Variant = frame_spec.get("sprites", [])
	if not (sprites_var is Array):
		return {}
	var sprites: Array = sprites_var as Array
	if sprites.is_empty():
		return {}

	var r0_raw: int = int(frame_spec.get("r0_bank", -1))
	var active_r0: int = (r0_raw if r0_raw >= 0 else r0_fallback) & 0xFE
	var active_r1: int = r1_bank & 0xFE
	var cache_key: String = "%d_%d_%d_%d_%s_%s" % [
		int(frame_spec.get("ptr", 0)),
		active_r0,
		active_r1,
		common_odd_bank,
		str(sprites),
		_palette_list_signature(palettes),
	]
	if _metasprite_cache.has(cache_key):
		return _metasprite_cache[cache_key] as Dictionary

	var min_x: int = 9999
	var max_x: int = -9999
	var min_y: int = 9999
	var max_y: int = -9999
	for sp_var: Variant in sprites:
		var sp: Dictionary = sp_var as Dictionary
		var dx: int = int(sp.get("dx", 0))
		var dy: int = int(sp.get("dy", 0))
		min_x = mini(min_x, dx)
		max_x = maxi(max_x, dx + Constants.TILE_SIZE)
		min_y = mini(min_y, dy)
		max_y = maxi(max_y, dy + Constants.METATILE_SIZE)

	var img_w: int = max_x - min_x
	var img_h: int = max_y - min_y
	if img_w <= 0 or img_h <= 0 or img_w > 128 or img_h > 128:
		return {}

	var out_rgba: PackedByteArray = PackedByteArray()
	out_rgba.resize(img_w * img_h * 4)

	# Draw back-to-front so NES OAM slot 0 takes top priority cleanly
	for s_idx: int in range(sprites.size() - 1, -1, -1):
		var sp: Dictionary = sprites[s_idx] as Dictionary
		var dx: int = int(sp.get("dx", 0)) - min_x
		var dy: int = int(sp.get("dy", 0)) - min_y
		var tile: int = int(sp.get("tile", 0)) & 0xFF
		var attr: int = int(sp.get("attr", 0)) & 0xFF
		var pal_idx: int = clampi(attr & 0x03, 0, palettes.size() - 1)
		var pal: PackedColorArray = palettes[pal_idx]
		if pal.size() < 4:
			continue
		var flip_h: bool = (attr & 0x40) != 0
		var flip_v: bool = (attr & 0x80) != 0

		var bank_1k: int = active_r0
		if tile >= 0x80:
			bank_1k = active_r1 + ((tile - 0x80) >> 6)
		elif (tile & 1) != 0:
			bank_1k = common_odd_bank + ((tile & 0x7E) >> 6)
		else:
			bank_1k = active_r0 + (tile >> 6)

		var bank_img: Image = get_chr_bank_image(bank_1k)
		if bank_img == null or bank_img.is_empty():
			continue
		var src_rgba: PackedByteArray = bank_img.get_data()
		var base_tile: int = tile & 0x3E

		for py: int in range(Constants.METATILE_SIZE):
			var src_y_total: int = (Constants.METATILE_SIZE - 1 - py) if flip_v else py
			var local_tile: int = base_tile + (src_y_total >> 3)
			var src_py: int = src_y_total & 7
			var tx0: int = (local_tile % 8) * Constants.TILE_SIZE
			var ty0: int = (local_tile / 8) * Constants.TILE_SIZE
			var src_row: int = ((ty0 + src_py) * Constants.CHR_1K_BANK_SHEET_WIDTH + tx0) * 4
			var dst_y: int = dy + py
			if dst_y < 0 or dst_y >= img_h:
				continue
			var dst_row: int = (dst_y * img_w) * 4
			for px: int in range(Constants.TILE_SIZE):
				var dst_x: int = dx + px
				if dst_x < 0 or dst_x >= img_w:
					continue
				var src_px: int = (Constants.TILE_SIZE - 1 - px) if flip_h else px
				var gray: int = src_rgba[src_row + src_px * 4]
				var c_idx: int = clampi((gray + 42) / 85, 0, 3)
				if c_idx == 0:
					continue
				var col: Color = pal[c_idx]
				var dst_off: int = dst_row + dst_x * 4
				out_rgba[dst_off] = clampi(int(round(col.r * 255.0)), 0, 255)
				out_rgba[dst_off + 1] = clampi(int(round(col.g * 255.0)), 0, 255)
				out_rgba[dst_off + 2] = clampi(int(round(col.b * 255.0)), 0, 255)
				out_rgba[dst_off + 3] = 255

	var img: Image = Image.create_from_data(img_w, img_h, false, Image.FORMAT_RGBA8, out_rgba)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	var out: Dictionary = {
		"texture": tex,
		"offset": Vector2(float(min_x), float(min_y) - 7.0),
		"width": img_w,
		"height": img_h,
	}
	_metasprite_cache[cache_key] = out
	return out


func build_rom_oam_8x16(
	bank_1k: int,
	left_col: Vector2i,
	right_col: Vector2i,
	palette_key: String,
	flip_left_h: bool = false,
	flip_right_h: bool = false,
	flip_v: bool = false,
	facing_dir: int = 1
) -> ImageTexture:
	# Assemble NES 8x16 hardware sprite columns (left=[TL,BL], right=[TR,BR]) into a 2x2 ImageTexture.
	# When facing_dir < 0, swap left/right columns and toggle horizontal flip on every 8x8 tile.
	var l_tl: int = (left_col.x & 0x3F) | (Constants.OAM_FLIP_H if flip_left_h else 0) | (Constants.OAM_FLIP_V if flip_v else 0)
	var l_bl: int = (left_col.y & 0x3F) | (Constants.OAM_FLIP_H if flip_left_h else 0) | (Constants.OAM_FLIP_V if flip_v else 0)
	var r_tr: int = (right_col.x & 0x3F) | (Constants.OAM_FLIP_H if flip_right_h else 0) | (Constants.OAM_FLIP_V if flip_v else 0)
	var r_br: int = (right_col.y & 0x3F) | (Constants.OAM_FLIP_H if flip_right_h else 0) | (Constants.OAM_FLIP_V if flip_v else 0)

	if facing_dir < 0:
		var m_tl: int = r_tr ^ Constants.OAM_FLIP_H
		var m_tr: int = l_tl ^ Constants.OAM_FLIP_H
		var m_bl: int = r_br ^ Constants.OAM_FLIP_H
		var m_br: int = l_bl ^ Constants.OAM_FLIP_H
		return build_rom_sprite_texture(bank_1k, PackedInt32Array([m_tl, m_tr, m_bl, m_br]), 2, 2, palette_key)

	return build_rom_sprite_texture(bank_1k, PackedInt32Array([l_tl, r_tr, l_bl, r_br]), 2, 2, palette_key)
