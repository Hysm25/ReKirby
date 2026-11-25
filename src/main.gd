extends Node2D
## Root boot coordinator, Mandatory ROM Setup Guard, and 60 TPS World 1 simulation loop.

const Constants = preload("res://src/core/constants.gd")
const ROMImporter = preload("res://src/importer/rom_importer.gd")
const LevelMap = preload("res://src/game/level_map.gd")
const KirbyController = preload("res://src/game/kirby_controller.gd")
const HUDRenderer = preload("res://src/game/hud_renderer.gd")
const VirtualGamepad = preload("res://src/game/virtual_gamepad.gd")
const APUEngine = preload("res://src/audio/apu_engine.gd")
const MusicPlayer = preload("res://src/audio/music_player.gd")
const EnemyBase = preload("res://src/game/entities/enemy_base.gd")
const StarProjectile = preload("res://src/game/entities/star_projectile.gd")
const WhispyWoods = preload("res://src/game/entities/whispy_woods.gd")
const BossController = preload("res://src/game/entities/boss_controller.gd")
const TitleScreen = preload("res://src/game/title_screen.gd")
const SaveManager = preload("res://src/core/save_manager.gd")

const DEFAULT_START_ROOM_ID: int = 43
const BOSS_ROOM_ID: int = 30
const BOSS_ROOM_IDS: Array[int] = [30, 31, 32, 33, 34, 35, 36]
const WORLD_NAMES: Array[String] = [
	"VEGETABLE VALLEY",
	"ICE CREAM ISLAND",
	"BUTTER BUILDING",
	"GRAPE GARDEN",
	"YOGURT YARD",
	"ORANGE OCEAN",
	"RAINBOW RESORT",
]
const DEFAULT_SPAWN_POS: Vector2 = Vector2(40.0, 128.0)
const STAGE_CLEAR_BONUS: int = 2000
const RESPAWN_DELAY_FRAMES: int = 60
const VICTORY_RETURN_FRAMES: int = 90
const DOOR_FADE_FRAMES: int = 8

var _current_state: int = Constants.GameState.ROM_SETUP
var _stage_root: Control = null
var _missing_rom_panel: Control = null
var _title_screen: TitleScreen = null
var _gameplay_panel: Control = null
var _playfield_clip: Control = null
var _transition_rect: ColorRect = null
var _world_container: Node2D = null
var _level_map: LevelMap = null
var _enemies_layer: Node2D = null
var _projectiles_layer: Node2D = null
var _kirby: KirbyController = null
var _hud_renderer: HUDRenderer = null
var _virtual_gamepad: VirtualGamepad = null
var _apu_engine: APUEngine = null
var _music_player: MusicPlayer = null
var _status_label: Label = null
var _camera_offset: Vector2 = Vector2.ZERO

var _enemies: Array[EnemyBase] = []
var _projectiles: Array[StarProjectile] = []
var _boss: Node2D = null

var _current_room_id: int = DEFAULT_START_ROOM_ID
var _room_spawn_pos: Vector2 = DEFAULT_SPAWN_POS
var _lives: int = 4
var _score: int = 0
var _defeat_frames: int = 0
var _victory_frames: int = 0
var _fade_frames: int = 0
var _cleared_stages: Dictionary = {}
var _current_world: int = 1
var _unlocked_world: int = 1
var _active_save_slot: int = 0
var _pre_pause_state: int = Constants.GameState.PLAYING
var _overlay_panel: ColorRect = null
var _overlay_label: Label = null


func _ready() -> void:
	_build_ui_layout()
	_attempt_rom_boot()


