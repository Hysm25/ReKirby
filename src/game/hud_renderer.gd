class_name HUDRenderer
extends Control
## MMC3 Scanline IRQ Split Bottom HUD (256x48 at Y=192..239).
## Assembles nametable rows, 4x5 Copy Ability card, HP pips, lives box, and SCORE/ENEMY strip
## strictly from runtime ROM-extracted Bank 19 nametables, CHR banks, and room BG_3 palettes.

const Constants = preload("res://src/core/constants.gd")

const HUD_WIDTH: int = Constants.NATIVE_WIDTH
const HUD_HEIGHT: int = Constants.HUD_HEIGHT
const HUD_COLS: int = 32
const HUD_VISIBLE_ROWS: int = 7
const HUD_CROP_Y: int = 4

var _hp: int = 6
var _max_hp: int = 6
var _lives: int = 4
var _score: int = 0
var _copy_ability: int = Constants.CopyAbility.NONE
var _boss_id: int = -1
var _boss_hp: int = 0
var _boss_max_hp: int = 0
var _room_id: int = -1
var _is_hub: bool = false
var _anim_tick: int = 0

var _dirty: bool = true
var _hud_image: Image = null
var _hud_texture: ImageTexture = null
var _texture_rect: TextureRect = null


func _ready() -> void:
	name = "HUDRenderer256x48"
	position = Vector2(0.0, float(Constants.HUD_Y))
	size = Vector2(float(HUD_WIDTH), float(HUD_HEIGHT))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_texture_rect()
	connect_event_bus()
	refresh()


func _ensure_texture_rect() -> void:
	if _texture_rect != null:
		return
	_texture_rect = TextureRect.new()
	_texture_rect.name = "HUDSurface"
	_texture_rect.position = Vector2.ZERO
	_texture_rect.size = Vector2(float(HUD_WIDTH), float(HUD_HEIGHT))
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP
	_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_texture_rect)


func connect_event_bus() -> void:
	if not EventBus.hp_changed.is_connected(_on_hp_changed):
		EventBus.hp_changed.connect(_on_hp_changed)
	if not EventBus.lives_changed.is_connected(_on_lives_changed):
		EventBus.lives_changed.connect(_on_lives_changed)
	if not EventBus.score_changed.is_connected(_on_score_changed):
		EventBus.score_changed.connect(_on_score_changed)
	if not EventBus.copy_ability_changed.is_connected(_on_copy_ability_changed):
		EventBus.copy_ability_changed.connect(_on_copy_ability_changed)
	if not EventBus.boss_hp_changed.is_connected(_on_boss_hp_changed):
		EventBus.boss_hp_changed.connect(_on_boss_hp_changed)
	if not EventBus.room_changed.is_connected(_on_room_changed):
		EventBus.room_changed.connect(_on_room_changed)


func set_hud_mode(is_hub: bool) -> void:
	if _is_hub == is_hub:
		return
	_is_hub = is_hub
	_dirty = true
	refresh()


func set_status(hp: int, max_hp: int, lives: int, score: int, ability: int) -> void:
	_hp = maxi(0, hp)
	_max_hp = maxi(1, max_hp)
	_lives = maxi(0, lives)
	_score = maxi(0, score)
	_copy_ability = ability
	_dirty = true
	refresh()


func set_boss_hp(boss_id: int, boss_hp: int, boss_max_hp: int) -> void:
	_boss_id = boss_id
	_boss_hp = maxi(0, boss_hp)
	_boss_max_hp = maxi(0, boss_max_hp)
	_dirty = true
	refresh()


func get_displayed_hp() -> int:
	return _hp


func get_displayed_max_hp() -> int:
	return _max_hp


func get_displayed_lives() -> int:
	return _lives


func get_displayed_score() -> int:
	return _score


func get_displayed_ability() -> int:
	return _copy_ability


func get_displayed_boss_hp() -> int:
	return _boss_hp


func get_hud_texture() -> ImageTexture:
	return _hud_texture


func get_hud_image() -> Image:
	return _hud_image


func is_dirty() -> bool:
	return _dirty


func step_frame() -> void:
	_anim_tick += 1
	if (_anim_tick & 7) == 0:
		_dirty = true
		refresh()


