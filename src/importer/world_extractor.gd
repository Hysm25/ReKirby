class_name WorldExtractor
extends RefCounted
## Extracts World 1 (Vegetable Valley) 16x16 metatile tilesets, room grids,
## palettes, CHR bank bindings, doors, and entity spawns from PRG-ROM via MMC3Mapper + HALDecompressor.

const Constants = preload("res://src/core/constants.gd")
const MMC3Mapper = preload("res://src/importer/mmc3_mapper.gd")
const HALDecompressor = preload("res://src/importer/hal_decompressor.gd")

const MAX_WORLD1_ROOMS: int = 64
const MAX_DOORS_PER_ROOM: int = 32
const MAX_ENTITIES_PER_ROOM: int = 128

# Structural offsets within PRG Bank 18 (0x12, mapped to $8000-$9FFF)
const B18_METATILE_PROP_TABLE: int = 0x83D3
const B18_METATILE_PROP_COUNT: int = 144

const B18_ROOM_BANK_LO: int = 0x84D1
const B18_ROOM_BANK_HI: int = 0x85D1
const B18_ROOM_TILESET_LO: int = 0x8618
const B18_ROOM_TILESET_HI: int = 0x8718
const B18_ROOM_ADDR_HI_LO: int = 0x875F
const B18_ROOM_ADDR_HI_HI: int = 0x885F
const B18_ROOM_ADDR_LO_LO: int = 0x88A6
const B18_ROOM_ADDR_LO_HI: int = 0x89A6

const B18_TILESET_BANK: int = 0x89ED
const B18_TILESET_ADDR_HI: int = 0x8A1E
const B18_TILESET_ADDR_LO: int = 0x8A4F
const B18_TILESET_CHR_FLAG: int = 0x9C5F

const B18_ENTITY_BANK_LO: int = 0x8A80
const B18_ENTITY_BANK_HI: int = 0x8B80
const B18_ENTITY_ADDR_HI_LO: int = 0x8BC7
const B18_ENTITY_ADDR_HI_HI: int = 0x8CC7
const B18_ENTITY_ADDR_LO_LO: int = 0x8D0E
const B18_ENTITY_ADDR_LO_HI: int = 0x8E0E

const B18_PALETTE_SET_TABLE: int = 0x8E55
const B18_DOOR_PTR_LO: int = 0x8F82
const B18_DOOR_PTR_HI: int = 0x90CB

# Structural offsets within PRG Bank 5 ($8000-$9FFF) and Bank 19 ($A000-$BFFF)
const B5_CHR_R3_TABLE: int = 0x9418
const B5_CHR_R4_TABLE: int = 0x9518
const B5_CHR_R5_TABLE: int = 0x9618

const B19_ACTOR_ID_TABLE: int = 0xA9D2
const B19_ACTOR_SUBTYPE_TABLE: int = 0xAAD2
const B19_BG3_OVERRIDE_ROOMS: int = 0xA766
const B24_ACTOR_SCRIPT_LO: int = 0xA0A7
const B24_ACTOR_SCRIPT_HI: int = 0xA117
const B24_ACTOR_SCRIPT_BANK: int = 0xA187
const PRG_BANK_ACTOR_INDEX: int = 24
const B56_HUD_PALETTE_ADDR: int = 0xB1CA # 4 HUD BG palettes (0..3) at $B1CA..$B1D9
const B56_KIRBY_PALETTE_ADDR: int = 0xB1DA # Kirby default SP0 palette [0F, 35, 25, 0F]
const B56_SP_EFFECT_PALETTE_ADDR: int = 0xB1DE # Fire/Star/Beam sprite palettes at $B1DE..$B1E9
const B19_STAGE_HUD_NAMETABLE: int = 0xAE7A # HAL-compressed 32x8 bottom HUD layout
const B19_HUB_HUD_NAMETABLE: int = 0xAED5 # HAL-compressed 32x8 hub map HUD layout
const B19_HUD_ATTR_FILL_BYTE: int = 0xADFA # 0xFF -> BG_3 across rows 22..29 ($2BE8..$2BFF)
const B19_SCORE_LABEL_BYTES: int = 0xB1F6 # 6 tiles ("SCORE-") written to $2B43
const B19_ENEMY_LABEL_BYTES: int = 0xB12C # 6 tiles ("ENEMY-") written to $2B43
const B19_CARD_R3_BANKS: int = 0xB313 # 37 R3 CHR bank indices indexed by (ability + 1)
const B19_CARD_TILE_SPECS: int = 0xB338 # 37 base tile & flag bytes indexed by (ability + 1)
const B19_LIVES_NORMAL_PACKET: int = 0xB3A4 # 00 D7 2A 08 07 + 56 tiles
const B19_LIVES_STAGE_PACKET: int = 0xB3E1 # 00 D7 2A 08 07 + 56 tiles
const B61_TITLE_NAMETABLE: int = 0xAB5C # HAL-compressed 32x30 nametable + 64 attr bytes
const B61_TITLE_CHR_INIT: int = 0xAA50 # MMC3 R0..R5 CHR banks for Title Screen
const B61_TITLE_PALETTES: int = 0xADB8 # 16 BG + 16 SP palette bytes at $ADB8..$ADD7
const MAX_OAM_SPRITES_PER_FRAME: int = 16
const MAX_METASPRITE_FRAMES: int = 128


class WorldExtractionResult extends RefCounted:
	var success: bool = false
	var error: String = ""
	var property_table: Array[int] = []
	var tilesets: Dictionary = {}
	var rooms: Dictionary = {}
	var palettes: Dictionary = {}
	var stage_start_rooms: Dictionary = {}
	var metasprites: Dictionary = {}
	var ui_layouts: Dictionary = {}


static func _map_r6(mapper: MMC3Mapper, bank_8k: int) -> void:
	mapper.write_register(0x8000, 0x86) # PRG mode 0, select R6 ($8000-$9FFF)
	mapper.write_register(0x8001, bank_8k & 0x3F)