func _physics_process(_delta: float) -> void:
	if _current_state == Constants.GameState.ROM_SETUP:
		return
	InputManager.step_frame()
	if _current_state == Constants.GameState.TITLE:
		if _title_screen != null:
			_title_screen.step_frame()
		if InputManager.is_just_pressed(Constants.NesButton.START) or InputManager.is_just_pressed(Constants.NesButton.A):
			start_new_game()
	elif _current_state == Constants.GameState.PAUSED:
		if InputManager.is_just_pressed(Constants.NesButton.START):
			toggle_pause()
		elif InputManager.is_just_pressed(Constants.NesButton.SELECT):
			_set_overlay(false, "")
			var hub_id: int = clampi(_current_world - 1, 0, 6)
			load_world_room(hub_id, DEFAULT_SPAWN_POS, true)
	elif _current_state == Constants.GameState.GAME_OVER:
		if InputManager.is_just_pressed(Constants.NesButton.START) or InputManager.is_just_pressed(Constants.NesButton.A):
			_set_overlay(false, "")
			_lives = 4
			_score = 0
			EventBus.score_changed.emit(_score, 0)
			EventBus.lives_changed.emit(_lives)
			var hub_id: int = clampi(_current_world - 1, 0, 6)
			load_world_room(hub_id, DEFAULT_SPAWN_POS, false)
	elif _current_state == Constants.GameState.ENDING:
		if InputManager.is_just_pressed(Constants.NesButton.START) or InputManager.is_just_pressed(Constants.NesButton.A):
			_set_overlay(false, "")
			_enter_ready_state()
	elif _kirby != null and _level_map != null and (_current_state == Constants.GameState.PLAYING or _current_state == Constants.GameState.BOSS_FIGHT):
		if InputManager.is_just_pressed(Constants.NesButton.START):
			toggle_pause()
		else:
			step_gameplay_frame()
	if _music_player != null:
		_music_player.step_frame()
	if _apu_engine != null:
		_apu_engine.step_audio_frame()


func step_gameplay_frame() -> void:
	if _kirby == null or _level_map == null:
		return

	if _victory_frames > 0:
		_victory_frames -= 1
		if _victory_frames == 0:
			var cleared_world: int = _current_world
			if BOSS_ROOM_IDS.has(_current_room_id):
				cleared_world = _current_room_id - BOSS_ROOM_ID + 1
				_cleared_stages["boss_%d" % cleared_world] = true
				_cleared_stages["boss"] = true
				_unlocked_world = maxi(_unlocked_world, mini(7, cleared_world + 1))
				SaveManager.record_world_clear(
					_active_save_slot,
					cleared_world,
					_score,
					_lives,
					_kirby.copy_ability if _kirby != null else Constants.CopyAbility.NONE
				)
			if _current_room_id == 36 or _current_room_id == Constants.FOUNTAIN_OF_DREAMS_ROOM_ID:
				_enter_ending_state()
				return
			var target_hub: int = clampi(cleared_world - 1, 0, 6)
			var hub_data: Dictionary = ContentRegistry.get_room_data(target_hub)
			var hub_w_scr: int = maxi(1, int(hub_data.get("width_screens", 2)))
			var hub_sx: int = 1 % hub_w_scr
			var hub_sy: int = 1 / hub_w_scr
			var hub_spawn: Vector2 = Vector2(
				float((hub_sx * Constants.ROOM_SCREEN_COLS + 12) * Constants.METATILE_SIZE + 8),
				float((hub_sy * Constants.ROOM_SCREEN_ROWS + 5) * Constants.METATILE_SIZE)
			)
			if load_world_room(target_hub, hub_spawn, true):
				_update_camera_scroll()
		return

	if _fade_frames > 0:
		_fade_frames -= 1
		if _transition_rect != null:
			_transition_rect.color.a = float(_fade_frames) / float(DOOR_FADE_FRAMES)
			_transition_rect.visible = _fade_frames > 0

	_kirby.step_physics()
	_spawn_projectile_list(_kirby.consume_spawned_projectiles())

	if _check_door_transition():
		return

	if _kirby.state != KirbyController.State.DEFEAT and _kirby.pos.y > float(_level_map.get_height_pixels()) + 16.0:
		_kirby.hp = 0
		_kirby.state = KirbyController.State.DEFEAT
		_kirby.vel = Vector2(0.0, -3.0)
		EventBus.hp_changed.emit(_kirby.hp, _kirby.max_hp)

	if _kirby.state == KirbyController.State.DEFEAT:
		_defeat_frames += 1
		if _defeat_frames >= RESPAWN_DELAY_FRAMES:
			_handle_kirby_respawn()
		_update_camera_scroll()
		if _hud_renderer != null:
			_hud_renderer.refresh()
		return
	_defeat_frames = 0

	var kirby_rect: Rect2 = _kirby.get_body_rect()
	var kirby_mouth: Vector2 = Vector2(_kirby.pos.x, _kirby.pos.y - 8.0)
	var kirby_hitboxes: Array[Dictionary] = _kirby.get_active_hitboxes()
	var inhale_rect: Rect2 = Rect2()
	var is_inhaling: bool = _kirby.state == KirbyController.State.INHALE
	if is_inhaling and not kirby_hitboxes.is_empty():
		inhale_rect = kirby_hitboxes[0].get("rect", Rect2()) as Rect2

	_step_enemies(kirby_rect, kirby_mouth, kirby_hitboxes, is_inhaling, inhale_rect)
	_step_boss(kirby_rect, kirby_hitboxes)
	_step_projectiles(kirby_rect, kirby_mouth, is_inhaling, inhale_rect)

	_update_camera_scroll()
	if _hud_renderer != null:
		_hud_renderer.step_frame()
		_hud_renderer.refresh()


