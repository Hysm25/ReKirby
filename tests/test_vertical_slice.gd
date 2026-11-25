extends RefCounted
## Verification tests for Phase 4: World 1 Vegetable Valley enemies (7 types),
## StarProjectile & inhale/ability-drop loop, Whispy Woods boss fight in Room 30,
## Stage 1-1..1-3 room progression, and Main vertical-slice integration.

const Constants = preload("res://src/core/constants.gd")
const LevelMap = preload("res://src/game/level_map.gd")
const KirbyController = preload("res://src/game/kirby_controller.gd")
const EnemyBase = preload("res://src/game/entities/enemy_base.gd")
const StarProjectile = preload("res://src/game/entities/star_projectile.gd")
const WhispyWoods = preload("res://src/game/entities/whispy_woods.gd")
const HUDRenderer = preload("res://src/game/hud_renderer.gd")
const MainScript = preload("res://src/main.gd")
const ROMImporter = preload("res://src/importer/rom_importer.gd")
const MAX_CLEANUP_ENTRIES: int = 2048

var _passed: int = 0
var _failed: int = 0


func run_tests() -> Dictionary:
	_test_actor_id_and_ability_mappings()
	_test_enemy_behaviors_and_inhale_copy()
	_test_star_projectile_physics_and_block_break()
	_test_whispy_woods_boss_cycle_and_defeat()
	_test_live_world1_stages_and_boss_vertical_slice()
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


func _build_flat_arena() -> LevelMap:
	var mts: Array[Dictionary] = [
		{"tl": 0, "tr": 0, "bl": 0, "br": 0, "palette": 0, "raw_prop": 0, "nes_collision": 0, "collision": Constants.TileCollision.AIR},
		{"tl": 0, "tr": 0, "bl": 0, "br": 0, "palette": 0, "raw_prop": 1, "nes_collision": 2, "collision": Constants.TileCollision.SOLID},
		{"tl": 0, "tr": 0, "bl": 0, "br": 0, "palette": 0, "raw_prop": 2, "nes_collision": 0x22, "collision": Constants.TileCollision.BREAKABLE_STAR},
	]
	var grid: Array[int] = []
	grid.resize(16 * 12)
	for i: int in range(grid.size()):
		grid[i] = 0
	for mx: int in range(16):
		grid[9 * 16 + mx] = 1
	grid[8 * 16 + 10] = 2 # Star block at (10, 8)
	var lvl: LevelMap = LevelMap.new()
	lvl.load_from_dicts({
		"room_id": 990,
		"tileset_id": 0,
		"width_screens": 1,
		"height_screens": 1,
		"width_metatiles": 16,
		"height_metatiles": 12,
		"metatiles": grid,
		"doors": [],
		"entities": [],
	}, {"tileset_id": 0, "metatiles": mts})
	return lvl


