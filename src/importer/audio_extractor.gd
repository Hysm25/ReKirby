class_name AudioExtractor
extends RefCounted
## Clean-room extractor for Kirby's Adventure PRG Bank 29 (0x1D) sound tables,
## 2A03 period/tempo/envelope tables, BGM tracks, SFX tracks, and fixed-bank DPCM samples.

const Constants = preload("res://src/core/constants.gd")
const MMC3Mapper = preload("res://src/importer/mmc3_mapper.gd")

const B29_PERIOD_TABLE_ADDR: int = 0x867A
const B29_PERIOD_COUNT: int = 75
const B29_ENVELOPE_PTR_TABLE: int = 0x88B1
const B29_ENVELOPE_COUNT: int = 83
const B29_TEMPO_TABLE_ADDR: int = 0x8955
const B29_TEMPO_COUNT: int = 10
const B29_TRACK_PTR_LO: int = 0x8991
const B29_TRACK_PTR_HI: int = 0x89CB
const B29_TRACK_BANK: int = 0x8A05
const B29_TRACK_COUNT: int = 58
const B29_SFX_PTR_LO: int = 0x8A3F
const B29_SFX_PTR_HI: int = 0x8A97
const B29_SFX_CH_MASK: int = 0x8AEF
const B29_SFX_PRIORITY: int = 0x8B47
const B29_SFX_COUNT: int = 88

const MAX_STREAM_BLOCKS: int = 256
const MAX_BLOCK_BYTES: int = 2048
const MAX_ENVELOPE_BYTES: int = 128


class AudioExtractionResult extends RefCounted:
	var success: bool = false
	var error: String = ""
	var period_table: Array[int] = []
	var tempo_tables: Array[Array] = []
	var envelopes: Dictionary = {}
	var tracks: Dictionary = {}
	var sfx: Dictionary = {}
	var dpcm_samples: Dictionary = {}

	func to_dict() -> Dictionary:
		return {
			"format_version": Constants.EXTRACTION_FORMAT_VERSION,
			"period_table": period_table,
			"tempo_tables": tempo_tables,
			"envelopes": envelopes,
			"tracks": tracks,
			"sfx": sfx,
			"dpcm_samples": dpcm_samples,
		}


static func _map_r6(mapper: MMC3Mapper, bank_8k: int) -> void:
	mapper.write_register(0x8000, 0x86)
	mapper.write_register(0x8001, bank_8k & 0x3F)


static func _map_r7(mapper: MMC3Mapper, bank_8k: int) -> void:
	mapper.write_register(0x8000, 0x87)
	mapper.write_register(0x8001, bank_8k & 0x3F)