static func _dispose_node(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n.is_inside_tree():
		n.queue_free()
	else:
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.free()


func _step_enemies(
	kirby_rect: Rect2,
	kirby_mouth: Vector2,
	kirby_hitboxes: Array[Dictionary],
	is_inhaling: bool,
	inhale_rect: Rect2
) -> void:
	var surviving: Array[EnemyBase] = []
	for enemy: EnemyBase in _enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			_dispose_node(enemy)
			continue

		if is_inhaling:
			if enemy.state == EnemyBase.State.BEING_INHALED or inhale_rect.intersects(enemy.get_body_rect()):
				enemy.begin_inhale_pull(kirby_mouth)
		elif enemy.state == EnemyBase.State.BEING_INHALED:
			enemy.release_inhale_pull()

		enemy.step_physics(_kirby.pos)
		_spawn_projectile_list(enemy.consume_spawned_projectiles())

		if is_inhaling and enemy.is_ready_for_capture(kirby_mouth):
			var ab_id: int = enemy.get_copy_ability()
			if _kirby.capture_inhaled_cargo(ab_id):
				enemy.mark_captured()
				_dispose_node(enemy)
				continue

		# Check Kirby attack / slide hitboxes against enemy
		var enemy_rect: Rect2 = enemy.get_body_rect()
		for hb: Dictionary in kirby_hitboxes:
			if not bool(hb.get("active", false)):
				continue
			var kind_str: String = String(hb.get("kind", ""))
			if kind_str == "inhale":
				continue
			var hb_rect: Rect2 = hb.get("rect", Rect2()) as Rect2
			if hb_rect.intersects(enemy_rect):
				var dmg: int = int(hb.get("damage", 1))
				var kdir: int = 1 if enemy.pos.x >= _kirby.pos.x else -1
				if enemy.take_damage(dmg, kdir):
					_spawn_projectile_list(enemy.consume_spawned_projectiles())
					if not enemy.is_alive():
						_add_score(enemy.score_value)
						break

		if not enemy.is_alive():
			_dispose_node(enemy)
			continue

		# Enemy contact & attack damage to Kirby
		var hit_kirby: bool = false
		if enemy.state == EnemyBase.State.ACTIVE and enemy_rect.intersects(kirby_rect):
			hit_kirby = true
		else:
			var e_hb: Dictionary = enemy.get_attack_hitbox()
			if bool(e_hb.get("active", false)):
				var e_rect: Rect2 = e_hb.get("rect", Rect2()) as Rect2
				if e_rect.intersects(kirby_rect):
					hit_kirby = true

		if hit_kirby:
			var knock_dir: int = 1 if _kirby.pos.x >= enemy.pos.x else -1
			_kirby.take_damage(1, knock_dir)

		surviving.append(enemy)
	_enemies = surviving


func _step_boss(kirby_rect: Rect2, kirby_hitboxes: Array[Dictionary]) -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	var was_defeated: bool = _boss.is_defeated()
	_boss.step_physics(_kirby.pos)
	_spawn_projectile_list(_boss.consume_spawned_projectiles())

	if _boss.is_defeated():
		if not was_defeated:
			_add_score(WhispyWoods.DEFEAT_SCORE)
		return

	var boss_rect: Rect2 = _boss.get_body_rect()
	for hb: Dictionary in kirby_hitboxes:
		if not bool(hb.get("active", false)):
			continue
		if String(hb.get("kind", "")) == "inhale":
			continue
		var hb_rect: Rect2 = hb.get("rect", Rect2()) as Rect2
		if hb_rect.intersects(boss_rect):
			var dmg: int = int(hb.get("damage", 1))
			if _boss.take_damage(dmg) and _boss.is_defeated():
				_add_score(WhispyWoods.DEFEAT_SCORE)
				_spawn_projectile_list(_boss.consume_spawned_projectiles())
				break

	if not _boss.is_defeated() and int(_boss.get("phase")) != 0 and boss_rect.intersects(kirby_rect):
		var knock_dir: int = -1 if _kirby.pos.x <= _boss.pos.x else 1
		_kirby.take_damage(1, knock_dir)


func _step_projectiles(
	kirby_rect: Rect2,
	kirby_mouth: Vector2,
	is_inhaling: bool,
	inhale_rect: Rect2
) -> void:
	var surviving: Array[StarProjectile] = []
	for proj: StarProjectile in _projectiles:
		if not is_instance_valid(proj) or not proj.is_alive():
			_dispose_node(proj)
			continue

		if is_inhaling and proj.is_inhalable():
			if proj.is_being_inhaled() or inhale_rect.intersects(proj.get_hitbox_rect()):
				proj.begin_inhale_pull(kirby_mouth)
		elif proj.is_being_inhaled():
			proj.cancel_inhale_pull()

		proj.step_physics()
		if not proj.is_alive():
			_dispose_node(proj)
			continue

		if is_inhaling and proj.is_ready_for_capture(kirby_mouth):
			if _kirby.capture_inhaled_cargo(proj.get_ability_id()):
				proj.kill()
				_dispose_node(proj)
				continue

		var p_rect: Rect2 = proj.get_hitbox_rect()

		if proj.is_goal_pickup():
			if p_rect.intersects(kirby_rect):
				proj.kill()
				_dispose_node(proj)
				_trigger_stage_victory()
				continue
		elif proj.is_friendly():
			var hit_something: bool = false
			for enemy: EnemyBase in _enemies:
				if not is_instance_valid(enemy) or not enemy.is_alive():
					continue
				if p_rect.intersects(enemy.get_body_rect()):
					var kdir: int = 1 if proj.vel.x >= 0.0 else -1
					if enemy.take_damage(proj.get_damage(), kdir):
						if not enemy.is_alive():
							_add_score(enemy.score_value)
							EventBus.sfx_requested.emit(Constants.NesSfx.BLOCK_BREAK)
						hit_something = true
						break
			if not hit_something and _boss != null and is_instance_valid(_boss) and not _boss.is_defeated():
				if p_rect.intersects(_boss.get_body_rect()):
					if _boss.take_damage(proj.get_damage()):
						if _boss.is_defeated():
							_add_score(WhispyWoods.DEFEAT_SCORE)
							_spawn_projectile_list(_boss.consume_spawned_projectiles())
							EventBus.sfx_requested.emit(Constants.NesSfx.STAGE_CLEAR)
						else:
							EventBus.sfx_requested.emit(Constants.NesSfx.BLOCK_BREAK)
					hit_something = true
			if hit_something:
				proj.kill()
				_dispose_node(proj)
				continue
		elif proj.is_hostile():
			if p_rect.intersects(kirby_rect):
				var knock_dir: int = 1 if _kirby.pos.x >= proj.pos.x else -1
				_kirby.take_damage(1, knock_dir)
				proj.kill()
				_dispose_node(proj)
				continue

		surviving.append(proj)
	_projectiles = surviving


func _spawn_projectile_list(items: Array[Dictionary]) -> void:
	if items.is_empty():
		return
	for item: Dictionary in items:
		var proj: StarProjectile = StarProjectile.from_spawn_dict(item, _level_map)
		if _projectiles_layer != null:
			_projectiles_layer.add_child(proj)
		_projectiles.append(proj)


func _add_score(points: int) -> void:
	if points <= 0:
		return
	_score += points
	EventBus.score_changed.emit(_score, points)


func _trigger_stage_victory() -> void:
	_add_score(STAGE_CLEAR_BONUS)
	_victory_frames = VICTORY_RETURN_FRAMES
	if ContentRegistry.has_music_track(1):
		EventBus.bgm_requested.emit(1)


func _handle_kirby_respawn() -> void:
	_defeat_frames = 0
	_lives -= 1
	if _lives <= 0:
		_lives = 0
		EventBus.lives_changed.emit(_lives)
		var prev: int = _current_state
		_current_state = Constants.GameState.GAME_OVER
		_set_overlay(true, "GAME OVER\n\nPRESS START TO CONTINUE\nWORLD %d: %s" % [_current_world, _get_world_name(_current_world)])
		EventBus.game_state_changed.emit(_current_state, prev)
	else:
		EventBus.lives_changed.emit(_lives)
		load_world_room(_current_room_id, _room_spawn_pos, false)


func _enter_ending_state() -> void:
	var prev: int = _current_state
	_current_state = Constants.GameState.ENDING
	_set_overlay(true, "CONGRATULATIONS!\nFOUNTAIN OF DREAMS RESTORED!\n\nSCORE: %07d\nPRESS START FOR TITLE" % _score)
	EventBus.game_state_changed.emit(_current_state, prev)


func toggle_pause() -> void:
	if _current_state == Constants.GameState.PAUSED:
		var prev: int = _current_state
		_current_state = _pre_pause_state
		_set_overlay(false, "")
		EventBus.game_state_changed.emit(_current_state, prev)
	elif _current_state == Constants.GameState.PLAYING or _current_state == Constants.GameState.BOSS_FIGHT:
		_pre_pause_state = _current_state
		_current_state = Constants.GameState.PAUSED
		var ab_name: String = "NORMAL"
		if _kirby != null and _kirby._active_ability != null:
			ab_name = _kirby._active_ability.get_ability_name()
		_set_overlay(true, "PAUSED\n\nWORLD %d: %s\nABILITY: %s\n\nSTART: RESUME\nSELECT: WORLD HUB" % [_current_world, _get_world_name(_current_world), ab_name])
		EventBus.game_state_changed.emit(_current_state, _pre_pause_state)


func _get_world_name(world_num: int) -> String:
	var idx: int = clampi(world_num - 1, 0, WORLD_NAMES.size() - 1)
	return WORLD_NAMES[idx]


func _set_overlay(show_panel: bool, msg: String) -> void:
	if _overlay_panel == null:
		return
	_overlay_panel.visible = show_panel
	if _overlay_label != null:
		_overlay_label.text = msg


func get_current_state() -> int:
	return _current_state


func get_current_world() -> int:
	return _current_world


func get_unlocked_world() -> int:
	return _unlocked_world


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_ev: InputEventKey = event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			var is_f11: bool = key_ev.keycode == KEY_F11
			var is_alt_enter: bool = key_ev.keycode == KEY_ENTER and key_ev.alt_pressed
			if is_f11 or is_alt_enter:
				var cur_mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
				if cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _build_ui_layout() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "UILayer"
	add_child(canvas)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.05, 0.05, 0.08, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(backdrop)

	# Centered 256x240 native NES stage container
	_stage_root = Control.new()
	_stage_root.name = "NativeStage256x240"
	_stage_root.custom_minimum_size = Vector2(Constants.NATIVE_WIDTH, Constants.NATIVE_HEIGHT)
	_stage_root.size = Vector2(Constants.NATIVE_WIDTH, Constants.NATIVE_HEIGHT)
	_stage_root.set_anchors_preset(Control.PRESET_CENTER)
	_stage_root.offset_left = -float(Constants.NATIVE_WIDTH) * 0.5
	_stage_root.offset_top = -float(Constants.NATIVE_HEIGHT) * 0.5
	_stage_root.offset_right = float(Constants.NATIVE_WIDTH) * 0.5
	_stage_root.offset_bottom = float(Constants.NATIVE_HEIGHT) * 0.5
	canvas.add_child(_stage_root)

	_build_missing_rom_panel()
	_build_title_screen()
	_build_gameplay_panel()


func _build_missing_rom_panel() -> void:
	_missing_rom_panel = Control.new()
	_missing_rom_panel.name = "MissingRomScreen"
	_missing_rom_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_root.add_child(_missing_rom_panel)

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.10, 0.04, 0.06, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_missing_rom_panel.add_child(bg)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.position = Vector2(12, 20)
	vbox.size = Vector2(Constants.NATIVE_WIDTH - 24, Constants.NATIVE_HEIGHT - 40)
	vbox.add_theme_constant_override("separation", 8)
	_missing_rom_panel.add_child(vbox)

	var title_lbl: Label = Label.new()
	title_lbl.text = "REKIRBY - ROM REQUIRED"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.72, 1.0))
	vbox.add_child(title_lbl)

	var body_lbl: Label = Label.new()
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.add_theme_font_size_override("font_size", 8)
	body_lbl.text = (
		"Gameplay halted: no extracted NES assets found in user://nes_data/.\n\n"
		+ "Place your valid Kirby's Adventure (USA) (Rev A) .nes ROM "
		+ "(512KB PRG + 256KB CHR, Mapper 4 MMC3) into:\n"
		+ "  rom/\n\n"
		+ "Zero procedural sprite or audio fallbacks are included."
	)
	vbox.add_child(body_lbl)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 8)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(_status_label)

	var retry_btn: Button = Button.new()
	retry_btn.text = "Retry ROM Scan"
	retry_btn.add_theme_font_size_override("font_size", 9)
	retry_btn.pressed.connect(_on_retry_pressed)
	vbox.add_child(retry_btn)


