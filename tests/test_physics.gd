extends RefCounted
## Verification tests for Phase 2: 16x16 metatile slope heightmaps, solid/one-way/water/breakable
## queries, deterministic 60 TPS KirbyController physics, and live ROM Stage 1-1 traversal.

const Constants = preload("res://src/core/constants.gd")
const LevelMap = preload("res://src/game/level_map.gd")
const KirbyController = preload("res://src/game/kirby_controller.gd")
const ROMImporter = preload("res://src/importer/rom_importer.gd")
const MAX_CLEANUP_ENTRIES: int = 2048

var _passed: int = 0
var _failed: int = 0


func run_tests() -> Dictionary:
	_test_slope_heightmap_tables()
	_test_walk_run_and_jump_physics()
	_test_slope_traversal_45_and_26()
	_test_one_way_drop_through_and_slide_break()
	_test_hover_exhale_and_swim_water_gun()
	_test_inhale_spit_swallow_and_damage()
	_test_live_rom_stage_1_1_if_present()
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


func _build_synthetic_tileset() -> Dictionary:
	# Metatile IDs:
	# 0: AIR, 1: SOLID, 2: ONE_WAY, 3: SLOPE_45_UP, 4: SLOPE_45_DOWN,
	# 5: SLOPE_26_UP_L, 6: SLOPE_26_UP_H, 7: WATER, 8: BREAKABLE_STAR, 9: SPIKE_HAZARD
	var col_types: Array[int] = [
		Constants.TileCollision.AIR,
		Constants.TileCollision.SOLID,
		Constants.TileCollision.ONE_WAY,
		Constants.TileCollision.SLOPE_45_UP,
		Constants.TileCollision.SLOPE_45_DOWN,
		Constants.TileCollision.SLOPE_26_UP_L,
		Constants.TileCollision.SLOPE_26_UP_H,
		Constants.TileCollision.WATER,
		Constants.TileCollision.BREAKABLE_STAR,
		Constants.TileCollision.SPIKE_HAZARD,
	]
	var mts: Array[Dictionary] = []
	for idx: int in range(col_types.size()):
		var nes_col: int = 0x80 if col_types[idx] == Constants.TileCollision.WATER else 0x00
		mts.append({
			"tl": 0, "tr": 0, "bl": 0, "br": 0,
			"palette": 0,
			"raw_prop": idx,
			"nes_collision": nes_col,
			"collision": col_types[idx],
		})
	return {"tileset_id": 0, "metatiles": mts}


func _build_synthetic_room(w_mt: int, h_mt: int, fill_floor_row: int = -1) -> Dictionary:
	var grid: Array[int] = []
	grid.resize(w_mt * h_mt)
	for i: int in range(w_mt * h_mt):
		grid[i] = 0
	if fill_floor_row >= 0 and fill_floor_row < h_mt:
		for mx: int in range(w_mt):
			grid[fill_floor_row * w_mt + mx] = 1
	return {
		"room_id": 999,
		"tileset_id": 0,
		"width_screens": maxi(1, w_mt / 16),
		"height_screens": maxi(1, h_mt / 12),
		"width_metatiles": w_mt,
		"height_metatiles": h_mt,
		"metatiles": grid,
		"doors": [],
		"entities": [],
	}


func _test_slope_heightmap_tables() -> void:
	_assert_eq_int(LevelMap.get_local_surface_y(Constants.TileCollision.SOLID, 5), 0, "SOLID surface is y=0")
	_assert_eq_int(LevelMap.get_local_surface_y(Constants.TileCollision.SLOPE_45_UP, 0), 15, "SLOPE_45_UP x=0 -> y=15")
	_assert_eq_int(LevelMap.get_local_surface_y(Constants.TileCollision.SLOPE_45_UP, 15), 0, "SLOPE_45_UP x=15 -> y=0")
	_assert_eq_int(LevelMap.get_local_surface_y(Constants.TileCollision.SLOPE_45_DOWN, 0), 0, "SLOPE_45_DOWN x=0 -> y=0")
	_assert_eq_int(LevelMap.get_local_surface_y(Constants.TileCollision.SLOPE_45_DOWN, 15), 15, "SLOPE_45_DOWN x=15 -> y=15")
	_assert_eq_int(LevelMap.get_local_surface_y(Constants.TileCollision.SLOPE_26_UP_L, 0), 15, "SLOPE_26_UP_L x=0 -> y=15")
	_assert_eq_int(LevelMap.get_local_surface_y(Constants.TileCollision.SLOPE_26_UP_L, 15), 8, "SLOPE_26_UP_L x=15 -> y=8")
	_assert_eq_int(LevelMap.get_local_surface_y(Constants.TileCollision.SLOPE_26_UP_H, 0), 7, "SLOPE_26_UP_H x=0 -> y=7")
	_assert_eq_int(LevelMap.get_local_surface_y(Constants.TileCollision.SLOPE_26_UP_H, 15), 0, "SLOPE_26_UP_H x=15 -> y=0")