static func _map_r7(mapper: MMC3Mapper, bank_8k: int) -> void:
	mapper.write_register(0x8000, 0x87) # PRG mode 0, select R7 ($A000-$BFFF)
	mapper.write_register(0x8001, bank_8k & 0x3F)


static func _decompress_at_a000(
	mapper: MMC3Mapper,
	prg_bank: int,
	cpu_addr: int,
	max_output_size: int
) -> HALDecompressor.DecompressResult:
	if cpu_addr < 0xA000 or cpu_addr > 0xBFFF:
		var bad: HALDecompressor.DecompressResult = HALDecompressor.DecompressResult.new()
		bad.error = "CPU address 0x%04X outside $A000-$BFFF window." % cpu_addr
		return bad
	_map_r7(mapper, prg_bank)
	var remaining: int = 0xC000 - cpu_addr
	var slice: PackedByteArray = mapper.read_prg_slice(cpu_addr, remaining)
	return HALDecompressor.decompress(slice, 0, max_output_size)


static func extract_metatile_property_table(mapper: MMC3Mapper) -> Array[int]:
	_map_r6(mapper, Constants.PRG_BANK_ROOM_TABLES)
	var raw: PackedByteArray = mapper.read_prg_slice(B18_METATILE_PROP_TABLE, B18_METATILE_PROP_COUNT)
	var table: Array[int] = []
	table.resize(raw.size())
	for i: int in range(raw.size()):
		table[i] = raw[i]
	return table


static func extract_tileset(
	mapper: MMC3Mapper,
	tileset_id: int,
	property_table: Array[int]
) -> Dictionary:
	if tileset_id < 0 or tileset_id >= Constants.TOTAL_ROM_TILESETS:
		return {}

	_map_r6(mapper, Constants.PRG_BANK_ROOM_TABLES)
	var ts_bank: int = mapper.read_prg_byte(B18_TILESET_BANK + tileset_id)
	var ts_hi: int = mapper.read_prg_byte(B18_TILESET_ADDR_HI + tileset_id)
	var ts_lo: int = mapper.read_prg_byte(B18_TILESET_ADDR_LO + tileset_id)
	var ts_chr_flag: int = mapper.read_prg_byte(B18_TILESET_CHR_FLAG + tileset_id)
	var cpu_addr: int = ts_lo | (ts_hi << 8)
	if cpu_addr < 0xA000 or cpu_addr > 0xBFFF:
		return {}

	var decomp: HALDecompressor.DecompressResult = _decompress_at_a000(
		mapper,
		ts_bank,
		cpu_addr,
		Constants.TILESET_STREAM_SIZE
	)
	if not decomp.success or decomp.data.size() != Constants.TILESET_STREAM_SIZE:
		return {}

	var stream: PackedByteArray = decomp.data
	var metatiles: Array[Dictionary] = []
	metatiles.resize(Constants.METATILES_PER_TILESET)

	for mt_id: int in range(Constants.METATILES_PER_TILESET):
		var tl: int = stream[mt_id * 4 + 0]
		var tr: int = stream[mt_id * 4 + 1]
		var bl: int = stream[mt_id * 4 + 2]
		var br: int = stream[mt_id * 4 + 3]

		var pal_byte: int = stream[1024 + (mt_id >> 2)]
		var shift: int = (3 - (mt_id & 3)) * 2
		var palette_idx: int = (pal_byte >> shift) & 0x03

		var raw_prop: int = stream[1088 + mt_id]
		var nes_collision: int = 0
		if raw_prop < property_table.size():
			nes_collision = property_table[raw_prop]
		var collision_type: int = Constants.map_nes_collision_to_enum(nes_collision, raw_prop)

		metatiles[mt_id] = {
			"tl": tl,
			"tr": tr,
			"bl": bl,
			"br": br,
			"palette": palette_idx,
			"raw_prop": raw_prop,
			"nes_collision": nes_collision,
			"collision": collision_type,
		}

	return {
		"tileset_id": tileset_id,
		"prg_bank": ts_bank,
		"cpu_addr": cpu_addr,
		"chr_flag": ts_chr_flag,
		"metatiles": metatiles,
	}


static func _extract_room_palettes(
	mapper: MMC3Mapper,
	room_id: int,
	palette_slot: int,
	palette_set_id: int,
	kirby_palette: Array[int]
) -> Dictionary:
	_map_r6(mapper, Constants.PRG_BANK_PALETTE_TABLES)
	var universal_bg: int = mapper.read_prg_byte(0x8000 + palette_slot) & 0x3F
	var bg0: Array[int] = [
		universal_bg,
		mapper.read_prg_byte(0x8100 + palette_slot) & 0x3F,
		mapper.read_prg_byte(0x8200 + palette_slot) & 0x3F,
		mapper.read_prg_byte(0x8300 + palette_slot) & 0x3F,
	]
	var bg1: Array[int] = [
		universal_bg,
		mapper.read_prg_byte(0x8400 + palette_slot) & 0x3F,
		mapper.read_prg_byte(0x8500 + palette_slot) & 0x3F,
		mapper.read_prg_byte(0x8600 + palette_slot) & 0x3F,
	]
	var bg2: Array[int] = [
		universal_bg,
		mapper.read_prg_byte(0x8700 + palette_slot) & 0x3F,
		mapper.read_prg_byte(0x8800 + palette_slot) & 0x3F,
		mapper.read_prg_byte(0x8900 + palette_slot) & 0x3F,
	]
	var bg3: Array[int] = [universal_bg, 0x37, 0x27, 0x07]

	# Check room-specific BG3 overrides in Bank 19 ($A713..$A777)
	_map_r7(mapper, Constants.PRG_BANK_LOADER_TABLES)
	if room_id == 0x11:
		bg3 = [universal_bg, 0x0F, 0x00, 0x20]
	else:
		for ov_idx: int in range(9):
			var lo: int = mapper.read_prg_byte(B19_BG3_OVERRIDE_ROOMS + ov_idx)
			var hi: int = mapper.read_prg_byte(B19_BG3_OVERRIDE_ROOMS + 9 + ov_idx)
			if ((hi << 8) | lo) == room_id:
				bg3 = [universal_bg, 0x20, 0x10, 0x00]
				break

	# Sprite palettes: SP0 = Kirby, SP1 = common stars/items ($30, $37, $17), SP2/SP3 = Bank 18 palette set
	_map_r6(mapper, Constants.PRG_BANK_ROOM_TABLES)
	var pal_set_addr: int = B18_PALETTE_SET_TABLE + palette_set_id * 6
	var sp0: Array[int] = [
		universal_bg,
		kirby_palette[1],
		kirby_palette[2],
		kirby_palette[3],
	]
	var sp1: Array[int] = [universal_bg, 0x30, 0x37, 0x17]
	var sp2: Array[int] = [
		universal_bg,
		mapper.read_prg_byte(pal_set_addr + 0) & 0x3F,
		mapper.read_prg_byte(pal_set_addr + 1) & 0x3F,
		mapper.read_prg_byte(pal_set_addr + 2) & 0x3F,
	]
	var sp3: Array[int] = [
		universal_bg,
		mapper.read_prg_byte(pal_set_addr + 3) & 0x3F,
		mapper.read_prg_byte(pal_set_addr + 4) & 0x3F,
		mapper.read_prg_byte(pal_set_addr + 5) & 0x3F,
	]

	return {
		"universal_bg": universal_bg,
		"bg_0": bg0,
		"bg_1": bg1,
		"bg_2": bg2,
		"bg_3": bg3,
		"sp_0": sp0,
		"sp_1": sp1,
		"sp_2": sp2,
		"sp_3": sp3,
	}