func _build_gameplay_panel() -> void:
	_gameplay_panel = Control.new()
	_gameplay_panel.name = "GameplayScreen"
	_gameplay_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gameplay_panel.visible = false
	_stage_root.add_child(_gameplay_panel)

	# Top 256x192 clipped scrolling playfield region (MMC3 scanline IRQ split Y=192)
	_playfield_clip = Control.new()
	_playfield_clip.name = "PlayfieldClip256x192"
	_playfield_clip.position = Vector2(0, 0)
	_playfield_clip.size = Vector2(Constants.PLAYFIELD_WIDTH, Constants.PLAYFIELD_HEIGHT)
	_playfield_clip.clip_contents = true
	_gameplay_panel.add_child(_playfield_clip)

	_world_container = Node2D.new()
	_world_container.name = "WorldContainer"
	_playfield_clip.add_child(_world_container)

	_transition_rect = ColorRect.new()
	_transition_rect.name = "DoorTransitionFade"
	_transition_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_transition_rect.position = Vector2.ZERO
	_transition_rect.size = Vector2(Constants.PLAYFIELD_WIDTH, Constants.PLAYFIELD_HEIGHT)
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_rect.visible = false
	_playfield_clip.add_child(_transition_rect)

	# Bottom 256x48 fixed Scanline IRQ Split HUD (Y=192..239)
	_hud_renderer = HUDRenderer.new()
	_gameplay_panel.add_child(_hud_renderer)

	# Pause / Game Over / Ending Overlay inside 256x192 playfield
	_overlay_panel = ColorRect.new()
	_overlay_panel.name = "StateOverlay"
	_overlay_panel.color = Color(0.0, 0.0, 0.0, 0.78)
	_overlay_panel.position = Vector2.ZERO
	_overlay_panel.size = Vector2(Constants.PLAYFIELD_WIDTH, Constants.PLAYFIELD_HEIGHT)
	_overlay_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_panel.visible = false
	_playfield_clip.add_child(_overlay_panel)

	_overlay_label = Label.new()
	_overlay_label.name = "OverlayText"
	_overlay_label.position = Vector2(12.0, 28.0)
	_overlay_label.size = Vector2(Constants.PLAYFIELD_WIDTH - 24.0, Constants.PLAYFIELD_HEIGHT - 56.0)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 10)
	_overlay_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_overlay_panel.add_child(_overlay_label)

	# Cross-platform mobile/touch overlay
	_virtual_gamepad = VirtualGamepad.new()
	add_child(_virtual_gamepad)

	# 2A03 5-channel APU synthesizer + PRG-ROM music/SFX sequencer
	_apu_engine = APUEngine.new()
	add_child(_apu_engine)
	_music_player = MusicPlayer.new()
	add_child(_music_player)
	_music_player.setup(_apu_engine)