static func extract_audio(prg_data: PackedByteArray) -> AudioExtractionResult:
	var result: AudioExtractionResult = AudioExtractionResult.new()
	if prg_data.size() != Constants.EXPECTED_PRG_SIZE:
		result.error = "Invalid PRG-ROM size %d for AudioExtractor." % prg_data.size()
		return result

	var mapper: MMC3Mapper = MMC3Mapper.new(prg_data, PackedByteArray())
	_map_r6(mapper, Constants.PRG_BANK_AUDIO_ENGINE)

	# 1. Extract 75 x 16-bit big-endian 2A03 period values ($867A..$870F)
	var raw_periods: PackedByteArray = mapper.read_prg_slice(B29_PERIOD_TABLE_ADDR, B29_PERIOD_COUNT * 2)
	for i: int in range(B29_PERIOD_COUNT):
		var hi: int = raw_periods[i * 2]
		var lo: int = raw_periods[i * 2 + 1]
		result.period_table.append(((hi << 8) | lo) & 0x07FF)

	# 2. Extract 10 x 6 tempo duration lookup tables ($8955..$8990)
	var raw_tempos: PackedByteArray = mapper.read_prg_slice(B29_TEMPO_TABLE_ADDR, B29_TEMPO_COUNT * 6)
	for t_idx: int in range(B29_TEMPO_COUNT):
		var row: Array[int] = []
		for d_idx: int in range(6):
			row.append(raw_tempos[t_idx * 6 + d_idx])
		result.tempo_tables.append(row)

	# 3. Extract volume/duty envelope sequences referenced from $88B1..$8954
	var env_ptrs_raw: PackedByteArray = mapper.read_prg_slice(B29_ENVELOPE_PTR_TABLE, B29_ENVELOPE_COUNT * 2)
	for env_idx: int in range(B29_ENVELOPE_COUNT):
		var ptr: int = env_ptrs_raw[env_idx * 2] | (env_ptrs_raw[env_idx * 2 + 1] << 8)
		if ptr >= 0x8000 and ptr < 0xA000:
			var env_seq: Array[int] = _trace_envelope_bytes(mapper, ptr)
			result.envelopes[str(env_idx)] = env_seq

	# Collect referenced DPCM sample descriptors "(addr_reg, len_reg)" across BGM & SFX
	var dpcm_refs: Dictionary = {}

	# 4. Extract all 58 BGM tracks + reachable bytecode blocks
	for tid: int in range(B29_TRACK_COUNT):
		_map_r6(mapper, Constants.PRG_BANK_AUDIO_ENGINE)
		var lo: int = mapper.read_prg_byte(B29_TRACK_PTR_LO + tid)
		var hi: int = mapper.read_prg_byte(B29_TRACK_PTR_HI + tid)
		var bank: int = mapper.read_prg_byte(B29_TRACK_BANK + tid)
		var hdr_addr: int = lo | (hi << 8)
		if hdr_addr < 0xA000 or hdr_addr >= 0xC000:
			continue

		_map_r7(mapper, bank)
		var ch_count: int = mini(mapper.read_prg_byte(hdr_addr), 5)
		if ch_count <= 0:
			continue

		var channels: Array[Dictionary] = []
		var blocks: Dictionary = {}
		var cursor: int = hdr_addr + 1
		for ch_idx: int in range(ch_count):
			var start_ptr: int = mapper.read_prg_byte(cursor) | (mapper.read_prg_byte(cursor + 1) << 8)
			var reg_off: int = mapper.read_prg_byte(cursor + 2) if ch_idx < ch_count - 1 else mapper.read_prg_byte(cursor + 2)
			# Track headers list ch_count * 3 bytes: (ptr_lo, ptr_hi, channel_reg_offset)
			cursor += 3
			channels.append({
				"slot": ch_idx,
				"reg_offset": reg_off,
				"start_addr": start_ptr,
			})
			_collect_stream_blocks(mapper, start_ptr, 0xA000, 0xC000, blocks, dpcm_refs)

		result.tracks[str(tid)] = {
			"track_id": tid,
			"prg_bank": bank,
			"header_addr": hdr_addr,
			"channels": channels,
			"blocks": blocks,
		}

	# 5. Extract all 88 SFX tracks from Bank 29 ($8000-$9FFF)
	_map_r6(mapper, Constants.PRG_BANK_AUDIO_ENGINE)
	for sfx_id: int in range(B29_SFX_COUNT):
		var s_lo: int = mapper.read_prg_byte(B29_SFX_PTR_LO + sfx_id)
		var s_hi: int = mapper.read_prg_byte(B29_SFX_PTR_HI + sfx_id)
		var s_addr: int = s_lo | (s_hi << 8)
		var ch_mask: int = mapper.read_prg_byte(B29_SFX_CH_MASK + sfx_id)
		var priority: int = mapper.read_prg_byte(B29_SFX_PRIORITY + sfx_id)
		if s_addr < 0x8000 or s_addr >= 0xA000:
			continue

		var ch_count: int = mini(mapper.read_prg_byte(s_addr), 5)
		if ch_count <= 0:
			continue
		var channels: Array[Dictionary] = []
		var blocks: Dictionary = {}
		var cursor: int = s_addr + 1
		for ch_idx: int in range(ch_count):
			var start_ptr: int = mapper.read_prg_byte(cursor) | (mapper.read_prg_byte(cursor + 1) << 8)
			var reg_off: int = mapper.read_prg_byte(cursor + 2)
			cursor += 3
			channels.append({
				"slot": ch_idx,
				"reg_offset": reg_off,
				"start_addr": start_ptr,
			})
			_collect_stream_blocks(mapper, start_ptr, 0x8000, 0xA000, blocks, dpcm_refs)

		result.sfx[str(sfx_id)] = {
			"sfx_id": sfx_id,
			"channel_mask": ch_mask,
			"priority": priority,
			"header_addr": s_addr,
			"channels": channels,
			"blocks": blocks,
		}

	# 6. Extract referenced DPCM sample bytes from fixed PRG $C000-$FFFF
	# ($4012 addr = $C000 + addr_reg * 64, $4013 len = len_reg * 16 + 1 bytes)
	for key_var: Variant in dpcm_refs.keys():
		var pair: Array = dpcm_refs[key_var] as Array
		var addr_reg: int = int(pair[0]) & 0xFF
		var len_reg: int = int(pair[1]) & 0xFF
		var cpu_addr: int = 0xC000 + addr_reg * 64
		var byte_len: int = len_reg * 16 + 1
		if cpu_addr + byte_len <= 0x10000:
			var prg_off: int = 62 * Constants.PRG_BANK_8K_SIZE + (cpu_addr - 0xC000)
			if prg_off >= 0 and prg_off + byte_len <= prg_data.size():
				var sample_bytes: Array[int] = []
				sample_bytes.resize(byte_len)
				for b_i: int in range(byte_len):
					sample_bytes[b_i] = prg_data[prg_off + b_i]
				result.dpcm_samples[String(key_var)] = {
					"addr_reg": addr_reg,
					"len_reg": len_reg,
					"cpu_addr": cpu_addr,
					"bytes": sample_bytes,
				}

	result.success = (
		result.period_table.size() == B29_PERIOD_COUNT
		and result.tracks.size() > 0
		and result.sfx.size() > 0
	)
	return result


