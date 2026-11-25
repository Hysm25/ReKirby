extends RefCounted
## Verification tests for Phase 0/1: ROMValidator, MMC3Mapper, HALDecompressor,
## CHRExtractor, ContentRegistry boot guard, and live ROM ingestion when present.

const Constants = preload("res://src/core/constants.gd")
const ROMValidator = preload("res://src/importer/rom_validator.gd")
const MMC3Mapper = preload("res://src/importer/mmc3_mapper.gd")
const HALDecompressor = preload("res://src/importer/hal_decompressor.gd")
const CHRExtractor = preload("res://src/importer/chr_extractor.gd")
const WorldExtractor = preload("res://src/importer/world_extractor.gd")
const ROMImporter = preload("res://src/importer/rom_importer.gd")
const MAX_CLEANUP_ENTRIES: int = 2048

var _passed: int = 0
var _failed: int = 0


func run_tests() -> Dictionary:
	_test_constants_and_palette()
	_test_collision_mapping()
	_test_input_manager_60tps()
	_test_rom_validator_synthetic()
	_test_mmc3_mapper()
	_test_hal_decompressor_opcodes()
	_test_chr_extractor_2bpp()
	_test_content_registry_guard()
	_test_live_rom_ingestion_if_present()
	return {"passed": _passed, "failed": _failed}


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  [FAIL] %s" % label)