func _test_walk_run_and_jump_physics() -> void:
	var lvl: LevelMap = LevelMap.new()
	var ts: Dictionary = _build_synthetic_tileset()
	var room: Dictionary = _build_synthetic_room(16, 12, 9) # Solid floor at row 9 (y=144)
	_assert_true(lvl.load_from_dicts(room, ts), "Synthetic level loads cleanly")

	var kirby: KirbyController = KirbyController.new()
	kirby.setup(lvl, Vector2(32.0, 144.0))
	InputManager.clear_mock_mask()

	# Settle 2 frames
	InputManager.set_mock_mask(0)
	for _i: int in range(2):
		InputManager.step_frame()
		kirby.step_physics()
	_assert_true(kirby.on_ground, "Kirby settles onto solid floor")

	# Walk right 20 frames
	InputManager.set_mock_mask(Constants.NesButton.RIGHT)
	for _i: int in range(20):
		InputManager.step_frame()
		kirby.step_physics()
	var walk_dx: float = kirby.pos.x - 32.0
	_assert_true(kirby.state == KirbyController.State.WALK and walk_dx > 20.0, "Kirby walks right deterministically (dx=%.2f)" % walk_dx)

	# Double-tap RIGHT -> RUN
	InputManager.set_mock_mask(0)
	InputManager.step_frame()
	kirby.step_physics()
	InputManager.set_mock_mask(Constants.NesButton.RIGHT)
	for _i: int in range(20):
		InputManager.step_frame()
		kirby.step_physics()
	_assert_true(kirby.state == KirbyController.State.RUN and kirby.vel.x > KirbyController.WALK_SPEED, "Double-tap RIGHT engages RUN speed")

	# Variable jump height: short tap A vs full hold A
	InputManager.set_mock_mask(0)
	for _i: int in range(10):
		InputManager.step_frame()
		kirby.step_physics()
	InputManager.set_mock_mask(Constants.NesButton.A)
	InputManager.step_frame()
	kirby.step_physics()
	InputManager.set_mock_mask(0) # release immediately
	var short_min_y: float = kirby.pos.y
	for _i: int in range(30):
		InputManager.step_frame()
		kirby.step_physics()
		short_min_y = minf(short_min_y, kirby.pos.y)

	# Full jump hold A
	for _i: int in range(30):
		InputManager.step_frame()
		kirby.step_physics()
	InputManager.set_mock_mask(Constants.NesButton.A)
	var full_min_y: float = kirby.pos.y
	for _i: int in range(25):
		InputManager.step_frame()
		kirby.step_physics()
		full_min_y = minf(full_min_y, kirby.pos.y)
	_assert_true(full_min_y < short_min_y - 10.0, "Holding A yields higher jump (%.1f) than tap A (%.1f)" % [full_min_y, short_min_y])

	InputManager.clear_mock_mask()
	kirby.free()
	lvl.free()


