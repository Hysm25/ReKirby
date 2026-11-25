extends Node2D
## Root boot coordinator and Mandatory ROM Setup Guard for ReKirby.

const Constants = preload("res://src/core/constants.gd")
const ROMImporter = preload("res://src/importer/rom_importer.gd")

var _current_state: int = Constants.GameState.ROM_SETUP
var _stage_root: Control = null
var _missing_rom_panel: Control = null
var _boot_verified_panel: Control = null
var _status_label: Label = null
var _chr_preview_row: HBoxContainer = null


func _ready() -> void:
	_build_ui_layout()
	_attempt_rom_boot()


func _physics_process(_delta: float) -> void:
	if _current_state == Constants.GameState.ROM_SETUP:
		return
	InputManager.step_frame()


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
	_build_boot_verified_panel()


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


func _build_boot_verified_panel() -> void:
	_boot_verified_panel = Control.new()
	_boot_verified_panel.name = "BootVerifiedScreen"
	_boot_verified_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_boot_verified_panel.visible = false
	_stage_root.add_child(_boot_verified_panel)

	# Top 256x192 scrolling playfield region (above MMC3 scanline IRQ Y=192)
	var playfield_bg: ColorRect = ColorRect.new()
	playfield_bg.color = Color(0.0, 0.0, 0.0, 1.0)
	playfield_bg.position = Vector2(0, 0)
	playfield_bg.size = Vector2(Constants.PLAYFIELD_WIDTH, Constants.PLAYFIELD_HEIGHT)
	_boot_verified_panel.add_child(playfield_bg)

	var header_lbl: Label = Label.new()
	header_lbl.position = Vector2(8, 8)
	header_lbl.size = Vector2(Constants.PLAYFIELD_WIDTH - 16, 48)
	header_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header_lbl.add_theme_font_size_override("font_size", 8)
	header_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	header_lbl.text = "REKIRBY PHASE 1: ROM INGESTION VERIFIED\n256x192 PLAYFIELD + 256x1KB CHR BANKS READY"
	_boot_verified_panel.add_child(header_lbl)

	_chr_preview_row = HBoxContainer.new()
	_chr_preview_row.position = Vector2(16, 64)
	_chr_preview_row.add_theme_constant_override("separation", 8)
	_boot_verified_panel.add_child(_chr_preview_row)

	# Bottom 256x48 fixed HUD region (MMC3 scanline IRQ split Y=192..239)
	var hud_bg: ColorRect = ColorRect.new()
	hud_bg.color = Color(0.14, 0.09, 0.16, 1.0)
	hud_bg.position = Vector2(0, Constants.HUD_Y)
	hud_bg.size = Vector2(Constants.NATIVE_WIDTH, Constants.HUD_HEIGHT)
	_boot_verified_panel.add_child(hud_bg)

	var hud_lbl: Label = Label.new()
	hud_lbl.position = Vector2(8, Constants.HUD_Y + 8)
	hud_lbl.size = Vector2(Constants.NATIVE_WIDTH - 16, Constants.HUD_HEIGHT - 16)
	hud_lbl.add_theme_font_size_override("font_size", 8)
	hud_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.85, 1.0))
	hud_lbl.text = "HUD SPLIT Y=192 (48PX FIXED)\n[PHASE 2: PHYSICS & ABILITIES PENDING]"
	_boot_verified_panel.add_child(hud_lbl)


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
	_boot_verified_panel.visible = false
	if _status_label != null and _status_label.text.is_empty():
		_status_label.text = "Status: Waiting for valid ROM in %s" % Constants.ROM_DIR
	EventBus.game_state_changed.emit(_current_state, prev)


func _enter_ready_state() -> void:
	var prev: int = _current_state
	_current_state = Constants.GameState.TITLE
	set_physics_process(true)
	_missing_rom_panel.visible = false
	_boot_verified_panel.visible = true
	_populate_chr_preview()
	EventBus.game_state_changed.emit(_current_state, prev)


func _populate_chr_preview() -> void:
	if _chr_preview_row == null or not ContentRegistry.is_ready():
		return
	for child: Node in _chr_preview_row.get_children():
		child.queue_free()

	var sample_banks: PackedInt32Array = PackedInt32Array([0, 4, 32])
	for bank_idx: int in sample_banks:
		var tex: ImageTexture = ContentRegistry.get_chr_bank_texture(bank_idx)
		if tex == null:
			continue
		var tex_rect: TextureRect = TextureRect.new()
		tex_rect.texture = tex
		tex_rect.custom_minimum_size = Vector2(64, 64)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP
		_chr_preview_row.add_child(tex_rect)


func _on_retry_pressed() -> void:
	if _status_label != null:
		_status_label.text = ""
	_attempt_rom_boot()
