extends RefCounted
## Verification tests for Phase 3: 2A03 5-channel APU waveform/sweep/envelope synthesis,
## 93-step periodic & white Noise LFSR, 1-bit DMC delta modulation, non-clipping headroom,
## 60 TPS stream stability, and live PRG-ROM AudioExtractor + MusicPlayer sequencing.

const Constants = preload("res://src/core/constants.gd")
const APUEngine = preload("res://src/audio/apu_engine.gd")
const MusicPlayer = preload("res://src/audio/music_player.gd")
const AudioExtractor = preload("res://src/importer/audio_extractor.gd")
const ROMImporter = preload("res://src/importer/rom_importer.gd")
const MAX_CLEANUP_ENTRIES: int = 2048

var _passed: int = 0
var _failed: int = 0


func run_tests() -> Dictionary:
	_test_pulse_duty_sweep_and_envelope()
	_test_triangle_and_ultrasonic_gate()
	_test_noise_lfsr_white_and_periodic()
	_test_dmc_rate_table_and_delta_counter()
	_test_five_channel_headroom_and_60fps_stability()
	_test_live_rom_audio_extraction_and_music_player()
	return {"passed": _passed, "failed": _failed}


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  [FAIL] %s" % label)


func _assert_eq_int(actual: int, expected: int, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		printerr("  [FAIL] %s: actual=%d expected=%d" % [label, actual, expected])


func _test_pulse_duty_sweep_and_envelope() -> void:
	var apu: APUEngine = APUEngine.new()
	apu.reset_apu()
	apu.write_register(0x4015, 0x03) # Enable Pulse 1 + Pulse 2

	# Test all 4 duty cycles produce alternating positive/negative waveform energy without NaN
	for duty: int in range(4):
		apu.write_register(0x4000, (duty << 6) | 0x3A) # Constant volume 10, halt length
		apu.write_register(0x4002, 0xFD) # A4 period ~253
		apu.write_register(0x4003, 0x08)
		var buf: PackedFloat32Array = apu.step_audio_frame()
		_assert_eq_int(buf.size(), APUEngine.SAMPLES_PER_FRAME, "Pulse duty %d produces 735 samples/frame" % duty)
		var peak: float = apu.get_last_peak_amplitude()
		_assert_true(peak > 0.01 and peak < 1.0, "Pulse duty %d generates valid waveform (peak=%.4f)" % [duty, peak])

	# Hardware envelope decay when constant_vol == 0
	apu.write_register(0x4000, 0x80) # 50% duty, env_decay period=0, constant_vol=false
	apu.write_register(0x4003, 0xF8) # Restart envelope (env_decay=15)
	apu.step_audio_frame()
	var peak_early: float = apu.get_last_peak_amplitude()
	for _i: int in range(10):
		apu.clock_frame_sequencer()
	apu.synthesize_frame_samples()
	var peak_late: float = apu.get_last_peak_amplitude()
	_assert_true(peak_late <= peak_early, "Hardware volume envelope decays over quarter-frame ticks")

	# Pulse 1 sweep unit increases period cleanly
	apu.write_register(0x4002, 0x80)
	apu.write_register(0x4003, 0xF9) # period = 0x180
	apu.write_register(0x4001, 0x82) # Sweep enabled, period=0, shift=2 (down pitch)
	for _i: int in range(4):
		apu.clock_frame_sequencer()
	apu.write_register(0x4001, 0x00)
	_assert_true((apu.get_active_channel_mask() & 0x01) != 0, "Pulse 1 remains active after sweep")

	apu.free()


func _test_triangle_and_ultrasonic_gate() -> void:
	var apu: APUEngine = APUEngine.new()
	apu.reset_apu()
	apu.write_register(0x4015, 0x04) # Enable Triangle only
	apu.write_register(0x4008, 0xFF) # Control flag=1, linear_reload=127
	apu.write_register(0x400A, 0x40)
	apu.write_register(0x400B, 0xF9) # Load length + trigger linear reload
	var buf: PackedFloat32Array = apu.step_audio_frame()
	_assert_eq_int(buf.size(), APUEngine.SAMPLES_PER_FRAME, "Triangle yields 735 samples")
	_assert_true(apu.get_last_peak_amplitude() > 0.01, "Triangle produces active quantized output")

	# Ultrasonic gate: period < 2 silences Triangle output delta
	apu.write_register(0x400A, 0x01)
	apu.write_register(0x400B, 0xF8)
	for _i: int in range(3):
		apu.step_audio_frame()
	_assert_true(apu.get_last_peak_amplitude() < 0.02, "Triangle ultrasonic period < 2 silences output cleanly")

	apu.free()


func _test_noise_lfsr_white_and_periodic() -> void:
	var apu: APUEngine = APUEngine.new()
	apu.reset_apu()
	apu.write_register(0x4015, 0x08) # Enable Noise only
	apu.write_register(0x400C, 0x3C) # Constant vol 12
	apu.write_register(0x400E, 0x04) # White mode, fast period index 4
	apu.write_register(0x400F, 0xF8)
	var lfsr_start: int = apu.get_noise_lfsr()
	apu.step_audio_frame()
	_assert_true(apu.get_noise_lfsr() != lfsr_start, "White Noise LFSR advances during frame synthesis")
	_assert_true(apu.get_last_peak_amplitude() > 0.005, "White Noise generates audible sample amplitude")

	# Verify periodic metallic mode LFSR produces period 93 on APUEngine.NoiseChannel
	var nc: APUEngine.NoiseChannel = APUEngine.NoiseChannel.new()
	nc.reset()
	nc.periodic_mode = true
	var initial_state: int = nc.lfsr
	var cycle_len: int = 0
	for step_i: int in range(1, 200):
		nc.step_lfsr()
		if nc.lfsr == initial_state:
			cycle_len = step_i
			break
	_assert_eq_int(cycle_len, 93, "Periodic Noise mode taps bit 6 with exact 93-step cycle")

	apu.free()


func _test_dmc_rate_table_and_delta_counter() -> void:
	_assert_eq_int(APUEngine.DMC_RATE_TABLE.size(), 16, "DMC rate table has 16 NTSC entries")
	_assert_eq_int(APUEngine.DMC_RATE_TABLE[0], 428, "DMC rate 0 is 428 CPU cycles")
	_assert_eq_int(APUEngine.DMC_RATE_TABLE[15], 54, "DMC rate 15 is 54 CPU cycles")

	var apu: APUEngine = APUEngine.new()
	apu.reset_apu()
	apu.write_register(0x4011, 64) # Start DAC at midpoint 64
	_assert_eq_int(apu.get_dmc_counter(), 64, "Direct $4011 write sets 7-bit DMC counter to 64")

	# Load ascending bit pattern (0xFF -> +2 per step) and step 1 frame at fastest rate 15
	var up_sample: PackedByteArray = PackedByteArray([0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
	apu.load_dpcm_sample(up_sample, 15, false)
	_assert_true(apu.is_dmc_playing(), "load_dpcm_sample marks DMC active")
	apu.step_audio_frame()
	_assert_true(apu.get_dmc_counter() > 64 and apu.get_dmc_counter() <= 127, "1-bit DPCM shifts delta counter upward within [0,127] (val=%d)" % apu.get_dmc_counter())

	# Load descending bit pattern (0x00 -> -2 per step, looping)
	var down_sample: PackedByteArray = PackedByteArray([0x00, 0x00, 0x00])
	apu.load_dpcm_sample(down_sample, 15, true)
	apu.step_audio_frame()
	_assert_true(apu.is_dmc_playing(), "Looping DMC sample stays active after crossing buffer end")
	_assert_true(apu.get_dmc_counter() >= 0 and apu.get_dmc_counter() < 127, "DPCM downward steps stay clamped >= 0")

	apu.free()


func _test_five_channel_headroom_and_60fps_stability() -> void:
	var apu: APUEngine = APUEngine.new()
	apu.reset_apu()
	# Saturate all 5 channels simultaneously at maximum volume
	apu.write_register(0x4015, 0x1F)
	apu.write_register(0x4000, 0xBF) # Pulse 1 max vol 15
	apu.write_register(0x4002, 0xFE)
	apu.write_register(0x4003, 0xF8)
	apu.write_register(0x4004, 0xBF) # Pulse 2 max vol 15
	apu.write_register(0x4006, 0xC9)
	apu.write_register(0x4007, 0xF8)
	apu.write_register(0x4008, 0xFF) # Triangle max
	apu.write_register(0x400A, 0x7E)
	apu.write_register(0x400B, 0xF8)
	apu.write_register(0x400C, 0x3F) # Noise max vol 15
	apu.write_register(0x400E, 0x03)
	apu.write_register(0x400F, 0xF8)
	apu.write_register(0x4011, 127)
	apu.load_dpcm_sample(PackedByteArray([0xAA, 0xFF, 0x55, 0x00]), 15, true)

	var max_abs: float = 0.0
	var has_nan_or_inf: bool = false
	var total_samples: int = 0
	for _frame: int in range(15):
		var samples: PackedFloat32Array = apu.step_audio_frame()
		total_samples += samples.size()
		for s: float in samples:
			if is_nan(s) or is_inf(s):
				has_nan_or_inf = true
				break
			max_abs = maxf(max_abs, absf(s))

	_assert_eq_int(total_samples, 15 * APUEngine.SAMPLES_PER_FRAME, "15 frames at 60 TPS yield 11025 continuous samples")
	_assert_true(not has_nan_or_inf, "2A03 5-channel mix contains zero NaN/Inf samples")
	_assert_true(max_abs > 0.05 and max_abs <= 1.0, "5-channel saturation stays within non-clipping [-1, 1] headroom (peak=%.4f)" % max_abs)

	apu.free()


func _test_live_rom_audio_extraction_and_music_player() -> void:
	var test_user_dir: String = ""
	if not ContentRegistry.is_ready():
		var candidates: Array[String] = ROMImporter.find_candidate_roms()
		if candidates.is_empty():
			print("  [INFO] No local ROM present in rom/ — skipping live ROM audio test.")
			return
		test_user_dir = "user://nes_data_audio_test"
		var res: ROMImporter.ImportResult = ROMImporter.import_rom_file(candidates[0], test_user_dir, true)
		_assert_true(res.success, "Live ROM import succeeds for audio verification (%s)" % res.error)

	var tables: Dictionary = ContentRegistry.get_audio_tables()
	var period_tbl: Array = tables.get("period_table", []) as Array
	var tempo_tbls: Array = tables.get("tempo_tables", []) as Array
	var tracks_dict: Dictionary = tables.get("tracks", {}) as Dictionary
	var sfx_dict: Dictionary = tables.get("sfx", {}) as Dictionary
	var dpcm_dict: Dictionary = tables.get("dpcm_samples", {}) as Dictionary

	_assert_eq_int(period_tbl.size(), AudioExtractor.B29_PERIOD_COUNT, "Extracted 75-entry 2A03 period table from PRG Bank 29")
	_assert_eq_int(tempo_tbls.size(), AudioExtractor.B29_TEMPO_COUNT, "Extracted 10 tempo tables from PRG Bank 29")
	_assert_eq_int(tracks_dict.size(), AudioExtractor.B29_TRACK_COUNT, "Extracted all 58 BGM tracks from PRG Banks 30-32")
	_assert_eq_int(sfx_dict.size(), AudioExtractor.B29_SFX_COUNT, "Extracted all 88 SFX tracks from PRG Bank 29")
	_assert_true(dpcm_dict.size() >= 3, "Extracted referenced fixed-bank DPCM samples (count=%d)" % dpcm_dict.size())

	var dpcm_sample: PackedByteArray = ContentRegistry.get_dpcm_sample_bytes(240, 11)
	_assert_eq_int(dpcm_sample.size(), 177, "Extracted DPCM sample ($FC00, len=11) has 177 bytes")

	# Play Green Greens / Track 0 via MusicPlayer -> APUEngine at 60 TPS
	var apu: APUEngine = APUEngine.new()
	var mp: MusicPlayer = MusicPlayer.new()
	mp.setup(apu)
	mp._connect_event_bus()

	EventBus.bgm_requested.emit(0)
	_assert_eq_int(mp.get_current_bgm_id(), 0, "EventBus.bgm_requested(0) starts Track 0")
	_assert_true(mp.is_bgm_playing(), "MusicPlayer reports BGM active on Track 0")

	var peak_bgm: float = 0.0
	for _i: int in range(12):
		mp.step_frame()
		apu.step_audio_frame()
		peak_bgm = maxf(peak_bgm, apu.get_last_peak_amplitude())
	_assert_true(peak_bgm > 0.02 and peak_bgm <= 1.0, "ROM Track 0 drives audible non-clipping 2A03 output (peak=%.4f)" % peak_bgm)

	# Trigger SFX override via EventBus and verify BGM keeps running seamlessly afterward
	EventBus.sfx_requested.emit(1)
	_assert_eq_int(mp.get_current_sfx_id(), 1, "EventBus.sfx_requested(1) activates SFX override")
	for _i: int in range(15):
		mp.step_frame()
		apu.step_audio_frame()
	_assert_true(mp.is_bgm_playing(), "BGM remains synced and playing after SFX override")

	EventBus.audio_stop_requested.emit()
	_assert_true(not mp.is_bgm_playing(), "EventBus.audio_stop_requested stops playback cleanly")

	mp.free()
	apu.free()
	if not test_user_dir.is_empty():
		_cleanup_dir_recursive(test_user_dir)


func _cleanup_dir_recursive(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var item: String = dir.get_next()
	var entries: int = 0
	while item != "" and entries < MAX_CLEANUP_ENTRIES:
		entries += 1
		if item != "." and item != "..":
			var full: String = dir_path.path_join(item)
			if dir.current_is_dir():
				_cleanup_dir_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		item = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)
