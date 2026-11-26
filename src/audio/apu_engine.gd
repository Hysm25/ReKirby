class_name APUEngine
extends Node
## Real-time 44,100 Hz NES 2A03 5-Channel APU Synthesizer (Pulse 1/2, Triangle, Noise, DMC)
## stepped deterministically at 60 TPS via AudioStreamGeneratorPlayback or offline buffers.

const Constants = preload("res://src/core/constants.gd")

const SAMPLE_RATE: int = 44100
const SAMPLES_PER_FRAME: int = 735 # 44100 / 60
const NES_CPU_CLOCK: float = Constants.NES_CPU_FREQ
const CYCLES_PER_SAMPLE: float = NES_CPU_CLOCK / float(SAMPLE_RATE)

const DUTY_CYCLES: Array = [
	[0, 1, 0, 0, 0, 0, 0, 0], # 12.5%
	[0, 1, 1, 0, 0, 0, 0, 0], # 25%
	[0, 1, 1, 1, 1, 0, 0, 0], # 50%
	[1, 0, 0, 1, 1, 1, 1, 1], # 75%
]

const TRIANGLE_STEPS: Array = [
	15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0,
	0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
]

const LENGTH_TABLE: Array = [
	10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14,
	12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30,
]

const NOISE_PERIOD_TABLE: Array = [
	4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068,
]

const DMC_RATE_TABLE: Array = [
	428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54,
]


class PulseChannel extends RefCounted:
	var is_pulse_2: bool = false
	var enabled: bool = false
	var duty: int = 2
	var halt_length: bool = false
	var constant_vol: bool = true
	var volume: int = 0
	var env_start: bool = false
	var env_divider: int = 0
	var env_decay: int = 15
	var sweep_enabled: bool = false
	var sweep_period: int = 0
	var sweep_negate: bool = false
	var sweep_shift: int = 0
	var sweep_reload: bool = false
	var sweep_divider: int = 0
	var period: int = 0
	var length_counter: int = 0
	var timer_acc: float = 0.0
	var duty_pos: int = 0

	func reset() -> void:
		enabled = false
		duty = 2
		halt_length = false
		constant_vol = true
		volume = 0
		env_start = false
		env_divider = 0
		env_decay = 15
		sweep_enabled = false
		sweep_period = 0
		sweep_negate = false
		sweep_shift = 0
		sweep_reload = false
		sweep_divider = 0
		period = 0
		length_counter = 0
		timer_acc = 0.0
		duty_pos = 0

	func get_sweep_target_period() -> int:
		var delta: int = period >> sweep_shift
		if sweep_negate:
			return period - delta - (0 if is_pulse_2 else 1)
		return period + delta


	func compute_hardware_sweep_edge() -> float:
		if is_muted_by_hardware():
			return 0.0
		var target: int = get_sweep_target_period()
		if target > 0x7FF:
			return 0.0
		return 1.0


	func is_muted_by_hardware() -> bool:
		if not enabled or length_counter <= 0 or period < 8 or period > 0x7FF:
			return true
		if get_sweep_target_period() > 0x7FF:
			return true
		return false

	func clock_envelope() -> void:
		if env_start:
			env_start = false
			env_decay = 15
			env_divider = volume
		else:
			if env_divider > 0:
				env_divider -= 1
			else:
				env_divider = volume
				if env_decay > 0:
					env_decay -= 1
				elif halt_length:
					env_decay = 15

	func clock_sweep() -> void:
		var target: int = get_sweep_target_period()
		if sweep_divider == 0 and sweep_enabled and sweep_shift > 0 and period >= 8 and target <= 0x7FF:
			period = maxi(0, target)
		if sweep_divider == 0 or sweep_reload:
			sweep_divider = sweep_period
			sweep_reload = false
		else:
			sweep_divider -= 1

	func sample(cpu_cycles: float) -> int:
		if period >= 8:
			timer_acc -= cpu_cycles * 0.5
			var guard: int = 0
			var reload_val: float = float(period + 1)
			while timer_acc <= 0.0 and guard < 64:
				timer_acc += reload_val
				duty_pos = (duty_pos + 1) & 7
				guard += 1
			if timer_acc <= 0.0:
				timer_acc = reload_val
		if is_muted_by_hardware():
			return 0
		var duty_seq: Array = DUTY_CYCLES[duty & 3] as Array
		if int(duty_seq[duty_pos]) == 0:
			return 0
		return volume if constant_vol else env_decay


