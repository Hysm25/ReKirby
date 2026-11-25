class_name MusicPlayer
extends Node
## PRG-ROM Music & SFX sequence interpreter driving APUEngine at 60 TPS
## matching Bank 29 HAL sound driver semantics (5-bit signed note offsets,
## master volume/gate/envelope VMs, explicit 0xC0..0xDF durations, nested 0xFC/0xFD loops).

const Constants = preload("res://src/core/constants.gd")
const APUEngine = preload("res://src/audio/apu_engine.gd")

const MAX_COMMANDS_PER_TICK: int = 64
const MAX_LOOP_STACK: int = 8

# Channel slot mapping: 0=Pulse1 ($4000), 1=Pulse2 ($4004), 2=Triangle ($4008), 3=Noise ($400C), 4=DMC
const REG_TO_HW_CH: Dictionary = {
	0x00: 0,
	0x04: 1,
	0x08: 2,
	0x0C: 3,
}


class ChannelRunner extends RefCounted:
	var active: bool = false
	var is_sfx: bool = false
	var hw_ch: int = 0
	var reg_offset: int = 0
	var priority: int = 0
	var blocks: Dictionary = {}
	var cur_block_key: String = ""
	var cursor: int = 0
	var delay_frames: int = 0
	var duration_ticks: int = 1
	var gate_frames: int = -1
	var gate_ratio: int = 0
	var tempo_idx: int = 0
	var duty: int = 2
	var master_vol: int = 12
	var env_vol: int = 15
	var env_id: int = 0x80
	var env_seq: Array = []
	var env_cursor: int = 0
	var env_wait: int = 0
	var base_note: int = 0
	var detune: int = 0
	var vibrato_id: int = 0
	var vibrato_tick: int = 0
	var last_period: int = 0
	var is_rested: bool = true
	var dmc_addr_reg: int = 240
	var dmc_len_reg: int = 11
	var loop_stack: Array[Dictionary] = []
	var call_stack: Array[Dictionary] = []

	func reset() -> void:
		active = false
		blocks = {}
		cur_block_key = ""
		cursor = 0
		delay_frames = 0
		duration_ticks = 1
		gate_frames = -1
		gate_ratio = 0
		tempo_idx = 0
		duty = 2
		master_vol = 12
		env_vol = 15
		env_id = 0x80
		env_seq = []
		env_cursor = 0
		env_wait = 0
		base_note = 0
		detune = 0
		vibrato_id = 0
		vibrato_tick = 0
		last_period = 0
		is_rested = true
		loop_stack.clear()
		call_stack.clear()

	func start_stream(p_blocks: Dictionary, start_addr: int, p_reg_offset: int, p_hw_ch: int, p_is_sfx: bool, p_priority: int = 0) -> void:
		reset()
		blocks = p_blocks
		cur_block_key = str(start_addr)
		cursor = 0
		reg_offset = p_reg_offset
		hw_ch = p_hw_ch
		is_sfx = p_is_sfx
		priority = p_priority
		active = blocks.has(cur_block_key)
		delay_frames = 1

	func effective_volume() -> int:
		if is_rested:
			return 0
		var atten: int = 15 - clampi(master_vol, 0, 15)
		return clampi(env_vol - atten, 0, 15)


var _apu: APUEngine = null
var _bgm_channels: Array[ChannelRunner] = []
var _sfx_channels: Array[ChannelRunner] = []
var _current_bgm_id: int = -1
var _current_sfx_id: int = -1
var _period_table: PackedInt32Array = PackedInt32Array()
var _tempo_tables: Array[PackedInt32Array] = []
var _envelopes: Dictionary = {}


func _ready() -> void:
	name = "MusicPlayer"
	_ensure_runners()
	_connect_event_bus()


func setup(apu: APUEngine) -> void:
	_apu = apu
	_ensure_runners()
	_sync_rom_tables()


func _ensure_runners() -> void:
	if _bgm_channels.size() == 5 and _sfx_channels.size() == 5:
		return
	_bgm_channels.clear()
	_sfx_channels.clear()
	for i: int in range(5):
		var b: ChannelRunner = ChannelRunner.new()
		b.hw_ch = i
		_bgm_channels.append(b)
		var s: ChannelRunner = ChannelRunner.new()
		s.hw_ch = i
		s.is_sfx = true
		_sfx_channels.append(s)


