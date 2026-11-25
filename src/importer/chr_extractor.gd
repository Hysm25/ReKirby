class_name CHRExtractor
extends RefCounted
## Decodes NES 2BPP planar 8x8 tiles across 256 x 1KB CHR-ROM banks into Images and ImageTextures.

const Constants = preload("res://src/core/constants.gd")


static func decode_tile_2bpp(chr_bytes: PackedByteArray, tile_offset: int) -> PackedByteArray:
	var pixels: PackedByteArray = PackedByteArray()
	pixels.resize(64)
	if tile_offset < 0 or tile_offset + Constants.CHR_BYTES_PER_TILE > chr_bytes.size():
		return pixels

	for row: int in range(Constants.TILE_SIZE):
		var plane0: int = chr_bytes[tile_offset + row]
		var plane1: int = chr_bytes[tile_offset + row + 8]
		var row_base: int = row * Constants.TILE_SIZE
		for col: int in range(Constants.TILE_SIZE):
			var bit: int = 7 - col
			var lo: int = (plane0 >> bit) & 1
			var hi: int = (plane1 >> bit) & 1
			pixels[row_base + col] = (hi << 1) | lo
	return pixels


static func decode_1k_bank_indices(chr_bytes: PackedByteArray, bank_1k_index: int) -> PackedByteArray:
	var total_pixels: int = Constants.CHR_1K_BANK_SHEET_WIDTH * Constants.CHR_1K_BANK_SHEET_HEIGHT
	var indices: PackedByteArray = PackedByteArray()
	indices.resize(total_pixels)

	var bank_offset: int = bank_1k_index * Constants.CHR_BANK_1K_SIZE
	if bank_offset < 0 or bank_offset + Constants.CHR_BANK_1K_SIZE > chr_bytes.size():
		return indices

	for tile_idx: int in range(Constants.CHR_TILES_PER_1K_BANK):
		var tile_pixels: PackedByteArray = decode_tile_2bpp(chr_bytes, bank_offset + tile_idx * Constants.CHR_BYTES_PER_TILE)
		var tile_col: int = tile_idx % 8
		var tile_row: int = tile_idx / 8
		var dst_x0: int = tile_col * Constants.TILE_SIZE
		var dst_y0: int = tile_row * Constants.TILE_SIZE
		for py: int in range(Constants.TILE_SIZE):
			var dst_row_offset: int = (dst_y0 + py) * Constants.CHR_1K_BANK_SHEET_WIDTH + dst_x0
			var src_row_offset: int = py * Constants.TILE_SIZE
			for px: int in range(Constants.TILE_SIZE):
				indices[dst_row_offset + px] = tile_pixels[src_row_offset + px]
	return indices


static func decode_1k_bank_image(
	chr_bytes: PackedByteArray,
	bank_1k_index: int,
	palette: PackedColorArray = PackedColorArray(),
	transparent_zero: bool = false
) -> Image:
	var total_pixels: int = Constants.CHR_1K_BANK_SHEET_WIDTH * Constants.CHR_1K_BANK_SHEET_HEIGHT
	var rgba: PackedByteArray = PackedByteArray()
	rgba.resize(total_pixels * 4)

	var bank_offset: int = bank_1k_index * Constants.CHR_BANK_1K_SIZE
	if bank_offset < 0 or bank_offset + Constants.CHR_BANK_1K_SIZE > chr_bytes.size():
		return Image.create_from_data(
			Constants.CHR_1K_BANK_SHEET_WIDTH,
			Constants.CHR_1K_BANK_SHEET_HEIGHT,
			false,
			Image.FORMAT_RGBA8,
			rgba
		)

	var use_palette: bool = palette.size() >= 4
	var lut_r: PackedByteArray = PackedByteArray([0, 85, 170, 255])
	var lut_g: PackedByteArray = PackedByteArray([0, 85, 170, 255])
	var lut_b: PackedByteArray = PackedByteArray([0, 85, 170, 255])
	if use_palette:
		for c_i: int in range(4):
			var c: Color = palette[c_i]
			lut_r[c_i] = clampi(int(round(c.r * 255.0)), 0, 255)
			lut_g[c_i] = clampi(int(round(c.g * 255.0)), 0, 255)
			lut_b[c_i] = clampi(int(round(c.b * 255.0)), 0, 255)

	var alpha_zero: int = 0 if transparent_zero else 255
	var sheet_w: int = Constants.CHR_1K_BANK_SHEET_WIDTH
	for tile_idx: int in range(Constants.CHR_TILES_PER_1K_BANK):
		var tile_off: int = bank_offset + tile_idx * Constants.CHR_BYTES_PER_TILE
		var dst_x0: int = (tile_idx % 8) * Constants.TILE_SIZE
		var dst_y0: int = (tile_idx / 8) * Constants.TILE_SIZE
		for py: int in range(Constants.TILE_SIZE):
			var p0: int = chr_bytes[tile_off + py]
			var p1: int = chr_bytes[tile_off + py + 8]
			var dst_row: int = ((dst_y0 + py) * sheet_w + dst_x0) * 4
			for px: int in range(Constants.TILE_SIZE):
				var bit: int = 7 - px
				var color_idx: int = (((p1 >> bit) & 1) << 1) | ((p0 >> bit) & 1)
				var dst: int = dst_row + px * 4
				rgba[dst] = lut_r[color_idx]
				rgba[dst + 1] = lut_g[color_idx]
				rgba[dst + 2] = lut_b[color_idx]
				rgba[dst + 3] = alpha_zero if color_idx == 0 else 255

	return Image.create_from_data(
		Constants.CHR_1K_BANK_SHEET_WIDTH,
		Constants.CHR_1K_BANK_SHEET_HEIGHT,
		false,
		Image.FORMAT_RGBA8,
		rgba
	)


