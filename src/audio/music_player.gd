class_name MusicPlayer
extends Node
## PRG-ROM Music & SFX sequence interpreter driving APUEngine at 60 TPS
## with priority-based SFX channel overrides and zero BGM drift.

const Constants = preload("res://src/core/constants.gd")
const APUEngine = preload("res://src/audio/apu_engine.gd")

const MAX_COMMANDS_PER_TICK: int = 32
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
	var tempo_idx: int = 0
	var duty: int = 2
	var volume: int = 12
	var transpose: int = 0
	var octave_offset: int = 0
	var detune: int = 0
	var last_period: int = 0
	var tie_active: bool = false
	var dmc_addr_reg: int = 240
	var dmc_len_reg: int = 11
	var loop_count: int = 0
	var loop_block: String = ""
	var loop_cursor: int = 0
	var call_stack: Array[Dictionary] = []

	func reset() -> void:
		active = false
		blocks = {}
		cur_block_key = ""
		cursor = 0
		delay_frames = 0
		duration_ticks = 1
		tempo_idx = 0
		duty = 2
		volume = 12
		transpose = 0
		octave_offset = 0
		detune = 0
		last_period = 0
		tie_active = false
		loop_count = 0
		loop_block = ""
		loop_cursor = 0
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


var _apu: APUEngine = null
var _bgm_channels: Array[ChannelRunner] = []
var _sfx_channels: Array[ChannelRunner] = []
var _current_bgm_id: int = -1
var _current_sfx_id: int = -1
var _period_table: PackedInt32Array = PackedInt32Array()
var _tempo_tables: Array[PackedInt32Array] = []


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
		# Second 0x0C channel in HAL headers routes to DMC slot 4
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
		# Lower priority value or higher urgency: allow preemption if active SFX priority >= new or higher
		if s_runner.active and s_runner.priority > prio:
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
				# Restore BGM channel gating cleanly after SFX finishes
				_restore_bgm_channel(bgm_r)
		if bgm_r.active:
			_step_runner(bgm_r, not sfx_r.active)
	if not any_sfx:
		_current_sfx_id = -1


func _restore_bgm_channel(ch: ChannelRunner) -> void:
	if _apu == null:
		return
	var ctrl_val: int = ((ch.duty & 3) << 6) | 0x30 | clampi(ch.volume, 0, 15)
	if ch.hw_ch == 0:
		_apu.write_register(0x4000, ctrl_val)
	elif ch.hw_ch == 1:
		_apu.write_register(0x4004, ctrl_val)
	elif ch.hw_ch == 2:
		_apu.write_register(0x4008, 0x80 | 0x7F)
	elif ch.hw_ch == 3:
		_apu.write_register(0x400C, 0x30 | clampi(ch.volume, 0, 15))


func _step_runner(ch: ChannelRunner, output_to_apu: bool) -> void:
	if not ch.active:
		return
	if ch.delay_frames > 1:
		ch.delay_frames -= 1
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
			_handle_note_byte(ch, b, output_to_apu)
			ch.delay_frames = maxi(1, ch.duration_ticks)
			break

		match b:
			0xE0:
				var a_reg: int = _read_arg(stream, ch)
				var l_reg: int = _read_arg(stream, ch)
				ch.dmc_addr_reg = a_reg
				ch.dmc_len_reg = l_reg
			0xE1:
				var arg: int = _read_arg(stream, ch)
				ch.tempo_idx = arg % maxi(1, _tempo_tables.size())
			0xE2:
				var d_arg: int = _read_arg(stream, ch)
				var _m_arg: int = _read_arg(stream, ch)
				ch.duty = (d_arg >> 6) & 3
			0xE3:
				ch.detune = _to_signed_byte(_read_arg(stream, ch))
			0xF0:
				var d_val: int = _read_arg(stream, ch)
				ch.duty = d_val & 3
				ch.volume = clampi(d_val & 0x0F, 1, 15)
			0xF1:
				ch.octave_offset += _to_signed_byte(_read_arg(stream, ch))
			0xF2:
				var t_idx: int = _read_arg(stream, ch)
				if not _tempo_tables.is_empty():
					ch.tempo_idx = clampi(t_idx, 0, _tempo_tables.size() - 1)
			0xF3:
				ch.duration_ticks = maxi(1, _read_arg(stream, ch))
			0xF4:
				var vol_v: int = _read_arg(stream, ch)
				ch.volume = clampi((vol_v >> 4) & 0x0F if vol_v > 15 else vol_v, 0, 15)
			0xF5:
				ch.transpose = _to_signed_byte(_read_arg(stream, ch))
			0xF6:
				var inst_v: int = _read_arg(stream, ch)
				if inst_v >= 0x80:
					ch.volume = clampi(inst_v & 0x0F, 0, 15)
				else:
					ch.volume = clampi(10 + (inst_v & 0x05), 4, 15)
			0xF7:
				var _mod_v: int = _read_arg(stream, ch)
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
				ch.loop_count = _read_arg(stream, ch)
				ch.loop_block = ch.cur_block_key
				ch.loop_cursor = ch.cursor
			0xFD:
				if ch.loop_count > 1:
					ch.loop_count -= 1
					ch.cur_block_key = ch.loop_block
					ch.cursor = ch.loop_cursor
			0xFE:
				var _skip_v: int = _read_arg(stream, ch)
			0xFF:
				ch.active = false
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