func _connect_event_bus() -> void:
	if not EventBus.bgm_requested.is_connected(_on_bgm_requested):
		EventBus.bgm_requested.connect(_on_bgm_requested)
	if not EventBus.sfx_requested.is_connected(_on_sfx_requested):
		EventBus.sfx_requested.connect(_on_sfx_requested)
	if not EventBus.audio_stop_requested.is_connected(stop_all):
		EventBus.audio_stop_requested.connect(stop_all)


func _sync_rom_tables() -> void:
	if not ContentRegistry.is_ready():
		return
	var tables: Dictionary = ContentRegistry.get_audio_tables()
	var p_raw: Variant = tables.get("period_table", [])
	if p_raw is Array:
		var arr: Array = p_raw as Array
		_period_table.resize(arr.size())
		for i: int in range(arr.size()):
			_period_table[i] = int(arr[i])
	_tempo_tables.clear()
	var t_raw: Variant = tables.get("tempo_tables", [])
	if t_raw is Array:
		for row_v: Variant in (t_raw as Array):
			if row_v is Array:
				var row_arr: Array = row_v as Array
				var p_row: PackedInt32Array = PackedInt32Array()
				for item: Variant in row_arr:
					p_row.append(int(item))
				_tempo_tables.append(p_row)
	var env_raw: Variant = tables.get("envelopes", {})
	if env_raw is Dictionary:
		_envelopes = env_raw as Dictionary


func get_current_bgm_id() -> int:
	return _current_bgm_id


func get_current_sfx_id() -> int:
	return _current_sfx_id


func is_bgm_playing() -> bool:
	for ch: ChannelRunner in _bgm_channels:
		if ch.active:
			return true
	return false


func is_sfx_active_on_channel(hw_ch: int) -> bool:
	if hw_ch < 0 or hw_ch >= _sfx_channels.size():
		return false
	return _sfx_channels[hw_ch].active


func play_bgm(track_id: int) -> bool:
	if not ContentRegistry.is_ready() or not ContentRegistry.has_music_track(track_id):
		return false
	_ensure_runners()
	_sync_rom_tables()
	var track: Dictionary = ContentRegistry.get_music_track(track_id)
	var blocks: Dictionary = track.get("blocks", {}) as Dictionary
	var ch_list: Array = track.get("channels", []) as Array

	for ch: ChannelRunner in _bgm_channels:
		ch.reset()
		_silence_channel(ch.hw_ch)
	if _apu != null:
		_apu.write_register(0x4015, 0x0F)

	var assigned_mask: int = 0
	for ch_v: Variant in ch_list:
		if not (ch_v is Dictionary):
			continue
		var ch_d: Dictionary = ch_v as Dictionary
		var reg_off: int = int(ch_d.get("reg_offset", 0))
		var start_addr: int = int(ch_d.get("start_addr", 0))
		var hw_ch: int = int(REG_TO_HW_CH.get(reg_off, 0))
		if reg_off == 0x0C and (assigned_mask & (1 << 3)) != 0:
			hw_ch = 4
		elif (assigned_mask & (1 << hw_ch)) != 0 and hw_ch < 4:
			for free_i: int in range(5):
				if (assigned_mask & (1 << free_i)) == 0:
					hw_ch = free_i
					break
		assigned_mask |= (1 << hw_ch)
		_bgm_channels[hw_ch].start_stream(blocks, start_addr, reg_off, hw_ch, false, 0)

	_current_bgm_id = track_id
	return true


func play_sfx(sfx_id: int) -> bool:
	if not ContentRegistry.is_ready() or not ContentRegistry.has_sfx_track(sfx_id):
		return false
	_ensure_runners()
	_sync_rom_tables()
	var sfx_data: Dictionary = ContentRegistry.get_sfx_track(sfx_id)
	var prio: int = int(sfx_data.get("priority", 0))
	var blocks: Dictionary = sfx_data.get("blocks", {}) as Dictionary
	var ch_list: Array = sfx_data.get("channels", []) as Array

	var started: bool = false
	for ch_v: Variant in ch_list:
		if not (ch_v is Dictionary):
			continue
		var ch_d: Dictionary = ch_v as Dictionary
		var reg_off: int = int(ch_d.get("reg_offset", 0))
		var start_addr: int = int(ch_d.get("start_addr", 0))
		var hw_ch: int = int(REG_TO_HW_CH.get(reg_off, 0))
		var s_runner: ChannelRunner = _sfx_channels[hw_ch]
		# Bank 29 ($8046): lower priority value = higher precedence
		if s_runner.active and s_runner.priority < prio:
			continue
		s_runner.start_stream(blocks, start_addr, reg_off, hw_ch, true, prio)
		started = true

	if started:
		_current_sfx_id = sfx_id
	return started


