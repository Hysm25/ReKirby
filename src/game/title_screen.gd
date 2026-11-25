class_name TitleScreen
extends Control
## Clean-room 256x240 Title Screen rendered dynamically from extracted ROM CHR banks and palettes.

const Constants = preload("res://src/core/constants.gd")
const HUDRenderer = preload("res://src/game/hud_renderer.gd")

signal start_requested

var _backdrop_rect: TextureRect = null
var _surface_texture: ImageTexture = null
var _kirby_rect: TextureRect = null
var _kirby_tex_open: ImageTexture = null
var _kirby_tex_blink: ImageTexture = null
var _star_rect: TextureRect = null
var _press_start_rect: TextureRect = null
var _frame_counter: int = 0
var _ready_visual: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(float(Constants.NATIVE_WIDTH), float(Constants.NATIVE_HEIGHT))
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _backdrop_rect != null:
		return

	_backdrop_rect = TextureRect.new()
	_backdrop_rect.name = "TitleBackdrop"
	_backdrop_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_backdrop_rect.stretch_mode = TextureRect.STRETCH_KEEP
	_backdrop_rect.position = Vector2.ZERO
	_backdrop_rect.size = Vector2(float(Constants.NATIVE_WIDTH), float(Constants.NATIVE_HEIGHT))
	_backdrop_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop_rect)

	_kirby_rect = TextureRect.new()
	_kirby_rect.name = "TitleKirby"
	_kirby_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_kirby_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_kirby_rect.position = Vector2(112.0, 124.0)
	_kirby_rect.size = Vector2(32.0, 32.0)
	_kirby_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_kirby_rect)

	_star_rect = TextureRect.new()
	_star_rect.name = "TitleStar"
	_star_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_star_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_star_rect.position = Vector2(148.0, 128.0)
	_star_rect.size = Vector2(16.0, 16.0)
	_star_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_star_rect)

	_press_start_rect = TextureRect.new()
	_press_start_rect.name = "PressStartBanner"
	_press_start_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_press_start_rect.stretch_mode = TextureRect.STRETCH_KEEP
	_press_start_rect.position = Vector2(84.0, 184.0)
	_press_start_rect.size = Vector2(88.0, 8.0)
	_press_start_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_press_start_rect)


func setup_from_rom() -> void:
	_ensure_nodes()
	_frame_counter = 0
	_ready_visual = false
	if not ContentRegistry.is_ready():
		return

	var font_bank: Image = ContentRegistry.get_chr_bank_image(Constants.CHR_BANK_HUD_FONT)
	if font_bank == null:
		return

	var bg1: PackedColorArray = ContentRegistry.get_palette_colors("hud_bg_1")
	var title_bg0: PackedColorArray = ContentRegistry.get_palette_colors("title_bg_0")
	var prompt_pal: PackedColorArray = title_bg0 if title_bg0.size() >= 4 else bg1

	var img: Image = Image.create(Constants.NATIVE_WIDTH, Constants.NATIVE_HEIGHT, false, Image.FORMAT_RGBA8)
	var title_layout: Dictionary = ContentRegistry.get_title_screen_layout()
	var rendered_nametable: bool = _render_title_nametable(img, title_layout)
	if not rendered_nametable:
		img.fill(Color(0.0, 0.0, 0.0, 1.0))

	_surface_texture = ImageTexture.create_from_image(img)
	_backdrop_rect.texture = _surface_texture

	var room_pals: Array[PackedColorArray] = ContentRegistry.get_room_sprite_palettes(-1)
	var k_open_spec: Dictionary = ContentRegistry.get_kirby_metasprite_frame("default", 0)
	var k_blink_spec: Dictionary = ContentRegistry.get_kirby_metasprite_frame("default", 2)
	var star_spec: Dictionary = ContentRegistry.get_effect_metasprite_frame("star", 0)
	var k_open_built: Dictionary = ContentRegistry.build_rom_metasprite(k_open_spec, room_pals)
	var k_blink_built: Dictionary = ContentRegistry.build_rom_metasprite(k_blink_spec, room_pals)
	var star_built: Dictionary = ContentRegistry.build_rom_metasprite(star_spec, room_pals)

	_kirby_tex_open = (k_open_built["texture"] as ImageTexture) if not k_open_built.is_empty() else ContentRegistry.build_rom_oam_8x16(
		Constants.CHR_BANK_KIRBY_DEFAULT,
		Vector2i(2, 3),
		Vector2i(18, 19),
		"kirby_default",
		false,
		false,
		false,
		1
	)
	_kirby_tex_blink = (k_blink_built["texture"] as ImageTexture) if not k_blink_built.is_empty() else ContentRegistry.build_rom_oam_8x16(
		Constants.CHR_BANK_KIRBY_DEFAULT,
		Vector2i(2, 3),
		Vector2i(28, 29),
		"kirby_default",
		false,
		false,
		false,
		1
	)
	_kirby_rect.position = Vector2(108.0, 96.0)
	_kirby_rect.texture = _kirby_tex_open
	_star_rect.position = Vector2(142.0, 102.0)
	_star_rect.texture = (star_built["texture"] as ImageTexture) if not star_built.is_empty() else ContentRegistry.build_rom_oam_8x16(
		Constants.CHR_BANK_STAR_EFFECTS,
		Vector2i(18, 19),
		Vector2i(22, 23),
		"hud_sp_star",
		false,
		false,
		false,
		1
	)

	var press_img: Image = Image.create(88, 8, false, Image.FORMAT_RGBA8)
	press_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	_draw_rom_text_scaled(press_img, font_bank, "PRESS START", 0, 0, prompt_pal, 1)
	_press_start_rect.position = Vector2(84.0, 166.0)
	_press_start_rect.texture = ImageTexture.create_from_image(press_img)
	_press_start_rect.visible = true

	_ready_visual = _surface_texture != null and _kirby_tex_open != null and _press_start_rect.texture != null