func _test_actor_id_and_ability_mappings() -> void:
	_assert_eq_int(EnemyBase.map_rom_actor_id(14), EnemyBase.EnemyType.WADDLE_DEE, "ROM actor_id 14 maps to Waddle Dee")
	_assert_eq_int(EnemyBase.map_rom_actor_id(15), EnemyBase.EnemyType.WADDLE_DOO, "ROM actor_id 15 maps to Waddle Doo")
	_assert_eq_int(EnemyBase.map_rom_actor_id(56), EnemyBase.EnemyType.POPPY_BROS_JR, "ROM actor_id 56 maps to Poppy Bros. Jr.")
	_assert_eq_int(EnemyBase.map_rom_actor_id(17), EnemyBase.EnemyType.BLADE_KNIGHT, "ROM actor_id 17 maps to Blade Knight")
	_assert_eq_int(EnemyBase.map_rom_actor_id(18), EnemyBase.EnemyType.HOT_HEAD, "ROM actor_id 18 maps to Hot Head")
	_assert_eq_int(EnemyBase.map_rom_actor_id(16), EnemyBase.EnemyType.SPARKY, "ROM actor_id 16 maps to Sparky")
	_assert_eq_int(EnemyBase.map_rom_actor_id(41), EnemyBase.EnemyType.BRONTO_BURT, "ROM actor_id 41 maps to Bronto Burt")
	_assert_eq_int(EnemyBase.map_rom_actor_id(6), -1, "Room 30 boss/apple actor_id 6 handled by WhispyWoods")

	_assert_eq_int(EnemyBase.default_ability_for_type(EnemyBase.EnemyType.WADDLE_DOO), Constants.CopyAbility.BEAM, "Waddle Doo grants Beam")
	_assert_eq_int(EnemyBase.default_ability_for_type(EnemyBase.EnemyType.BLADE_KNIGHT), Constants.CopyAbility.SWORD, "Blade Knight grants Sword")
	_assert_eq_int(EnemyBase.default_ability_for_type(EnemyBase.EnemyType.HOT_HEAD), Constants.CopyAbility.FIRE, "Hot Head grants Fire")
	_assert_eq_int(EnemyBase.default_ability_for_type(EnemyBase.EnemyType.SPARKY), Constants.CopyAbility.SPARK, "Sparky grants Spark")
	_assert_eq_int(EnemyBase.default_ability_for_type(EnemyBase.EnemyType.WADDLE_DEE), Constants.CopyAbility.NONE, "Waddle Dee grants NONE")