func stop_all() -> void:
	_ensure_runners()
	for ch: ChannelRunner in _bgm_channels:
		ch.reset()
	for s: ChannelRunner in _sfx_channels:
		s.reset()
	_current_bgm_id = -1
	_current_sfx_id = -1
	if _apu != null:
		for hw_i: int in range(4):
			_silence_channel(hw_i)
		_apu.write_register(0x4015, 0x00)


func step_frame() -> void:
	_ensure_runners()
	var any_sfx: bool = false
	for hw_ch: int in range(5):
		var sfx_r: ChannelRunner = _sfx_channels[hw_ch]
		var bgm_r: ChannelRunner = _bgm_channels[hw_ch]
		if sfx_r.active:
			_step_runner(sfx_r, true)
			if sfx_r.active:
				any_sfx = true
			elif bgm_r.active and _apu != null:
				_restore_bgm_channel(bgm_r)
			elif _apu != null:
				_silence_channel(hw_ch)
		if bgm_r.active:
			_step_runner(bgm_r, not sfx_r.active)
	if not any_sfx:
		_current_sfx_id = -1


func _restore_bgm_channel(ch: ChannelRunner) -> void:
	if _apu == null:
		return
	if ch.is_rested:
		_silence_channel(ch.hw_ch)
		return
	_apply_channel_volume_to_apu(ch)