static func _extract_room_doors(
	mapper: MMC3Mapper,
	room_id: int,
	w_screens: int = 1,
	h_screens: int = 1
) -> Array[Dictionary]:
	_map_r6(mapper, Constants.PRG_BANK_ROOM_TABLES)
	var start_addr: int = mapper.read_prg_byte(B18_DOOR_PTR_LO + room_id) | (mapper.read_prg_byte(B18_DOOR_PTR_HI + room_id) << 8)
	var end_addr: int = mapper.read_prg_byte(B18_DOOR_PTR_LO + room_id + 1) | (mapper.read_prg_byte(B18_DOOR_PTR_HI + room_id + 1) << 8)
	var doors: Array[Dictionary] = []
	if end_addr <= start_addr or start_addr < 0x8000 or end_addr > 0xA000:
		return doors

	var byte_len: int = mini(end_addr - start_addr, MAX_DOORS_PER_ROOM * 5)
	var raw: PackedByteArray = mapper.read_prg_slice(start_addr, byte_len)
	var count: int = raw.size() / 5
	for i: int in range(count):
		var off: int = i * 5
		var b0: int = raw[off]
		var b1: int = raw[off + 1]
		var b2: int = raw[off + 2]
		var b3: int = raw[off + 3]
		var b4: int = raw[off + 4]
		var special: int = ((b3 & 0xF0) | (b0 >> 4)) & 0x7F
		var dest_room_id: int = (((b3 >> 7) & 0x01) << 8) | b2
		var src_scr: int = b0 & 0x0F
		var src_x: int = (b1 >> 4) & 0x0F
		var src_y: int = b1 & 0x0F
		var sx: int = src_scr % maxi(1, w_screens)
		var sy: int = src_scr / maxi(1, w_screens)
		var trigger_mode: String = "up_press"
		if sy == 0 and src_y == 0:
			trigger_mode = "edge_top"
		elif sy == maxi(1, h_screens) - 1 and src_y == Constants.ROOM_SCREEN_ROWS - 1:
			trigger_mode = "edge_bottom"
		elif sx == maxi(1, w_screens) - 1 and src_x == Constants.ROOM_SCREEN_COLS - 1:
			trigger_mode = "edge_right"
		doors.append({
			"special": special,
			"src_screen": src_scr,
			"src_x": src_x,
			"src_y": src_y,
			"dest_room_id": dest_room_id,
			"dst_screen": b3 & 0x0F,
			"dst_x": (b4 >> 4) & 0x0F,
			"dst_y": b4 & 0x0F,
			"trigger_mode": trigger_mode,
		})
	return doors


static func _extract_room_entities(mapper: MMC3Mapper, room_id: int) -> Array[Dictionary]:
	_map_r6(mapper, Constants.PRG_BANK_ROOM_TABLES)
	var is_hi_page: bool = room_id >= 256
	var idx: int = room_id - 256 if is_hi_page else room_id
	var ent_bank: int = mapper.read_prg_byte((B18_ENTITY_BANK_HI if is_hi_page else B18_ENTITY_BANK_LO) + idx)
	var ent_hi: int = mapper.read_prg_byte((B18_ENTITY_ADDR_HI_HI if is_hi_page else B18_ENTITY_ADDR_HI_LO) + idx)
	var ent_lo: int = mapper.read_prg_byte((B18_ENTITY_ADDR_LO_HI if is_hi_page else B18_ENTITY_ADDR_LO_LO) + idx)
	var ent_addr: int = ent_lo | (ent_hi << 8)
	var entities: Array[Dictionary] = []
	if ent_addr < 0xA000 or ent_addr > 0xBFFF:
		return entities

	_map_r7(mapper, ent_bank)
	var n_slices: int = mapper.read_prg_byte(ent_addr)
	if n_slices == 0 or n_slices > 64:
		return entities

	var slice_ends: PackedByteArray = mapper.read_prg_slice(ent_addr + 2, n_slices)
	var total_ents: int = slice_ends[n_slices - 1]
	if total_ents == 0:
		return entities
	total_ents = mini(total_ents, MAX_ENTITIES_PER_ROOM)

	var coords_addr: int = ent_addr + 2 + n_slices
	var types_addr: int = coords_addr + slice_ends[n_slices - 1]
	var coords: PackedByteArray = mapper.read_prg_slice(coords_addr, total_ents)
	var raw_types: PackedByteArray = mapper.read_prg_slice(types_addr, total_ents)

	# Lookup actor_id & subtype from Bank 19 tables ($A9D2 / $AAD2)
	_map_r7(mapper, Constants.PRG_BANK_LOADER_TABLES)
	var actor_ids: PackedInt32Array = PackedInt32Array()
	var subtypes: PackedInt32Array = PackedInt32Array()
	actor_ids.resize(total_ents)
	subtypes.resize(total_ents)
	for i: int in range(total_ents):
		var raw_t: int = raw_types[i]
		actor_ids[i] = mapper.read_prg_byte(B19_ACTOR_ID_TABLE + raw_t)
		subtypes[i] = mapper.read_prg_byte(B19_ACTOR_SUBTYPE_TABLE + raw_t)

	var prev_end: int = 0
	for s_idx: int in range(n_slices):
		var cur_end: int = mini(slice_ends[s_idx], total_ents)
		for i: int in range(prev_end, cur_end):
			var packed_xy: int = coords[i]
			entities.append({
				"screen": s_idx,
				"tile_x": (packed_xy >> 4) & 0x0F,
				"tile_y": packed_xy & 0x0F,
				"raw_type": raw_types[i],
				"actor_id": actor_ids[i],
				"subtype": subtypes[i],
			})
		prev_end = cur_end

	return entities