func refresh() -> void:
	if not _dirty:
		return
	if not ContentRegistry.is_ready():
		return
	_rebuild_hud_texture()
	_dirty = false


func _on_hp_changed(current_hp: int, max_hp: int) -> void:
	_hp = maxi(0, current_hp)
	_max_hp = maxi(1, max_hp)
	_dirty = true
	refresh()


func _on_lives_changed(lives: int) -> void:
	_lives = maxi(0, lives)
	_dirty = true
	refresh()


func _on_score_changed(score: int, _delta_points: int) -> void:
	_score = maxi(0, score)
	_dirty = true
	refresh()


func _on_copy_ability_changed(ability: int) -> void:
	_copy_ability = ability
	_dirty = true
	refresh()


func _on_boss_hp_changed(boss_id: int, current_hp: int, max_hp: int) -> void:
	_boss_id = boss_id
	_boss_hp = maxi(0, current_hp)
	_boss_max_hp = maxi(0, max_hp)
	_dirty = true
	refresh()


func _on_room_changed(_world_id: int, _stage_id: int, room_id: int) -> void:
	_room_id = room_id
	_is_hub = (room_id >= 0 and room_id < 7)
	_dirty = true
	refresh()


func _resolve_hud_palette() -> PackedColorArray:
	if _room_id >= 0:
		var room_pal: PackedColorArray = ContentRegistry.get_palette_colors("room_%d_bg_3" % _room_id)
		if room_pal.size() >= 4:
			return room_pal
	var stage1_pal: PackedColorArray = ContentRegistry.get_palette_colors("room_43_bg_3")
	if stage1_pal.size() >= 4:
		return stage1_pal
	return ContentRegistry.get_palette_colors("hud_bg_0")