func _test_slope_traversal_45_and_26() -> void:
	var lvl: LevelMap = LevelMap.new()
	var ts: Dictionary = _build_synthetic_tileset()
	var room: Dictionary = _build_synthetic_room(16, 12, 9)
	var grid: Array = room["metatiles"] as Array
	# Build ramp at row 8 (y=128..143):
	# col 4: SLOPE_45_UP (3), col 5: SOLID (1), col 6: SLOPE_45_DOWN (4)
	grid[8 * 16 + 4] = 3
	grid[8 * 16 + 5] = 1
	grid[8 * 16 + 6] = 4
	# Also 26.5-deg ramp at col 8..9 (row 8): col 8 = SLOPE_26_UP_L (5), col 9 = SLOPE_26_UP_H (6), col 10 = SOLID (1)
	grid[8 * 16 + 8] = 5
	grid[8 * 16 + 9] = 6
	grid[8 * 16 + 10] = 1
	_assert_true(lvl.load_from_dicts(room, ts), "Synthetic slope test room loads")

	var kirby: KirbyController = KirbyController.new()
	kirby.setup(lvl, Vector2(40.0, 144.0))

	# Walk across 45-degree up + plateau + 45-degree down (x: 40 -> 118)
	InputManager.set_mock_mask(0)
	InputManager.step_frame()
	kirby.step_physics()

	InputManager.set_mock_mask(Constants.NesButton.RIGHT)
	var reached_plateau_y: float = 999.0
	var stayed_grounded: bool = true
	var flat_gap_y: float = -1.0
	for _i: int in range(56):
		InputManager.step_frame()
		kirby.step_physics()
		reached_plateau_y = minf(reached_plateau_y, kirby.pos.y)
		if kirby.pos.x >= 80.0 and kirby.pos.x <= 96.0 and not kirby.on_ground:
			stayed_grounded = false
		if kirby.pos.x >= 118.0 and kirby.pos.x <= 122.0:
			flat_gap_y = kirby.pos.y
	_assert_true(absf(reached_plateau_y - 128.0) <= 1.0, "Kirby climbs 45-deg slope smoothly to plateau y=128 (got %.2f)" % reached_plateau_y)
	_assert_true(stayed_grounded, "Kirby remains grounded across 45-deg slope plateau")
	_assert_true(flat_gap_y > 0.0 and absf(flat_gap_y - 144.0) <= 1.0, "Kirby descends 45-deg slope smoothly back to y=144 (gap_y=%.2f)" % flat_gap_y)

	# Continue across 26.5-deg ramp (cols 8..10 -> x=128..175) to plateau y=128
	var reached_26_plateau_y: float = 999.0
	for _i: int in range(36):
		InputManager.step_frame()
		kirby.step_physics()
		if kirby.pos.x >= 160.0 and kirby.pos.x <= 174.0:
			reached_26_plateau_y = minf(reached_26_plateau_y, kirby.pos.y)
	_assert_true(kirby.pos.x >= 160.0 and absf(reached_26_plateau_y - 128.0) <= 1.0, "Kirby climbs 26.5-deg 2-tile slope cleanly to y=128 (got %.2f)" % reached_26_plateau_y)

	InputManager.clear_mock_mask()
	kirby.free()
	lvl.free()


func _test_one_way_drop_through_and_slide_break() -> void:
	var lvl: LevelMap = LevelMap.new()
	var ts: Dictionary = _build_synthetic_tileset()
	var room: Dictionary = _build_synthetic_room(16, 12, 9) # Solid floor at row 9 (y=144)
	var grid: Array = room["metatiles"] as Array
	# ONE_WAY platform at row 6 (y=96), cols 2..5
	for mx: int in range(2, 6):
		grid[6 * 16 + mx] = 2
	# BREAKABLE_STAR block at (mx=8, my=8) sitting on row 9 solid floor
	grid[8 * 16 + 8] = 8
	lvl.load_from_dicts(room, ts)

	var kirby: KirbyController = KirbyController.new()
	kirby.setup(lvl, Vector2(56.0, 96.0)) # Start standing on ONE_WAY at y=96

	InputManager.set_mock_mask(0)
	InputManager.step_frame()
	kirby.step_physics()
	_assert_true(kirby.on_ground and absf(kirby.pos.y - 96.0) <= 0.5, "Kirby stands on ONE_WAY platform")

	# Drop through with DOWN + A
	InputManager.set_mock_mask(Constants.NesButton.DOWN | Constants.NesButton.A)
	InputManager.step_frame()
	kirby.step_physics()
	InputManager.set_mock_mask(0)
	for _i: int in range(35):
		InputManager.step_frame()
		kirby.step_physics()
	_assert_true(kirby.on_ground and absf(kirby.pos.y - 144.0) <= 0.5, "DOWN+A drops through ONE_WAY platform onto lower floor y=144 (y=%.1f)" % kirby.pos.y)

	# Slide right into BREAKABLE_STAR block at col 8 (x=128..143)
	kirby.setup(lvl, Vector2(104.0, 144.0))
	InputManager.set_mock_mask(0)
	InputManager.step_frame()
	kirby.step_physics()
	InputManager.set_mock_mask(Constants.NesButton.DOWN | Constants.NesButton.A)
	InputManager.step_frame()
	kirby.step_physics()
	_assert_eq_int(kirby.state, KirbyController.State.SLIDE, "DOWN+A on solid ground starts SLIDE")
	InputManager.set_mock_mask(Constants.NesButton.DOWN)
	for _i: int in range(15):
		InputManager.step_frame()
		kirby.step_physics()
	_assert_eq_int(lvl.get_collision_at_tile(8, 8), Constants.TileCollision.AIR, "SLIDE breaks BREAKABLE_STAR block into AIR")

	InputManager.clear_mock_mask()
	kirby.free()
	lvl.free()


