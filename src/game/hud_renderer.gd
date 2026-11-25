class_name HUDRenderer
extends Control
## MMC3 Scanline IRQ Split Bottom HUD (256x48 at Y=192..239).
## Renders HP pips, lives, score, boss HP, and Copy Ability portrait card
## strictly from ROM CHR banks and Bank 56 HUD palettes in ContentRegistry.

const Constants = preload("res://src/core/constants.gd")

const HUD_WIDTH: int = Constants.NATIVE_WIDTH
const HUD_HEIGHT: int = Constants.HUD_HEIGHT

var _hp: int = 6
var _max_hp: int = 6
var _lives: int = 4
var _score: int = 0
var _copy_ability: int = Constants.CopyAbility.NONE
var _boss_id: int = -1
var _boss_hp: int = 0
var _boss_max_hp: int = 0

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


func is_dirty() -> bool:
	return _dirty


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


func _rebuild_hud_texture() -> void:
	var font_img: Image = ContentRegistry.get_chr_bank_image(Constants.CHR_BANK_HUD_FONT)
	var card_img: Image = ContentRegistry.get_chr_bank_image(Constants.CHR_BANK_HUD_CARDS_A)
	var pal_bg0: PackedColorArray = ContentRegistry.get_palette_colors("hud_bg_0")
	var pal_bg1: PackedColorArray = ContentRegistry.get_palette_colors("hud_bg_1")
	var pal_bg2: PackedColorArray = ContentRegistry.get_palette_colors("hud_bg_2")
	var pal_kirby: PackedColorArray = ContentRegistry.get_palette_colors("kirby_default")
	if font_img == null or card_img == null or pal_bg0.size() < 4 or pal_bg1.size() < 4 or pal_bg2.size() < 4 or pal_kirby.size() < 4:
		return

	var out_rgba: PackedByteArray = PackedByteArray()
	out_rgba.resize(HUD_WIDTH * HUD_HEIGHT * 4)

	# Fill base HUD panel backdrop using ROM HUD palette universal color & panel pink
	_fill_rect(out_rgba, 0, 0, HUD_WIDTH, HUD_HEIGHT, pal_bg0[0])
	_fill_rect(out_rgba, 4, 3, HUD_WIDTH - 8, HUD_HEIGHT - 6, pal_bg0[1])
	_fill_rect(out_rgba, 6, 5, 174, HUD_HEIGHT - 10, pal_bg0[0])

	var font_rgba: PackedByteArray = font_img.get_data()
	var card_rgba: PackedByteArray = card_img.get_data()

	# Row 1 (Y=7): SCORE label + 7 digits using ROM font CHR bank 254 (0xFE)
	var score_str: String = "SCORE %07d" % mini(_score, 9999999)
	_draw_rom_text(out_rgba, font_rgba, score_str, 12, 7, pal_bg1, pal_bg0[0])

	# Row 2 (Y=20): Kirby mini icon + Lives + HP Pips
	var kirby_bank: Image = ContentRegistry.get_chr_bank_image(Constants.CHR_BANK_KIRBY_DEFAULT)
	if kirby_bank != null:
		var kirby_rgba: PackedByteArray = kirby_bank.get_data()
		var k_tiles: PackedInt32Array = PackedInt32Array([8, 12, 9, 13])
		_blit_tile_grid(out_rgba, kirby_rgba, k_tiles, 2, 2, 12, 20, pal_kirby, true)

	var lives_str: String = "%02d" % mini(_lives, 99)
	_draw_rom_text(out_rgba, font_rgba, lives_str, 30, 24, pal_bg1, pal_bg0[0])

	# HP Pips using Bank 221 tile 0x09 (pip glyph)
	_draw_rom_text(out_rgba, font_rgba, "HP", 56, 24, pal_bg1, pal_bg0[0])
	var pip_count: int = clampi(_max_hp, 1, 8)
	for i: int in range(pip_count):
		var px: int = 76 + i * 10
		var pip_pal: PackedColorArray = pal_bg2 if i < _hp else pal_bg0
		_blit_single_tile(out_rgba, card_rgba, 0x09, px, 24, pip_pal, false, i < _hp, pal_bg0[1], pal_bg0[0])

	# Optional Boss HP bar when boss fight is active
	if _boss_max_hp > 0:
		var boss_pips: int = clampi(_boss_hp, 0, 12)
		_draw_rom_text(out_rgba, font_rgba, "BOSS", 56, 35, pal_bg1, pal_bg0[0])
		for b_i: int in range(12):
			var bpx: int = 92 + b_i * 7
			var filled_b: bool = b_i < boss_pips
			_blit_single_tile(out_rgba, card_rgba, 0x09, bpx, 35, pal_bg1 if filled_b else pal_bg0, false, filled_b, pal_bg0[2], pal_bg0[0])

	# Right Card Frame (X=184..248, Y=5..43): Copy Ability portrait + label
	_fill_rect(out_rgba, 184, 5, 64, 38, pal_bg2[0])
	_fill_rect(out_rgba, 186, 7, 60, 34, pal_bg2[2])
	_draw_ability_card_portrait(out_rgba, 208, 10)
	var ab_label: String = _ability_label(_copy_ability)
	var label_x: int = 186 + (60 - ab_label.length() * Constants.TILE_SIZE) / 2
	_draw_rom_text(out_rgba, font_rgba, ab_label, label_x, 30, pal_bg1, pal_bg0[0])

	_hud_image = Image.create_from_data(HUD_WIDTH, HUD_HEIGHT, false, Image.FORMAT_RGBA8, out_rgba)
	if _hud_texture == null:
		_hud_texture = ImageTexture.create_from_image(_hud_image)
	else:
		_hud_texture.update(_hud_image)
	_ensure_texture_rect()
	_texture_rect.texture = _hud_texture