static func extract_room(
	mapper: MMC3Mapper,
	room_id: int,
	kirby_palette: Array[int]
) -> Dictionary:
	if room_id < 0 or room_id >= Constants.TOTAL_ROM_ROOMS:
		return {}

	_map_r6(mapper, Constants.PRG_BANK_ROOM_TABLES)
	var is_hi_page: bool = room_id >= 256
	var idx: int = room_id - 256 if is_hi_page else room_id
	var bank_raw: int = mapper.read_prg_byte((B18_ROOM_BANK_HI if is_hi_page else B18_ROOM_BANK_LO) + idx)
	var tileset_id: int = mapper.read_prg_byte((B18_ROOM_TILESET_HI if is_hi_page else B18_ROOM_TILESET_LO) + idx)
	var addr_hi: int = mapper.read_prg_byte((B18_ROOM_ADDR_HI_HI if is_hi_page else B18_ROOM_ADDR_HI_LO) + idx)
	var addr_lo: int = mapper.read_prg_byte((B18_ROOM_ADDR_LO_HI if is_hi_page else B18_ROOM_ADDR_LO_LO) + idx)
	var room_bank: int = bank_raw & 0x7F
	var room_addr: int = addr_lo | (addr_hi << 8)

	var decomp: HALDecompressor.DecompressResult = _decompress_at_a000(mapper, room_bank, room_addr, 16384)
	if not decomp.success or decomp.data.size() < Constants.ROOM_HEADER_SIZE:
		return {}

	var raw: PackedByteArray = decomp.data
	var w_screens: int = raw[0]
	var h_screens: int = raw[1]
	var chr_slot: int = raw[2]
	var palette_slot: int = raw[3]
	var sprite_chr_bank: int = raw[4]
	var palette_set_id: int = raw[5]
	var bgm_id: int = raw[6] & 0xFF
	var scroll_flag: int = raw[7] & 0xFF
	var screen_count: int = w_screens * h_screens
	if w_screens <= 0 or h_screens <= 0 or raw.size() < Constants.ROOM_HEADER_SIZE:
		return {}

	var screen_grid: Array[int] = []
	screen_grid.resize(screen_count)
	var max_scr_idx: int = 0
	for i: int in range(screen_count):
		var s_val: int = raw[8 + i]
		screen_grid[i] = s_val
		if s_val > max_scr_idx:
			max_scr_idx = s_val
	var expected_size: int = Constants.ROOM_HEADER_SIZE + (max_scr_idx + 1) * Constants.ROOM_SCREEN_METATILES
	if raw.size() < expected_size:
		return {}

	# Unpack flat 2D metatile map in row-major order: width = w_screens * 16, height = h_screens * 12
	var map_width: int = w_screens * Constants.ROOM_SCREEN_COLS
	var map_height: int = h_screens * Constants.ROOM_SCREEN_ROWS
	var metatiles_flat: Array[int] = []
	metatiles_flat.resize(map_width * map_height)
	for sy: int in range(h_screens):
		for sx: int in range(w_screens):
			var screen_idx: int = screen_grid[sy * w_screens + sx]
			if screen_idx >= screen_count:
				screen_idx = sy * w_screens + sx
			var screen_base: int = Constants.ROOM_HEADER_SIZE + screen_idx * Constants.ROOM_SCREEN_METATILES
			for ly: int in range(Constants.ROOM_SCREEN_ROWS):
				var global_y: int = sy * Constants.ROOM_SCREEN_ROWS + ly
				var dst_row_base: int = global_y * map_width + sx * Constants.ROOM_SCREEN_COLS
				var src_row_base: int = screen_base + ly * Constants.ROOM_SCREEN_COLS
				for lx: int in range(Constants.ROOM_SCREEN_COLS):
					metatiles_flat[dst_row_base + lx] = raw[src_row_base + lx]

	# Resolve 4 x 1KB BG CHR banks (R2, R3, R4, R5) via Bank 5 tables
	_map_r6(mapper, Constants.PRG_BANK_CHR_TABLES)
	var chr_r2: int = 0
	var chr_r3: int = mapper.read_prg_byte(B5_CHR_R3_TABLE + chr_slot)
	var chr_r4: int = mapper.read_prg_byte(B5_CHR_R4_TABLE + chr_slot)
	var chr_r5: int = mapper.read_prg_byte(B5_CHR_R5_TABLE + chr_slot)
	var bg_chr_banks: Array[int] = [chr_r2, chr_r3, chr_r4, chr_r5]

	var room_palettes: Dictionary = _extract_room_palettes(
		mapper,
		room_id,
		palette_slot,
		palette_set_id,
		kirby_palette
	)
	var doors: Array[Dictionary] = _extract_room_doors(mapper, room_id, w_screens, h_screens)
	var entities: Array[Dictionary] = _extract_room_entities(mapper, room_id)

	return {
		"room_id": room_id,
		"width_screens": w_screens,
		"height_screens": h_screens,
		"width_metatiles": map_width,
		"height_metatiles": map_height,
		"tileset_id": tileset_id,
		"chr_slot": chr_slot,
		"palette_slot": palette_slot,
		"palette_set_id": palette_set_id,
		"bgm_id": bgm_id,
		"scroll_flag": scroll_flag,
		"sprite_chr_bank": sprite_chr_bank,
		"bg_chr_banks": bg_chr_banks,
		"is_checkpoint": (bank_raw & 0x80) != 0,
		"screen_grid": screen_grid,
		"metatiles": metatiles_flat,
		"palettes": room_palettes,
		"doors": doors,
		"entities": entities,
	}