static func apply_palette_to_bank_image(
	indexed_img: Image,
	palette: PackedColorArray,
	transparent_zero: bool = false
) -> ImageTexture:
	if indexed_img == null or indexed_img.is_empty() or palette.size() < 4:
		return null

	var w: int = indexed_img.get_width()
	var h: int = indexed_img.get_height()
	var src_rgba: PackedByteArray = indexed_img.get_data()
	var out_rgba: PackedByteArray = PackedByteArray()
	out_rgba.resize(w * h * 4)

	for i: int in range(w * h):
		var src_offset: int = i * 4
		var gray: int = src_rgba[src_offset]
		var color_idx: int = clampi((gray + 42) / 85, 0, 3)
		var c: Color = palette[color_idx]
		out_rgba[src_offset] = clampi(int(round(c.r * 255.0)), 0, 255)
		out_rgba[src_offset + 1] = clampi(int(round(c.g * 255.0)), 0, 255)
		out_rgba[src_offset + 2] = clampi(int(round(c.b * 255.0)), 0, 255)
		out_rgba[src_offset + 3] = 0 if (transparent_zero and color_idx == 0) else 255

	var mapped_img: Image = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out_rgba)
	return ImageTexture.create_from_image(mapped_img)


static func extract_all_chr_sheets(chr_bytes: PackedByteArray, chr_banks_dir: String) -> Array[Image]:
	var bank_images: Array[Image] = []
	if chr_bytes.size() < Constants.EXPECTED_CHR_SIZE:
		push_error("CHRExtractor: Invalid CHR size %d (expected %d)." % [chr_bytes.size(), Constants.EXPECTED_CHR_SIZE])
		return bank_images

	var err: Error = DirAccess.make_dir_recursive_absolute(chr_banks_dir)
	if err != OK:
		push_error("CHRExtractor: Failed to create CHR directory %s (err=%d)." % [chr_banks_dir, err])
		return bank_images

	var sheet_width: int = Constants.CHR_1K_BANK_SHEET_WIDTH * 8
	var sheet_height: int = Constants.CHR_1K_BANK_SHEET_HEIGHT

	for bank_8k: int in range(Constants.EXPECTED_CHR_BANKS_8K):
		var sheet_img: Image = Image.create(sheet_width, sheet_height, false, Image.FORMAT_RGBA8)
		for slot: int in range(8):
			var bank_1k_idx: int = bank_8k * 8 + slot
			var bank_img: Image = decode_1k_bank_image(chr_bytes, bank_1k_idx)
			bank_images.append(bank_img)
			sheet_img.blit_rect(
				bank_img,
				Rect2i(0, 0, Constants.CHR_1K_BANK_SHEET_WIDTH, Constants.CHR_1K_BANK_SHEET_HEIGHT),
				Vector2i(slot * Constants.CHR_1K_BANK_SHEET_WIDTH, 0)
			)
		var out_path: String = "%s/chr_8k_%02d.png" % [chr_banks_dir, bank_8k]
		var save_err: Error = sheet_img.save_png(out_path)
		if save_err != OK:
			push_error("CHRExtractor: Failed saving %s (err=%d)." % [out_path, save_err])
			bank_images.clear()
			return bank_images

	return bank_images