func _draw_ability_card_portrait(out_rgba: PackedByteArray, dst_x: int, dst_y: int) -> void:
	var bank_id: int = Constants.CHR_BANK_KIRBY_DEFAULT
	var tiles: PackedInt32Array = PackedInt32Array([8, 12, 9, 13])
	var w_t: int = 2
	var h_t: int = 2
	var pal_key: String = "kirby_default"

	match _copy_ability:
		Constants.CopyAbility.SWORD:
			bank_id = Constants.CHR_BANK_ABILITY_EFFECTS
			tiles = PackedInt32Array([2, 3])
			w_t = 1
			h_t = 2
			pal_key = "hud_sp_star"
		Constants.CopyAbility.FIRE:
			bank_id = Constants.CHR_BANK_ABILITY_EFFECTS
			tiles = PackedInt32Array([4, 6, 5, 7])
			w_t = 2
			h_t = 2
			pal_key = "hud_sp_fire"
		Constants.CopyAbility.SPARK:
			bank_id = Constants.CHR_BANK_STAR_EFFECTS
			tiles = PackedInt32Array([4, 5])
			w_t = 1
			h_t = 2
			pal_key = "hud_sp_star"
		Constants.CopyAbility.BEAM:
			bank_id = Constants.CHR_BANK_ABILITY_EFFECTS
			tiles = PackedInt32Array([12, 14, 13, 15])
			w_t = 2
			h_t = 2
			pal_key = "hud_sp_beam"
		_:
			pass

	var img: Image = ContentRegistry.get_chr_bank_image(bank_id)
	var pal: PackedColorArray = ContentRegistry.get_palette_colors(pal_key)
	if img == null or pal.size() < 4:
		return
	var offset_x: int = dst_x + (16 - w_t * Constants.TILE_SIZE) / 2
	_blit_tile_grid(out_rgba, img.get_data(), tiles, w_t, h_t, offset_x, dst_y, pal, true)


static func _ability_label(ability: int) -> String:
	match ability:
		Constants.CopyAbility.SWORD:
			return "SWORD"
		Constants.CopyAbility.FIRE:
			return "FIRE"
		Constants.CopyAbility.SPARK:
			return "SPARK"
		Constants.CopyAbility.BEAM:
			return "BEAM"
		_:
			return "NORMAL"


static func map_char_to_font_tile(ch: String) -> int:
	if ch.is_empty():
		return -1
	var code: int = ch.unicode_at(0)
	if code >= 48 and code <= 57:
		return 0x1C + (code - 48) # '0'..'9' -> 0x1C..0x25 in CHR Bank 254 (0xFE)
	if code >= 65 and code <= 90:
		return 0x26 + (code - 65) # 'A'..'Z' -> 0x26..0x3F in CHR Bank 254 (0xFE)
	return -1


static func _ascii_to_rom_font_tile(ch: String) -> int:
	return map_char_to_font_tile(ch)


