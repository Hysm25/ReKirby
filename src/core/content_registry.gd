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
	audio_tables: Dictionary
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
	_initialized = true


func load_from_user_data(
	manifest_path: String = Constants.MANIFEST_PATH,
	chr_banks_dir: String = Constants.CHR_BANKS_DIR,
	palettes_path: String = Constants.PALETTES_PATH,
	world1_path: String = ""
) -> bool:
	clear()
	var resolved_world1_path: String = world1_path
	if resolved_world1_path.is_empty():
		resolved_world1_path = manifest_path.get_base_dir().path_join("world1_data.json")

	if not FileAccess.file_exists(manifest_path):
		return false
	if not FileAccess.file_exists(palettes_path):
		return false
	if not FileAccess.file_exists(resolved_world1_path):
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
	var tilesets_var: Variant = world1_data.get("tilesets", {})
	var rooms_var: Variant = world1_data.get("rooms", {})
	if not (tilesets_var is Dictionary) or not (rooms_var is Dictionary):
		return false
	var tilesets: Dictionary = tilesets_var as Dictionary
	var rooms: Dictionary = rooms_var as Dictionary
	if tilesets.is_empty() or rooms.is_empty():
		return false

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

	populate_from_extraction(manifest, loaded_1k_images, palettes, tilesets, rooms, {})
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