func _ensure_world_nodes() -> void:
	if _level_map == null:
		_level_map = LevelMap.new()
		_level_map.name = "LevelMap"
		_world_container.add_child(_level_map)
	if _enemies_layer == null:
		_enemies_layer = Node2D.new()
		_enemies_layer.name = "EnemiesLayer"
		_world_container.add_child(_enemies_layer)
	if _projectiles_layer == null:
		_projectiles_layer = Node2D.new()
		_projectiles_layer.name = "ProjectilesLayer"
		_world_container.add_child(_projectiles_layer)
	if _kirby == null:
		_kirby = KirbyController.new()
		_kirby.name = "KirbyController"
		_world_container.add_child(_kirby)


func _attempt_rom_boot() -> void:
	var loaded_cached: bool = ContentRegistry.load_from_user_data()
	if not loaded_cached:
		var import_res: ROMImporter.ImportResult = ROMImporter.import_from_default_locations()
		if not import_res.success and _status_label != null:
			_status_label.text = import_res.error

	if ContentRegistry.is_ready():
		_enter_ready_state()
	else:
		_enter_missing_rom_state()


func _enter_missing_rom_state() -> void:
	var prev: int = _current_state
	_current_state = Constants.GameState.ROM_SETUP
	set_physics_process(false)
	_missing_rom_panel.visible = true
	_gameplay_panel.visible = false
	if _status_label != null and _status_label.text.is_empty():
		_status_label.text = "Status: Waiting for valid ROM in %s" % Constants.ROM_DIR
	EventBus.game_state_changed.emit(_current_state, prev)