static func _render_title_nametable(dest: Image, layout: Dictionary) -> bool:
	if layout.is_empty():
		return false
	var chr_banks: Array = layout.get("chr_banks", []) as Array
	var nt: Array = layout.get("nametable", []) as Array
	var attrs: Array = layout.get("attributes", []) as Array
	if chr_banks.size() < 4 or nt.size() < 960 or attrs.size() < 64:
		return false

	var bank_data: Array[PackedByteArray] = []
	bank_data.resize(4)
	for s_i: int in range(4):
		var b_img: Image = ContentRegistry.get_chr_bank_image(int(chr_banks[s_i]))
		if b_img == null or b_img.is_empty():
			return false
		bank_data[s_i] = b_img.get_data()

	var pals: Array[PackedColorArray] = []
	pals.resize(4)
	for p_i: int in range(4):
		var p_cols: PackedColorArray = ContentRegistry.get_palette_colors("title_bg_%d" % p_i)
		if p_cols.size() < 4:
			return false
		pals[p_i] = p_cols

	var out_rgba: PackedByteArray = PackedByteArray()
	out_rgba.resize(Constants.NATIVE_WIDTH * Constants.NATIVE_HEIGHT * 4)

	for ty: int in range(30):
		for tx: int in range(32):
			var tile_id: int = int(nt[ty * 32 + tx]) & 0xFF
			var slot: int = (tile_id >> 6) & 0x03
			var local_tile: int = tile_id & 0x3F
			var attr_byte: int = int(attrs[(ty / 4) * 8 + (tx / 4)]) & 0xFF
			var attr_shift: int = ((ty & 2) * 2) + (tx & 2)
			var pal: PackedColorArray = pals[(attr_byte >> attr_shift) & 0x03]
			var src_rgba: PackedByteArray = bank_data[slot]
			var tx0: int = (local_tile % 8) * Constants.TILE_SIZE
			var ty0: int = (local_tile / 8) * Constants.TILE_SIZE
			var dst_x0: int = tx * Constants.TILE_SIZE
			var dst_y0: int = ty * Constants.TILE_SIZE
			for py: int in range(Constants.TILE_SIZE):
				var src_row: int = ((ty0 + py) * Constants.CHR_1K_BANK_SHEET_WIDTH + tx0) * 4
				var dst_row: int = ((dst_y0 + py) * Constants.NATIVE_WIDTH + dst_x0) * 4
				for px: int in range(Constants.TILE_SIZE):
					var gray: int = src_rgba[src_row + px * 4]
					var c_idx: int = clampi((gray + 42) / 85, 0, 3)
					var col: Color = pal[c_idx]
					var dst_off: int = dst_row + px * 4
					out_rgba[dst_off] = clampi(int(round(col.r * 255.0)), 0, 255)
					out_rgba[dst_off + 1] = clampi(int(round(col.g * 255.0)), 0, 255)
					out_rgba[dst_off + 2] = clampi(int(round(col.b * 255.0)), 0, 255)
					out_rgba[dst_off + 3] = 255

	dest.set_data(Constants.NATIVE_WIDTH, Constants.NATIVE_HEIGHT, false, Image.FORMAT_RGBA8, out_rgba)
	return true


func step_frame() -> void:
	_frame_counter += 1
	if _press_start_rect != null:
		_press_start_rect.visible = ((_frame_counter / 30) % 2) == 0
	if _kirby_rect != null:
		var blink_phase: int = _frame_counter % 150
		if blink_phase >= 142 and _kirby_tex_blink != null:
			_kirby_rect.texture = _kirby_tex_blink
		elif _kirby_tex_open != null:
			_kirby_rect.texture = _kirby_tex_open
		var bob_offset: float = -2.0 if ((_frame_counter / 20) % 2) == 1 else 0.0
		_kirby_rect.position.y = 96.0 + bob_offset
	if _star_rect != null:
		var star_bob: float = -1.0 if ((_frame_counter / 15) % 2) == 1 else 1.0
		_star_rect.position.y = 102.0 + star_bob


func is_ready_visual() -> bool:
	return _ready_visual


func get_surface_texture() -> ImageTexture:
	return _surface_texture


func get_frame_counter() -> int:
	return _frame_counter


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			start_requested.emit()
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			start_requested.emit()


static func _draw_rom_text_scaled(
	dest: Image,
	font_bank: Image,
	text: String,
	origin_x: int,
	origin_y: int,
	palette: PackedColorArray,
	scale_px: int
) -> void:
	if font_bank == null or palette.size() < 4:
		return
	var step_x: int = 8 * scale_px
	for i: int in range(text.length()):
		var ch: String = text.substr(i, 1)
		if ch == " ":
			continue
		var tile_idx: int = HUDRenderer.map_char_to_font_tile(ch)
		if tile_idx < 0:
			continue
		var src_base_x: int = (tile_idx % 8) * 8
		var src_base_y: int = (tile_idx / 8) * 8
		for py: int in range(8):
			for px: int in range(8):
				var c_idx: int = int(roundf(font_bank.get_pixel(src_base_x + px, src_base_y + py).r * 3.0))
				# Bank 254 glyphs use c_idx <= 1 as transparent background padding.
				if c_idx <= 1:
					continue
				var col: Color = palette[clampi(c_idx, 0, 3)]
				for sy: int in range(scale_px):
					for sx: int in range(scale_px):
						var dx: int = origin_x + i * step_x + px * scale_px + sx
						var dy: int = origin_y + py * scale_px + sy
						if dx >= 0 and dx < dest.get_width() and dy >= 0 and dy < dest.get_height():
							dest.set_pixel(dx, dy, col)