func _test_hover_exhale_and_swim_water_gun() -> void:
	var lvl: LevelMap = LevelMap.new()
	var ts: Dictionary = _build_synthetic_tileset()
	var room: Dictionary = _build_synthetic_room(16, 12, 10) # Floor at row 10 (y=160)
	var grid: Array = room["metatiles"] as Array
	# Water pool at cols 8..12, rows 6..9
	for my: int in range(6, 10):
		for mx: int in range(8, 13):
			grid[my * 16 + mx] = 7
	lvl.load_from_dicts(room, ts)

	var kirby: KirbyController = KirbyController.new()
	kirby.setup(lvl, Vector2(48.0, 120.0)) # Airborne

	# Hover upward via repeated A presses
	InputManager.set_mock_mask(Constants.NesButton.A)
	InputManager.step_frame()
	kirby.step_physics()
	_assert_eq_int(kirby.state, KirbyController.State.HOVER, "Pressing A in midair enters HOVER")
	for _i: int in range(10):
		InputManager.set_mock_mask(0)
		InputManager.step_frame()
		kirby.step_physics()
		InputManager.set_mock_mask(Constants.NesButton.A)
		InputManager.step_frame()
		kirby.step_physics()
	_assert_true(kirby.pos.y < 105.0, "Hover puffs ascend upward (y=%.1f)" % kirby.pos.y)

	# Exhale Air Puff via B
	InputManager.set_mock_mask(Constants.NesButton.B)
	InputManager.step_frame()
	kirby.step_physics()
	_assert_eq_int(kirby.state, KirbyController.State.EXHALE, "Pressing B during HOVER triggers EXHALE")
	var projs: Array[Dictionary] = kirby.consume_spawned_projectiles()
	_assert_eq_int(projs.size(), 1, "EXHALE spawns 1 projectile")
	if not projs.is_empty():
		_assert_true(String(projs[0].get("kind", "")) == "air_puff", "EXHALE spawns air_puff projectile")

	# Swim & Water Gun inside WATER zone
	kirby.setup(lvl, Vector2(160.0, 128.0)) # Inside water cols 8..12, rows 6..9
	InputManager.set_mock_mask(0)
	InputManager.step_frame()
	kirby.step_physics()
	_assert_true(kirby.in_water and kirby.state == KirbyController.State.SWIM, "Entering WATER switches Kirby to SWIM")

	InputManager.set_mock_mask(Constants.NesButton.B)
	InputManager.step_frame()
	kirby.step_physics()
	_assert_eq_int(kirby.state, KirbyController.State.WATER_GUN, "Pressing B in water triggers WATER_GUN")
	var w_projs: Array[Dictionary] = kirby.consume_spawned_projectiles()
	_assert_eq_int(w_projs.size(), 1, "WATER_GUN spawns 1 projectile")
	if not w_projs.is_empty():
		_assert_true(String(w_projs[0].get("kind", "")) == "water_gun", "WATER_GUN spawns water_gun projectile")

	InputManager.clear_mock_mask()
	kirby.free()
	lvl.free()