func _build_title_screen() -> void:
	_title_screen = TitleScreen.new()
	_title_screen.name = "TitleScreen"
	_title_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_screen.visible = false
	_title_screen.start_requested.connect(_on_title_start_requested)
	_stage_root.add_child(_title_screen)


func _on_title_start_requested() -> void:
	if _current_state == Constants.GameState.TITLE:
		start_new_game()


func _enter_ready_state() -> void:
	var prev: int = _current_state
	_missing_rom_panel.visible = false
	_gameplay_panel.visible = false
	_ensure_world_nodes()
	if _title_screen == null:
		_build_title_screen()
	if _title_screen != null:
		_title_screen.setup_from_rom()
		_title_screen.visible = true
	_current_state = Constants.GameState.TITLE
	set_physics_process(true)
	if _music_player != null:
		_music_player.setup(_apu_engine)
		EventBus.bgm_requested.emit(0)
	EventBus.game_state_changed.emit(_current_state, prev)


func start_new_game() -> bool:
	var prev: int = _current_state
	_missing_rom_panel.visible = false
	if _title_screen != null:
		_title_screen.visible = false
	_gameplay_panel.visible = true
	_ensure_world_nodes()

	_lives = 4
	_score = 0
	_cleared_stages.clear()
	var slots: Array[Dictionary] = SaveManager.load_all_slots()
	var slot_data: Dictionary = slots[_active_save_slot]
	_unlocked_world = clampi(int(slot_data.get("unlocked_world", 1)), 1, 7)
	_current_world = 1
	_set_overlay(false, "")
	var start_room: int = DEFAULT_START_ROOM_ID if ContentRegistry.has_room(DEFAULT_START_ROOM_ID) else Constants.WORLD1_HUB_ROOM_ID
	if load_world_room(start_room, DEFAULT_SPAWN_POS, false):
		_update_camera_scroll()
		set_physics_process(true)
		if _hud_renderer != null:
			_hud_renderer.set_status(_kirby.hp, _kirby.max_hp, _lives, _score, _kirby.copy_ability)
		if _music_player != null:
			_music_player.setup(_apu_engine)
			EventBus.bgm_requested.emit(0)
		EventBus.game_state_changed.emit(_current_state, prev)
		return true
	_enter_missing_rom_state()
	return false