class TriangleChannel extends RefCounted:
	var enabled: bool = false
	var control_flag: bool = false
	var linear_reload_val: int = 0
	var linear_reload_flag: bool = false
	var linear_counter: int = 0
	var length_counter: int = 0
	var period: int = 0
	var timer_acc: float = 0.0
	var seq_pos: int = 0

	func reset() -> void:
		enabled = false
		control_flag = false
		linear_reload_val = 0
		linear_reload_flag = false
		linear_counter = 0
		length_counter = 0
		period = 0
		timer_acc = 0.0
		seq_pos = 0

	func clock_linear() -> void:
		if linear_reload_flag:
			linear_counter = linear_reload_val
		elif linear_counter > 0:
			linear_counter -= 1
		if not control_flag:
			linear_reload_flag = false

	func sample(cpu_cycles: float) -> int:
		if enabled and length_counter > 0 and linear_counter > 0 and period >= 8:
			timer_acc -= cpu_cycles
			var guard: int = 0
			var reload_val: float = float(period + 1)
			while timer_acc <= 0.0 and guard < 64:
				timer_acc += reload_val
				seq_pos = (seq_pos + 1) & 31
				guard += 1
			if timer_acc <= 0.0:
				timer_acc = reload_val
		if not enabled or length_counter <= 0 or linear_counter <= 0 or period < 8:
			return 0
		return int(TRIANGLE_STEPS[seq_pos])


class NoiseChannel extends RefCounted:
	var enabled: bool = false
	var halt_length: bool = false
	var constant_vol: bool = true
	var volume: int = 0
	var env_start: bool = false
	var env_divider: int = 0
	var env_decay: int = 15
	var periodic_mode: bool = false
	var period_idx: int = 0
	var length_counter: int = 0
	var lfsr: int = 1
	var timer_acc: float = 0.0

	func reset() -> void:
		enabled = false
		halt_length = false
		constant_vol = true
		volume = 0
		env_start = false
		env_divider = 0
		env_decay = 15
		periodic_mode = false
		period_idx = 0
		length_counter = 0
		lfsr = 1
		timer_acc = 0.0

	func clock_envelope() -> void:
		if env_start:
			env_start = false
			env_decay = 15
			env_divider = volume
		else:
			if env_divider > 0:
				env_divider -= 1
			else:
				env_divider = volume
				if env_decay > 0:
					env_decay -= 1
				elif halt_length:
					env_decay = 15

	func step_lfsr() -> void:
		var bit0: int = lfsr & 1
		var tap_shift: int = 6 if periodic_mode else 1
		var tap_bit: int = (lfsr >> tap_shift) & 1
		var feedback: int = bit0 ^ tap_bit
		lfsr = (lfsr >> 1) | (feedback << 14)

	func sample(cpu_cycles: float) -> int:
		var n_period: float = float(NOISE_PERIOD_TABLE[period_idx & 0x0F])
		timer_acc -= cpu_cycles
		var guard: int = 0
		while timer_acc <= 0.0 and guard < 64:
			timer_acc += n_period
			step_lfsr()
			guard += 1
		if timer_acc <= 0.0:
			timer_acc = n_period
		if not enabled or length_counter <= 0 or (lfsr & 1) != 0:
			return 0
		return volume if constant_vol else env_decay