func _test_enemy_behaviors_and_inhale_copy() -> void:
	var lvl: LevelMap = _build_flat_arena()
	var kirby_pos: Vector2 = Vector2(48.0, 144.0)

	# Waddle Dee patrols horizontally and cycles animation frames
	var dee: EnemyBase = EnemyBase.new()
	dee.setup(EnemyBase.EnemyType.WADDLE_DEE, Vector2(120.0, 144.0), lvl, -1)
	var dee_start_x: float = dee.pos.x
	var dee_frames: Dictionary = {}
	for _i: int in range(16):
		dee.step_physics(kirby_pos)
		dee_frames[dee.get_current_anim_frame_index()] = true
	_assert_true(dee.pos.x < dee_start_x and dee.on_ground, "Waddle Dee walks along solid floor")
	_assert_eq_int(dee_frames.size(), 2, "Waddle Dee alternates between 2 walk animation frames")

	# Waddle Doo fires enemy_beam
	var doo: EnemyBase = EnemyBase.new()
	doo.setup(EnemyBase.EnemyType.WADDLE_DOO, Vector2(120.0, 144.0), lvl, -1)
	var doo_fired: bool = false
	for _i: int in range(55):
		doo.step_physics(kirby_pos)
		var spawned: Array[Dictionary] = doo.consume_spawned_projectiles()
		if not spawned.is_empty() and String(spawned[0].get("kind", "")) == "enemy_beam":
			doo_fired = true
			break
	_assert_true(doo_fired, "Waddle Doo emits enemy_beam attack")

	# Poppy Bros. Jr. hops
	var poppy: EnemyBase = EnemyBase.new()
	poppy.setup(EnemyBase.EnemyType.POPPY_BROS_JR, Vector2(120.0, 144.0), lvl, -1)
	var poppy_airborne: bool = false
	for _i: int in range(60):
		poppy.step_physics(kirby_pos)
		if poppy.vel.y < -1.0:
			poppy_airborne = true
			break
	_assert_true(poppy_airborne, "Poppy Bros. Jr. performs rhythmic hop")

	# Blade Knight lunges with sword hitbox when Kirby is close
	var knight: EnemyBase = EnemyBase.new()
	knight.setup(EnemyBase.EnemyType.BLADE_KNIGHT, Vector2(76.0, 144.0), lvl, -1)
	var knight_slashed: bool = false
	for _i: int in range(55):
		knight.step_physics(kirby_pos)
		var hb: Dictionary = knight.get_attack_hitbox()
		if bool(hb.get("active", false)) and String(hb.get("kind", "")) == "enemy_sword":
			knight_slashed = true
			break
	_assert_true(knight_slashed, "Blade Knight activates sword slash hitbox near Kirby")

	# Hot Head emits enemy_fire
	var hot: EnemyBase = EnemyBase.new()
	hot.setup(EnemyBase.EnemyType.HOT_HEAD, Vector2(120.0, 144.0), lvl, -1)
	var hot_fired: bool = false
	for _i: int in range(55):
		hot.step_physics(kirby_pos)
		var spawned: Array[Dictionary] = hot.consume_spawned_projectiles()
		if not spawned.is_empty() and String(spawned[0].get("kind", "")) == "enemy_fire":
			hot_fired = true
			break
	_assert_true(hot_fired, "Hot Head emits enemy_fire projectile")

	# Sparky activates 360-degree enemy_spark aura
	var sparky: EnemyBase = EnemyBase.new()
	sparky.setup(EnemyBase.EnemyType.SPARKY, Vector2(120.0, 144.0), lvl, -1)
	var spark_active: bool = false
	for _i: int in range(60):
		sparky.step_physics(kirby_pos)
		var hb: Dictionary = sparky.get_attack_hitbox()
		if bool(hb.get("active", false)) and String(hb.get("kind", "")) == "enemy_spark":
			spark_active = true
			break
	_assert_true(spark_active, "Sparky activates 360-deg electric barrier hitbox")

	# Bronto Burt flies in sine wave
	var bronto: EnemyBase = EnemyBase.new()
	bronto.setup(EnemyBase.EnemyType.BRONTO_BURT, Vector2(140.0, 80.0), lvl, -1)
	var min_y: float = 999.0
	var max_y: float = -999.0
	for _i: int in range(45):
		bronto.step_physics(kirby_pos)
		min_y = minf(min_y, bronto.pos.y)
		max_y = maxf(max_y, bronto.pos.y)
	_assert_true(max_y - min_y > 8.0 and bronto.pos.x < 140.0, "Bronto Burt flies in sine wave pattern")

	# Inhale + Swallow integration: Kirby inhales Sparky and gains CopyAbility.SPARK
	var kirby: KirbyController = KirbyController.new()
	kirby.setup(lvl, Vector2(48.0, 144.0))
	sparky.setup(EnemyBase.EnemyType.SPARKY, Vector2(76.0, 144.0), lvl, -1)
	InputManager.set_mock_mask(Constants.NesButton.B)
	for _i: int in range(25):
		InputManager.step_frame()
		kirby.step_physics()
		var mouth: Vector2 = Vector2(kirby.pos.x, kirby.pos.y - 8.0)
		var hbs: Array[Dictionary] = kirby.get_active_hitboxes()
		if kirby.state == KirbyController.State.INHALE and not hbs.is_empty():
			var ir: Rect2 = hbs[0].get("rect", Rect2()) as Rect2
			if sparky.state == EnemyBase.State.BEING_INHALED or ir.intersects(sparky.get_body_rect()):
				sparky.begin_inhale_pull(mouth)
		sparky.step_physics(kirby.pos)
		if sparky.is_ready_for_capture(mouth):
			if kirby.capture_inhaled_cargo(sparky.get_copy_ability()):
				sparky.mark_captured()
				break
	_assert_true(not sparky.is_alive() and kirby.has_cargo, "Kirby inhales and captures Sparky into Mouth-Full state")
	InputManager.set_mock_mask(Constants.NesButton.DOWN)
	InputManager.step_frame()
	kirby.step_physics()
	_assert_eq_int(kirby.copy_ability, Constants.CopyAbility.SPARK, "Swallowing Sparky grants CopyAbility.SPARK")

	InputManager.clear_mock_mask()
	for n: Node in [dee, doo, poppy, knight, hot, sparky, bronto, kirby, lvl]:
		n.free()


