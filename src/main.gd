extends Node2D
## Root boot coordinator and Mandatory ROM Setup Guard for ReKirby.

const Constants = preload("res://src/core/constants.gd")
const ROMImporter = preload("res://src/importer/rom_importer.gd")
const LevelMap = preload("res://src/game/level_map.gd")
const KirbyController = preload("res://src/game/kirby_controller.gd")
const HUDRenderer = preload("res://src/game/hud_renderer.gd")
const VirtualGamepad = preload("res://src/game/virtual_gamepad.gd")

const DEFAULT_START_ROOM_ID: int = 43

var _current_state: int = Constants.GameState.ROM_SETUP
var _stage_root: Control = null
var _missing_rom_panel: Control = null
var _gameplay_panel: Control = null
var _playfield_clip: Control = null
var _world_container: Node2D = null
var _level_map: LevelMap = null
var _kirby: KirbyController = null
var _hud_renderer: HUDRenderer = null
var _virtual_gamepad: VirtualGamepad = null
var _status_label: Label = null
var _camera_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	_build_ui_layout()
	_attempt_rom_boot()


func _physics_process(_delta: float) -> void:
	if _current_state == Constants.GameState.ROM_SETUP:
		return
	InputManager.step_frame()
	if _kirby != null and _level_map != null and _current_state == Constants.GameState.PLAYING:
		_kirby.step_physics()
		_kirby.consume_spawned_projectiles()
		_check_door_transition()
		_update_camera_scroll()
		if _hud_renderer != null:
			_hud_renderer.refresh()


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

	# Bottom 256x48 fixed Scanline IRQ Split HUD (Y=192..239)
	_hud_renderer = HUDRenderer.new()
	_gameplay_panel.add_child(_hud_renderer)

	# Cross-platform mobile/touch overlay
	_virtual_gamepad = VirtualGamepad.new()
	add_child(_virtual_gamepad)


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


func _enter_ready_state() -> void:
	var prev: int = _current_state
	_missing_rom_panel.visible = false
	_gameplay_panel.visible = true

	if _level_map == null:
		_level_map = LevelMap.new()
		_level_map.name = "LevelMap"
		_world_container.add_child(_level_map)
	if _kirby == null:
		_kirby = KirbyController.new()
		_kirby.name = "KirbyController"
		_world_container.add_child(_kirby)

	var start_room: int = DEFAULT_START_ROOM_ID if ContentRegistry.has_room(DEFAULT_START_ROOM_ID) else Constants.WORLD1_HUB_ROOM_ID
	if _level_map.load_room(start_room):
		_kirby.setup(_level_map, Vector2(40.0, 128.0))
		_update_camera_scroll()
		_current_state = Constants.GameState.PLAYING
		set_physics_process(true)
		if _hud_renderer != null:
			_hud_renderer.set_status(_kirby.hp, _kirby.max_hp, 4, 0, _kirby.copy_ability)
		EventBus.room_changed.emit(1, 1, start_room)
		EventBus.game_state_changed.emit(_current_state, prev)
	else:
		_enter_missing_rom_state()


func _check_door_transition() -> void:
	if not InputManager.is_just_pressed(Constants.NesButton.UP):
		return
	var door: Dictionary = _level_map.find_door_at_pixel(_kirby.pos.x, _kirby.pos.y - 8.0)
	if door.is_empty():
		return
	var dst_room: int = int(door.get("dest_room_id", -1))
	if not ContentRegistry.has_room(dst_room):
		return
	var dst_scr: int = int(door.get("dst_screen", 0))
	var dst_x: int = int(door.get("dst_x", 2))
	var dst_y: int = int(door.get("dst_y", 6))
	if _level_map.load_room(dst_room):
		var spawn_px: float = float((dst_scr * Constants.ROOM_SCREEN_COLS + dst_x) * Constants.METATILE_SIZE + 8)
		var spawn_py: float = float((dst_y + 1) * Constants.METATILE_SIZE)
		_kirby.setup(_level_map, Vector2(spawn_px, spawn_py))
		_update_camera_scroll()
		EventBus.room_changed.emit(1, 1, dst_room)


func _update_camera_scroll() -> void:
	if _level_map == null or _kirby == null or _world_container == null:
		return
	var max_cam_x: float = maxf(0.0, float(_level_map.get_width_pixels() - Constants.PLAYFIELD_WIDTH))
	var max_cam_y: float = maxf(0.0, float(_level_map.get_height_pixels() - Constants.PLAYFIELD_HEIGHT))
	var target_x: float = clampf(_kirby.pos.x - float(Constants.PLAYFIELD_WIDTH) * 0.5, 0.0, max_cam_x)
	var target_y: float = clampf(_kirby.pos.y - float(Constants.PLAYFIELD_HEIGHT) * 0.6, 0.0, max_cam_y)
	_camera_offset = Vector2(roundf(target_x), roundf(target_y))
	_world_container.position = -_camera_offset


func _on_retry_pressed() -> void:
	if _status_label != null:
		_status_label.text = ""
	_attempt_rom_boot()