func _step_runner(ch: ChannelRunner, output_to_apu: bool) -> void:
	if not ch.active:
		return

	# Step note gate, envelope & vibrato LFO while waiting out current note duration
	if ch.delay_frames > 1:
		ch.delay_frames -= 1
		if ch.gate_frames > 0:
			ch.gate_frames -= 1
			if ch.gate_frames == 0:
				_trigger_release_envelope(ch, output_to_apu)
		_step_envelope(ch, output_to_apu)
		ch.vibrato_tick += 1
		if ch.vibrato_id > 0 and ch.hw_ch < 3 and not ch.is_rested and ch.last_period > 0:
			var vib_delta: int = compute_vibrato_delta(ch.vibrato_id, ch.vibrato_tick)
			var mod_period: int = clampi(ch.last_period + vib_delta, 8, 0x7FF)
			if output_to_apu:
				_write_channel_period_only(ch, mod_period)
		return

	var ops: int = 0
	while ch.active and ops < MAX_COMMANDS_PER_TICK:
		ops += 1
		if not ch.blocks.has(ch.cur_block_key):
			ch.active = false
			break
		var stream: Array = ch.blocks[ch.cur_block_key] as Array
		if ch.cursor >= stream.size():
			ch.active = false
			break

		var b: int = int(stream[ch.cursor]) & 0xFF
		ch.cursor += 1

		if b < 0xE0:
			_handle_note_byte(ch, stream, b, output_to_apu)
			ch.delay_frames = maxi(1, ch.duration_ticks)
			break

		match b:
			0xE0:
				var a_reg: int = _read_arg(stream, ch)
				var l_reg: int = _read_arg(stream, ch)
				ch.dmc_addr_reg = a_reg
				ch.dmc_len_reg = l_reg
			0xE1:
				# Bank 29 $8413 writes global fade/attenuation ($0601); tempo is 0xF2 ($06AF,X)
				var _fade_arg: int = _read_arg(stream, ch)
			0xE2:
				# Bank 29 $83DC writes raw 11-bit period ($4002/$4003) and retriggers channel
				var p_lo: int = _read_arg(stream, ch)
				var p_hi_len: int = _read_arg(stream, ch)
				ch.last_period = clampi(p_lo | ((p_hi_len & 0x07) << 8), 8, 0x7FF)
				ch.is_rested = false
				_start_attack_envelope(ch)
				if output_to_apu:
					_write_channel_period_and_ctrl(ch, ch.last_period)
			0xE3:
				# Bank 29 $8404 -> $8666 adds signed 8-bit period delta to active period
				var delta_p: int = _to_signed_byte(_read_arg(stream, ch))
				ch.last_period = clampi(ch.last_period + delta_p, 8, 0x7FF)
				if output_to_apu and not ch.is_rested:
					_write_channel_period_only(ch, ch.last_period)
			0xF0:
				var v_arg: int = _read_arg(stream, ch)
				ch.master_vol = v_arg & 0x0F
				if output_to_apu:
					_apply_channel_volume_to_apu(ch)
			0xF1:
				var dv: int = _to_signed_byte(_read_arg(stream, ch))
				ch.master_vol = clampi(ch.master_vol + dv, 0, 15)
				if output_to_apu:
					_apply_channel_volume_to_apu(ch)
			0xF2:
				var t_idx: int = _read_arg(stream, ch)
				if not _tempo_tables.is_empty():
					ch.tempo_idx = clampi(t_idx, 0, _tempo_tables.size() - 1)
			0xF3:
				ch.duration_ticks = maxi(1, _read_arg(stream, ch))
			0xF4:
				ch.gate_ratio = _read_arg(stream, ch)
			0xF5:
				ch.base_note = _read_arg(stream, ch) & 0x7F
			0xF6:
				ch.env_id = _read_arg(stream, ch)
				if ch.env_id >= 0x80:
					ch.env_seq = []
					ch.env_vol = 15
			0xF7:
				ch.vibrato_id = _read_arg(stream, ch)
			0xF8:
				var j_lo: int = _read_arg(stream, ch)
				var j_hi: int = _read_arg(stream, ch)
				var j_ptr: int = j_lo | (j_hi << 8)
				if ch.blocks.has(str(j_ptr)):
					ch.cur_block_key = str(j_ptr)
					ch.cursor = 0
				else:
					ch.active = false
			0xFA:
				var c_lo: int = _read_arg(stream, ch)
				var c_hi: int = _read_arg(stream, ch)
				var c_ptr: int = c_lo | (c_hi << 8)
				if ch.call_stack.size() < MAX_LOOP_STACK and ch.blocks.has(str(c_ptr)):
					ch.call_stack.append({"block": ch.cur_block_key, "cursor": ch.cursor})
					ch.cur_block_key = str(c_ptr)
					ch.cursor = 0
			0xFB:
				if ch.call_stack.is_empty():
					ch.active = false
				else:
					var ret: Dictionary = ch.call_stack.pop_back() as Dictionary
					ch.cur_block_key = String(ret.get("block", ""))
					ch.cursor = int(ret.get("cursor", 0))
			0xFC:
				var l_cnt: int = _read_arg(stream, ch)
				if ch.loop_stack.size() < MAX_LOOP_STACK:
					ch.loop_stack.append({
						"count": l_cnt,
						"block": ch.cur_block_key,
						"cursor": ch.cursor,
					})
			0xFD:
				if not ch.loop_stack.is_empty():
					var top: Dictionary = ch.loop_stack[ch.loop_stack.size() - 1] as Dictionary
					var rem: int = int(top.get("count", 1)) - 1
					if rem > 0:
						top["count"] = rem
						ch.cur_block_key = String(top.get("block", ch.cur_block_key))
						ch.cursor = int(top.get("cursor", 0))
					else:
						ch.loop_stack.pop_back()
			0xFE:
				var _skip_v: int = _read_arg(stream, ch)
			0xFF:
				ch.active = false
				ch.is_rested = true
				if output_to_apu and _apu != null:
					_silence_channel(ch.hw_ch)
				break


func _read_arg(stream: Array, ch: ChannelRunner) -> int:
	if ch.cursor >= stream.size():
		return 0
	var val: int = int(stream[ch.cursor]) & 0xFF
	ch.cursor += 1
	return val


static func _to_signed_byte(b: int) -> int:
	return b - 256 if b >= 128 else b


static func decode_signed_5bit_note_offset(note_bits: int) -> int:
	var n: int = note_bits & 0x1F
	return (n - 32) if (n & 0x10) != 0 else n