func _rebuild_hud_texture() -> void:
	var hud_layout: Dictionary = ContentRegistry.get_hud_layout()
	var hud_pal: PackedColorArray = _resolve_hud_palette()
	if hud_layout.is_empty() or hud_pal.size() < 4:
		return

	var base_key: String = "hub_nametable" if _is_hub else "stage_nametable"
	var base_arr: Array = hud_layout.get(base_key, []) as Array
	if base_arr.size() < HUD_COLS * HUD_VISIBLE_ROWS:
		return

	var tile_grid: PackedInt32Array = PackedInt32Array()
	tile_grid.resize(HUD_COLS * HUD_VISIBLE_ROWS)
	for idx: int in range(tile_grid.size()):
		tile_grid[idx] = int(base_arr[idx]) & 0xFF

	var anim_banks: Array = hud_layout.get("chr_r2_anim_banks", [Constants.CHR_BANK_HUD_ANIM_BASE]) as Array
	var r2_bank: int = int(anim_banks[(_anim_tick >> 3) % anim_banks.size()]) if not anim_banks.is_empty() else Constants.CHR_BANK_HUD_ANIM_BASE
	var r3_bank: int = Constants.CHR_BANK_HUD_CARDS_A
	var r4_bank: int = int(hud_layout.get("chr_r4_frame", Constants.CHR_BANK_HUD_BG_FRAME))
	var r5_bank: int = int(hud_layout.get("chr_r5_text", Constants.CHR_BANK_HUD_BG_TEXT))

	if _is_hub:
		# Hub HUD (B19 $AED5 / $B46E): writes 2 lives digits at row 5, cols 26..27
		var hub_lives: String = "%02d" % mini(_lives, 99)
		_set_tile(tile_grid, 26, 5, 0xC0 + map_char_to_font_tile(hub_lives.substr(0, 1)))
		_set_tile(tile_grid, 27, 5, 0xC0 + map_char_to_font_tile(hub_lives.substr(1, 1)))
	else:
		# Stage HUD: overlay $B3E1 8x7 lives packet at (23, 0)
		var lives_tiles: Array = hud_layout.get("lives_stage_tiles", []) as Array
		var box_col: int = int(hud_layout.get("lives_box_col", 23))
		var box_row: int = int(hud_layout.get("lives_box_row", 0))
		var box_cols: int = int(hud_layout.get("lives_box_cols", 8))
		var box_rows: int = int(hud_layout.get("lives_box_rows", 7))
		if lives_tiles.size() >= box_cols * box_rows:
			for ly: int in range(box_rows):
				for lx: int in range(box_cols):
					_set_tile(tile_grid, box_col + lx, box_row + ly, int(lives_tiles[ly * box_cols + lx]) & 0xFF)

		var lives_str: String = "%02d" % mini(_lives, 99)
		_set_tile(tile_grid, 27, 4, 0xC0 + map_char_to_font_tile(lives_str.substr(0, 1)))
		_set_tile(tile_grid, 28, 4, 0xC0 + map_char_to_font_tile(lives_str.substr(1, 1)))

		# Copy Ability Card (4x5 column-major tiles at col 19, row 1; B19 $B313/$B338)
		var ab_map: Dictionary = hud_layout.get("ability_card_map", {}) as Dictionary
		var cards_arr: Array = hud_layout.get("cards", []) as Array
		var rom_card_idx: int = int(ab_map.get(str(_copy_ability), 0))
		if rom_card_idx >= 0 and rom_card_idx < cards_arr.size():
			var card_spec: Dictionary = cards_arr[rom_card_idx] as Dictionary
			r3_bank = int(card_spec.get("r3_bank", r3_bank))
			var base_tile: int = (int(card_spec.get("base_tile", 0)) & 0x0F) | 0x40
			var card_col: int = int(hud_layout.get("card_col", 19))
			var card_row: int = int(hud_layout.get("card_row", 1))
			var card_cols: int = int(hud_layout.get("card_cols", 4))
			var card_rows: int = int(hud_layout.get("card_rows", 5))
			for cx: int in range(card_cols):
				for cy: int in range(card_rows):
					_set_tile(tile_grid, card_col + cx, card_row + cy, base_tile + cx * 0x10 + cy)

		# HP Pips (6 pips x 3 rows at col 10..15, rows 1..3; B19 $B227)
		var hp_col: int = int(hud_layout.get("hp_pip_col", 10))
		var hp_row: int = int(hud_layout.get("hp_pip_row", 1))
		var hp_slots: int = int(hud_layout.get("hp_pip_max", 6))
		var full_arr: Array = hud_layout.get("hp_pip_full", [0x1A, 0x1B, 0x1C]) as Array
		var empty_arr: Array = hud_layout.get("hp_pip_empty", [0x81, 0x98, 0x81]) as Array
		var filled_pips: int = clampi(int(roundf((float(_hp) / float(maxi(1, _max_hp))) * float(hp_slots))), 0, hp_slots)
		for p_i: int in range(hp_slots):
			var src_col_tiles: Array = full_arr if p_i < filled_pips else empty_arr
			for r_i: int in range(3):
				_set_tile(tile_grid, hp_col + p_i, hp_row + r_i, int(src_col_tiles[r_i]) & 0xFF)

		# Row 4: SCORE + 7 digits OR ENEMY + Boss HP gauge (cols 3..16; B19 $B12C / $B1F6)
		var s_row: int = int(hud_layout.get("score_row", 4))
		var l_col: int = int(hud_layout.get("score_label_col", 3))
		var d_col: int = int(hud_layout.get("score_digits_col", 10))
		if _boss_max_hp > 0:
			var enemy_tiles: Array = hud_layout.get("enemy_label_tiles", []) as Array
			for e_i: int in range(mini(6, enemy_tiles.size())):
				_set_tile(tile_grid, l_col + e_i, s_row, int(enemy_tiles[e_i]) & 0xFF)
			_set_tile(tile_grid, d_col - 1, s_row, 0x81)
			var boss_units: int = clampi(int(roundf((float(_boss_hp) / float(_boss_max_hp)) * 28.0)), 0, 28)
			for b_i: int in range(7):
				var seg: int = clampi(boss_units - b_i * 4, 0, 4)
				var b_tile: int = 0x81
				if seg > 0:
					b_tile = 0x93 + seg
				elif b_i == 0:
					b_tile = 0x92
				_set_tile(tile_grid, d_col + b_i, s_row, b_tile)
		else:
			var score_tiles: Array = hud_layout.get("score_label_tiles", []) as Array
			for s_i: int in range(mini(6, score_tiles.size())):
				_set_tile(tile_grid, l_col + s_i, s_row, int(score_tiles[s_i]) & 0xFF)
			_set_tile(tile_grid, d_col - 1, s_row, 0x81)
			var score_str: String = "%07d" % mini(_score, 9999999)
			for d_i: int in range(7):
				var digit_local: int = map_char_to_font_tile(score_str.substr(d_i, 1))
				_set_tile(tile_grid, d_col + d_i, s_row, 0xC0 + digit_local)

	var chr_slots: PackedInt32Array = PackedInt32Array([r2_bank, r3_bank, r4_bank, r5_bank])
	var bank_data: Array[PackedByteArray] = []
	bank_data.resize(4)
	for slot_idx: int in range(4):
		var b_img: Image = ContentRegistry.get_chr_bank_image(chr_slots[slot_idx])
		if b_img == null or b_img.is_empty():
			return
		bank_data[slot_idx] = b_img.get_data()

	var full_h: int = HUD_VISIBLE_ROWS * Constants.TILE_SIZE
	var full_rgba: PackedByteArray = PackedByteArray()
	full_rgba.resize(HUD_WIDTH * full_h * 4)

	for ty: int in range(HUD_VISIBLE_ROWS):
		for tx: int in range(HUD_COLS):
			var tile_id: int = tile_grid[ty * HUD_COLS + tx]
			var slot: int = (tile_id >> 6) & 0x03
			var local_tile: int = tile_id & 0x3F
			var src_rgba: PackedByteArray = bank_data[slot]
			var tx0: int = (local_tile % 8) * Constants.TILE_SIZE
			var ty0: int = (local_tile / 8) * Constants.TILE_SIZE
			var dst_x0: int = tx * Constants.TILE_SIZE
			var dst_y0: int = ty * Constants.TILE_SIZE
			for py: int in range(Constants.TILE_SIZE):
				var src_row: int = ((ty0 + py) * Constants.CHR_1K_BANK_SHEET_WIDTH + tx0) * 4
				var dst_row: int = ((dst_y0 + py) * HUD_WIDTH + dst_x0) * 4
				for px: int in range(Constants.TILE_SIZE):
					var gray: int = src_rgba[src_row + px * 4]
					var c_idx: int = clampi((gray + 42) / 85, 0, 3)
					var col: Color = hud_pal[c_idx]
					var dst_off: int = dst_row + px * 4
					full_rgba[dst_off] = clampi(int(round(col.r * 255.0)), 0, 255)
					full_rgba[dst_off + 1] = clampi(int(round(col.g * 255.0)), 0, 255)
					full_rgba[dst_off + 2] = clampi(int(round(col.b * 255.0)), 0, 255)
					full_rgba[dst_off + 3] = 255

	var start_byte: int = HUD_CROP_Y * HUD_WIDTH * 4
	var end_byte: int = (HUD_CROP_Y + HUD_HEIGHT) * HUD_WIDTH * 4
	var out_rgba: PackedByteArray = full_rgba.slice(start_byte, end_byte)

	_hud_image = Image.create_from_data(HUD_WIDTH, HUD_HEIGHT, false, Image.FORMAT_RGBA8, out_rgba)
	_hud_texture = ImageTexture.create_from_image(_hud_image)
	_ensure_texture_rect()
	_texture_rect.texture = _hud_texture


static func _set_tile(grid: PackedInt32Array, col: int, row: int, tile_id: int) -> void:
	if col < 0 or col >= HUD_COLS or row < 0 or row >= HUD_VISIBLE_ROWS:
		return
	grid[row * HUD_COLS + col] = tile_id & 0xFF


static func map_char_to_font_tile(ch: String) -> int:
	if ch.is_empty():
		return -1
	var code: int = ch.unicode_at(0)
	if code >= 48 and code <= 57:
		return 0x1C + (code - 48) # '0'..'9' -> 0x1C..0x25 in CHR 63 / 254
	if code >= 65 and code <= 90:
		return 0x26 + (code - 65) # 'A'..'Z' -> 0x26..0x3F in CHR 63 / 254
	if ch == "-":
		return 0x18
	if ch == "x":
		return 0x19
	return -1


static func _ascii_to_rom_font_tile(ch: String) -> int:
	return map_char_to_font_tile(ch)