func _test_star_projectile_physics_and_block_break() -> void:
	var lvl: LevelMap = _build_flat_arena()
	var star: StarProjectile = StarProjectile.new()
	star.setup(StarProjectile.Kind.STAR_SPIT, Vector2(120.0, 136.0), Vector2(4.5, 0.0), lvl)
	for _i: int in range(15):
		star.step_physics()
		if not star.is_alive():
			break
	_assert_eq_int(lvl.get_collision_at_tile(10, 8), Constants.TileCollision.AIR, "Star Spit breaks BREAKABLE_STAR block at (10,8)")
	_assert_true(not star.is_alive(), "Star Spit dissipates after breaking star block")

	# Ability Star bounces off floor and stays inhalable
	var ab_star: StarProjectile = StarProjectile.new()
	ab_star.setup(StarProjectile.Kind.ABILITY_STAR, Vector2(64.0, 110.0), Vector2(0.8, 0.0), lvl, Constants.CopyAbility.BEAM)
	var bounced: bool = false
	for _i: int in range(30):
		ab_star.step_physics()
		if ab_star.vel.y < -1.5:
			bounced = true
			break
	_assert_true(bounced and ab_star.is_inhalable(), "Dropped Ability Star bounces on floor and remains inhalable")
	_assert_eq_int(ab_star.get_ability_id(), Constants.CopyAbility.BEAM, "Ability Star retains CopyAbility.BEAM payload")

	star.free()
	ab_star.free()
	lvl.free()


func _test_whispy_woods_boss_cycle_and_defeat() -> void:
	var lvl: LevelMap = _build_flat_arena()
	var boss: WhispyWoods = WhispyWoods.new()
	var hud: HUDRenderer = HUDRenderer.new()
	hud.connect_event_bus()
	boss.setup(Vector2(160.0, 144.0), lvl)
	_assert_eq_int(hud.get_displayed_boss_hp(), WhispyWoods.DEFAULT_MAX_HP, "Whispy Woods initializes HUD boss HP bar via EventBus")

	var saw_apple: bool = false
	var saw_puff: bool = false
	var kirby_pos: Vector2 = Vector2(48.0, 144.0)
	for _i: int in range(240):
		boss.step_physics(kirby_pos)
		var spawned: Array[Dictionary] = boss.consume_spawned_projectiles()
		for item: Dictionary in spawned:
			var k: String = String(item.get("kind", ""))
			if k == "apple":
				saw_apple = true
			elif k == "boss_air_puff":
				saw_puff = true
	_assert_true(saw_apple, "Whispy Woods drops inhalable apples during attack cycle")
	_assert_true(saw_puff, "Whispy Woods fires horizontal boss_air_puff attacks")

	# Defeat Whispy Woods with Star Spit hits (6 hits x 2 dmg = 12 HP)
	for _hit: int in range(6):
		for _wait: int in range(WhispyWoods.HIT_INVULN_FRAMES + 1):
			boss.step_physics(kirby_pos)
		boss.take_damage(2)
	_assert_true(boss.is_defeated(), "Whispy Woods enters DEFEATED after 12 damage")
	_assert_eq_int(hud.get_displayed_boss_hp(), 0, "Boss HP bar reaches 0 upon Whispy Woods defeat")
	var defeat_drops: Array[Dictionary] = boss.consume_spawned_projectiles()
	var spawned_goal_rod: bool = false
	for drop_d: Dictionary in defeat_drops:
		if String(drop_d.get("kind", "")) == "goal_star_rod":
			spawned_goal_rod = true
			break
	_assert_true(spawned_goal_rod, "Defeating Whispy Woods spawns goal_star_rod")

	hud.free()
	boss.free()
	lvl.free()


