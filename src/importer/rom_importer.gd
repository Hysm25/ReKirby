class_name ROMImporter
extends RefCounted
## Discovers a user-supplied Kirby's Adventure .nes ROM in rom/, validates it,
## extracts CHR/metadata into user://nes_data/, and populates ContentRegistry.

const Constants = preload("res://src/core/constants.gd")
const ROMValidator = preload("res://src/importer/rom_validator.gd")
const CHRExtractor = preload("res://src/importer/chr_extractor.gd")
const MAX_DIR_ENTRIES: int = 1024


class ImportResult extends RefCounted:
	var success: bool = false
	var rom_path: String = ""
	var error: String = ""
	var manifest: Dictionary = {}


static func find_candidate_roms(search_dirs: Array[String] = []) -> Array[String]:
	var dirs_to_scan: Array[String] = search_dirs
	if dirs_to_scan.is_empty():
		dirs_to_scan = [Constants.ROM_DIR, Constants.ROM_FALLBACK_DIR]

	var found: Array[String] = []
	for dir_path: String in dirs_to_scan:
		var dir: DirAccess = DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		var dir_entries: int = 0
		while file_name != "" and dir_entries < MAX_DIR_ENTRIES:
			dir_entries += 1
			if not dir.current_is_dir() and file_name.to_lower().ends_with(".nes"):
				var full_path: String = dir_path.path_join(file_name)
				if not found.has(full_path):
					found.append(full_path)
			file_name = dir.get_next()
		dir.list_dir_end()
	found.sort()
	return found


static func import_from_default_locations(
	search_dirs: Array[String] = [],
	user_data_dir: String = Constants.USER_DATA_DIR
) -> ImportResult:
	var candidates: Array[String] = find_candidate_roms(search_dirs)
	if candidates.is_empty():
		var empty_res: ImportResult = ImportResult.new()
		empty_res.error = "No .nes ROM found in %s." % Constants.ROM_DIR
		EventBus.rom_missing.emit()
		return empty_res

	var last_error: String = ""
	for candidate_path: String in candidates:
		var res: ImportResult = import_rom_file(candidate_path, user_data_dir)
		if res.success:
			return res
		last_error = res.error

	var fail_res: ImportResult = ImportResult.new()
	fail_res.error = last_error if not last_error.is_empty() else "No valid Kirby's Adventure ROM found."
	EventBus.rom_extraction_failed.emit(fail_res.error)
	return fail_res


static func import_rom_file(
	rom_path: String,
	user_data_dir: String = Constants.USER_DATA_DIR,
	strict_checksum: bool = true
) -> ImportResult:
	var res: ImportResult = ImportResult.new()
	res.rom_path = rom_path
	EventBus.rom_extraction_started.emit(rom_path)

	var report: ROMValidator.ValidationReport = ROMValidator.validate_file(rom_path, strict_checksum)
	if not report.valid:
		res.error = report.error
		EventBus.rom_extraction_failed.emit(res.error)
		return res

	var dir_err: Error = DirAccess.make_dir_recursive_absolute(user_data_dir)
	if dir_err != OK:
		res.error = "Failed to create output directory %s (err=%d)." % [user_data_dir, dir_err]
		EventBus.rom_extraction_failed.emit(res.error)
		return res

	var chr_dir: String = user_data_dir.path_join("chr_banks")
	var chr_1k_images: Array[Image] = CHRExtractor.extract_all_chr_sheets(report.chr_data, chr_dir)
	if chr_1k_images.size() != Constants.EXPECTED_CHR_BANKS_1K:
		res.error = "CHR extraction failed: produced %d banks." % chr_1k_images.size()
		EventBus.rom_extraction_failed.emit(res.error)
		return res

	# Hardware 2C02 PPU grayscale diagnostic ramp (zero copyrighted game data)
	var palettes: Dictionary = {
		"ppu_grayscale": [0x0F, 0x00, 0x10, 0x30],
	}
	var palettes_path: String = user_data_dir.path_join("palettes.json")
	var pal_file: FileAccess = FileAccess.open(palettes_path, FileAccess.WRITE)
	if pal_file == null:
		res.error = "Failed to write %s." % palettes_path
		EventBus.rom_extraction_failed.emit(res.error)
		return res
	pal_file.store_string(JSON.stringify(palettes, "\t"))
	pal_file.close()

	var manifest: Dictionary = {
		"format_version": Constants.EXTRACTION_FORMAT_VERSION,
		"source_filename": rom_path.get_file(),
		"mapper_id": report.mapper_id,
		"prg_size": report.prg_size,
		"chr_size": report.chr_size,
		"chr_banks_1k": chr_1k_images.size(),
		"full_crc32": report.full_crc32,
		"prg_crc32": report.prg_crc32,
		"chr_crc32": report.chr_crc32,
		"full_sha256": report.full_sha256,
		"prg_sha256": report.prg_sha256,
		"chr_sha256": report.chr_sha256,
	}
	var manifest_path: String = user_data_dir.path_join("manifest.json")
	var man_file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if man_file == null:
		res.error = "Failed to write %s." % manifest_path
		EventBus.rom_extraction_failed.emit(res.error)
		return res
	man_file.store_string(JSON.stringify(manifest, "\t"))
	man_file.close()

	ContentRegistry.populate_from_extraction(manifest, chr_1k_images, palettes, {}, {}, {})
	if not ContentRegistry.is_ready():
		res.error = "ContentRegistry failed to populate after ROM extraction."
		EventBus.rom_extraction_failed.emit(res.error)
		return res

	res.success = true
	res.manifest = manifest
	EventBus.rom_extraction_completed.emit(manifest)
	return res
