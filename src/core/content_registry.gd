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
	_metatiles = metatiles.duplicate(true)
	_rooms = rooms.duplicate(true)
	_audio_tables = audio_tables.duplicate(true)
	_initialized = true


func load_from_user_data(
	manifest_path: String = Constants.MANIFEST_PATH,
	chr_banks_dir: String = Constants.CHR_BANKS_DIR,
	palettes_path: String = Constants.PALETTES_PATH
) -> bool:
	clear()
	if not FileAccess.file_exists(manifest_path):
		return false
	if not FileAccess.file_exists(palettes_path):
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

	populate_from_extraction(manifest, loaded_1k_images, palettes, {}, {}, {})
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