func _assert_eq_int(actual: int, expected: int, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		printerr("  [FAIL] %s: actual=%d expected=%d" % [label, actual, expected])


func _assert_eq_bytes(actual: PackedByteArray, expected: PackedByteArray, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		printerr("  [FAIL] %s: actual=%s expected=%s" % [label, str(actual), str(expected)])


func _test_constants_and_palette() -> void:
	var master: PackedInt32Array = Constants.get_ntsc_master_palette_rgb()
	_assert_eq_int(master.size(), 64, "2C02 NTSC master palette has 64 entries")
	var white: Color = Constants.get_nes_color(0x30)
	_assert_true(white.is_equal_approx(Color(1.0, 1.0, 1.0, 1.0)), "NES color 0x30 is white")
	var black: Color = Constants.get_nes_color(0x0F)
	_assert_true(black.is_equal_approx(Color(0.0, 0.0, 0.0, 1.0)), "NES color 0x0F is black")


func _test_collision_mapping() -> void:
	_assert_eq_int(Constants.map_nes_collision_to_enum(0x00), Constants.TileCollision.AIR, "NES prop 0x00 maps to AIR")
	_assert_eq_int(Constants.map_nes_collision_to_enum(0x20), Constants.TileCollision.AIR, "NES prop 0x20 maps to AIR")
	_assert_eq_int(Constants.map_nes_collision_to_enum(0x02), Constants.TileCollision.SOLID, "NES prop 0x02 maps to SOLID")
	_assert_eq_int(Constants.map_nes_collision_to_enum(0x22), Constants.TileCollision.BREAKABLE_STAR, "NES prop 0x22 maps to BREAKABLE_STAR")
	_assert_eq_int(Constants.map_nes_collision_to_enum(0x01), Constants.TileCollision.ONE_WAY, "NES prop 0x01 maps to ONE_WAY")
	_assert_eq_int(Constants.map_nes_collision_to_enum(0x05), Constants.TileCollision.SLOPE_45_UP, "NES prop 0x05 maps to SLOPE_45_UP")
	_assert_eq_int(Constants.map_nes_collision_to_enum(0x06), Constants.TileCollision.SLOPE_45_DOWN, "NES prop 0x06 maps to SLOPE_45_DOWN")
	_assert_eq_int(Constants.map_nes_collision_to_enum(0x03), Constants.TileCollision.SLOPE_26_UP_L, "NES prop 0x03 maps to SLOPE_26_UP_L")
	_assert_eq_int(Constants.map_nes_collision_to_enum(0x04), Constants.TileCollision.SLOPE_26_DOWN_L, "NES prop 0x04 maps to SLOPE_26_DOWN_L")
	_assert_eq_int(Constants.map_nes_collision_to_enum(0xA0), Constants.TileCollision.WATER, "NES prop 0xA0 maps to WATER")
	_assert_eq_int(Constants.map_nes_collision_to_enum(0x0F), Constants.TileCollision.SPIKE_HAZARD, "NES prop 0x0F maps to SPIKE_HAZARD")


func _test_input_manager_60tps() -> void:
	InputManager.clear_mock_mask()
	InputManager.clear_touch_mask()
	InputManager.set_mock_mask(Constants.NesButton.A | Constants.NesButton.RIGHT)
	InputManager.step_frame()
	_assert_true(InputManager.is_pressed(Constants.NesButton.A), "InputManager reads pressed A")
	_assert_true(InputManager.is_just_pressed(Constants.NesButton.A), "InputManager detects just_pressed A on frame 1")
	InputManager.step_frame()
	_assert_true(not InputManager.is_just_pressed(Constants.NesButton.A), "InputManager clears just_pressed on frame 2")

	# SOCD neutral cleaning: LEFT + RIGHT cancels both
	InputManager.set_mock_mask(Constants.NesButton.LEFT | Constants.NesButton.RIGHT | Constants.NesButton.B)
	InputManager.step_frame()
	_assert_true(not InputManager.is_pressed(Constants.NesButton.LEFT) and not InputManager.is_pressed(Constants.NesButton.RIGHT), "InputManager SOCD cancels opposing LEFT+RIGHT")
	_assert_true(InputManager.is_pressed(Constants.NesButton.B), "InputManager preserves non-opposing B during SOCD")
	_assert_true(InputManager.is_just_released(Constants.NesButton.A), "InputManager detects just_released A")
	InputManager.clear_mock_mask()


func _test_rom_validator_synthetic() -> void:
	# Known standard CRC32 / SHA-256 test vector: "123456789"
	var vec: PackedByteArray = "123456789".to_ascii_buffer()
	_assert_eq_int(ROMValidator.compute_crc32(vec), 0xCBF43926, "CRC32 matches IEEE 802.3 vector")
	_assert_true(
		ROMValidator.compute_sha256(vec) == "15e2b0d3c33891ebb0f1ef609ec419420c20e320ce94c65fbc8c3312448eb225",
		"SHA-256 matches standard vector"
	)

	# Reject invalid magic header
	var bad_magic: PackedByteArray = PackedByteArray([0x00, 0x01, 0x02, 0x03, 32, 32, 0x42, 0x00, 0, 0, 0, 0, 0, 0, 0, 0])
	var r_magic: ROMValidator.ValidationReport = ROMValidator.validate_bytes(bad_magic, false)
	_assert_true(not r_magic.valid, "ROMValidator rejects invalid iNES magic")

	# Reject wrong mapper (Mapper 0 instead of Mapper 4 MMC3)
	var bad_mapper: PackedByteArray = PackedByteArray([0x4E, 0x45, 0x53, 0x1A, 32, 32, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0])
	var r_mapper: ROMValidator.ValidationReport = ROMValidator.validate_bytes(bad_mapper, false)
	_assert_true(not r_mapper.valid and r_mapper.mapper_id == 0, "ROMValidator rejects non-MMC3 mapper")

	# Accept valid synthetic Mapper 4 geometry when strict_checksum = false
	var synth: PackedByteArray = PackedByteArray()
	synth.resize(Constants.EXPECTED_ROM_TOTAL_SIZE)
	synth[0] = 0x4E
	synth[1] = 0x45
	synth[2] = 0x53
	synth[3] = 0x1A
	synth[4] = Constants.EXPECTED_PRG_BANKS_16K
	synth[5] = Constants.EXPECTED_CHR_BANKS_8K
	synth[6] = 0x42 # Mapper 4 low nibble + battery
	synth[7] = 0x00
	var r_synth: ROMValidator.ValidationReport = ROMValidator.validate_bytes(synth, false)
	_assert_true(r_synth.valid, "ROMValidator accepts valid Mapper 4 512KB/256KB layout (non-strict)")
	_assert_true(not ROMValidator.validate_bytes(synth, true).valid, "ROMValidator rejects zeroed synthetic ROM under strict checksum")


func _test_mmc3_mapper() -> void:
	var prg: PackedByteArray = PackedByteArray()
	prg.resize(Constants.EXPECTED_PRG_SIZE)
	for bank: int in range(Constants.EXPECTED_PRG_BANKS_8K):
		prg[bank * Constants.PRG_BANK_8K_SIZE] = bank

	var chr_data: PackedByteArray = PackedByteArray()
	chr_data.resize(Constants.EXPECTED_CHR_SIZE)

	var mapper: MMC3Mapper = MMC3Mapper.new(prg, chr_data)

	# PRG mode 0: $8000 = R6, $A000 = R7, $C000 = 62, $E000 = 63
	mapper.write_register(0x8000, 0x06) # Select R6, PRG mode 0
	mapper.write_register(0x8001, 5)
	mapper.write_register(0x8000, 0x07) # Select R7
	mapper.write_register(0x8001, 12)
	_assert_eq_int(mapper.read_prg_byte(0x8000), 5, "MMC3 mode 0 $8000 reads bank R6 (5)")
	_assert_eq_int(mapper.read_prg_byte(0xA000), 12, "MMC3 mode 0 $A000 reads bank R7 (12)")
	_assert_eq_int(mapper.read_prg_byte(0xC000), 62, "MMC3 mode 0 $C000 fixed to second-last bank (62)")
	_assert_eq_int(mapper.read_prg_byte(0xE000), 63, "MMC3 mode 0 $E000 fixed to last bank (63)")

	# PRG mode 1: $8000 = 62, $C000 = R6
	mapper.write_register(0x8000, 0x46) # PRG mode 1 + R6
	_assert_eq_int(mapper.read_prg_byte(0x8000), 62, "MMC3 mode 1 $8000 fixed to 62")
	_assert_eq_int(mapper.read_prg_byte(0xC000), 5, "MMC3 mode 1 $C000 reads bank R6 (5)")

	# CHR A12 inversion & 2KB alignment (bit 0 ignored on R0/R1)
	mapper.write_register(0x8000, 0x00)
	mapper.write_register(0x8001, 11) # Even-aligned -> 10, 11
	mapper.write_register(0x8000, 0x02)
	mapper.write_register(0x8001, 25)
	_assert_eq_int(mapper.resolve_chr_1k_bank(0x0000), 10, "MMC3 CHR A12=0 slot 0 masks bit 0 (10)")
	_assert_eq_int(mapper.resolve_chr_1k_bank(0x0400), 11, "MMC3 CHR A12=0 slot 1 pairs odd bank (11)")
	_assert_eq_int(mapper.resolve_chr_1k_bank(0x1000), 25, "MMC3 CHR A12=0 slot 4 reads R2 (25)")

	mapper.write_register(0x8000, 0x80) # Enable CHR A12 inversion
	_assert_eq_int(mapper.resolve_chr_1k_bank(0x0000), 25, "MMC3 CHR A12=1 slot 0 reads R2 (25)")
	_assert_eq_int(mapper.resolve_chr_1k_bank(0x1000), 10, "MMC3 CHR A12=1 slot 4 reads R0 even (10)")

	# Mirroring and Scanline IRQ counter
	mapper.write_register(0xA000, 0x01)
	_assert_true(mapper.is_mirroring_horizontal(), "MMC3 $A000=1 sets horizontal mirroring")
	mapper.write_register(0xC000, 2)
	mapper.write_register(0xC001, 0)
	mapper.write_register(0xE001, 0)
	_assert_true(not mapper.clock_scanline(), "MMC3 IRQ scanline 1 reloads counter to 2")
	_assert_true(not mapper.clock_scanline(), "MMC3 IRQ scanline 2 decrements counter to 1")
	_assert_true(mapper.clock_scanline(), "MMC3 IRQ scanline 3 reaches 0 and fires IRQ")


func _test_hal_decompressor_opcodes() -> void:
	# Construct a test stream exercising all 7 HAL opcodes (0..6) + extended length:
	# - Op 0 (len 4): [0x03, 0x80, 0xC0, 0x01, 0x02] -> 80, C0, 01, 02
	# - Op 1 (8-bit RLE, len 3): [0x22, 0xAA] -> AA, AA, AA
	# - Op 2 (16-bit RLE, len 2): [0x41, 0x12, 0x34] -> 12, 34, 12, 34
	# - Op 3 (Incrementing, len 4): [0x63, 0xFE] -> FE, FF, 00, 01
	# - Op 4 (LZ77 copy from off 2, len 3): [0x82, 0x00, 0x02] -> 01, 02, AA
	# - Op 5 (LZ77 bit-reversed from off 0, len 2): [0xA1, 0x00, 0x00] -> rev(0x80)=0x01, rev(0xC0)=0x03
	# - Op 6 (LZ77 backward copy from off 3, len 3): [0xC2, 0x00, 0x03] -> out[3]=02, out[2]=01, out[1]=C0
	# - Op 7 extended (opcode 1, len=33 -> (cmd=0xE4, ext=0x20)): [0xE4, 0x20, 0x55] -> 33 x 0x55
	# - Terminator: [0xFF]
	var stream: PackedByteArray = PackedByteArray([
		0x03, 0x80, 0xC0, 0x01, 0x02,
		0x22, 0xAA,
		0x41, 0x12, 0x34,
		0x63, 0xFE,
		0x82, 0x00, 0x02,
		0xA1, 0x00, 0x00,
		0xC2, 0x00, 0x03,
		0xE4, 0x20, 0x55,
		0xFF
	])

	var res: HALDecompressor.DecompressResult = HALDecompressor.decompress(stream)
	_assert_true(res.success, "HALDecompressor succeeds on multi-opcode stream (%s)" % res.error)
	_assert_eq_int(res.bytes_consumed, stream.size(), "HALDecompressor consumed exact stream size")

	var expected: PackedByteArray = PackedByteArray([
		0x80, 0xC0, 0x01, 0x02,
		0xAA, 0xAA, 0xAA,
		0x12, 0x34, 0x12, 0x34,
		0xFE, 0xFF, 0x00, 0x01,
		0x01, 0x02, 0xAA,
		0x01, 0x03,
		0x02, 0x01, 0xC0
	])
	for _i: int in range(33):
		expected.append(0x55)

	_assert_eq_bytes(res.data, expected, "HALDecompressor output matches opcodes 0..6 + extended length")

	# Bounds safety checks
	var bad_eof: PackedByteArray = PackedByteArray([0x05, 0x01, 0x02])
	_assert_true(not HALDecompressor.decompress(bad_eof).success, "HALDecompressor rejects truncated literal")
	var bad_backref: PackedByteArray = PackedByteArray([0x80, 0x00, 0x05, 0xFF])
	_assert_true(not HALDecompressor.decompress(bad_backref).success, "HALDecompressor rejects out-of-bounds back-reference")


func _test_chr_extractor_2bpp() -> void:
	# 16-byte synthetic 2BPP tile:
	# Row 0: plane0 = 0b10101010 (0xAA), plane1 = 0b11001100 (0xCC)
	# Col 0 (bit 7): p1=1, p0=1 -> 3
	# Col 1 (bit 6): p1=1, p0=0 -> 2
	# Col 2 (bit 5): p1=0, p0=1 -> 1
	# Col 3 (bit 4): p1=0, p0=0 -> 0
	var tile: PackedByteArray = PackedByteArray()
	tile.resize(16)
	tile[0] = 0xAA
	tile[8] = 0xCC

	var decoded: PackedByteArray = CHRExtractor.decode_tile_2bpp(tile, 0)
	_assert_eq_int(decoded.size(), 64, "2BPP tile decodes to 64 pixels")
	_assert_eq_int(decoded[0], 3, "2BPP pixel (0,0) = 3")
	_assert_eq_int(decoded[1], 2, "2BPP pixel (1,0) = 2")
	_assert_eq_int(decoded[2], 1, "2BPP pixel (2,0) = 1")
	_assert_eq_int(decoded[3], 0, "2BPP pixel (3,0) = 0")

	var fake_chr: PackedByteArray = PackedByteArray()
	fake_chr.resize(Constants.CHR_BANK_1K_SIZE)
	fake_chr[0] = 0xAA
	fake_chr[8] = 0xCC
	var bank_img: Image = CHRExtractor.decode_1k_bank_image(fake_chr, 0)
	_assert_eq_int(bank_img.get_width(), 64, "1KB CHR bank image width is 64")
	_assert_eq_int(bank_img.get_height(), 64, "1KB CHR bank image height is 64")
	_assert_eq_int(int(round(bank_img.get_pixel(0, 0).r * 255.0)), 255, "Bank pixel (0,0) index 3 -> 255")
	_assert_eq_int(int(round(bank_img.get_pixel(3, 0).r * 255.0)), 0, "Bank pixel (3,0) index 0 -> 0")


func _test_content_registry_guard() -> void:
	# Verify ContentRegistry refuses uninitialized access cleanly without touching persistent user:// data
	var temp_reg_script: GDScript = load("res://src/core/content_registry.gd") as GDScript
	var temp_reg: Node = temp_reg_script.new() as Node
	_assert_true(not bool(temp_reg.call("is_ready")), "Fresh ContentRegistry starts uninitialized")
	_assert_true(not bool(temp_reg.call("load_from_user_data", "user://nonexistent_manifest.json", "user://nonexistent_chr", "user://nonexistent_pal.json")), "load_from_user_data returns false when extracted assets are absent")
	_assert_eq_int(int(temp_reg.call("get_chr_1k_bank_count")), 0, "Uninitialized ContentRegistry exposes 0 CHR banks")
	temp_reg.free()


func _test_live_rom_ingestion_if_present() -> void:
	var candidates: Array[String] = ROMImporter.find_candidate_roms()
	if candidates.is_empty():
		print("  [INFO] No local ROM present in rom/ — skipping live ROM ingestion test.")
		return

	var test_user_dir: String = "user://nes_data_test"
	var res: ROMImporter.ImportResult = ROMImporter.import_rom_file(candidates[0], test_user_dir, true)
	_assert_true(res.success, "Live ROM import succeeds cleanly (%s)" % res.error)
	_assert_eq_int(int(res.manifest.get("chr_banks_1k", 0)), 256, "Live ROM extracted 256 x 1KB CHR banks")
	_assert_eq_int(int(res.manifest.get("world1_room_count", 0)), 21, "Live ROM extracted 21 World 1 rooms")
	_assert_eq_int(int(res.manifest.get("world1_tileset_count", 0)), 9, "Live ROM extracted 9 World 1 tilesets")
	_assert_eq_int(int(res.manifest.get("prg_crc32", 0)), Constants.ROM_PRG_CRC32, "Live ROM PRG CRC32 verified")
	_assert_eq_int(int(res.manifest.get("chr_crc32", 0)), Constants.ROM_CHR_CRC32, "Live ROM CHR CRC32 verified")

	# Verify reloading cached PNG sheets, palettes, and World 1 room/metatile tables from disk
	var reloaded: bool = ContentRegistry.load_from_user_data(
		test_user_dir.path_join("manifest.json"),
		test_user_dir.path_join("chr_banks"),
		test_user_dir.path_join("palettes.json"),
		test_user_dir.path_join("world1_data.json")
	)
	_assert_true(reloaded and ContentRegistry.is_ready(), "ContentRegistry reloads cached CHR, palettes, and World 1 data from disk")
	_assert_eq_int(ContentRegistry.get_chr_1k_bank_count(), 256, "Reloaded ContentRegistry exposes 256 x 1KB CHR banks")
	_assert_eq_int(ContentRegistry.get_room_ids().size(), 21, "Reloaded ContentRegistry exposes 21 World 1 rooms")
	_assert_eq_int(ContentRegistry.get_tileset_ids().size(), 9, "Reloaded ContentRegistry exposes 9 World 1 tilesets")

	# Verify World 1 Hub (R000), Stage 1-1 Room 1 (R043), and Whispy Woods Boss (R030)
	_assert_true(ContentRegistry.has_room(0), "ContentRegistry contains World 1 Hub (Room 0)")
	_assert_true(ContentRegistry.has_room(43), "ContentRegistry contains Stage 1-1 Room 1 (Room 43)")
	_assert_true(ContentRegistry.has_room(30), "ContentRegistry contains Whispy Woods Boss (Room 30)")

	var r43: Dictionary = ContentRegistry.get_room_data(43)
	_assert_eq_int(int(r43.get("width_screens", 0)), 4, "Room 43 is 4 screens wide")
	_assert_eq_int(int(r43.get("height_screens", 0)), 1, "Room 43 is 1 screen tall")
	_assert_eq_int(int(r43.get("tileset_id", -1)), 7, "Room 43 uses tileset 7")
	var r43_chr: Array = r43.get("bg_chr_banks", []) as Array
	_assert_eq_int(r43_chr.size(), 4, "Room 43 resolves 4 x 1KB BG CHR banks")
	if r43_chr.size() == 4:
		_assert_eq_int(int(r43_chr[0]), 0, "Room 43 CHR R2 = 0")
		_assert_eq_int(int(r43_chr[1]), 14, "Room 43 CHR R3 = 14")
		_assert_eq_int(int(r43_chr[2]), 15, "Room 43 CHR R4 = 15")
		_assert_eq_int(int(r43_chr[3]), 28, "Room 43 CHR R5 = 28")

	var r43_mts: Array = r43.get("metatiles", []) as Array
	_assert_eq_int(r43_mts.size(), 4 * 16 * 12, "Room 43 unpacked 768 metatiles (64x12)")
	var r43_doors: Array = r43.get("doors", []) as Array
	_assert_eq_int(r43_doors.size(), 1, "Room 43 has 1 exit door")
	if not r43_doors.is_empty():
		var exit_door: Dictionary = r43_doors[0] as Dictionary
		_assert_eq_int(int(exit_door.get("dest_room_id", -1)), 44, "Room 43 door leads to Room 44")
	var r43_ents: Array = r43.get("entities", []) as Array
	_assert_eq_int(r43_ents.size(), 10, "Room 43 contains 10 entity spawns")

	# Verify tileset 7 metatile definitions (0x58 = grass SOLID, 0x00 = sky AIR)
	_assert_true(ContentRegistry.has_tileset(7), "ContentRegistry contains tileset 7")
	var mt_grass: Dictionary = ContentRegistry.get_metatile(7, 0x58)
	_assert_eq_int(int(mt_grass.get("tl", -1)), 0x4B, "Tileset 7 grass MT 0x58 TL=0x4B")
	_assert_eq_int(int(mt_grass.get("collision", -1)), Constants.TileCollision.SOLID, "Tileset 7 grass MT 0x58 is SOLID")
	var mt_sky: Dictionary = ContentRegistry.get_metatile(7, 0x00)
	_assert_eq_int(int(mt_sky.get("collision", -1)), Constants.TileCollision.AIR, "Tileset 7 sky MT 0x00 is AIR")

	# Verify extracted ROM palettes (R43 BG0 & Kirby default SP0)
	var bg0_pal: PackedInt32Array = ContentRegistry.get_palette_indices("room_43_bg_0")
	_assert_eq_int(bg0_pal.size(), 4, "Room 43 BG0 palette has 4 NES color entries")
	if bg0_pal.size() == 4:
		_assert_eq_int(bg0_pal[0], 0x21, "Room 43 BG0 universal sky color is 0x21")
	var kirby_pal: PackedInt32Array = ContentRegistry.get_palette_indices("kirby_default")
	_assert_eq_int(kirby_pal.size(), 4, "Kirby default palette extracted with 4 entries")
	if kirby_pal.size() == 4:
		_assert_eq_int(kirby_pal[1], 0x35, "Kirby default palette light pink index is 0x35")
		_assert_eq_int(kirby_pal[2], 0x25, "Kirby default palette dark pink index is 0x25")
		_assert_eq_int(kirby_pal[3], 0x0F, "Kirby default palette outline index is 0x0F")
	var hud_bg0: PackedInt32Array = ContentRegistry.get_palette_indices("hud_bg_0")
	_assert_eq_int(hud_bg0.size(), 4, "HUD BG0 palette extracted from Bank 56 with 4 entries")
	if hud_bg0.size() == 4:
		_assert_eq_int(hud_bg0[1], 0x35, "HUD BG0 panel color is light pink 0x35")

	# Verify PRG-ROM OAM metasprites & R0..R5 bank catalog extraction (Track A)
	var k_stand: Dictionary = ContentRegistry.get_kirby_metasprite_frame("default", 0)
	_assert_eq_int(int(k_stand.get("r0_bank", -1)), 128, "Kirby stand frame uses R0 CHR bank 128 (0x80)")
	var k_stand_sprs: Array = k_stand.get("sprites", []) as Array
	_assert_eq_int(k_stand_sprs.size(), 2, "Kirby stand frame defines 2 x 8x16 OAM sprites")
	var k_hover: Dictionary = ContentRegistry.get_kirby_metasprite_frame("default", 80)
	_assert_eq_int(int(k_hover.get("r0_bank", -1)), 130, "Kirby hover frame uses R0 CHR bank 130 (0x82)")
	_assert_eq_int((k_hover.get("sprites", []) as Array).size(), 6, "Kirby hover frame defines 6 x 8x16 OAM sprites (24x32)")
	var star0: Dictionary = ContentRegistry.get_effect_metasprite_frame("star", 0)
	_assert_eq_int((star0.get("sprites", []) as Array).size(), 2, "Star Spit frame 0 defines 2 x 8x16 OAM sprites")
	for core_aid: int in [14, 15, 16, 17, 18, 41, 56]:
		var a_frames: Array = ContentRegistry.get_actor_metasprite_frames(core_aid)
		_assert_true(a_frames.size() >= 4, "World 1 actor_id %d extracted >= 4 ROM metasprite frames (got %d)" % [core_aid, a_frames.size()])
	var bronto_frames: Array = ContentRegistry.get_actor_metasprite_frames(41)
	if bronto_frames.size() >= 2:
		var br_sprs: Array = (bronto_frames[1] as Dictionary).get("sprites", []) as Array
		if not br_sprs.is_empty():
			var br0: Dictionary = br_sprs[0] as Dictionary
			_assert_true(int(br0.get("tile", 0)) >= 0xE0, "Bronto Burt uses upper 1KB CHR bank R1+1 (tile=0x%02X)" % int(br0.get("tile", 0)))
			_assert_eq_int(int(br0.get("pal", -1)), 3, "Bronto Burt uses SP3 sprite palette")

	# Verify PRG-ROM HUD & Title Screen nametable/card extraction (Track B)
	var hud_layout: Dictionary = ContentRegistry.get_hud_layout()
	_assert_true(not hud_layout.is_empty(), "ContentRegistry exposes extracted ROM HUD layout")
	_assert_eq_int((hud_layout.get("stage_nametable", []) as Array).size(), 256, "Stage HUD nametable B19 $AE7A unpacked 32x8 tiles")
	_assert_eq_int((hud_layout.get("hub_nametable", []) as Array).size(), 256, "Hub HUD nametable B19 $AED5 unpacked 32x8 tiles")
	_assert_eq_int((hud_layout.get("lives_stage_tiles", []) as Array).size(), 56, "Lives stage packet B19 $B3E1 extracted 8x7 tiles")
	_assert_eq_int((hud_layout.get("cards", []) as Array).size(), 37, "Copy Ability card table B19 $B313/$B338 extracted 37 entries")
	_assert_eq_int(int(hud_layout.get("chr_r4_frame", -1)), 58, "HUD R4 frame bank is CHR 58 (0x3A)")
	_assert_eq_int(int(hud_layout.get("chr_r5_text", -1)), 63, "HUD R5 text bank is CHR 63 (0x3F)")

	var title_layout: Dictionary = ContentRegistry.get_title_screen_layout()
	_assert_true(not title_layout.is_empty(), "ContentRegistry exposes extracted ROM Title Screen layout")
	_assert_eq_int((title_layout.get("nametable", []) as Array).size(), 960, "Title Screen nametable B61 $AB5C unpacked 32x30 tiles")
	_assert_eq_int((title_layout.get("attributes", []) as Array).size(), 64, "Title Screen attribute table has 64 bytes")
	var t_banks: Array = title_layout.get("chr_banks", []) as Array
	_assert_eq_int(t_banks.size(), 4, "Title Screen resolves 4 x 1KB BG CHR banks")
	if t_banks.size() == 4:
		_assert_eq_int(int(t_banks[0]), 104, "Title Screen CHR R2 = 104")
		_assert_eq_int(int(t_banks[3]), 107, "Title Screen CHR R5 = 107")
	var t_pal0: PackedInt32Array = ContentRegistry.get_palette_indices("title_bg_0")
	_assert_eq_int(t_pal0.size(), 4, "Title Screen BG0 palette extracted from B61 $ADB8")
	if t_pal0.size() == 4:
		_assert_eq_int(t_pal0[0], 0x30, "Title Screen universal sky color is 0x30")
		_assert_eq_int(t_pal0[1], 0x25, "Title Screen BG0 accent color is 0x25")

	# Clean up temporary test extraction directory
	_cleanup_dir_recursive(test_user_dir)


func _cleanup_dir_recursive(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var item: String = dir.get_next()
	var entries: int = 0
	while item != "" and entries < MAX_CLEANUP_ENTRIES:
		entries += 1
		if item != "." and item != "..":
			var full: String = dir_path.path_join(item)
			if dir.current_is_dir():
				_cleanup_dir_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		item = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)