func _start_attack_envelope(ch: ChannelRunner) -> void:
	if ch.env_id >= 0x80:
		ch.env_seq = []
		ch.env_vol = 15
		return
	var key: String = str(ch.env_id * 2)
	if _envelopes.has(key):
		ch.env_seq = _envelopes[key] as Array
		ch.env_cursor = 0
		ch.env_wait = 0
		ch.env_vol = 15
		_step_envelope(ch, false)
	else:
		ch.env_seq = []
		ch.env_vol = 15


func _trigger_release_envelope(ch: ChannelRunner, output_to_apu: bool) -> void:
	if ch.env_id < 0x80:
		var rel_key: String = str(ch.env_id * 2 + 1)
		if _envelopes.has(rel_key):
			ch.env_seq = _envelopes[rel_key] as Array
			ch.env_cursor = 0
			ch.env_wait = 0
			_step_envelope(ch, output_to_apu)
			return
	ch.is_rested = true
	if output_to_apu:
		_silence_channel(ch.hw_ch)


func _step_envelope(ch: ChannelRunner, output_to_apu: bool) -> void:
	if ch.env_seq.is_empty() or ch.is_rested:
		return
	if ch.env_wait > 1:
		ch.env_wait -= 1
		return
	var steps: int = 0
	while ch.env_cursor < ch.env_seq.size() and steps < 16:
		steps += 1
		var cmd: int = int(ch.env_seq[ch.env_cursor]) & 0xFF
		ch.env_cursor += 1
		if cmd < 0x20:
			ch.env_wait = maxi(1, cmd)
			break
		elif cmd < 0x40:
			ch.env_wait = maxi(1, cmd & 0x0F)
			break
		elif cmd < 0x60:
			ch.env_vol = cmd & 0x0F
		elif cmd < 0x80:
			var dv: int = cmd & 0x0F
			if dv >= 8:
				dv -= 16
			ch.env_vol = clampi(ch.env_vol + dv, 0, 15)
		elif cmd < 0xA0:
			ch.duty = cmd & 0x03
		elif cmd == 0xF0 and ch.env_cursor < ch.env_seq.size():
			ch.env_cursor += 1
		elif cmd == 0xFF:
			ch.env_seq = []
			break
	if output_to_apu:
		_apply_channel_volume_to_apu(ch)


func _handle_note_byte(ch: ChannelRunner, stream: Array, b: int, output_to_apu: bool) -> void:
	var dur_idx: int = (b >> 5) & 0x07
	if dur_idx == 6:
		ch.duration_ticks = maxi(1, _read_arg(stream, ch))
	elif dur_idx < 6 and ch.tempo_idx < _tempo_tables.size():
		var t_row: PackedInt32Array = _tempo_tables[ch.tempo_idx]
		if dur_idx < t_row.size():
			ch.duration_ticks = maxi(1, t_row[dur_idx])

	if ch.gate_ratio > 0:
		ch.gate_frames = maxi(1, (ch.gate_ratio * ch.duration_ticks) >> 8)
	else:
		ch.gate_frames = -1

	# Noise / DMC track channel (0x0C)
	if ch.reg_offset == 0x0C:
		var is_dmc_cmd: bool = (b & 0x10) != 0
		if is_dmc_cmd or ch.hw_ch == 4:
			var rate_idx: int = b & 0x0F
			if rate_idx == 0x0F:
				ch.is_rested = true
				return
			ch.is_rested = false
			if output_to_apu and _apu != null:
				var dpcm: PackedByteArray = ContentRegistry.get_dpcm_sample_bytes(ch.dmc_addr_reg, ch.dmc_len_reg)
				if not dpcm.is_empty():
					_apu.load_dpcm_sample(dpcm, rate_idx, false)
					_apu.write_register(0x4010, rate_idx)
					_apu.write_register(0x4015, _apu.get_active_channel_mask() | 0x1F)
			return
		var noise_p: int = b & 0x0F
		if noise_p == 0x0F:
			ch.is_rested = true
			if output_to_apu:
				_silence_channel(ch.hw_ch)
			return
		ch.is_rested = false
		_start_attack_envelope(ch)
		if output_to_apu and _apu != null:
			var vol_n: int = maxi(1, ch.effective_volume())
			_apu.write_register(0x400C, 0x30 | vol_n)
			_apu.write_register(0x400E, noise_p)
			_apu.write_register(0x400F, 0xF8)
		return

	# Melodic Pulse / Triangle channels
	var note_bits: int = b & 0x1F
	if note_bits == 0x10:
		ch.is_rested = true
		ch.gate_frames = -1
		if output_to_apu:
			_silence_channel(ch.hw_ch)
		return

	ch.is_rested = false
	ch.vibrato_tick = 0
	_start_attack_envelope(ch)
	if _period_table.is_empty():
		return
	var signed_offset: int = decode_signed_5bit_note_offset(note_bits)
	var pitched_idx: int = clampi(ch.base_note + signed_offset, 0, _period_table.size() - 1)
	var period: int = clampi(_period_table[pitched_idx] + ch.detune, 8, 0x7FF)
	ch.last_period = period

	if not output_to_apu or _apu == null:
		return

	_write_channel_period_and_ctrl(ch, period)