func _clear_room_entities() -> void:
	for e: EnemyBase in _enemies:
		_dispose_node(e)
	_enemies.clear()
	for p: StarProjectile in _projectiles:
		_dispose_node(p)
	_projectiles.clear()
	if _boss != null and is_instance_valid(_boss):
		_dispose_node(_boss)
	_boss = null


func load_world_room(room_id: int, spawn_pos: Vector2, preserve_status: bool = true) -> bool:
	_ensure_world_nodes()
	if not _level_map.load_room(room_id):
		return false

	_clear_room_entities()
	_victory_frames = 0
	_defeat_frames = 0
	_current_room_id = room_id
	if Constants.WORLD_HUB_ROOM_IDS.has(room_id):
		_current_world = room_id + 1
	elif BOSS_ROOM_IDS.has(room_id):
		_current_world = room_id - BOSS_ROOM_ID + 1
	var actual_spawn: Vector2 = spawn_pos
	if BOSS_ROOM_IDS.has(room_id) and actual_spawn == Vector2.ZERO:
		actual_spawn = Vector2(48.0, 512.0)
	_room_spawn_pos = actual_spawn

	_kirby.setup(_level_map, actual_spawn, preserve_status)

	var room_data: Dictionary = ContentRegistry.get_room_data(room_id)
	var sp_chr_bank: int = int(room_data.get("sprite_chr_bank", 154))
	for ent: Dictionary in _level_map.get_entities():
		var actor_id: int = int(ent.get("actor_id", -1))
		var e_type: int = EnemyBase.map_rom_actor_id(actor_id)
		if e_type < 0:
			continue
		var scr: int = int(ent.get("screen", 0))
		var tx: int = int(ent.get("tile_x", 0))
		var ty: int = int(ent.get("tile_y", 0))
		var e_pos: Vector2 = _level_map.screen_tile_to_pixel(scr, tx, ty) + Vector2(8.0, 16.0)
		var enemy: EnemyBase = EnemyBase.new()
		enemy.setup(e_type, e_pos, _level_map, -1, sp_chr_bank, actor_id)
		_enemies_layer.add_child(enemy)
		_enemies.append(enemy)

	var is_boss_arena: bool = BOSS_ROOM_IDS.has(room_id) or room_id in [8, 9, 10, 11, 12, 14, 15]
	if room_id == BOSS_ROOM_ID:
		_current_state = Constants.GameState.BOSS_FIGHT
		var whispy: WhispyWoods = WhispyWoods.new()
		_boss = whispy
		_enemies_layer.add_child(whispy)
		whispy.setup(Vector2(128.0, 544.0), _level_map)
		if ContentRegistry.has_music_track(5):
			EventBus.bgm_requested.emit(5)
	elif is_boss_arena:
		_current_state = Constants.GameState.BOSS_FIGHT
		var bc: BossController = BossController.new()
		_boss = bc
		_enemies_layer.add_child(bc)
		var boss_y: float = float(clampi(_level_map.get_height_pixels() - 32, 144, 544))
		bc.setup_for_room(room_id, Vector2(180.0, boss_y), _level_map)
		if ContentRegistry.has_music_track(5):
			EventBus.bgm_requested.emit(5)
	else:
		_current_state = Constants.GameState.PLAYING
		EventBus.boss_hp_changed.emit(0, 0, 0)
		if _music_player != null:
			var target_bgm: int = _level_map.get_bgm_id()
			if not ContentRegistry.has_music_track(target_bgm):
				target_bgm = 0
			if _music_player.get_current_bgm_id() != target_bgm:
				EventBus.bgm_requested.emit(target_bgm)

	EventBus.hp_changed.emit(_kirby.hp, _kirby.max_hp)
	EventBus.copy_ability_changed.emit(_kirby.copy_ability)
	EventBus.room_changed.emit(_current_world, 1, room_id)
	return true