static func extract_world1(prg_data: PackedByteArray) -> WorldExtractionResult:
	var result: WorldExtractionResult = WorldExtractionResult.new()
	if prg_data.size() != Constants.EXPECTED_PRG_SIZE:
		result.error = "Invalid PRG-ROM size %d for WorldExtractor." % prg_data.size()
		return result

	var mapper: MMC3Mapper = MMC3Mapper.new(prg_data, PackedByteArray())

	# Extract HUD & Sprite palettes from Bank 56 ($B1CA..$B1E9)
	_map_r7(mapper, Constants.PRG_BANK_HUD_PALETTES)
	var hud_pal_raw: PackedByteArray = mapper.read_prg_slice(B56_HUD_PALETTE_ADDR, 32)
	var kirby_palette: Array[int] = [
		hud_pal_raw[16] & 0x3F,
		hud_pal_raw[17] & 0x3F,
		hud_pal_raw[18] & 0x3F,
		hud_pal_raw[19] & 0x3F,
	]

	var prop_table: Array[int] = extract_metatile_property_table(mapper)
	if prop_table.size() != B18_METATILE_PROP_COUNT:
		result.error = "Failed to read Bank 18 metatile property table."
		return result
	result.property_table = prop_table

	# Hardware 2C02 diagnostic ramp + extracted HUD & Kirby SP palettes
	result.palettes["ppu_grayscale"] = [0x0F, 0x00, 0x10, 0x30]
	result.palettes["kirby_default"] = kirby_palette
	for hud_idx: int in range(4):
		var off: int = hud_idx * 4
		result.palettes["hud_bg_%d" % hud_idx] = [
			hud_pal_raw[off] & 0x3F,
			hud_pal_raw[off + 1] & 0x3F,
			hud_pal_raw[off + 2] & 0x3F,
			hud_pal_raw[off + 3] & 0x3F,
		]
	result.palettes["hud_sp_fire"] = [
		hud_pal_raw[20] & 0x3F,
		hud_pal_raw[21] & 0x3F,
		hud_pal_raw[22] & 0x3F,
		hud_pal_raw[23] & 0x3F,
	]
	result.palettes["hud_sp_star"] = [
		hud_pal_raw[24] & 0x3F,
		hud_pal_raw[25] & 0x3F,
		hud_pal_raw[26] & 0x3F,
		hud_pal_raw[27] & 0x3F,
	]
	result.palettes["hud_sp_beam"] = [
		hud_pal_raw[28] & 0x3F,
		hud_pal_raw[29] & 0x3F,
		hud_pal_raw[30] & 0x3F,
		hud_pal_raw[31] & 0x3F,
	]

	# Traverse World 1 dynamically starting at Room 0 (Vegetable Valley Hub) to track World 1 metrics,
	# then extract all remaining ROM rooms (0..326) and all 49 tilesets (0..48) for Worlds 1-7 parity.
	var queue: Array[int] = [Constants.WORLD1_HUB_ROOM_ID]
	var visited: Dictionary = {}
	var world1_tilesets: Dictionary = {}
	var needed_tilesets: Dictionary = {}
	var seen_actors: Dictionary = {}
	var iterations: int = 0

	while not queue.is_empty() and iterations < MAX_WORLD1_ROOMS:
		iterations += 1
		var rid: int = int(queue.pop_front())
		if visited.has(rid):
			continue
		visited[rid] = true

		var room_data: Dictionary = extract_room(mapper, rid, kirby_palette)
		if room_data.is_empty():
			result.error = "Failed to extract World 1 room %d." % rid
			return result

		result.rooms[rid] = room_data
		var ts_id: int = int(room_data["tileset_id"])
		world1_tilesets[ts_id] = true
		needed_tilesets[ts_id] = true
		var r_ents: Array = room_data.get("entities", []) as Array
		for ent_var: Variant in r_ents:
			var ent_d: Dictionary = ent_var as Dictionary
			var aid: int = int(ent_d.get("actor_id", -1))
			if aid >= 0:
				seen_actors[aid] = true

		# Register room palettes in global palette repository
		var r_pals: Dictionary = room_data["palettes"] as Dictionary
		for p_idx: int in range(4):
			result.palettes["room_%d_bg_%d" % [rid, p_idx]] = r_pals["bg_%d" % p_idx]
			result.palettes["room_%d_sp_%d" % [rid, p_idx]] = r_pals["sp_%d" % p_idx]

		# Enqueue World 1 destination rooms (exclude World 2 Hub and mini-game/subgame rooms)
		var doors: Array = room_data["doors"] as Array
		for door_var: Variant in doors:
			var door: Dictionary = door_var as Dictionary
			var sp: int = int(door["special"])
			var dst: int = int(door["dest_room_id"])
			if rid == Constants.WORLD1_HUB_ROOM_ID and sp >= 1 and sp <= 4:
				result.stage_start_rooms[sp] = dst
			elif rid == Constants.WORLD1_HUB_ROOM_ID and sp == 0x1D:
				result.stage_start_rooms["boss"] = dst
			elif rid == Constants.WORLD1_HUB_ROOM_ID and sp == 0x18:
				result.stage_start_rooms["museum"] = dst

			if dst == Constants.WORLD2_HUB_ROOM_ID or sp == 0x1F or sp == 0x1C:
				continue
			if not visited.has(dst) and not queue.has(dst):
				queue.append(dst)

	result.stage_start_rooms["world1_room_count"] = visited.size()
	result.stage_start_rooms["world1_tileset_count"] = world1_tilesets.size()

	# Extract all remaining ROM rooms (0..326) across Worlds 2-7 & bonus/arena rooms
	for rid: int in range(Constants.TOTAL_ROM_ROOMS):
		if result.rooms.has(rid):
			continue
		var room_data: Dictionary = extract_room(mapper, rid, kirby_palette)
		if room_data.is_empty():
			continue
		result.rooms[rid] = room_data
		var ts_id: int = int(room_data["tileset_id"])
		needed_tilesets[ts_id] = true
		var r_ents: Array = room_data.get("entities", []) as Array
		for ent_var: Variant in r_ents:
			var ent_d: Dictionary = ent_var as Dictionary
			var aid: int = int(ent_d.get("actor_id", -1))
			if aid >= 0:
				seen_actors[aid] = true
		var r_pals: Dictionary = room_data["palettes"] as Dictionary
		for p_idx: int in range(4):
			result.palettes["room_%d_bg_%d" % [rid, p_idx]] = r_pals["bg_%d" % p_idx]
			result.palettes["room_%d_sp_%d" % [rid, p_idx]] = r_pals["sp_%d" % p_idx]

	for ts_id: int in range(Constants.TOTAL_ROM_TILESETS):
		var ts_data: Dictionary = extract_tileset(mapper, ts_id, prop_table)
		if ts_data.is_empty():
			if needed_tilesets.has(ts_id):
				result.error = "Failed to extract needed ROM tileset %d." % ts_id
				return result
			continue
		result.tilesets[ts_id] = ts_data

	var actor_id_list: Array[int] = []
	for core_aid: int in [5, 6, 14, 15, 16, 17, 18, 41, 56, 61, 63, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 79]:
		seen_actors[core_aid] = true
	for aid_key: Variant in seen_actors.keys():
		actor_id_list.append(int(aid_key))
	actor_id_list.sort()
	result.metasprites = extract_metasprite_catalog(mapper, actor_id_list)
	result.ui_layouts = extract_ui_layouts(mapper, result.palettes)

	result.success = (
		not result.rooms.is_empty()
		and not result.tilesets.is_empty()
		and not result.metasprites.is_empty()
		and not result.ui_layouts.is_empty()
	)
	return result