class DMCChannel extends RefCounted:
	var enabled: bool = false
	var loop_flag: bool = false
	var rate_idx: int = 0
	var addr_reg: int = 0
	var len_reg: int = 0
	var output_level: int = 0 # 7-bit 0..127
	var sample_bytes: PackedByteArray = PackedByteArray()
	var byte_cursor: int = 0
	var bit_cursor: int = 0
	var current_byte: int = 0
	var active: bool = false
	var timer_acc: float = 0.0

	func reset() -> void:
		enabled = false
		loop_flag = false
		rate_idx = 0
		addr_reg = 0
		len_reg = 0
		output_level = 0
		sample_bytes = PackedByteArray()
		byte_cursor = 0
		bit_cursor = 0
		current_byte = 0
		active = false
		timer_acc = 0.0

	func load_sample(data: PackedByteArray, should_loop: bool = false) -> void:
		sample_bytes = data
		loop_flag = should_loop
		byte_cursor = 0
		bit_cursor = 0
		if not sample_bytes.is_empty():
			current_byte = sample_bytes[0]
			active = true
			enabled = true
		else:
			active = false

	func sample(cpu_cycles: float) -> int:
		if active and not sample_bytes.is_empty():
			var d_period: float = float(DMC_RATE_TABLE[rate_idx & 0x0F])
			timer_acc -= cpu_cycles
			var guard: int = 0
			while timer_acc <= 0.0 and guard < 32 and active:
				timer_acc += d_period
				var delta_bit: int = (current_byte >> bit_cursor) & 1
				if delta_bit == 1:
					if output_level <= 125:
						output_level += 2
				else:
					if output_level >= 2:
						output_level -= 2
				bit_cursor += 1
				if bit_cursor >= 8:
					bit_cursor = 0
					byte_cursor += 1
					if byte_cursor >= sample_bytes.size():
						if loop_flag:
							byte_cursor = 0
						else:
							active = false
							break
					current_byte = sample_bytes[byte_cursor]
				guard += 1
		return output_level


var _pulse1: PulseChannel = PulseChannel.new()
var _pulse2: PulseChannel = PulseChannel.new()
var _triangle: TriangleChannel = TriangleChannel.new()
var _noise: NoiseChannel = NoiseChannel.new()
var _dmc: DMCChannel = DMCChannel.new()

var _frame_quarter_counter: int = 0
var _dc_lp: float = 0.0
var _last_peak: float = 0.0
var _master_gain: float = 0.85

var _player: AudioStreamPlayer = null
var _generator: AudioStreamGenerator = null
var _playback: AudioStreamGeneratorPlayback = null


func _ready() -> void:
	name = "APUEngine"
	_pulse2.is_pulse_2 = true
	_setup_audio_stream()


func _setup_audio_stream() -> void:
	if _player != null:
		return
	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = float(SAMPLE_RATE)
	_generator.buffer_length = 0.05
	_player = AudioStreamPlayer.new()
	_player.name = "APUStreamPlayer"
	_player.stream = _generator
	add_child(_player)
	if DisplayServer.get_name() != "headless":
		_player.play()
		var pb: AudioStreamPlayback = _player.get_stream_playback()
		if pb is AudioStreamGeneratorPlayback:
			_playback = pb as AudioStreamGeneratorPlayback


func reset_apu() -> void:
	_pulse1.reset()
	_pulse2.reset()
	_pulse2.is_pulse_2 = true
	_triangle.reset()
	_noise.reset()
	_dmc.reset()
	_frame_quarter_counter = 0
	_dc_lp = 0.0
	_last_peak = 0.0


func set_master_gain(gain: float) -> void:
	_master_gain = clampf(gain, 0.0, 1.0)


func get_last_peak_amplitude() -> float:
	return _last_peak


func get_active_channel_mask() -> int:
	var mask: int = 0
	if _pulse1.enabled and _pulse1.length_counter > 0:
		mask |= 0x01
	if _pulse2.enabled and _pulse2.length_counter > 0:
		mask |= 0x02
	if _triangle.enabled and _triangle.length_counter > 0 and _triangle.linear_counter > 0:
		mask |= 0x04
	if _noise.enabled and _noise.length_counter > 0:
		mask |= 0x08
	if _dmc.active:
		mask |= 0x10
	return mask


func get_dmc_counter() -> int:
	return _dmc.output_level


func get_noise_lfsr() -> int:
	return _noise.lfsr


func is_dmc_playing() -> bool:
	return _dmc.active


func load_dpcm_sample(sample_data: PackedByteArray, rate_idx: int = 15, loop_flag: bool = false) -> void:
	_dmc.rate_idx = rate_idx & 0x0F
	_dmc.load_sample(sample_data, loop_flag)