func get_enemies() -> Array[EnemyBase]:
	return _enemies


func get_projectiles() -> Array[StarProjectile]:
	return _projectiles


func get_boss() -> Node2D:
	return _boss


func get_score() -> int:
	return _score


func get_lives() -> int:
	return _lives


func get_cleared_stages() -> Dictionary:
	return _cleared_stages.duplicate()


func _check_door_transition() -> bool:
	var door: Dictionary = {}
	if InputManager.is_just_pressed(Constants.NesButton.UP):
		door = _level_map.find_door_at_pixel(_kirby.pos.x, _kirby.pos.y - 8.0)
	if door.is_empty():
		door = _level_map.find_edge_door_at_kirby(_kirby.pos.x, _kirby.pos.y, _kirby.vel.y)
	if door.is_empty():
		return false
	var dst_room: int = int(door.get("dest_room_id", -1))
	if not ContentRegistry.has_room(dst_room):
		return false
	if int(door.get("special", 0)) == 16:
		_cleared_stages[_current_room_id] = true
		_add_score(STAGE_CLEAR_BONUS)

	var dst_data: Dictionary = ContentRegistry.get_room_data(dst_room)
	var spawn_pos: Vector2 = LevelMap.compute_door_spawn_pixel(dst_data, door)
	if load_world_room(dst_room, spawn_pos, true):
		EventBus.sfx_requested.emit(Constants.NesSfx.DOOR_WARP)
		_fade_frames = DOOR_FADE_FRAMES
		if _transition_rect != null:
			_transition_rect.color.a = 1.0
			_transition_rect.visible = true
		_update_camera_scroll()
		return true
	return false


func _update_camera_scroll() -> void:
	if _level_map == null or _kirby == null or _world_container == null:
		return
	var max_cam_x: float = maxf(0.0, float(_level_map.get_width_pixels() - Constants.PLAYFIELD_WIDTH))
	var max_cam_y: float = maxf(0.0, float(_level_map.get_height_pixels() - Constants.PLAYFIELD_HEIGHT))
	var target_x: float = clampf(_kirby.pos.x - float(Constants.PLAYFIELD_WIDTH) * 0.5, 0.0, max_cam_x)
	var target_y: float = clampf(_kirby.pos.y - float(Constants.PLAYFIELD_HEIGHT) * 0.6, 0.0, max_cam_y)
	if _current_room_id == BOSS_ROOM_ID and _kirby.pos.y >= 384.0:
		target_x = 0.0
		target_y = max_cam_y
	_camera_offset = Vector2(roundf(target_x), roundf(target_y))
	_world_container.position = -_camera_offset


func _on_retry_pressed() -> void:
	if _status_label != null:
		_status_label.text = ""
	_attempt_rom_boot()
