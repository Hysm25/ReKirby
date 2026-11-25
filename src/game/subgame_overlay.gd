class_name SubgameOverlay
extends Control
## Playable 60 TPS NES Sub-Game Overlay (Crane Fever 0x1A, Egg Catcher 0x1B, Quick Draw 0x1C).
## Renders using extracted ROM star/Kirby sprites and awards bonus score and 1UPs cleanly.

const Constants = preload("res://src/core/constants.gd")

signal subgame_finished(bonus_score: int, extra_lives: int)

enum SubgameKind {
	CRANE_FEVER = 0x1A,
	EGG_CATCHER = 0x1B,
	QUICK_DRAW = 0x1C,
}

var kind: int = SubgameKind.QUICK_DRAW
var active: bool = false
var won: bool = false
var reward_score: int = 0
var reward_lives: int = 0

var _frame: int = 0
var _target_frame: int = 45
var _cursor_x: float = 40.0
var _cursor_dir: float = 2.4
var _acted: bool = false
var _finish_timer: int = 0

var _bg_rect: ColorRect = null
var _title_label: Label = null
var _status_label: Label = null
var _actor_sprite: Sprite2D = null
var _target_sprite: Sprite2D = null


func _ready() -> void:
	name = "SubgameOverlay"
	position = Vector2.ZERO
	size = Vector2(float(Constants.PLAYFIELD_WIDTH), float(Constants.PLAYFIELD_HEIGHT))
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _bg_rect != null:
		return
	_bg_rect = ColorRect.new()
	_bg_rect.position = Vector2.ZERO
	_bg_rect.size = Vector2(float(Constants.PLAYFIELD_WIDTH), float(Constants.PLAYFIELD_HEIGHT))
	_bg_rect.color = Color(0.06, 0.08, 0.22, 0.96)
	add_child(_bg_rect)

	_title_label = Label.new()
	_title_label.position = Vector2(12.0, 18.0)
	_title_label.size = Vector2(232.0, 22.0)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 11)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1.0))
	add_child(_title_label)

	_status_label = Label.new()
	_status_label.position = Vector2(12.0, 128.0)
	_status_label.size = Vector2(232.0, 44.0)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 9)
	_status_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	add_child(_status_label)

	_target_sprite = Sprite2D.new()
	_target_sprite.centered = true
	_target_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_target_sprite)

	_actor_sprite = Sprite2D.new()
	_actor_sprite.centered = true
	_actor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_actor_sprite)


func start_subgame(p_kind: int) -> void:
	_ensure_nodes()
	kind = p_kind
	active = true
	won = false
	reward_score = 0
	reward_lives = 0
	_frame = 0
	_target_frame = 42
	_cursor_x = 40.0
	_cursor_dir = 2.6
	_acted = false
	_finish_timer = 0
	visible = true

	if ContentRegistry.is_ready():
		var pals: Array[PackedColorArray] = ContentRegistry.get_room_sprite_palettes(-1)
		var star_spec: Dictionary = ContentRegistry.get_effect_metasprite_frame("star", 0)
		if not star_spec.is_empty():
			var b_star: Dictionary = ContentRegistry.build_rom_metasprite(star_spec, pals, Constants.CHR_BANK_STAR_EFFECTS, 154, Constants.CHR_BANK_STAR_EFFECTS)
			if not b_star.is_empty():
				_actor_sprite.texture = b_star["texture"] as ImageTexture
		var kirby_spec: Dictionary = ContentRegistry.get_kirby_metasprite_frame("default", 0)
		if not kirby_spec.is_empty():
			var b_k: Dictionary = ContentRegistry.build_rom_metasprite(kirby_spec, pals, Constants.CHR_BANK_KIRBY_DEFAULT, 154, Constants.CHR_BANK_STAR_EFFECTS)
			if not b_k.is_empty():
				_target_sprite.texture = b_k["texture"] as ImageTexture

	match kind:
		SubgameKind.CRANE_FEVER:
			_title_label.text = "CRANE FEVER"
			_status_label.text = "PRESS A OVER KIRBY!"
			_target_sprite.position = Vector2(128.0, 96.0)
			_actor_sprite.position = Vector2(_cursor_x, 60.0)
		SubgameKind.EGG_CATCHER:
			_title_label.text = "EGG CATCHER"
			_status_label.text = "PRESS A AS EGG LANDS!"
			_target_sprite.position = Vector2(128.0, 98.0)
			_actor_sprite.position = Vector2(128.0, 46.0)
		_:
			_title_label.text = "QUICK DRAW"
			_status_label.text = "WAIT FOR SIGNAL..."
			_target_sprite.position = Vector2(176.0, 88.0)
			_actor_sprite.position = Vector2(80.0, 88.0)


func step_frame() -> void:
	if not active:
		return
	_frame += 1

	if _acted:
		_finish_timer += 1
		if _finish_timer >= 36:
			active = false
			visible = false
			subgame_finished.emit(reward_score, reward_lives)
		return

	var pressed_act: bool = InputManager.is_just_pressed(Constants.NesButton.A) or InputManager.is_just_pressed(Constants.NesButton.B)
	match kind:
		SubgameKind.CRANE_FEVER:
			_cursor_x += _cursor_dir
			if _cursor_x >= 212.0 or _cursor_x <= 44.0:
				_cursor_dir = -_cursor_dir
			_actor_sprite.position = Vector2(_cursor_x, 60.0)
			if pressed_act:
				_acted = true
				won = absf(_cursor_x - 128.0) <= 28.0
				_apply_outcome()
		SubgameKind.EGG_CATCHER:
			var fall_y: float = 46.0 + float(_frame) * 1.35
			_actor_sprite.position = Vector2(128.0, minf(120.0, fall_y))
			if pressed_act or fall_y >= 118.0:
				_acted = true
				won = pressed_act and absf(fall_y - 98.0) <= 24.0
				_apply_outcome()
		_:
			if _frame == _target_frame:
				_status_label.text = "FIRE!! PRESS A!"
				EventBus.sfx_requested.emit(Constants.NesSfx.STAR_SPIT)
			elif _frame > _target_frame + 28:
				_acted = true
				won = false
				_apply_outcome()
			elif pressed_act:
				_acted = true
				won = _frame >= _target_frame and _frame <= _target_frame + 24
				_apply_outcome()


func _apply_outcome() -> void:
	if won:
		reward_score = 1000
		reward_lives = 1
		_status_label.text = "CLEAR! +1000 PTS  +1UP!"
		EventBus.sfx_requested.emit(Constants.NesSfx.STAGE_CLEAR)
	else:
		reward_score = 100
		reward_lives = 0
		_status_label.text = "NICE TRY! +100 PTS"
		EventBus.sfx_requested.emit(Constants.NesSfx.ABILITY_DROP)
