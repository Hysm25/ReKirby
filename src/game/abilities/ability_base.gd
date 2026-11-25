class_name AbilityBase
extends Node2D
## Base typed Copy Ability component providing 60 TPS attack lifecycle,
## active combat hitboxes, block breaking, and ROM CHR sprite composition.

const Constants = preload("res://src/core/constants.gd")

var _active: bool = false
var _frame: int = 0
var _facing_dir: int = 1
var _origin: Vector2 = Vector2.ZERO
var _sprites: Array[Sprite2D] = []
var _cached_textures: Dictionary = {}


func get_ability_id() -> int:
	return Constants.CopyAbility.NONE


func get_ability_name() -> String:
	return "NORMAL"


func is_active() -> bool:
	return _active


func is_movement_locked() -> bool:
	return _active


func is_blocking_contact() -> bool:
	return false


func get_attack_frame() -> int:
	return _frame


func get_dash_impulse(_facing_dir: int) -> float:
	return 0.0


func start_attack(facing_dir: int, _is_grounded: bool, _is_running: bool, origin: Vector2) -> bool:
	_active = true
	_frame = 0
	_facing_dir = 1 if facing_dir >= 0 else -1
	_origin = origin
	return true


func step_attack(facing_dir: int, _is_grounded: bool, _is_running: bool, origin: Vector2, _b_held: bool) -> void:
	_facing_dir = 1 if facing_dir >= 0 else -1
	_origin = origin
	_frame += 1


func cancel_attack() -> void:
	_active = false
	_frame = 0
	_hide_all_sprites()


func get_active_hitboxes() -> Array[Dictionary]:
	return []


func sync_visuals() -> void:
	if not _active:
		_hide_all_sprites()
		return
	_update_rom_visuals()


func _update_rom_visuals() -> void:
	_hide_all_sprites()


func _hide_all_sprites() -> void:
	for spr: Sprite2D in _sprites:
		spr.visible = false


func _ensure_sprite_pool(count: int) -> void:
	while _sprites.size() < count:
		var spr: Sprite2D = Sprite2D.new()
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.visible = false
		add_child(spr)
		_sprites.append(spr)


func _get_rom_tile_texture(bank_1k: int, tile_ids: PackedInt32Array, width_tiles: int, height_tiles: int, palette_key: String) -> ImageTexture:
	if not ContentRegistry.is_ready():
		return null
	var cache_key: String = "%d_%s_%s_%dx%d" % [bank_1k, str(tile_ids), palette_key, width_tiles, height_tiles]
	if _cached_textures.has(cache_key):
		return _cached_textures[cache_key] as ImageTexture

	var bank_img: Image = ContentRegistry.get_chr_bank_image(bank_1k)
	if bank_img == null or bank_img.is_empty():
		return null
	var pal: PackedColorArray = ContentRegistry.get_palette_colors(palette_key)
	if pal.size() < 4:
		pal = ContentRegistry.get_palette_colors("kirby_default")
	if pal.size() < 4:
		return null

	var img_w: int = width_tiles * Constants.TILE_SIZE
	var img_h: int = height_tiles * Constants.TILE_SIZE
	var src_rgba: PackedByteArray = bank_img.get_data()
	var out_rgba: PackedByteArray = PackedByteArray()
	out_rgba.resize(img_w * img_h * 4)

	var tile_count: int = mini(tile_ids.size(), width_tiles * height_tiles)
	for slot: int in range(tile_count):
		var local_tile: int = tile_ids[slot] & 0x3F
		var tx0: int = (local_tile % 8) * Constants.TILE_SIZE
		var ty0: int = (local_tile / 8) * Constants.TILE_SIZE
		var dst_tx: int = (slot % width_tiles) * Constants.TILE_SIZE
		var dst_ty: int = (slot / width_tiles) * Constants.TILE_SIZE
		for py: int in range(Constants.TILE_SIZE):
			var src_row: int = ((ty0 + py) * Constants.CHR_1K_BANK_SHEET_WIDTH + tx0) * 4
			var dst_row: int = ((dst_ty + py) * img_w + dst_tx) * 4
			for px: int in range(Constants.TILE_SIZE):
				var gray: int = src_rgba[src_row + px * 4]
				var c_idx: int = clampi((gray + 42) / 85, 0, 3)
				var dst_off: int = dst_row + px * 4
				if c_idx == 0:
					out_rgba[dst_off] = 0
					out_rgba[dst_off + 1] = 0
					out_rgba[dst_off + 2] = 0
					out_rgba[dst_off + 3] = 0
				else:
					var col: Color = pal[c_idx]
					out_rgba[dst_off] = clampi(int(round(col.r * 255.0)), 0, 255)
					out_rgba[dst_off + 1] = clampi(int(round(col.g * 255.0)), 0, 255)
					out_rgba[dst_off + 2] = clampi(int(round(col.b * 255.0)), 0, 255)
					out_rgba[dst_off + 3] = 255

	var img: Image = Image.create_from_data(img_w, img_h, false, Image.FORMAT_RGBA8, out_rgba)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_cached_textures[cache_key] = tex
	return tex