static func _signed_byte(val: int) -> int:
	var b: int = val & 0xFF
	return b - 256 if b >= 128 else b


static func _parse_oam_frame_table(
	mapper: MMC3Mapper,
	bank_8k: int,
	table_addr: int,
	has_r0_prefix: bool,
	max_frames: int = MAX_METASPRITE_FRAMES
) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	if bank_8k <= 0 or bank_8k >= Constants.EXPECTED_PRG_BANKS_8K:
		return frames
	var win_base: int = 0xA000 if table_addr >= 0xA000 else 0x8000
	if table_addr < win_base or table_addr >= win_base + Constants.PRG_BANK_8K_SIZE:
		return frames
	if win_base == 0x8000:
		_map_r6(mapper, bank_8k)
	else:
		_map_r7(mapper, bank_8k)

	var min_data_ptr: int = win_base + Constants.PRG_BANK_8K_SIZE
	var limit: int = mini(max_frames, MAX_METASPRITE_FRAMES)
	for f_idx: int in range(limit):
		var ptr_addr: int = table_addr + f_idx * 2
		if ptr_addr >= min_data_ptr or ptr_addr + 1 >= win_base + Constants.PRG_BANK_8K_SIZE:
			break
		var frame_ptr: int = mapper.read_prg_byte(ptr_addr) | (mapper.read_prg_byte(ptr_addr + 1) << 8)
		if frame_ptr < win_base or frame_ptr >= win_base + Constants.PRG_BANK_8K_SIZE - 5:
			break
		if frame_ptr > table_addr and frame_ptr < min_data_ptr:
			min_data_ptr = frame_ptr

		var cur: int = frame_ptr
		var r0_bank: int = -1
		if has_r0_prefix:
			r0_bank = mapper.read_prg_byte(cur)
			cur += 1
		var count: int = mapper.read_prg_byte(cur)
		cur += 1
		if count <= 0 or count > MAX_OAM_SPRITES_PER_FRAME:
			break
		if cur + count * 4 > win_base + Constants.PRG_BANK_8K_SIZE:
			break

		var sprites: Array[Dictionary] = []
		sprites.resize(count)
		for s_idx: int in range(count):
			var base_s: int = cur + s_idx * 4
			var dx: int = _signed_byte(mapper.read_prg_byte(base_s))
			var dy: int = _signed_byte(mapper.read_prg_byte(base_s + 1))
			var tile: int = mapper.read_prg_byte(base_s + 2)
			var attr: int = mapper.read_prg_byte(base_s + 3)
			sprites[s_idx] = {
				"dx": dx,
				"dy": dy,
				"tile": tile,
				"attr": attr,
				"pal": attr & 0x03,
				"flip_h": (attr & 0x40) != 0,
				"flip_v": (attr & 0x80) != 0,
			}

		frames.append({
			"ptr": frame_ptr,
			"r0_bank": r0_bank,
			"sprites": sprites,
		})
	return frames