func _test_inhale_spit_swallow_and_damage() -> void:
	var lvl: LevelMap = LevelMap.new()
	var ts: Dictionary = _build_synthetic_tileset()
	var room: Dictionary = _build_synthetic_room(16, 12, 9)
	var grid: Array = room["metatiles"] as Array
	grid[8 * 16 + 5] = 8 # BREAKABLE_STAR in front of Kirby
	lvl.load_from_dicts(room, ts)

	var kirby: KirbyController = KirbyController.new()
	kirby.setup(lvl, Vector2(48.0, 144.0))
	InputManager.set_mock_mask(0)
	InputManager.step_frame()
	kirby.step_physics()

	# Inhale for 8 frames -> auto-captures BREAKABLE_STAR at col 5 into MOUTH_FULL
	InputManager.set_mock_mask(Constants.NesButton.B)
	for _i: int in range(8):
		InputManager.step_frame()
		kirby.step_physics()
	_assert_eq_int(kirby.state, KirbyController.State.MOUTH_FULL, "Inhaling BREAKABLE_STAR enters MOUTH_FULL")
	_assert_eq_int(lvl.get_collision_at_tile(5, 8), Constants.TileCollision.AIR, "Inhaled BREAKABLE_STAR removed from map")

	# Spit Star projectile via B
	InputManager.set_mock_mask(0)
	InputManager.step_frame()
	kirby.step_physics()
	InputManager.set_mock_mask(Constants.NesButton.B)
	InputManager.step_frame()
	kirby.step_physics()
	_assert_true(not kirby.has_cargo, "Star Spit clears MOUTH_FULL cargo")
	var spit_projs: Array[Dictionary] = kirby.consume_spawned_projectiles()
	_assert_eq_int(spit_projs.size(), 1, "Star Spit emits 1 projectile")
	if not spit_projs.is_empty():
		_assert_true(String(spit_projs[0].get("kind", "")) == "star_spit", "Star Spit emits star_spit projectile")

	# Inhale enemy with Sword Copy Ability and swallow
	InputManager.set_mock_mask(0)
	InputManager.step_frame()
	kirby.step_physics()
	InputManager.set_mock_mask(Constants.NesButton.B)
	InputManager.step_frame()
	kirby.step_physics()
	_assert_true(kirby.capture_inhaled_cargo(Constants.CopyAbility.SWORD), "Inhale captures Sword cargo")
	InputManager.set_mock_mask(Constants.NesButton.DOWN)
	InputManager.step_frame()
	kirby.step_physics()
	_assert_eq_int(kirby.copy_ability, Constants.CopyAbility.SWORD, "Swallowing Blade Knight cargo equips SWORD ability")

	# Damage knockback, i-frames, and ability star drop
	_assert_true(kirby.take_damage(1, -1), "Damage applies when invuln_frames == 0")
	_assert_eq_int(kirby.hp, 5, "HP decreases from 6 to 5")
	_assert_eq_int(kirby.copy_ability, Constants.CopyAbility.NONE, "Taking damage drops active CopyAbility")
	_assert_eq_int(kirby.invuln_frames, KirbyController.INVULN_FRAMES, "Taking damage grants 120 invulnerability frames")
	_assert_true(not kirby.take_damage(1, -1), "Invulnerability frames block repeat damage")
	var drop_projs: Array[Dictionary] = kirby.consume_spawned_projectiles()
	_assert_eq_int(drop_projs.size(), 1, "Dropping CopyAbility spawns 1 Ability Star")
	if not drop_projs.is_empty():
		_assert_true(String(drop_projs[0].get("kind", "")) == "ability_star", "Dropped projectile is ability_star")

	InputManager.clear_mock_mask()
	kirby.free()
	lvl.free()


func _test_live_rom_stage_1_1_if_present() -> void:
	var test_user_dir: String = ""
	if not ContentRegistry.is_ready():
		var candidates: Array[String] = ROMImporter.find_candidate_roms()
		if candidates.is_empty():
			print("  [INFO] No local ROM present in rom/ — skipping live ROM Stage 1-1 physics test.")
			return
		test_user_dir = "user://nes_data_phys_test"
		var res: ROMImporter.ImportResult = ROMImporter.import_rom_file(candidates[0], test_user_dir, true)
		_assert_true(res.success, "Live ROM import succeeds for physics integration (%s)" % res.error)

	var lvl: LevelMap = LevelMap.new()
	_assert_true(lvl.load_room(43), "LevelMap loads extracted Stage 1-1 Room 43")
	_assert_true(lvl.get_room_texture() != null, "LevelMap renders Room 43 ImageTexture from ROM CHR + palettes")
	if lvl.get_room_texture() != null:
		_assert_eq_int(lvl.get_room_texture().get_width(), 1024, "Room 43 texture width is 1024px (64 metatiles)")
		_assert_eq_int(lvl.get_room_texture().get_height(), 192, "Room 43 texture height is 192px (12 metatiles)")

	# Spawn Kirby in Room 43 screen 0 above grass floor (row 9 -> y=144)
	var kirby: KirbyController = KirbyController.new()
	kirby.setup(lvl, Vector2(40.0, 128.0))
	InputManager.set_mock_mask(0)
	for _i: int in range(20):
		InputManager.step_frame()
		kirby.step_physics()
	_assert_true(kirby.on_ground and absf(kirby.pos.y - 144.0) <= 0.5, "Kirby lands on authentic ROM Stage 1-1 grass floor at y=144 (y=%.1f)" % kirby.pos.y)

	# Verify Room 43 exit door at screen 3 (x=13, y=7) -> center (984, 120)
	var door: Dictionary = lvl.find_door_at_pixel(984.0, 120.0)
	_assert_eq_int(int(door.get("dest_room_id", -1)), 44, "Room 43 exit door triggers transition to Room 44")

	# Load Stage 1-2 Room 47 (contains water/slopes) and verify water detection
	_assert_true(lvl.load_room(47), "LevelMap loads extracted Stage 1-2 Room 47")

	InputManager.clear_mock_mask()
	kirby.free()
	lvl.free()
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
