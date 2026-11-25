class_name HALDecompressor
extends RefCounted
## Clean-room HAL Laboratory LZ77 / RLE bitstream decompressor for Kirby's Adventure (NES).

const MAX_ITERATIONS: int = 131072


class DecompressResult extends RefCounted:
	var success: bool = false
	var data: PackedByteArray = PackedByteArray()
	var bytes_consumed: int = 0
	var error: String = ""


static var _bit_reverse_table: PackedByteArray = PackedByteArray()


static func _ensure_bit_reverse_table() -> void:
	if not _bit_reverse_table.is_empty():
		return
	_bit_reverse_table.resize(256)
	for i: int in range(256):
		var rev: int = 0
		var v: int = i
		for _b: int in range(8):
			rev = (rev << 1) | (v & 1)
			v >>= 1
		_bit_reverse_table[i] = rev


static func reverse_bits(byte_val: int) -> int:
	_ensure_bit_reverse_table()
	return _bit_reverse_table[byte_val & 0xFF]


static func decompress(input: PackedByteArray, start_offset: int = 0, max_output_size: int = 65536) -> DecompressResult:
	var result: DecompressResult = DecompressResult.new()
	if start_offset < 0 or start_offset >= input.size():
		result.error = "Start offset %d out of bounds (input size=%d)." % [start_offset, input.size()]
		return result
	if max_output_size <= 0:
		result.error = "Invalid max_output_size: %d." % max_output_size
		return result

	_ensure_bit_reverse_table()
	var pos: int = start_offset
	var out: PackedByteArray = PackedByteArray()
	var iterations: int = 0

	while pos < input.size():
		iterations += 1
		if iterations > MAX_ITERATIONS:
			result.error = "HALDecompressor exceeded MAX_ITERATIONS (%d)." % MAX_ITERATIONS
			return result
		var cmd_byte: int = input[pos]
		pos += 1

		if cmd_byte == 0xFF:
			result.success = true
			result.data = out
			result.bytes_consumed = pos - start_offset
			return result

		var op: int = (cmd_byte >> 5) & 0x07
		var length: int = 0
		if op == 7:
			if pos >= input.size():
				result.error = "Unexpected EOF reading extended HAL command length."
				return result
			op = (cmd_byte >> 2) & 0x07
			if op == 7:
				result.error = "Invalid extended HAL opcode 7 (byte=0x%02X)." % cmd_byte
				return result
			var ext_lo: int = input[pos]
			pos += 1
			length = (((cmd_byte & 0x03) << 8) | ext_lo) + 1
		else:
			length = (cmd_byte & 0x1F) + 1

		match op:
			0: # Uncompressed raw literal copy
				if pos + length > input.size():
					result.error = "Unexpected EOF in opcode 0 literal copy (need %d bytes)." % length
					return result
				if out.size() + length > max_output_size:
					result.error = "Output exceeded max_output_size (%d)." % max_output_size
					return result
				var old_size: int = out.size()
				out.resize(old_size + length)
				for i: int in range(length):
					out[old_size + i] = input[pos + i]
				pos += length

			1: # 8-bit RLE fill
				if pos >= input.size():
					result.error = "Unexpected EOF in opcode 1 8-bit RLE."
					return result
				if out.size() + length > max_output_size:
					result.error = "Output exceeded max_output_size (%d)." % max_output_size
					return result
				var fill_val: int = input[pos]
				pos += 1
				var old_size: int = out.size()
				out.resize(old_size + length)
				for i: int in range(length):
					out[old_size + i] = fill_val

			2: # 16-bit RLE fill
				if pos + 1 >= input.size():
					result.error = "Unexpected EOF in opcode 2 16-bit RLE."
					return result
				var add_bytes: int = length * 2
				if out.size() + add_bytes > max_output_size:
					result.error = "Output exceeded max_output_size (%d)." % max_output_size
					return result
				var b0: int = input[pos]
				var b1: int = input[pos + 1]
				pos += 2
				var old_size: int = out.size()
				out.resize(old_size + add_bytes)
				for i: int in range(length):
					out[old_size + i * 2] = b0
					out[old_size + i * 2 + 1] = b1

			3: # Incrementing byte sequence
				if pos >= input.size():
					result.error = "Unexpected EOF in opcode 3 incrementing fill."
					return result
				if out.size() + length > max_output_size:
					result.error = "Output exceeded max_output_size (%d)." % max_output_size
					return result
				var seed_val: int = input[pos]
				pos += 1
				var old_size: int = out.size()
				out.resize(old_size + length)
				for i: int in range(length):
					out[old_size + i] = (seed_val + i) & 0xFF

			4, 5, 6: # LZ77 back-references (16-bit big-endian output offset)
				if pos + 1 >= input.size():
					result.error = "Unexpected EOF reading LZ77 back-reference offset."
					return result
				if out.size() + length > max_output_size:
					result.error = "Output exceeded max_output_size (%d)." % max_output_size
					return result
				var back_offset: int = (input[pos] << 8) | input[pos + 1]
				pos += 2
				if back_offset < 0 or back_offset >= out.size():
					result.error = "Invalid LZ77 back-reference offset %d (output size=%d)." % [back_offset, out.size()]
					return result
				for i: int in range(length):
					var src_idx: int = (back_offset - i) if op == 6 else (back_offset + i)
					if src_idx < 0 or src_idx >= out.size():
						result.error = "LZ77 source index %d out of bounds (output size=%d)." % [src_idx, out.size()]
						return result
					var copied_byte: int = out[src_idx]
					if op == 5:
						copied_byte = _bit_reverse_table[copied_byte]
					out.append(copied_byte)

			_:
				result.error = "Unhandled HAL opcode %d." % op
				return result

	result.error = "HAL stream terminated without 0xFF end marker."
	return result
