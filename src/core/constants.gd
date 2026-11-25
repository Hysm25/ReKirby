class_name Constants
extends RefCounted
## Central hardware, memory, checksum, and gameplay constants for ReKirby.

const NES_CPU_FREQ: float = 1789772.727
const TARGET_TPS: int = 60

# Screen and MMC3 scanline split geometry
const NATIVE_WIDTH: int = 256
const NATIVE_HEIGHT: int = 240
const PLAYFIELD_WIDTH: int = 256
const PLAYFIELD_HEIGHT: int = 192
const HUD_Y: int = 192
const HUD_HEIGHT: int = 48
const SCANLINE_IRQ_Y: int = 192
const TILE_SIZE: int = 8
const METATILE_SIZE: int = 16

# iNES & MMC3 (Mapper 4) bank constants
const INES_HEADER_SIZE: int = 16
const INES_MAGIC_0: int = 0x4E # 'N'
const INES_MAGIC_1: int = 0x45 # 'E'
const INES_MAGIC_2: int = 0x53 # 'S'
const INES_MAGIC_3: int = 0x1A # EOF
const EXPECTED_MAPPER_ID: int = 4

const PRG_BANK_16K_SIZE: int = 16384
const PRG_BANK_8K_SIZE: int = 8192
const CHR_BANK_8K_SIZE: int = 8192
const CHR_BANK_1K_SIZE: int = 1024
const CHR_BYTES_PER_TILE: int = 16
const CHR_TILES_PER_1K_BANK: int = 64
const CHR_1K_BANK_SHEET_WIDTH: int = 64
const CHR_1K_BANK_SHEET_HEIGHT: int = 64

const EXPECTED_PRG_BANKS_16K: int = 32
const EXPECTED_CHR_BANKS_8K: int = 32
const EXPECTED_PRG_BANKS_8K: int = 64
const EXPECTED_CHR_BANKS_1K: int = 256
const EXPECTED_PRG_SIZE: int = 524288
const EXPECTED_CHR_SIZE: int = 262144
const EXPECTED_ROM_TOTAL_SIZE: int = 786448

# Authentic NTSC Kirby's Adventure (USA) (Rev A) checksums
const ROM_FULL_CRC32: int = 0x9EFD5757
const ROM_PRG_CRC32: int = 0x8FFF3F32
const ROM_CHR_CRC32: int = 0x7EDAE6F3
const ROM_FULL_SHA256: String = "34afcebaf04d57a42c2436fb95b933c7841e1621f1dc3be482380baef33ec3d8"
const ROM_PRG_SHA256: String = "da723759b15e5c468aa7817a8d57b5e41a694ae9f504eab381e3fa8758027156"
const ROM_CHR_SHA256: String = "7e6189a311a4dee04b63935ac2218586a6e3a57b506e57b3b03e3545f87b2182"

# Runtime extraction and ROM storage paths
const ROM_DIR: String = "res://rom"
const ROM_FALLBACK_DIR: String = "res://"
const USER_DATA_DIR: String = "user://nes_data"
const CHR_BANKS_DIR: String = "user://nes_data/chr_banks"
const MANIFEST_PATH: String = "user://nes_data/manifest.json"
const PALETTES_PATH: String = "user://nes_data/palettes.json"
const WORLD1_DATA_PATH: String = "user://nes_data/world1_data.json"
const AUDIO_DATA_PATH: String = "user://nes_data/audio_data.json"
const EXTRACTION_FORMAT_VERSION: int = 4

# PRG-ROM MMC3 structural table locations (Kirby's Adventure USA Rev A)
const PRG_BANK_PALETTE_TABLES: int = 0
const PRG_BANK_CHR_TABLES: int = 5
const PRG_BANK_ROOM_TABLES: int = 18
const PRG_BANK_LOADER_TABLES: int = 19
const PRG_BANK_AUDIO_ENGINE: int = 29
const PRG_BANK_HUD_PALETTES: int = 56
const CHR_BANK_KIRBY_DEFAULT: int = 128
const CHR_BANK_STAR_EFFECTS: int = 131
const CHR_BANK_ABILITY_EFFECTS: int = 133
const CHR_BANK_ABILITY_KIRBY: int = 134
const CHR_BANK_HUD_FONT: int = 254
const CHR_BANK_HUD_CARDS_A: int = 221
const CHR_BANK_HUD_CARDS_B: int = 222
const OAM_FLIP_H: int = 0x100
const OAM_FLIP_V: int = 0x200
const WORLD1_HUB_ROOM_ID: int = 0
const WORLD2_HUB_ROOM_ID: int = 1
const TOTAL_ROM_ROOMS: int = 327
const TOTAL_ROM_TILESETS: int = 49
const METATILES_PER_TILESET: int = 256
const TILESET_STREAM_SIZE: int = 1344
const ROOM_HEADER_SIZE: int = 218
const ROOM_SCREEN_COLS: int = 16
const ROOM_SCREEN_ROWS: int = 12
const ROOM_SCREEN_METATILES: int = 192

enum CopyAbility {
	NONE = 0,
	SWORD = 1,
	FIRE = 2,
	SPARK = 3,
	BEAM = 4,
}