static func _extract_actor_metasprite_entry(mapper: MMC3Mapper, actor_id: int) -> Dictionary:
	if actor_id < 0 or actor_id >= 112:
		return {}
	_map_r7(mapper, PRG_BANK_ACTOR_INDEX)
	var sc_lo: int = mapper.read_prg_byte(B24_ACTOR_SCRIPT_LO + actor_id)
	var sc_hi: int = mapper.read_prg_byte(B24_ACTOR_SCRIPT_HI + actor_id)
	var sc_bank: int = mapper.read_prg_byte(B24_ACTOR_SCRIPT_BANK + actor_id)
	var sc_addr: int = sc_lo | (sc_hi << 8)
	if sc_bank <= 0 or sc_bank >= Constants.EXPECTED_PRG_BANKS_8K or sc_addr < 0xA000 or sc_addr >= 0xBFFF:
		return {}

	_map_r7(mapper, sc_bank)
	var scan_len: int = mini(224, 0xC000 - sc_addr - 4)
	var slice: PackedByteArray = mapper.read_prg_slice(sc_addr, scan_len)
	for i: int in range(maxi(0, slice.size() - 4)):
		if slice[i] == 0x1A:
			var tbl_addr: int = slice[i + 1] | (slice[i + 2] << 8)
			var tbl_bank: int = slice[i + 3]
			if tbl_addr >= 0x8000 and tbl_addr < 0xC000 and tbl_bank >= 1 and tbl_bank < Constants.EXPECTED_PRG_BANKS_8K:
				var has_r0: bool = false
				for j: int in range(maxi(0, i - 16), mini(slice.size() - 2, i + 16)):
					if slice[j] == 0x20 and slice[j + 1] == 0xAA and slice[j + 2] == 0xDD:
						has_r0 = true
						break
				var frames: Array[Dictionary] = _parse_oam_frame_table(mapper, tbl_bank, tbl_addr, has_r0, 64)
				if not frames.is_empty():
					return {
						"actor_id": actor_id,
						"script_bank": sc_bank,
						"script_addr": sc_addr,
						"table_bank": tbl_bank,
						"table_addr": tbl_addr,
						"has_r0_prefix": has_r0,
						"frames": frames,
					}
	return {}


static func extract_metasprite_catalog(mapper: MMC3Mapper, actor_ids: Array[int]) -> Dictionary:
	var actors: Dictionary = {}
	for aid: int in actor_ids:
		var entry: Dictionary = _extract_actor_metasprite_entry(mapper, aid)
		if not entry.is_empty():
			actors[str(aid)] = entry

	var kirby_tables: Dictionary = {
		"default": _parse_oam_frame_table(mapper, 26, 0x8000, true, 128),
		"hover_wide": _parse_oam_frame_table(mapper, 26, 0x8846, true, 32),
		"hat_walk": _parse_oam_frame_table(mapper, 26, 0x8EE6, true, 32),
		"sword": _parse_oam_frame_table(mapper, 27, 0x8000, true, 64),
		"beam": _parse_oam_frame_table(mapper, 27, 0x88F2, true, 32),
		"fire": _parse_oam_frame_table(mapper, 27, 0x9320, true, 32),
		"somersault": _parse_oam_frame_table(mapper, 27, 0x9CAE, true, 16),
		"spark_swim": _parse_oam_frame_table(mapper, 28, 0x8216, true, 32),
	}

	var effect_tables: Dictionary = {
		"star": _parse_oam_frame_table(mapper, 28, 0x9CD7, false, 16),
		"air_puff": _parse_oam_frame_table(mapper, 28, 0x9F0B, false, 8),
		"items": _parse_oam_frame_table(mapper, 28, 0x9FC4, false, 8),
		"boss_apples": _parse_oam_frame_table(mapper, 58, 0x9C62, false, 8),
		"boss_puffs": _parse_oam_frame_table(mapper, 58, 0x9E25, false, 8),
	}

	return {
		"actors": actors,
		"kirby_tables": kirby_tables,
		"effect_tables": effect_tables,
	}


static func _packed_to_int_array(bytes: PackedByteArray, start_idx: int = 0, count: int = -1) -> Array[int]:
	var out: Array[int] = []
	var end_idx: int = bytes.size() if count < 0 else mini(bytes.size(), start_idx + count)
	for i: int in range(maxi(0, start_idx), end_idx):
		out.append(int(bytes[i]) & 0xFF)
	return out


