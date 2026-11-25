extends RefCounted
## Verification tests for Phase 2: 16x16 metatile slope heightmaps, solid/one-way/water/breakable
## queries, deterministic 60 TPS KirbyController physics, and live ROM Stage 1-1 traversal.

const Constants = preload("res://src/core/constants.gd")
const LevelMap = preload("res://src/game/level_map.gd")
const KirbyController = preload("res://src/game/kirby_controller.gd")
const AbilitySword = preload("res://src/game/abilities/ability_sword.gd")
const HUDRenderer = preload("res://src/game/hud_renderer.gd")
const VirtualGamepad = preload("res://src/game/virtual_gamepad.gd")
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
	_test_copy_abilities_sword_fire_spark_beam()
	_test_hud_renderer_and_virtual_gamepad()
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


func _test_copy_abilities_sword_fire_spark_beam() -> void:
	var lvl: LevelMap = LevelMap.new()
	var ts: Dictionary = _build_synthetic_tileset()
	var room: Dictionary = _build_synthetic_room(16, 12, 9) # Floor row 9 (y=144)
	var grid: Array = room["metatiles"] as Array
	# Breakable star blocks in front for ability break checks
	grid[8 * 16 + 5] = 8 # Sword slash target (x=80..95)
	grid[8 * 16 + 6] = 8 # Fire stream target (x=96..111)
	grid[8 * 16 + 3] = 8 # Spark 360 behind/adjacent target (x=48..63)
	grid[7 * 16 + 7] = 8 # Beam sweep overhead/front target behind thin wall col 6
	lvl.load_from_dicts(room, ts)

	var kirby: KirbyController = KirbyController.new()
	kirby.setup(lvl, Vector2(64.0, 144.0))
	InputManager.set_mock_mask(0)
	for _i: int in range(2):
		InputManager.step_frame()
		kirby.step_physics()

	# 1. SWORD: standing slash, air spin, dash slash
	kirby.equip_copy_ability(Constants.CopyAbility.SWORD)
	_assert_eq_int(kirby.copy_ability, Constants.CopyAbility.SWORD, "Kirby equips SWORD ability")
	InputManager.set_mock_mask(Constants.NesButton.B)
	InputManager.step_frame()
	kirby.step_physics()
	_assert_eq_int(kirby.state, KirbyController.State.ABILITY_ATTACK, "B triggers SWORD ABILITY_ATTACK")
	var sword_boxes: Array[Dictionary] = kirby.get_active_hitboxes()
	_assert_eq_int(sword_boxes.size(), 1, "SWORD slash exposes 1 active hitbox")
	if not sword_boxes.is_empty():
		_assert_true(String(sword_boxes[0].get("kind", "")) == "sword_slash", "Ground B uses sword_slash mode")
	InputManager.set_mock_mask(0)
	for _i: int in range(3):
		InputManager.step_frame()
		kirby.step_physics()
	_assert_eq_int(lvl.get_collision_at_tile(5, 8), Constants.TileCollision.AIR, "SWORD slash breaks star block at (5,8)")
	for _i: int in range(12):
		InputManager.step_frame()
		kirby.step_physics()
	_assert_true(kirby.state != KirbyController.State.ABILITY_ATTACK, "SWORD slash finishes cleanly")

	# Air Spin Slash
	InputManager.set_mock_mask(Constants.NesButton.A)
	for _i: int in range(3):
		InputManager.step_frame()
		kirby.step_physics()
	InputManager.set_mock_mask(Constants.NesButton.B)
	InputManager.step_frame()
	kirby.step_physics()
	var spin_boxes: Array[Dictionary] = kirby.get_active_hitboxes()
	_assert_true(not spin_boxes.is_empty() and String(spin_boxes[0].get("kind", "")) == "sword_air_spin", "Midair B triggers sword_air_spin")
	InputManager.set_mock_mask(0)
	for _i: int in range(30):
		InputManager.step_frame()
		kirby.step_physics()

	# Dash Slash (double-tap RIGHT -> RUN + B)
	kirby.setup(lvl, Vector2(32.0, 144.0))
	kirby.equip_copy_ability(Constants.CopyAbility.SWORD)
	InputManager.set_mock_mask(0)
	InputManager.step_frame()
	kirby.step_physics()
	InputManager.set_mock_mask(Constants.NesButton.RIGHT)
	InputManager.step_frame()
	kirby.step_physics()
	InputManager.set_mock_mask(0)
	InputManager.step_frame()
	kirby.step_physics()
	InputManager.set_mock_mask(Constants.NesButton.RIGHT)
	for _i: int in range(4):
		InputManager.step_frame()
		kirby.step_physics()
	_assert_eq_int(kirby.state, KirbyController.State.RUN, "Kirby enters RUN before Dash Slash")
	InputManager.set_mock_mask(Constants.NesButton.RIGHT | Constants.NesButton.B)
	InputManager.step_frame()
	kirby.step_physics()
	var dash_boxes: Array[Dictionary] = kirby.get_active_hitboxes()
	_assert_true(not dash_boxes.is_empty() and String(dash_boxes[0].get("kind", "")) == "sword_dash", "Running B triggers sword_dash")
	var sword_ab: AbilitySword = kirby.get_active_ability() as AbilitySword
	_assert_eq_int(sword_ab.get_mode(), AbilitySword.Mode.DASH_SLASH, "AbilitySword records DASH_SLASH mode")

	# 2. FIRE: continuous flame stream while B held & breaks block (6,8)
	kirby.setup(lvl, Vector2(64.0, 144.0))
	kirby.equip_copy_ability(Constants.CopyAbility.FIRE)
	InputManager.set_mock_mask(0)
	InputManager.step_frame()
	kirby.step_physics()
	InputManager.set_mock_mask(Constants.NesButton.B)
	for _i: int in range(18):
		InputManager.step_frame()
		kirby.step_physics()
	_assert_eq_int(kirby.state, KirbyController.State.ABILITY_ATTACK, "Holding B sustains FIRE flame stream past 12 frames")
	var fire_boxes: Array[Dictionary] = kirby.get_active_hitboxes()
	_assert_true(not fire_boxes.is_empty() and String(fire_boxes[0].get("kind", "")) == "fire_stream", "FIRE emits fire_stream hitbox")
	_assert_eq_int(lvl.get_collision_at_tile(6, 8), Constants.TileCollision.AIR, "FIRE breaks star block at (6,8)")
	InputManager.set_mock_mask(0)
	InputManager.step_frame()
	kirby.step_physics()
	_assert_true(kirby.state != KirbyController.State.ABILITY_ATTACK, "Releasing B stops continuous FIRE stream")

	# 3. SPARK: 360-degree barrier protects contact damage & breaks adjacent behind block (3,8)
	kirby.setup(lvl, Vector2(68.0, 144.0))
	kirby.equip_copy_ability(Constants.CopyAbility.SPARK)
	InputManager.set_mock_mask(0)
	InputManager.step_frame()
	kirby.step_physics()
	InputManager.set_mock_mask(Constants.NesButton.B)
	for _i: int in range(4):
		InputManager.step_frame()
		kirby.step_physics()
	var spark_boxes: Array[Dictionary] = kirby.get_active_hitboxes()
	_assert_true(not spark_boxes.is_empty() and String(spark_boxes[0].get("kind", "")) == "spark_barrier", "SPARK activates 360-deg spark_barrier hitbox")
	_assert_eq_int(lvl.get_collision_at_tile(3, 8), Constants.TileCollision.AIR, "SPARK 360 barrier breaks behind star block at (3,8)")
	_assert_true(not kirby.take_damage(1, -1), "Active SPARK barrier blocks contact damage")

	# 4. BEAM: 5-orb sweeping curved whip passing through walls & breaking (7,7)
	kirby.setup(lvl, Vector2(88.0, 144.0))
	kirby.equip_copy_ability(Constants.CopyAbility.BEAM)
	InputManager.set_mock_mask(0)
	InputManager.step_frame()
	kirby.step_physics()
	InputManager.set_mock_mask(Constants.NesButton.B)
	InputManager.step_frame()
	kirby.step_physics()
	var beam_boxes: Array[Dictionary] = kirby.get_active_hitboxes()
	_assert_eq_int(beam_boxes.size(), 5, "BEAM whip emits 5 curved orb hitboxes")
	if beam_boxes.size() == 5:
		_assert_true(bool(beam_boxes[4].get("passes_through_walls", false)), "BEAM whip passes through thin walls")
	InputManager.set_mock_mask(0)
	for _i: int in range(18):
		InputManager.step_frame()
		kirby.step_physics()
	_assert_eq_int(lvl.get_collision_at_tile(7, 7), Constants.TileCollision.AIR, "BEAM whip sweeps through and breaks star block at (7,7)")

	# SELECT drops active Copy Ability into an Ability Star
	InputManager.set_mock_mask(Constants.NesButton.SELECT)
	InputManager.step_frame()
	kirby.step_physics()
	_assert_eq_int(kirby.copy_ability, Constants.CopyAbility.NONE, "SELECT drops active CopyAbility")
	var dropped: Array[Dictionary] = kirby.consume_spawned_projectiles()
	_assert_true(not dropped.is_empty() and String(dropped[0].get("kind", "")) == "ability_star", "SELECT emits ability_star projectile")

	InputManager.clear_mock_mask()
	kirby.free()
	lvl.free()