func _write_channel_period_and_ctrl(ch: ChannelRunner, period: int) -> void:
	if _apu == null:
		return
	var out_vol: int = ch.effective_volume()
	var ctrl: int = ((ch.duty & 3) << 6) | 0x30 | out_vol
	if ch.hw_ch == 0:
		_apu.write_register(0x4000, ctrl)
		_apu.write_register(0x4002, period & 0xFF)
		_apu.write_register(0x4003, 0xF8 | ((period >> 8) & 0x07))
	elif ch.hw_ch == 1:
		_apu.write_register(0x4004, ctrl)
		_apu.write_register(0x4006, period & 0xFF)
		_apu.write_register(0x4007, 0xF8 | ((period >> 8) & 0x07))
	elif ch.hw_ch == 2:
		_apu.write_register(0x4008, 0xFF if out_vol >= 4 else 0x00)
		_apu.write_register(0x400A, period & 0xFF)
		_apu.write_register(0x400B, 0xF8 | ((period >> 8) & 0x07))


func _write_channel_period_only(ch: ChannelRunner, period: int) -> void:
	if _apu == null:
		return
	if ch.hw_ch == 0:
		_apu.write_register(0x4002, period & 0xFF)
		_apu.write_register(0x4003, 0xF8 | ((period >> 8) & 0x07))
	elif ch.hw_ch == 1:
		_apu.write_register(0x4006, period & 0xFF)
		_apu.write_register(0x4007, 0xF8 | ((period >> 8) & 0x07))
	elif ch.hw_ch == 2:
		_apu.write_register(0x400A, period & 0xFF)
		_apu.write_register(0x400B, 0xF8 | ((period >> 8) & 0x07))


func _apply_channel_volume_to_apu(ch: ChannelRunner) -> void:
	if _apu == null:
		return
	var out_vol: int = ch.effective_volume()
	var ctrl_val: int = ((ch.duty & 3) << 6) | 0x30 | out_vol
	if ch.hw_ch == 0:
		_apu.write_register(0x4000, ctrl_val)
	elif ch.hw_ch == 1:
		_apu.write_register(0x4004, ctrl_val)
	elif ch.hw_ch == 2:
		if out_vol >= 4:
			_apu.write_register(0x4008, 0xFF)
			_apu.write_register(0x400B, 0xF8 | ((ch.last_period >> 8) & 0x07))
		else:
			_apu.write_register(0x4008, 0x00)
			_apu.write_register(0x400B, (ch.last_period >> 8) & 0x07)
	elif ch.hw_ch == 3:
		_apu.write_register(0x400C, 0x30 | out_vol)


func _silence_channel(hw_ch: int) -> void:
	if _apu == null:
		return
	if hw_ch == 0:
		_apu.write_register(0x4000, 0x30)
	elif hw_ch == 1:
		_apu.write_register(0x4004, 0x30)
	elif hw_ch == 2:
		_apu.write_register(0x4008, 0x00)
		_apu.write_register(0x400B, 0x00)
	elif hw_ch == 3:
		_apu.write_register(0x400C, 0x30)


static func compute_vibrato_delta(vibrato_id: int, tick: int) -> int:
	if vibrato_id <= 0:
		return 0
	var amp: int = clampi(vibrato_id & 0x07, 1, 4)
	var step: int = (tick >> 1) & 0x03
	match step:
		1:
			return amp
		3:
			return -amp
		_:
			return 0


func _on_bgm_requested(track_id: int) -> void:
	play_bgm(track_id)


func _on_sfx_requested(sfx_id: int) -> void:
	play_sfx(sfx_id)