func write_register(addr: int, value: int) -> void:
	var v: int = value & 0xFF
	match addr:
		0x4000:
			_pulse1.duty = (v >> 6) & 3
			_pulse1.halt_length = (v & 0x20) != 0
			_pulse1.constant_vol = (v & 0x10) != 0
			_pulse1.volume = v & 0x0F
		0x4001:
			_pulse1.sweep_enabled = (v & 0x80) != 0
			_pulse1.sweep_period = (v >> 4) & 7
			_pulse1.sweep_negate = (v & 0x08) != 0
			_pulse1.sweep_shift = v & 7
			_pulse1.sweep_reload = true
		0x4002:
			_pulse1.period = (_pulse1.period & 0x700) | v
		0x4003:
			_pulse1.period = (_pulse1.period & 0xFF) | ((v & 7) << 8)
			if _pulse1.enabled:
				_pulse1.length_counter = LENGTH_TABLE[(v >> 3) & 0x1F]
			_pulse1.duty_pos = 0
			_pulse1.env_start = true
		0x4004:
			_pulse2.duty = (v >> 6) & 3
			_pulse2.halt_length = (v & 0x20) != 0
			_pulse2.constant_vol = (v & 0x10) != 0
			_pulse2.volume = v & 0x0F
		0x4005:
			_pulse2.sweep_enabled = (v & 0x80) != 0
			_pulse2.sweep_period = (v >> 4) & 7
			_pulse2.sweep_negate = (v & 0x08) != 0
			_pulse2.sweep_shift = v & 7
			_pulse2.sweep_reload = true
		0x4006:
			_pulse2.period = (_pulse2.period & 0x700) | v
		0x4007:
			_pulse2.period = (_pulse2.period & 0xFF) | ((v & 7) << 8)
			if _pulse2.enabled:
				_pulse2.length_counter = LENGTH_TABLE[(v >> 3) & 0x1F]
			_pulse2.duty_pos = 0
			_pulse2.env_start = true
		0x4008:
			_triangle.control_flag = (v & 0x80) != 0
			_triangle.linear_reload_val = v & 0x7F
		0x400A:
			_triangle.period = (_triangle.period & 0x700) | v
		0x400B:
			_triangle.period = (_triangle.period & 0xFF) | ((v & 7) << 8)
			if _triangle.enabled:
				_triangle.length_counter = LENGTH_TABLE[(v >> 3) & 0x1F]
			_triangle.linear_reload_flag = true
		0x400C:
			_noise.halt_length = (v & 0x20) != 0
			_noise.constant_vol = (v & 0x10) != 0
			_noise.volume = v & 0x0F
		0x400E:
			_noise.periodic_mode = (v & 0x80) != 0
			_noise.period_idx = v & 0x0F
		0x400F:
			if _noise.enabled:
				_noise.length_counter = LENGTH_TABLE[(v >> 3) & 0x1F]
			_noise.env_start = true
		0x4010:
			_dmc.loop_flag = (v & 0x40) != 0
			_dmc.rate_idx = v & 0x0F
		0x4011:
			_dmc.output_level = v & 0x7F
		0x4012:
			_dmc.addr_reg = v
		0x4013:
			_dmc.len_reg = v
		0x4015:
			_pulse1.enabled = (v & 0x01) != 0
			if not _pulse1.enabled:
				_pulse1.length_counter = 0
			_pulse2.enabled = (v & 0x02) != 0
			if not _pulse2.enabled:
				_pulse2.length_counter = 0
			_triangle.enabled = (v & 0x04) != 0
			if not _triangle.enabled:
				_triangle.length_counter = 0
			_noise.enabled = (v & 0x08) != 0
			if not _noise.enabled:
				_noise.length_counter = 0
			var dmc_en: bool = (v & 0x10) != 0
			_dmc.enabled = dmc_en
			if not dmc_en:
				_dmc.active = false
			elif not _dmc.sample_bytes.is_empty():
				_dmc.load_sample(_dmc.sample_bytes, _dmc.loop_flag)
		_:
			pass