func _handle_note_byte(ch: ChannelRunner, b: int, output_to_apu: bool) -> void:
	var dur_idx: int = (b >> 5) & 0x07
	if dur_idx < 6 and ch.tempo_idx < _tempo_tables.size():
		var t_row: PackedInt32Array = _tempo_tables[ch.tempo_idx]
		if dur_idx < t_row.size():
			ch.duration_ticks = maxi(1, t_row[dur_idx])

	if not output_to_apu or _apu == null:
		return

	# Noise / DMC track channel (0x0C)
	if ch.reg_offset == 0x0C:
		var is_dmc_cmd: bool = (b & 0x10) != 0
		if is_dmc_cmd or ch.hw_ch == 4:
			var rate_idx: int = b & 0x0F
			if rate_idx == 0x0F:
				return
			var dpcm: PackedByteArray = ContentRegistry.get_dpcm_sample_bytes(ch.dmc_addr_reg, ch.dmc_len_reg)
			if not dpcm.is_empty():
				_apu.load_dpcm_sample(dpcm, rate_idx, false)
				_apu.write_register(0x4010, rate_idx)
				_apu.write_register(0x4015, _apu.get_active_channel_mask() | 0x1F)
			return
		var noise_p: int = b & 0x0F
		if noise_p == 0x0F:
			_apu.write_register(0x400C, 0x30)
		else:
			_apu.write_register(0x400C, 0x30 | clampi(ch.volume, 1, 15))
			_apu.write_register(0x400E, noise_p)
			_apu.write_register(0x400F, 0xF8)
		return

	# Melodic Pulse / Triangle channels
	var note_idx: int = b & 0x1F
	if note_idx == 0x10 or (b & 0xE0) == 0xC0:
		# Rest or tie/slur
		if note_idx == 0x10 and (b & 0xE0) != 0xC0:
			_silence_channel(ch.hw_ch)
		return

	if _period_table.is_empty():
		return
	var pitched_idx: int = clampi(note_idx + ch.transpose + ch.octave_offset * 12, 0, _period_table.size() - 1)
	var period: int = clampi(_period_table[pitched_idx] + ch.detune, 8, 0x7FF)
	ch.last_period = period

	var ctrl: int = ((ch.duty & 3) << 6) | 0x30 | clampi(ch.volume, 1, 15)
	if ch.hw_ch == 0:
		_apu.write_register(0x4000, ctrl)
		_apu.write_register(0x4002, period & 0xFF)
		_apu.write_register(0x4003, 0xF8 | ((period >> 8) & 0x07))
	elif ch.hw_ch == 1:
		_apu.write_register(0x4004, ctrl)
		_apu.write_register(0x4006, period & 0xFF)
		_apu.write_register(0x4007, 0xF8 | ((period >> 8) & 0x07))
	elif ch.hw_ch == 2:
		_apu.write_register(0x4008, 0xFF)
		_apu.write_register(0x400A, period & 0xFF)
		_apu.write_register(0x400B, 0xF8 | ((period >> 8) & 0x07))


func _silence_channel(hw_ch: int) -> void:
	if _apu == null:
		return
	if hw_ch == 0:
		_apu.write_register(0x4000, 0x30)
	elif hw_ch == 1:
		_apu.write_register(0x4004, 0x30)
	elif hw_ch == 2:
		_apu.write_register(0x4008, 0x00)
	elif hw_ch == 3:
		_apu.write_register(0x400C, 0x30)


func _on_bgm_requested(track_id: int) -> void:
	play_bgm(track_id)


func _on_sfx_requested(sfx_id: int) -> void:
	play_sfx(sfx_id)
