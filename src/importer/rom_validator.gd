class_name ROMValidator
extends RefCounted
## Validates iNES ROM headers (Mapper 4 MMC3, 512KB PRG, 256KB CHR) and verifies CRC32 / SHA-256.

const Constants = preload("res://src/core/constants.gd")


class ValidationReport extends RefCounted:
	var valid: bool = false
	var error: String = ""
	var mapper_id: int = -1
	var prg_banks_16k: int = 0
	var chr_banks_8k: int = 0
	var prg_size: int = 0
	var chr_size: int = 0
	var has_battery: bool = false
	var has_trainer: bool = false
	var mirroring_vertical: bool = false
	var full_crc32: int = 0
	var prg_crc32: int = 0
	var chr_crc32: int = 0
	var full_sha256: String = ""
	var prg_sha256: String = ""
	var chr_sha256: String = ""
	var prg_data: PackedByteArray = PackedByteArray()
	var chr_data: PackedByteArray = PackedByteArray()


static var _crc_table: PackedInt64Array = PackedInt64Array()


static func _ensure_crc_table() -> void:
	if not _crc_table.is_empty():
		return
	_crc_table.resize(256)
	for i: int in range(256):
		var c: int = i
		for _bit: int in range(8):
			if (c & 1) != 0:
				c = 0xEDB88320 ^ ((c >> 1) & 0x7FFFFFFF)
			else:
				c = (c >> 1) & 0x7FFFFFFF
		_crc_table[i] = c


static func compute_crc32(data: PackedByteArray) -> int:
	_ensure_crc_table()
	var crc: int = 0xFFFFFFFF
	for byte_val: int in data:
		var idx: int = (crc ^ byte_val) & 0xFF
		crc = (_crc_table[idx] ^ ((crc >> 8) & 0x00FFFFFF)) & 0xFFFFFFFF
	return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF


static func compute_sha256(data: PackedByteArray) -> String:
	var ctx: HashingContext = HashingContext.new()
	var err: Error = ctx.start(HashingContext.HASH_SHA256)
	if err != OK:
		return ""
	if not data.is_empty():
		ctx.update(data)
	var digest: PackedByteArray = ctx.finish()
	return digest.hex_encode()


static func validate_file(rom_path: String, strict_checksum: bool = true) -> ValidationReport:
	var report: ValidationReport = ValidationReport.new()
	if not FileAccess.file_exists(rom_path):
		report.error = "ROM file does not exist: %s" % rom_path
		return report
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(rom_path)
	if bytes.is_empty():
		report.error = "Failed to read ROM bytes or file is empty: %s" % rom_path
		return report
	return validate_bytes(bytes, strict_checksum)


static func validate_bytes(rom_bytes: PackedByteArray, strict_checksum: bool = true) -> ValidationReport:
	var report: ValidationReport = ValidationReport.new()
	if rom_bytes.size() < Constants.INES_HEADER_SIZE:
		report.error = "File too small for iNES header (%d bytes)." % rom_bytes.size()
		return report

	if (
		rom_bytes[0] != Constants.INES_MAGIC_0
		or rom_bytes[1] != Constants.INES_MAGIC_1
		or rom_bytes[2] != Constants.INES_MAGIC_2
		or rom_bytes[3] != Constants.INES_MAGIC_3
	):
		report.error = "Invalid iNES magic header."
		return report

	var prg_banks: int = rom_bytes[4]
	var chr_banks: int = rom_bytes[5]
	var flags6: int = rom_bytes[6]
	var flags7: int = rom_bytes[7]

	var mapper_id: int = ((flags6 >> 4) & 0x0F) | (flags7 & 0xF0)
	var mirroring_vertical: bool = (flags6 & 0x01) != 0
	var has_battery: bool = (flags6 & 0x02) != 0
	var has_trainer: bool = (flags6 & 0x04) != 0

	var prg_size: int = prg_banks * Constants.PRG_BANK_16K_SIZE
	var chr_size: int = chr_banks * Constants.CHR_BANK_8K_SIZE
	var trainer_size: int = 512 if has_trainer else 0
	var expected_min_size: int = Constants.INES_HEADER_SIZE + trainer_size + prg_size + chr_size

	report.mapper_id = mapper_id
	report.prg_banks_16k = prg_banks
	report.chr_banks_8k = chr_banks
	report.prg_size = prg_size
	report.chr_size = chr_size
	report.has_battery = has_battery
	report.has_trainer = has_trainer
	report.mirroring_vertical = mirroring_vertical

	if mapper_id != Constants.EXPECTED_MAPPER_ID:
		report.error = "Unsupported iNES mapper %d (expected Mapper %d MMC3)." % [mapper_id, Constants.EXPECTED_MAPPER_ID]
		return report

	if prg_size != Constants.EXPECTED_PRG_SIZE or chr_size != Constants.EXPECTED_CHR_SIZE:
		report.error = "Unexpected ROM geometry: PRG=%d bytes, CHR=%d bytes (expected %d / %d)." % [
			prg_size, chr_size, Constants.EXPECTED_PRG_SIZE, Constants.EXPECTED_CHR_SIZE
		]
		return report

	if rom_bytes.size() < expected_min_size:
		report.error = "Truncated ROM: %d bytes available, %d bytes required." % [rom_bytes.size(), expected_min_size]
		return report

	var prg_start: int = Constants.INES_HEADER_SIZE + trainer_size
	var chr_start: int = prg_start + prg_size
	report.prg_data = rom_bytes.slice(prg_start, chr_start)
	report.chr_data = rom_bytes.slice(chr_start, chr_start + chr_size)

	report.full_crc32 = compute_crc32(rom_bytes)
	report.prg_crc32 = compute_crc32(report.prg_data)
	report.chr_crc32 = compute_crc32(report.chr_data)
	report.full_sha256 = compute_sha256(rom_bytes)
	report.prg_sha256 = compute_sha256(report.prg_data)
	report.chr_sha256 = compute_sha256(report.chr_data)

	if strict_checksum:
		if report.prg_crc32 != Constants.ROM_PRG_CRC32 or report.prg_sha256 != Constants.ROM_PRG_SHA256:
			report.error = "PRG-ROM checksum mismatch (CRC32=0x%08X, expected 0x%08X)." % [
				report.prg_crc32, Constants.ROM_PRG_CRC32
			]
			return report
		if report.chr_crc32 != Constants.ROM_CHR_CRC32 or report.chr_sha256 != Constants.ROM_CHR_SHA256:
			report.error = "CHR-ROM checksum mismatch (CRC32=0x%08X, expected 0x%08X)." % [
				report.chr_crc32, Constants.ROM_CHR_CRC32
			]
			return report

	report.valid = true
	return report