enum GameState {
	ROM_SETUP = 0,
	TITLE = 1,
	WORLD_MAP = 2,
	PLAYING = 3,
	PAUSED = 4,
	DOOR_TRANSITION = 5,
	BOSS_FIGHT = 6,
	GAME_OVER = 7,
}

enum NesButton {
	RIGHT = 0x01,
	LEFT = 0x02,
	DOWN = 0x04,
	UP = 0x08,
	START = 0x10,
	SELECT = 0x20,
	B = 0x40,
	A = 0x80,
}

enum TileCollision {
	AIR = 0,
	SOLID = 1,
	ONE_WAY = 2,
	SLOPE_45_UP = 3,
	SLOPE_45_DOWN = 4,
	SLOPE_26_UP_L = 5,
	SLOPE_26_UP_H = 6,
	WATER = 7,
	BREAKABLE_STAR = 8,
	SPIKE_HAZARD = 9,
	DOOR_TRANSITION = 10,
	SLOPE_26_DOWN_L = 11,
	SLOPE_26_DOWN_H = 12,
	BOMB_BLOCK = 13,
}


static func map_nes_collision_to_enum(nes_collision_byte: int, raw_prop: int = -1) -> int:
	# Bank 18 raw_prop 18..21 disambiguates lower vs upper half of 26.5-degree slopes
	if raw_prop == 18:
		return TileCollision.SLOPE_26_UP_L
	if raw_prop == 19:
		return TileCollision.SLOPE_26_UP_H
	if raw_prop == 20:
		return TileCollision.SLOPE_26_DOWN_L
	if raw_prop == 21:
		return TileCollision.SLOPE_26_DOWN_H

	var shape: int = nes_collision_byte & 0x0F
	var is_water: bool = (nes_collision_byte & 0x80) != 0
	var is_breakable: bool = (nes_collision_byte & 0x20) != 0

	if shape == 0:
		return TileCollision.WATER if is_water else TileCollision.AIR
	if shape == 1:
		return TileCollision.ONE_WAY
	if shape == 2:
		return TileCollision.BREAKABLE_STAR if is_breakable else TileCollision.SOLID
	if shape == 3:
		return TileCollision.SLOPE_26_UP_L
	if shape == 4:
		return TileCollision.SLOPE_26_DOWN_L
	if shape == 5:
		return TileCollision.SLOPE_45_UP
	if shape == 6:
		return TileCollision.SLOPE_45_DOWN
	if shape == 9 or shape == 10:
		return TileCollision.SLOPE_26_UP_H
	if shape == 11 or shape == 12:
		return TileCollision.SLOPE_26_DOWN_H
	if shape == 13:
		return TileCollision.SOLID
	if shape == 14:
		return TileCollision.BOMB_BLOCK if is_breakable else TileCollision.SPIKE_HAZARD
	if shape == 15:
		return TileCollision.SPIKE_HAZARD
	return TileCollision.SOLID if is_water == false else TileCollision.WATER

# Authentic 2C02 NTSC 64-color master palette (RGB24 packed integers)
static func get_ntsc_master_palette_rgb() -> PackedInt32Array:
	return PackedInt32Array([
		0x626262, 0x001FB2, 0x2404C8, 0x5200B2, 0x730076, 0x800024, 0x730B00, 0x522800,
		0x244400, 0x005700, 0x005C00, 0x005324, 0x003C76, 0x000000, 0x000000, 0x000000,
		0xABABAB, 0x0D57FF, 0x4B30FF, 0x8A13FF, 0xBC08D6, 0xD21269, 0xC72E00, 0x9D5400,
		0x607B00, 0x209800, 0x00A300, 0x009942, 0x007DB4, 0x000000, 0x000000, 0x000000,
		0xFFFFFF, 0x53AEFF, 0x9085FF, 0xD365FF, 0xFF57FF, 0xFF5DCF, 0xFF7757, 0xFA9E00,
		0xBDC700, 0x7AE700, 0x43F611, 0x26EF7E, 0x2CD5F6, 0x4E4E4E, 0x000000, 0x000000,
		0xFFFFFF, 0xB6E1FF, 0xCED1FF, 0xE9C3FF, 0xFFBCFF, 0xFFBDF4, 0xFFC6C3, 0xFFD59A,
		0xE9E681, 0xCEF481, 0xB6FB9A, 0xA9F7C3, 0xA9EEF4, 0xB8B8B8, 0x000000, 0x000000,
	])


static func get_nes_color(nes_index: int) -> Color:
	var table: PackedInt32Array = get_ntsc_master_palette_rgb()
	var clamped_idx: int = nes_index & 0x3F
	var rgb: int = table[clamped_idx]
	var r: float = float((rgb >> 16) & 0xFF) / 255.0
	var g: float = float((rgb >> 8) & 0xFF) / 255.0
	var b: float = float(rgb & 0xFF) / 255.0
	return Color(r, g, b, 1.0)


static func build_nes_subpalette(indices: PackedInt32Array) -> PackedColorArray:
	var colors: PackedColorArray = PackedColorArray()
	var count: int = mini(indices.size(), 4)
	for i: int in range(count):
		colors.append(get_nes_color(indices[i]))
	while colors.size() < 4:
		colors.append(Color(0.0, 0.0, 0.0, 1.0))
	return colors