static func extract_ui_layouts(mapper: MMC3Mapper, palettes_out: Dictionary) -> Dictionary:
	_map_r7(mapper, Constants.PRG_BANK_LOADER_TABLES)
	var stage_res: HALDecompressor.DecompressResult = _decompress_at_a000(
		mapper,
		Constants.PRG_BANK_LOADER_TABLES,
		B19_STAGE_HUD_NAMETABLE,
		512
	)
	var hub_res: HALDecompressor.DecompressResult = _decompress_at_a000(
		mapper,
		Constants.PRG_BANK_LOADER_TABLES,
		B19_HUB_HUD_NAMETABLE,
		512
	)
	if not stage_res.success or stage_res.data.size() < 256:
		return {}
	if not hub_res.success or hub_res.data.size() < 256:
		return {}

	_map_r7(mapper, Constants.PRG_BANK_LOADER_TABLES)
	var attr_fill: int = mapper.read_prg_byte(B19_HUD_ATTR_FILL_BYTE) & 0xFF
	var score_label_raw: PackedByteArray = mapper.read_prg_slice(B19_SCORE_LABEL_BYTES, 6)
	var enemy_label_raw: PackedByteArray = mapper.read_prg_slice(B19_ENEMY_LABEL_BYTES, 6)
	var lives_normal_raw: PackedByteArray = mapper.read_prg_slice(B19_LIVES_NORMAL_PACKET + 5, 56)
	var lives_stage_raw: PackedByteArray = mapper.read_prg_slice(B19_LIVES_STAGE_PACKET + 5, 56)

	var card_banks_raw: PackedByteArray = mapper.read_prg_slice(B19_CARD_R3_BANKS, 37)
	var card_specs_raw: PackedByteArray = mapper.read_prg_slice(B19_CARD_TILE_SPECS, 37)
	var cards: Array[Dictionary] = []
	for i: int in range(37):
		var spec_byte: int = int(card_specs_raw[i]) & 0xFF
		cards.append({
			"r3_bank": int(card_banks_raw[i]) & 0xFF,
			"base_tile": spec_byte & 0x0F,
			"flag": (spec_byte >> 4) & 0x0F,
		})

	# Map ReKirby CopyAbility enum -> B19 $B313/$B338 card index (0..24)
	var ability_card_map: Dictionary = {
		str(Constants.CopyAbility.NONE): 0,
		str(Constants.CopyAbility.SWORD): 4,
		str(Constants.CopyAbility.FIRE): 1,
		str(Constants.CopyAbility.SPARK): 2,
		str(Constants.CopyAbility.BEAM): 16,
		str(Constants.CopyAbility.CUTTER): 3,
		str(Constants.CopyAbility.ICE): 13,
		str(Constants.CopyAbility.FREEZE): 14,
		str(Constants.CopyAbility.WHEEL): 8,
		str(Constants.CopyAbility.STONE): 17,
		str(Constants.CopyAbility.HAMMER): 9,
		str(Constants.CopyAbility.PARASOL): 10,
		str(Constants.CopyAbility.NEEDLE): 12,
		str(Constants.CopyAbility.TORNADO): 19,
		str(Constants.CopyAbility.HI_JUMP): 15,
		str(Constants.CopyAbility.BALL): 18,
		str(Constants.CopyAbility.FIREBALL): 5,
		str(Constants.CopyAbility.LASER): 6,
		str(Constants.CopyAbility.MIKE): 7,
		str(Constants.CopyAbility.CRASH): 20,
		str(Constants.CopyAbility.THROW): 23,
		str(Constants.CopyAbility.BACKDROP): 22,
		str(Constants.CopyAbility.LIGHT): 21,
		str(Constants.CopyAbility.UFO): 24,
		str(Constants.CopyAbility.SLEEP): 11,
	}

	var hud_dict: Dictionary = {
		"cols": 32,
		"rows": 8,
		"stage_nametable": _packed_to_int_array(stage_res.data, 0, 256),
		"hub_nametable": _packed_to_int_array(hub_res.data, 0, 256),
		"lives_normal_tiles": _packed_to_int_array(lives_normal_raw),
		"lives_stage_tiles": _packed_to_int_array(lives_stage_raw),
		"lives_box_col": 23,
		"lives_box_row": 0,
		"lives_box_cols": 8,
		"lives_box_rows": 7,
		"score_label_tiles": _packed_to_int_array(score_label_raw),
		"enemy_label_tiles": _packed_to_int_array(enemy_label_raw),
		"score_row": 4,
		"score_label_col": 3,
		"score_digits_col": 10,
		"hp_pip_col": 10,
		"hp_pip_row": 1,
		"hp_pip_max": 6,
		"hp_pip_full": [0x1A, 0x1B, 0x1C],
		"hp_pip_empty": [0x81, 0x98, 0x81],
		"card_col": 19,
		"card_row": 1,
		"card_cols": 4,
		"card_rows": 5,
		"chr_r2_anim_banks": [
			Constants.CHR_BANK_HUD_ANIM_BASE,
			Constants.CHR_BANK_HUD_ANIM_BASE + 1,
			Constants.CHR_BANK_HUD_ANIM_BASE + 2,
			Constants.CHR_BANK_HUD_ANIM_BASE + 3,
		],
		"chr_r4_frame": Constants.CHR_BANK_HUD_BG_FRAME,
		"chr_r5_text": Constants.CHR_BANK_HUD_BG_TEXT,
		"hud_attr_fill": attr_fill,
		"cards": cards,
		"ability_card_map": ability_card_map,
	}

	# Extract Title Screen (Bank 61 $AB5C nametable + $AA50 CHR banks + $ADB8 palettes)
	var title_res: HALDecompressor.DecompressResult = _decompress_at_a000(
		mapper,
		Constants.PRG_BANK_TITLE_SCREEN,
		B61_TITLE_NAMETABLE,
		2048
	)
	if not title_res.success or title_res.data.size() < 1024:
		return {}

	_map_r7(mapper, Constants.PRG_BANK_TITLE_SCREEN)
	var chr_init_raw: PackedByteArray = mapper.read_prg_slice(B61_TITLE_CHR_INIT, 28)
	var r2_bank: int = int(chr_init_raw[9]) & 0xFF # $AA59 (0x68 = 104)
	var r3_bank: int = int(chr_init_raw[14]) & 0xFF # $AA5E (0x69 = 105)
	var r4_bank: int = int(chr_init_raw[19]) & 0xFF # $AA63 (0x6A = 106)
	var r5_bank: int = int(chr_init_raw[24]) & 0xFF # $AA68 (0x6B = 107)

	var title_pal_raw: PackedByteArray = mapper.read_prg_slice(B61_TITLE_PALETTES, 32)
	var title_univ: int = int(title_pal_raw[0]) & 0x3F
	var title_bg_pals: Array[Array] = []
	var title_sp_pals: Array[Array] = []
	for p_idx: int in range(4):
		var bg_off: int = p_idx * 4
		var bg_arr: Array[int] = [
			title_univ,
			int(title_pal_raw[bg_off + 1]) & 0x3F,
			int(title_pal_raw[bg_off + 2]) & 0x3F,
			int(title_pal_raw[bg_off + 3]) & 0x3F,
		]
		title_bg_pals.append(bg_arr)
		palettes_out["title_bg_%d" % p_idx] = bg_arr

		var sp_off: int = 16 + p_idx * 4
		var sp_arr: Array[int] = [
			title_univ,
			int(title_pal_raw[sp_off + 1]) & 0x3F,
			int(title_pal_raw[sp_off + 2]) & 0x3F,
			int(title_pal_raw[sp_off + 3]) & 0x3F,
		]
		title_sp_pals.append(sp_arr)
		palettes_out["title_sp_%d" % p_idx] = sp_arr

	var title_dict: Dictionary = {
		"cols": 32,
		"rows": 30,
		"chr_banks": [r2_bank, r3_bank, r4_bank, r5_bank],
		"nametable": _packed_to_int_array(title_res.data, 0, 960),
		"attributes": _packed_to_int_array(title_res.data, 960, 64),
		"palettes_bg": title_bg_pals,
		"palettes_sp": title_sp_pals,
	}

	return {
		"hud": hud_dict,
		"title_screen": title_dict,
	}