static func _trace_envelope_bytes(mapper: MMC3Mapper, start_ptr: int) -> Array[int]:
	var bytes: Array[int] = []
	var addr: int = start_ptr
	for _i: int in range(MAX_ENVELOPE_BYTES):
		if addr < 0x8000 or addr >= 0xA000:
			break
		var b: int = mapper.read_prg_byte(addr)
		bytes.append(b)
		addr += 1
		if b == 0xFF or b == 0xFB:
			break
		if b == 0xFC:
			bytes.append(mapper.read_prg_byte(addr))
			addr += 1
		elif b == 0xF8 or b == 0xFA:
			var lo: int = mapper.read_prg_byte(addr)
			var hi: int = mapper.read_prg_byte(addr + 1)
			bytes.append(lo)
			bytes.append(hi)
			addr += 2
			if b == 0xF8:
				break
	return bytes


static func _collect_stream_blocks(
	mapper: MMC3Mapper,
	start_addr: int,
	win_min: int,
	win_max: int,
	blocks: Dictionary,
	dpcm_refs: Dictionary
) -> void:
	var queue: Array[int] = [start_addr]
	var visited_count: int = 0
	while not queue.is_empty() and visited_count < MAX_STREAM_BLOCKS:
		visited_count += 1
		var block_addr: int = int(queue.pop_front())
		var block_key: String = str(block_addr)
		if blocks.has(block_key):
			continue
		if block_addr < win_min or block_addr >= win_max:
			continue

		var stream: Array[int] = []
		var addr: int = block_addr
		var done: bool = false
		var count: int = 0
		while not done and count < MAX_BLOCK_BYTES and addr < win_max:
			count += 1
			var b: int = mapper.read_prg_byte(addr)
			stream.append(b)
			addr += 1
			if b < 0xE0:
				if (b & 0xE0) == 0xC0 and addr < win_max:
					stream.append(mapper.read_prg_byte(addr))
					addr += 1
				continue
			match b:
				0xE0:
					var a_reg: int = mapper.read_prg_byte(addr)
					var l_reg: int = mapper.read_prg_byte(addr + 1)
					stream.append(a_reg)
					stream.append(l_reg)
					addr += 2
					var d_key: String = "%d_%d" % [a_reg, l_reg]
					dpcm_refs[d_key] = [a_reg, l_reg]
				0xE2:
					stream.append(mapper.read_prg_byte(addr))
					stream.append(mapper.read_prg_byte(addr + 1))
					addr += 2
				0xE1, 0xE3, 0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xFC, 0xFE:
					stream.append(mapper.read_prg_byte(addr))
					addr += 1
				0xF8, 0xFA:
					var t_lo: int = mapper.read_prg_byte(addr)
					var t_hi: int = mapper.read_prg_byte(addr + 1)
					stream.append(t_lo)
					stream.append(t_hi)
					addr += 2
					var target: int = t_lo | (t_hi << 8)
					if target >= win_min and target < win_max and not blocks.has(str(target)):
						queue.append(target)
					if b == 0xF8:
						done = true
				0xFB, 0xFF:
					done = true
				_:
					pass
		blocks[block_key] = stream