func clock_frame_sequencer() -> void:
	# Step 4 quarter-frames (240 Hz) per 60 Hz NTSC frame; 2 half-frames (120 Hz)
	for step_idx: int in range(4):
		_pulse1.clock_envelope()
		_pulse2.clock_envelope()
		_noise.clock_envelope()
		_triangle.clock_linear()
		if (step_idx & 1) == 1:
			_clock_half_frame_units()
		_frame_quarter_counter = (_frame_quarter_counter + 1) & 3


func _clock_half_frame_units() -> void:
	if not _pulse1.halt_length and _pulse1.length_counter > 0:
		_pulse1.length_counter -= 1
	if not _pulse2.halt_length and _pulse2.length_counter > 0:
		_pulse2.length_counter -= 1
	if not _triangle.control_flag and _triangle.length_counter > 0:
		_triangle.length_counter -= 1
	if not _noise.halt_length and _noise.length_counter > 0:
		_noise.length_counter -= 1
	_pulse1.clock_sweep()
	_pulse2.clock_sweep()


func synthesize_frame_samples(sample_count: int = SAMPLES_PER_FRAME) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(sample_count)
	var peak: float = 0.0

	# Snapshot channel state into fast local scalars for inner DSP loop
	var p1_period: int = _pulse1.period
	var p1_reload: float = float(p1_period + 1)
	var p1_acc: float = _pulse1.timer_acc
	var p1_pos: int = _pulse1.duty_pos
	var p1_duty_arr: Array = DUTY_CYCLES[_pulse1.duty & 3] as Array
	var p1_vol: int = 0 if _pulse1.is_muted_by_hardware() else (_pulse1.volume if _pulse1.constant_vol else _pulse1.env_decay)

	var p2_period: int = _pulse2.period
	var p2_reload: float = float(p2_period + 1)
	var p2_acc: float = _pulse2.timer_acc
	var p2_pos: int = _pulse2.duty_pos
	var p2_duty_arr: Array = DUTY_CYCLES[_pulse2.duty & 3] as Array
	var p2_vol: int = 0 if _pulse2.is_muted_by_hardware() else (_pulse2.volume if _pulse2.constant_vol else _pulse2.env_decay)

	var tri_active: bool = _triangle.enabled and _triangle.length_counter > 0 and _triangle.linear_counter > 0 and _triangle.period >= 8
	var tri_out_on: bool = tri_active
	var tri_reload: float = float(_triangle.period + 1)
	var tri_acc: float = _triangle.timer_acc
	var tri_pos: int = _triangle.seq_pos

	var noi_on: bool = _noise.enabled and _noise.length_counter > 0
	var noi_vol: int = _noise.volume if _noise.constant_vol else _noise.env_decay
	var noi_period: float = float(int(NOISE_PERIOD_TABLE[_noise.period_idx & 0x0F]))
	var noi_acc: float = _noise.timer_acc
	var noi_lfsr: int = _noise.lfsr
	var noi_tap_shift: int = 6 if _noise.periodic_mode else 1

	var dmc_active: bool = _dmc.active and not _dmc.sample_bytes.is_empty()
	var dmc_bytes: PackedByteArray = _dmc.sample_bytes
	var dmc_bytes_size: int = dmc_bytes.size()
	var dmc_period: float = float(int(DMC_RATE_TABLE[_dmc.rate_idx & 0x0F]))
	var dmc_acc: float = _dmc.timer_acc
	var dmc_level: int = _dmc.output_level
	var dmc_byte_cur: int = _dmc.byte_cursor
	var dmc_bit_cur: int = _dmc.bit_cursor
	var dmc_cur_byte: int = _dmc.current_byte
	var dmc_loop: bool = _dmc.loop_flag

	var half_cyc: float = CYCLES_PER_SAMPLE * 0.5
	var full_cyc: float = CYCLES_PER_SAMPLE
	var dc_lp: float = _dc_lp
	var gain_mul: float = _master_gain

	for i: int in range(sample_count):
		var p1: int = 0
		if p1_period >= 8 and p1_vol > 0:
			p1_acc -= half_cyc
			if p1_acc <= 0.0:
				var steps1: int = mini(63, int(-p1_acc / p1_reload) + 1)
				p1_acc += float(steps1) * p1_reload
				p1_pos = (p1_pos + steps1) & 7
			if int(p1_duty_arr[p1_pos]) != 0:
				p1 = p1_vol

		var p2: int = 0
		if p2_period >= 8 and p2_vol > 0:
			p2_acc -= half_cyc
			if p2_acc <= 0.0:
				var steps2: int = mini(63, int(-p2_acc / p2_reload) + 1)
				p2_acc += float(steps2) * p2_reload
				p2_pos = (p2_pos + steps2) & 7
			if int(p2_duty_arr[p2_pos]) != 0:
				p2 = p2_vol

		if tri_active:
			tri_acc -= full_cyc
			if tri_acc <= 0.0:
				var steps_t: int = mini(63, int(-tri_acc / tri_reload) + 1)
				tri_acc += float(steps_t) * tri_reload
				tri_pos = (tri_pos + steps_t) & 31
		var tri: int = int(TRIANGLE_STEPS[tri_pos]) if tri_out_on else 0

		noi_acc -= full_cyc
		if noi_acc <= 0.0:
			var steps_n: int = mini(16, int(-noi_acc / noi_period) + 1)
			noi_acc += float(steps_n) * noi_period
			for _ns: int in range(steps_n):
				var bit0: int = noi_lfsr & 1
				var tap_bit: int = (noi_lfsr >> noi_tap_shift) & 1
				noi_lfsr = (noi_lfsr >> 1) | ((bit0 ^ tap_bit) << 14)
		var noi: int = noi_vol if (noi_on and (noi_lfsr & 1) == 0) else 0

		if dmc_active:
			dmc_acc -= full_cyc
			var dmc_guard: int = 0
			while dmc_acc <= 0.0 and dmc_active and dmc_guard < 16:
				dmc_guard += 1
				dmc_acc += dmc_period
				if ((dmc_cur_byte >> dmc_bit_cur) & 1) == 1:
					if dmc_level <= 125:
						dmc_level += 2
				elif dmc_level >= 2:
					dmc_level -= 2
				dmc_bit_cur += 1
				if dmc_bit_cur >= 8:
					dmc_bit_cur = 0
					dmc_byte_cur += 1
					if dmc_byte_cur >= dmc_bytes_size:
						if dmc_loop:
							dmc_byte_cur = 0
						else:
							dmc_active = false
							break
					dmc_cur_byte = dmc_bytes[dmc_byte_cur]

		var raw_unipolar: float = (
			(float(p1) / 15.0) * 0.22
			+ (float(p2) / 15.0) * 0.22
			+ (float(tri) / 15.0) * 0.28
			+ (float(noi) / 15.0) * 0.10
			+ (float(dmc_level) / 127.0) * 0.18
		)
		dc_lp = dc_lp * 0.996 + raw_unipolar * 0.004
		var sample_val: float = clampf((raw_unipolar - dc_lp) * gain_mul, -0.99, 0.99)
		out[i] = sample_val
		peak = maxf(peak, absf(sample_val))

	# Write back mutable DSP counters
	_pulse1.timer_acc = p1_acc
	_pulse1.duty_pos = p1_pos
	_pulse2.timer_acc = p2_acc
	_pulse2.duty_pos = p2_pos
	_triangle.timer_acc = tri_acc
	_triangle.seq_pos = tri_pos
	_noise.timer_acc = noi_acc
	_noise.lfsr = noi_lfsr
	_dmc.timer_acc = dmc_acc
	_dmc.output_level = dmc_level
	_dmc.byte_cursor = dmc_byte_cur
	_dmc.bit_cursor = dmc_bit_cur
	_dmc.current_byte = dmc_cur_byte
	_dmc.active = dmc_active
	_dc_lp = dc_lp
	_last_peak = peak
	return out


func step_audio_frame() -> PackedFloat32Array:
	clock_frame_sequencer()
	var count: int = SAMPLES_PER_FRAME
	if _playback != null:
		var avail: int = _playback.get_frames_available()
		if avail <= 0:
			return PackedFloat32Array()
		count = mini(SAMPLES_PER_FRAME, avail)
	var buf: PackedFloat32Array = synthesize_frame_samples(count)
	if _playback != null and buf.size() > 0:
		for s: float in buf:
			_playback.push_frame(Vector2(s, s))
	return buf