func _draw_rom_text(
	out_rgba: PackedByteArray,
	font_rgba: PackedByteArray,
	text: String,
	dst_x: int,
	dst_y: int,
	palette: PackedColorArray,
	bg_override: Color
) -> void:
	for idx: int in range(text.length()):
		var tile_id: int = _ascii_to_rom_font_tile(text.substr(idx, 1))
		if tile_id < 0:
			continue
		var tx0: int = (tile_id % 8) * Constants.TILE_SIZE
		var ty0: int = (tile_id / 8) * Constants.TILE_SIZE
		for py: int in range(Constants.TILE_SIZE):
			var sy: int = ty0 + py
			var dy: int = dst_y + py
			if dy < 0 or dy >= HUD_HEIGHT:
				continue
			var src_row: int = (sy * Constants.CHR_1K_BANK_SHEET_WIDTH + tx0) * 4
			var dst_row: int = (dy * HUD_WIDTH) * 4
			for px: int in range(Constants.TILE_SIZE):
				var dx: int = dst_x + idx * Constants.TILE_SIZE + px
				if dx < 0 or dx >= HUD_WIDTH:
					continue
				var gray: int = font_rgba[src_row + px * 4]
				var c_idx: int = clampi((gray + 42) / 85, 0, 3)
				# Color 0 and 1 in Bank 254 (0xFE) are transparent glyph cell background; 3=primary stroke, 2=drop shadow
				if c_idx <= 1:
					continue
				var col: Color = palette[1] if c_idx == 3 else bg_override
				var dst_off: int = dst_row + dx * 4
				out_rgba[dst_off] = clampi(int(round(col.r * 255.0)), 0, 255)
				out_rgba[dst_off + 1] = clampi(int(round(col.g * 255.0)), 0, 255)
				out_rgba[dst_off + 2] = clampi(int(round(col.b * 255.0)), 0, 255)
				out_rgba[dst_off + 3] = 255


func _blit_tile_grid(
	out_rgba: PackedByteArray,
	bank_rgba: PackedByteArray,
	tiles: PackedInt32Array,
	cols: int,
	rows: int,
	dst_x: int,
	dst_y: int,
	palette: PackedColorArray,
	transparent_zero: bool
) -> void:
	for ty: int in range(rows):
		for tx: int in range(cols):
			var idx: int = ty * cols + tx
			if idx >= tiles.size():
				continue
			_blit_single_tile(
				out_rgba,
				bank_rgba,
				tiles[idx],
				dst_x + tx * Constants.TILE_SIZE,
				dst_y + ty * Constants.TILE_SIZE,
				palette,
				transparent_zero,
				false,
				Color.BLACK,
				Color.BLACK
			)


func _blit_single_tile(
	out_rgba: PackedByteArray,
	bank_rgba: PackedByteArray,
	tile_id: int,
	dst_x: int,
	dst_y: int,
	palette: PackedColorArray,
	transparent_zero: bool,
	fill_interior: bool,
	interior_col: Color,
	outline_col: Color
) -> void:
	var local_tile: int = tile_id & 0x3F
	var tx0: int = (local_tile % 8) * Constants.TILE_SIZE
	var ty0: int = (local_tile / 8) * Constants.TILE_SIZE
	for py: int in range(Constants.TILE_SIZE):
		var dy: int = dst_y + py
		if dy < 0 or dy >= HUD_HEIGHT:
			continue
		var src_row: int = ((ty0 + py) * Constants.CHR_1K_BANK_SHEET_WIDTH + tx0) * 4
		var dst_row: int = dy * HUD_WIDTH * 4
		for px: int in range(Constants.TILE_SIZE):
			var dx: int = dst_x + px
			if dx < 0 or dx >= HUD_WIDTH:
				continue
			var gray: int = bank_rgba[src_row + px * 4]
			var c_idx: int = clampi((gray + 42) / 85, 0, 3)
			if transparent_zero and c_idx == 0:
				continue
			var col: Color = palette[c_idx]
			if fill_interior and py >= 2 and py <= 5 and px >= 2 and px <= 5:
				col = interior_col
			elif not fill_interior and c_idx == 0 and outline_col != Color.BLACK:
				col = outline_col
			var dst_off: int = dst_row + dx * 4
			out_rgba[dst_off] = clampi(int(round(col.r * 255.0)), 0, 255)
			out_rgba[dst_off + 1] = clampi(int(round(col.g * 255.0)), 0, 255)
			out_rgba[dst_off + 2] = clampi(int(round(col.b * 255.0)), 0, 255)
			out_rgba[dst_off + 3] = 255


static func _fill_rect(out_rgba: PackedByteArray, x0: int, y0: int, w: int, h: int, col: Color) -> void:
	var r8: int = clampi(int(round(col.r * 255.0)), 0, 255)
	var g8: int = clampi(int(round(col.g * 255.0)), 0, 255)
	var b8: int = clampi(int(round(col.b * 255.0)), 0, 255)
	var x_end: int = mini(HUD_WIDTH, x0 + w)
	var y_end: int = mini(HUD_HEIGHT, y0 + h)
	for py: int in range(maxi(0, y0), y_end):
		var row_off: int = py * HUD_WIDTH * 4
		for px: int in range(maxi(0, x0), x_end):
			var off: int = row_off + px * 4
			out_rgba[off] = r8
			out_rgba[off + 1] = g8
			out_rgba[off + 2] = b8
			out_rgba[off + 3] = 255