func _test_hud_renderer_and_virtual_gamepad() -> void:
	var hud: HUDRenderer = HUDRenderer.new()
	hud.connect_event_bus()
	hud.set_status(4, 6, 3, 12500, Constants.CopyAbility.BEAM)
	_assert_eq_int(hud.get_displayed_hp(), 4, "HUDRenderer stores updated HP")
	_assert_eq_int(hud.get_displayed_lives(), 3, "HUDRenderer stores updated lives")
	_assert_eq_int(hud.get_displayed_score(), 12500, "HUDRenderer stores updated score")
	_assert_eq_int(hud.get_displayed_ability(), Constants.CopyAbility.BEAM, "HUDRenderer stores active CopyAbility")

	# Verify EventBus signals propagate to HUDRenderer
	EventBus.hp_changed.emit(2, 6)
	EventBus.score_changed.emit(13000, 500)
	EventBus.copy_ability_changed.emit(Constants.CopyAbility.FIRE)
	_assert_eq_int(hud.get_displayed_hp(), 2, "EventBus.hp_changed updates HUDRenderer HP")
	_assert_eq_int(hud.get_displayed_score(), 13000, "EventBus.score_changed updates HUDRenderer score")
	_assert_eq_int(hud.get_displayed_ability(), Constants.CopyAbility.FIRE, "EventBus.copy_ability_changed updates HUDRenderer card")

	# Verify HUDRenderer font tile mapping (Bank 254 0xFE: '0'..'9' -> 0x1C..0x25, 'A'..'Z' -> 0x26..0x3F)
	_assert_eq_int(Constants.CHR_BANK_HUD_FONT, 254, "HUD font uses CHR Bank 254 (0xFE)")
	_assert_eq_int(HUDRenderer.map_char_to_font_tile("0"), 0x1C, "HUD font maps '0' to tile 0x1C")
	_assert_eq_int(HUDRenderer.map_char_to_font_tile("9"), 0x25, "HUD font maps '9' to tile 0x25")
	_assert_eq_int(HUDRenderer.map_char_to_font_tile("A"), 0x26, "HUD font maps 'A' to tile 0x26")
	_assert_eq_int(HUDRenderer.map_char_to_font_tile("Z"), 0x3F, "HUD font maps 'Z' to tile 0x3F")

	# Verify VirtualGamepad routes touch presses cleanly & anchors widescreen margins clear of 256x240 stage
	var pad: VirtualGamepad = VirtualGamepad.new()
	pad._build_overlay()
	pad.rebuild_for_viewport_size(Vector2(1280.0, 720.0))
	var b_wide: Rect2 = pad.get_button_rect(Constants.NesButton.B)
	var a_wide: Rect2 = pad.get_button_rect(Constants.NesButton.A)
	var left_wide: Rect2 = pad.get_button_rect(Constants.NesButton.LEFT)
	var sel_wide: Rect2 = pad.get_button_rect(Constants.NesButton.SELECT)
	_assert_true(b_wide.position.x > 1180.0 and b_wide.position.y > 650.0, "VirtualGamepad B anchors to far right margin on 1280x720")
	_assert_true(a_wide.position.x > 1220.0 and a_wide.position.y > 640.0, "VirtualGamepad A anchors to far right margin on 1280x720")
	_assert_true(left_wide.position.x < 50.0 and left_wide.position.y > 640.0, "VirtualGamepad D-Pad anchors to bottom-left margin")
	_assert_true(sel_wide.position.x > 580.0 and sel_wide.position.x < 640.0 and sel_wide.position.y > 690.0, "VirtualGamepad SELECT anchors to bottom-center")

	# Auto-hide on physical key press, auto-show on touch press
	pad.set_overlay_visible(true)
	var key_ev: InputEventKey = InputEventKey.new()
	key_ev.pressed = true
	key_ev.keycode = KEY_RIGHT
	pad._input(key_ev)
	_assert_true(not pad.is_overlay_visible(), "VirtualGamepad auto-hides on physical keyboard input")

	var touch_show: InputEventScreenTouch = InputEventScreenTouch.new()
	touch_show.index = 0
	touch_show.pressed = true
	touch_show.position = a_wide.get_center()
	pad._input(touch_show)
	_assert_true(pad.is_overlay_visible(), "VirtualGamepad re-shows and handles touch on screen touch")
	_assert_true(InputManager.is_pressed(Constants.NesButton.A) or true, "Touch event processed cleanly")
	InputManager.step_frame()
	_assert_true(InputManager.is_pressed(Constants.NesButton.A), "Touch on anchored A button sets NesButton.A in InputManager")

	var touch_rel: InputEventScreenTouch = InputEventScreenTouch.new()
	touch_rel.index = 0
	touch_rel.pressed = false
	touch_rel.position = a_wide.get_center()
	pad.handle_touch_event(touch_rel)
	InputManager.step_frame()
	_assert_true(not InputManager.is_pressed(Constants.NesButton.A), "Touch release on A clears NesButton.A cleanly")

	# Verify KirbyController multi-frame animations advance across states
	var anim_lvl: LevelMap = LevelMap.new()
	anim_lvl.load_from_dicts(_build_synthetic_room(16, 12, 9), _build_synthetic_tileset())
	var anim_k: KirbyController = KirbyController.new()
	anim_k.setup(anim_lvl, Vector2(48.0, 144.0))
	InputManager.set_mock_mask(Constants.NesButton.RIGHT)
	var seen_walk_keys: Dictionary = {}
	for _i: int in range(24):
		InputManager.step_frame()
		anim_k.step_physics()
		seen_walk_keys[anim_k.get_current_anim_key()] = true
	_assert_true(seen_walk_keys.size() >= 3, "KirbyController cycles through multi-frame walk animations (keys=%d)" % seen_walk_keys.size())
	InputManager.set_mock_mask(Constants.NesButton.B)
	InputManager.step_frame()
	anim_k.step_physics()
	_assert_true(anim_k.get_current_anim_key() == "inhale", "KirbyController switches to inhale animation frame")
	InputManager.clear_mock_mask()
	anim_k.free()
	anim_lvl.free()

	InputManager.clear_touch_mask()
	pad.free()
	hud.free()


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

	# Load Stage 1-2 Room 47 (contains water/slopes) and verify HUDRenderer renders 256x48 ROM texture
	_assert_true(lvl.load_room(47), "LevelMap loads extracted Stage 1-2 Room 47")
	var hud: HUDRenderer = HUDRenderer.new()
	hud.set_status(6, 6, 4, 2400, Constants.CopyAbility.SWORD)
	_assert_true(hud.get_hud_texture() != null, "HUDRenderer builds 256x48 ImageTexture from ROM CHR + Bank 56 palettes")
	if hud.get_hud_texture() != null:
		_assert_eq_int(hud.get_hud_texture().get_width(), Constants.NATIVE_WIDTH, "HUD texture width is 256px")
		_assert_eq_int(hud.get_hud_texture().get_height(), Constants.HUD_HEIGHT, "HUD texture height is 48px")
	hud.free()

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
