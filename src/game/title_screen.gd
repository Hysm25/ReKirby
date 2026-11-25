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

	var bg0: PackedColorArray = ContentRegistry.get_palette_colors("hud_bg_0")
	var bg1: PackedColorArray = ContentRegistry.get_palette_colors("hud_bg_1")
	var bg2: PackedColorArray = ContentRegistry.get_palette_colors("hud_bg_2")
	var kirby_pal: PackedColorArray = ContentRegistry.get_palette_colors("kirby_default")
	var star_pal: PackedColorArray = ContentRegistry.get_palette_colors("hud_sp_star")
	if bg0.size() < 4 or kirby_pal.size() < 4:
		return

	var sky_color: Color = Color(0.0, 0.0, 0.0, 1.0)
	var border_color: Color = kirby_pal[2] if kirby_pal.size() > 2 else Color(1.0, 0.55, 0.75, 1.0)
	var accent_color: Color = star_pal[2] if star_pal.size() > 2 else bg0[3]

	var img: Image = Image.create(Constants.NATIVE_WIDTH, Constants.NATIVE_HEIGHT, false, Image.FORMAT_RGBA8)
	img.fill(sky_color)

	# Clean NES-style frame border using ROM palette colors.
	for x: int in range(8, Constants.NATIVE_WIDTH - 8):
		img.set_pixel(x, 12, border_color)
		img.set_pixel(x, 13, accent_color)
		img.set_pixel(x, Constants.NATIVE_HEIGHT - 14, accent_color)
		img.set_pixel(x, Constants.NATIVE_HEIGHT - 13, border_color)

	var title_pal: PackedColorArray = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.0, 0.0, 0.0, 0.0),
		border_color,
		bg0[3],
	])
	var gold_pal: PackedColorArray = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.0, 0.0, 0.0, 0.0),
		bg1[2] if bg1.size() > 2 else accent_color,
		accent_color,
	])
	var sub_pal: PackedColorArray = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.0, 0.0, 0.0, 0.0),
		bg2[2] if bg2.size() > 2 else bg0[2],
		bg0[3],
	])

	_draw_rom_text_scaled(img, font_bank, "KIRBYS", 80, 40, title_pal, 2)
	_draw_rom_text_scaled(img, font_bank, "ADVENTURE", 56, 62, gold_pal, 2)
	_draw_rom_text_scaled(img, font_bank, "WORLD 1 VERTICAL SLICE", 40, 92, sub_pal, 1)

	_surface_texture = ImageTexture.create_from_image(img)
	_backdrop_rect.texture = _surface_texture

	_kirby_tex_open = ContentRegistry.build_rom_oam_8x16(
		Constants.CHR_BANK_KIRBY_DEFAULT,
		Vector2i(8, 9),
		Vector2i(12, 13),
		"kirby_default",
		false,
		false,
		false,
		1
	)
	_kirby_tex_blink = ContentRegistry.build_rom_oam_8x16(
		Constants.CHR_BANK_KIRBY_DEFAULT,
		Vector2i(8, 9),
		Vector2i(14, 15),
		"kirby_default",
		false,
		false,
		false,
		1
	)
	_kirby_rect.texture = _kirby_tex_open
	_star_rect.texture = ContentRegistry.build_rom_oam_8x16(
		Constants.CHR_BANK_STAR_EFFECTS,
		Vector2i(16, 17),
		Vector2i(18, 19),
		"hud_sp_star",
		false,
		false,
		false,
		1
	)

	var press_img: Image = Image.create(88, 8, false, Image.FORMAT_RGBA8)
	press_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	_draw_rom_text_scaled(press_img, font_bank, "PRESS START", 0, 0, gold_pal, 1)
	_press_start_rect.texture = ImageTexture.create_from_image(press_img)
	_press_start_rect.visible = true

	_ready_visual = _surface_texture != null and _kirby_tex_open != null and _press_start_rect.texture != null


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
		_kirby_rect.position.y = 124.0 + bob_offset
	if _star_rect != null:
		var star_bob: float = -1.0 if ((_frame_counter / 15) % 2) == 1 else 1.0
		_star_rect.position.y = 128.0 + star_bob


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
