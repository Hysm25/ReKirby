class_name FileSelectScreen
extends Control
## Interactive 3-Slot File Select Screen (256x240) backed by SaveManager and ROM CHR graphics.

const Constants = preload("res://src/core/constants.gd")
const SaveManager = preload("res://src/core/save_manager.gd")

signal slot_selected(slot_idx: int)
signal back_to_title

var selected_slot: int = 0
var _slots: Array[Dictionary] = []
var _bg_rect: ColorRect = null
var _header_label: Label = null
var _slot_labels: Array[Label] = []
var _cursor_sprite: Sprite2D = null
var _frame_counter: int = 0


func _ready() -> void:
	name = "FileSelectScreen"
	custom_minimum_size = Vector2(float(Constants.NATIVE_WIDTH), float(Constants.NATIVE_HEIGHT))
	size = Vector2(float(Constants.NATIVE_WIDTH), float(Constants.NATIVE_HEIGHT))
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _bg_rect != null:
		return
	_bg_rect = ColorRect.new()
	_bg_rect.name = "FileSelectBG"
	_bg_rect.position = Vector2.ZERO
	_bg_rect.size = Vector2(float(Constants.NATIVE_WIDTH), float(Constants.NATIVE_HEIGHT))
	_bg_rect.color = Color(0.08, 0.14, 0.36, 1.0)
	add_child(_bg_rect)

	_header_label = Label.new()
	_header_label.name = "HeaderLabel"
	_header_label.position = Vector2(16.0, 16.0)
	_header_label.size = Vector2(224.0, 24.0)
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_font_size_override("font_size", 11)
	_header_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1.0))
	_header_label.text = "SELECT FILE"
	add_child(_header_label)

	for i: int in range(SaveManager.SLOT_COUNT):
		var lbl: Label = Label.new()
		lbl.name = "SlotLabel_%d" % i
		lbl.position = Vector2(56.0, 56.0 + float(i) * 44.0)
		lbl.size = Vector2(180.0, 32.0)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		add_child(lbl)
		_slot_labels.append(lbl)

	var hint: Label = Label.new()
	hint.name = "FileHint"
	hint.position = Vector2(16.0, 198.0)
	hint.size = Vector2(224.0, 28.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 1.0))
	hint.text = "A/START: PLAY   SEL: ERASE"
	add_child(hint)

	_cursor_sprite = Sprite2D.new()
	_cursor_sprite.name = "CursorKirby"
	_cursor_sprite.centered = false
	_cursor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_cursor_sprite)


func setup_from_rom(save_path: String = Constants.SAVE_DATA_PATH) -> void:
	_ensure_nodes()
	_slots = SaveManager.load_all_slots(save_path)
	if ContentRegistry.is_ready():
		var bg0: PackedColorArray = ContentRegistry.get_palette_colors("title_bg_0")
		if bg0.size() >= 1:
			_bg_rect.color = Color(bg0[0].r, bg0[0].g, bg0[0].b, 1.0)
		var frame_spec: Dictionary = ContentRegistry.get_kirby_metasprite_frame("default", 0)
		if not frame_spec.is_empty():
			var pals: Array[PackedColorArray] = ContentRegistry.get_room_sprite_palettes(-1)
			var built: Dictionary = ContentRegistry.build_rom_metasprite(
				frame_spec,
				pals,
				Constants.CHR_BANK_KIRBY_DEFAULT,
				154,
				Constants.CHR_BANK_STAR_EFFECTS
			)
			if not built.is_empty():
				_cursor_sprite.texture = built["texture"] as ImageTexture
	_refresh_labels()


func _refresh_labels() -> void:
	for i: int in range(mini(_slot_labels.size(), _slots.size())):
		var s: Dictionary = _slots[i]
		var occ: bool = bool(s.get("occupied", false))
		var prefix: String = "> " if i == selected_slot else "  "
		if not occ:
			_slot_labels[i].text = "%sFILE %d : NEW GAME" % [prefix, i + 1]
		else:
			var uw: int = int(s.get("unlocked_world", 1))
			var pct: int = int(s.get("percent", 0))
			var sc: int = int(s.get("score", 0))
			_slot_labels[i].text = "%sFILE %d : W%d  %d%%  %06d" % [prefix, i + 1, uw, pct, sc]
		_slot_labels[i].modulate = Color(1.0, 0.95, 0.5, 1.0) if i == selected_slot else Color(0.85, 0.85, 0.9, 1.0)
	if _cursor_sprite != null:
		_cursor_sprite.position = Vector2(28.0, 56.0 + float(selected_slot) * 44.0 + (sin(float(_frame_counter) * 0.2) * 2.0))


func step_frame(save_path: String = Constants.SAVE_DATA_PATH) -> int:
	_frame_counter += 1
	if InputManager.is_just_pressed(Constants.NesButton.UP):
		selected_slot = (selected_slot + SaveManager.SLOT_COUNT - 1) % SaveManager.SLOT_COUNT
		EventBus.sfx_requested.emit(Constants.NesSfx.JUMP)
		_refresh_labels()
	elif InputManager.is_just_pressed(Constants.NesButton.DOWN):
		selected_slot = (selected_slot + 1) % SaveManager.SLOT_COUNT
		EventBus.sfx_requested.emit(Constants.NesSfx.JUMP)
		_refresh_labels()
	elif InputManager.is_just_pressed(Constants.NesButton.SELECT):
		SaveManager.erase_slot(selected_slot, save_path)
		_slots = SaveManager.load_all_slots(save_path)
		EventBus.sfx_requested.emit(Constants.NesSfx.ABILITY_DROP)
		_refresh_labels()
	elif InputManager.is_just_pressed(Constants.NesButton.START) or InputManager.is_just_pressed(Constants.NesButton.A):
		EventBus.sfx_requested.emit(Constants.NesSfx.SWALLOW)
		slot_selected.emit(selected_slot)
		return selected_slot
	elif InputManager.is_just_pressed(Constants.NesButton.B):
		back_to_title.emit()
		return -2
	else:
		_refresh_labels()
	return -1


func get_slot_data(slot_idx: int) -> Dictionary:
	var idx: int = clampi(slot_idx, 0, maxi(0, _slots.size() - 1))
	return _slots[idx] if idx < _slots.size() else {}