func _test_live_world1_stages_and_boss_vertical_slice() -> void:
	var test_user_dir: String = ""
	if not ContentRegistry.is_ready():
		var candidates: Array[String] = ROMImporter.find_candidate_roms()
		if candidates.is_empty():
			print("  [INFO] No local ROM present in rom/ — skipping live World 1 vertical slice test.")
			return
		test_user_dir = "user://nes_data_vs_test"
		var res: ROMImporter.ImportResult = ROMImporter.import_rom_file(candidates[0], test_user_dir, true)
		_assert_true(res.success, "Live ROM import succeeds for vertical slice (%s)" % res.error)

	var game: Node2D = MainScript.new()
	game._build_ui_layout()
	game._enter_ready_state()

	# Verify Stage 1-1 Room 43 spawns authentic enemies
	_assert_true(game.get_enemies().size() >= 5, "Stage 1-1 Room 43 spawns World 1 enemies (count=%d)" % game.get_enemies().size())

	# Progress across Stage 1-2 (47), Stage 1-3 (53), and Boss Room 30 (Whispy Woods)
	_assert_true(game.load_world_room(47, Vector2(40.0, 128.0), true), "Main transitions to Stage 1-2 Room 47")
	_assert_true(game.get_enemies().size() >= 3, "Stage 1-2 Room 47 spawns enemies")
	_assert_true(game.load_world_room(53, Vector2(40.0, 128.0), true), "Main transitions to Stage 1-3 Room 53")
	_assert_true(game.get_enemies().size() >= 3, "Stage 1-3 Room 53 spawns enemies")
	_assert_true(game.load_world_room(30, Vector2(48.0, 512.0), true), "Main transitions to Boss Room 30")
	_assert_true(game.get_boss() != null, "Boss Room 30 spawns WhispyWoods")

	# Verify vertical multi-screen exit door resolution in Room 30 (screen=2, x=7, y=6 -> pixel ~(120, 488))
	var exit_door: Dictionary = game._level_map.find_door_at_pixel(120.0, 488.0)
	_assert_eq_int(int(exit_door.get("dest_room_id", -1)), 0, "Room 30 vertical screen 2 door resolves cleanly to Hub Room 0")

	# Step deterministic 60 TPS simulation in Boss Room 30 and defeat boss via Star Spit
	InputManager.set_mock_mask(0)
	for _i: int in range(30):
		InputManager.step_frame()
		game.step_gameplay_frame()

	var boss: WhispyWoods = game.get_boss()
	_assert_true(boss != null and boss.phase != WhispyWoods.Phase.INTRO, "Whispy Woods advances out of INTRO at 60 TPS")
	if boss != null:
		boss.hp = 2
		var spit: StarProjectile = StarProjectile.new()
		spit.setup(StarProjectile.Kind.STAR_SPIT, Vector2(boss.pos.x - 16.0, boss.pos.y - 20.0), Vector2(4.5, 0.0), game._level_map)
		game._projectiles_layer.add_child(spit)
		game._projectiles.append(spit)
		for _i: int in range(10):
			InputManager.step_frame()
			game.step_gameplay_frame()
		_assert_true(boss.is_defeated(), "Star Spit defeats Whispy Woods inside Main simulation")
		_assert_true(game.get_score() >= WhispyWoods.DEFEAT_SCORE, "Defeating Whispy Woods awards 5000 score points")

		# Collect spawned goal_star_rod and verify victory state triggers
		var found_rod: StarProjectile = null
		for p: StarProjectile in game.get_projectiles():
			if is_instance_valid(p) and p.is_goal_pickup():
				found_rod = p
				break
		_assert_true(found_rod != null, "Goal Star Rod exists in Room 30 after Whispy Woods defeat")
		if found_rod != null:
			found_rod.pos = Vector2(game._kirby.pos.x, game._kirby.pos.y - 8.0)
			InputManager.step_frame()
			game.step_gameplay_frame()
			_assert_true(game.get_score() >= WhispyWoods.DEFEAT_SCORE + MainScript.STAGE_CLEAR_BONUS, "Collecting Goal Star Rod awards Stage Clear bonus")

	InputManager.clear_mock_mask()
	game._clear_room_entities()
	game.free()
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
