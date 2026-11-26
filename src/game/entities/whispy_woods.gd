class_name WhispyWoods
extends Node2D
## World 1 Boss: Whispy Woods (Room 30).
## Runs deterministically at 60 TPS: drops inhalable apples from canopy height,
## blows horizontal air puffs toward Kirby, updates HUD boss HP via EventBus,
## and spawns the Goal Star Rod upon defeat.

const Constants = preload("res://src/core/constants.gd")
const LevelMap = preload("res://src/game/level_map.gd")

enum Phase {
	INTRO = 0,
	IDLE = 1,
	DROP_APPLES = 2,
	PUFF_ATTACK = 3,
	DEFEATED = 4,
}

const BOSS_ID: int = 1
const DEFAULT_MAX_HP: int = 12
const HIT_INVULN_FRAMES: int = 12
const TRUNK_HALF_WIDTH: float = 24.0
const TRUNK_HEIGHT: float = 92.0
const DEFEAT_SCORE: int = 5000

var pos: Vector2 = Vector2(128.0, 544.0)
var hp: int = DEFAULT_MAX_HP
var max_hp: int = DEFAULT_MAX_HP
var phase: int = Phase.INTRO
var facing_dir: int = -1

var _phase_frames: int = 0
var _cycle_step: int = 0
var _invuln_frames: int = 0
var _apples_dropped_in_phase: int = 0
var _puffs_fired_in_phase: int = 0
var _canopy_y: float = 408.0
var _mouth_y: float = 488.0
var _spawned_projectiles: Array[Dictionary] = []
var _face_sprite: Sprite2D = null
var _canopy_patch_sprite: Sprite2D = null
var _face_tex_idle: ImageTexture = null
var _face_tex_blink: ImageTexture = null
var _face_tex_puff: ImageTexture = null
var _canopy_tex: ImageTexture = null


func _ready() -> void:
	_ensure_visual()


func _ensure_visual() -> void:
	if _face_sprite == null:
		_face_sprite = Sprite2D.new()
		_face_sprite.name = "WhispyFaceOverlay"
		_face_sprite.centered = true
		_face_sprite.position = Vector2(0.0, -76.0)
		_face_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_face_sprite)
	if _canopy_patch_sprite == null:
		_canopy_patch_sprite = Sprite2D.new()
		_canopy_patch_sprite.name = "WhispyCanopyPatch"
		_canopy_patch_sprite.centered = true
		_canopy_patch_sprite.position = Vector2(0.0, -138.0)
		_canopy_patch_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_canopy_patch_sprite)
	if _face_tex_idle == null and ContentRegistry.is_ready():
		var pal_key: String = "room_30_bg_2"
		if ContentRegistry.get_palette_indices(pal_key).is_empty():
			pal_key = "hud_bg_0"
		# Authentic Whispy Woods face & canopy patch tiles from CHR Bank 180
		_canopy_tex = ContentRegistry.build_rom_sprite_texture(
			180,
			PackedInt32Array([0, 1, 18, 20, 22, 24, 25, 26]),
			4,
			2,
			pal_key
		)
		_face_tex_idle = ContentRegistry.build_rom_sprite_texture(
			180,
			PackedInt32Array([2, 4, 6, 8, 3, 5, 7, 9]),
			4,
			2,
			pal_key
		)
		_face_tex_blink = ContentRegistry.build_rom_sprite_texture(
			180,
			PackedInt32Array([10, 12, 14, 16, 11, 13, 15, 17]),
			4,
			2,
			pal_key
		)
		_face_tex_puff = ContentRegistry.build_rom_sprite_texture(
			180,
			PackedInt32Array([2, 4, 6, 8, 19, 21, 23, 9]),
			4,
			2,
			pal_key
		)
	if _face_tex_idle != null and _face_sprite.texture == null:
		_face_sprite.texture = _face_tex_idle
	if _canopy_tex != null and _canopy_patch_sprite != null and _canopy_patch_sprite.texture == null:
		_canopy_patch_sprite.texture = _canopy_tex


func get_canopy_patch_sprite() -> Sprite2D:
	return _canopy_patch_sprite


func setup(spawn_pos: Vector2, level_map: LevelMap = null) -> void:
	pos = spawn_pos
	position = pos
	hp = DEFAULT_MAX_HP
	max_hp = DEFAULT_MAX_HP
	phase = Phase.INTRO
	facing_dir = -1
	_phase_frames = 0
	_cycle_step = 0
	_invuln_frames = 0
	_apples_dropped_in_phase = 0
	_puffs_fired_in_phase = 0
	_canopy_y = pos.y - 136.0
	_mouth_y = pos.y - 44.0
	if level_map != null and level_map.get_room_id() == 30:
		# Align canopy & mouth directly with Room 30 BG trunk/canopy
		_canopy_y = 408.0
		_mouth_y = 520.0
	_spawned_projectiles.clear()
	_ensure_visual()
	_sync_visual()
	EventBus.boss_hp_changed.emit(BOSS_ID, hp, max_hp)


func is_defeated() -> bool:
	return phase == Phase.DEFEATED


func get_body_rect() -> Rect2:
	return Rect2(pos.x - TRUNK_HALF_WIDTH, pos.y - TRUNK_HEIGHT, TRUNK_HALF_WIDTH * 2.0, TRUNK_HEIGHT)


func consume_spawned_projectiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = _spawned_projectiles.duplicate(true)
	_spawned_projectiles.clear()
	return out


func take_damage(amount: int) -> bool:
	if phase == Phase.DEFEATED or _invuln_frames > 0:
		return false
	hp = maxi(0, hp - maxi(1, amount))
	_invuln_frames = HIT_INVULN_FRAMES
	EventBus.boss_hp_changed.emit(BOSS_ID, hp, max_hp)
	if hp <= 0:
		_enter_defeat()
	return true


func _enter_defeat() -> void:
	phase = Phase.DEFEATED
	_phase_frames = 0
	_spawned_projectiles.append({
		"kind": "goal_star_rod",
		"pos": Vector2(pos.x, pos.y - 24.0),
		"vel": Vector2.ZERO,
	})
	_sync_visual()


func step_physics(kirby_pos: Vector2) -> void:
	if phase == Phase.DEFEATED:
		_phase_frames += 1
		_sync_visual()
		return

	_phase_frames += 1
	if _invuln_frames > 0:
		_invuln_frames -= 1
	facing_dir = 1 if kirby_pos.x >= pos.x else -1

	match phase:
		Phase.INTRO:
			if _phase_frames >= 24:
				phase = Phase.IDLE
				_phase_frames = 0
		Phase.IDLE:
			if _phase_frames >= 48:
				_phase_frames = 0
				_cycle_step = (_cycle_step + 1) % 2
				if _cycle_step == 1:
					phase = Phase.DROP_APPLES
					_apples_dropped_in_phase = 0
				else:
					phase = Phase.PUFF_ATTACK
					_puffs_fired_in_phase = 0
		Phase.DROP_APPLES:
			if _phase_frames == 1 or _phase_frames == 22 or _phase_frames == 44:
				var drop_offsets: PackedFloat32Array = PackedFloat32Array([-76.0, 76.0, -44.0])
				var idx: int = mini(_apples_dropped_in_phase, drop_offsets.size() - 1)
				var apple_x: float = clampf(pos.x + drop_offsets[idx], 20.0, 236.0)
				_spawned_projectiles.append({
					"kind": "apple",
					"pos": Vector2(apple_x, _canopy_y),
					"vel": Vector2(0.0, 0.2),
				})
				_apples_dropped_in_phase += 1
			if _phase_frames >= 66:
				phase = Phase.IDLE
				_phase_frames = 0
		Phase.PUFF_ATTACK:
			if _phase_frames == 12 or _phase_frames == 36:
				var puff_y: float = _mouth_y - (16.0 if _puffs_fired_in_phase > 0 else 0.0)
				_spawned_projectiles.append({
					"kind": "boss_air_puff",
					"pos": Vector2(pos.x + float(facing_dir) * 26.0, puff_y),
					"vel": Vector2(float(facing_dir) * 2.25, 0.0),
				})
				_puffs_fired_in_phase += 1
			if _phase_frames >= 54:
				phase = Phase.IDLE
				_phase_frames = 0

	_sync_visual()


func _sync_visual() -> void:
	position = pos
	if _face_sprite == null:
		return
	if _face_tex_idle == null and ContentRegistry.is_ready():
		_ensure_visual()
	if phase == Phase.DEFEATED:
		if _face_tex_blink != null:
			_face_sprite.texture = _face_tex_blink
		_face_sprite.visible = (_phase_frames < 30) and ((_phase_frames % 4) < 2)
		return
	if phase == Phase.PUFF_ATTACK and _face_tex_puff != null:
		_face_sprite.texture = _face_tex_puff
	elif (_phase_frames % 90) >= 82 and _face_tex_blink != null:
		_face_sprite.texture = _face_tex_blink
	elif _face_tex_idle != null:
		_face_sprite.texture = _face_tex_idle
	if _invuln_frames > 0:
		_face_sprite.visible = (_invuln_frames % 2) == 0
		if _canopy_patch_sprite != null:
			_canopy_patch_sprite.position = Vector2(float((_invuln_frames % 3) - 1) * 2.0, -138.0)
	else:
		_face_sprite.visible = true
		if _canopy_patch_sprite != null:
			var rustle_y: float = -137.0 if (phase == Phase.DROP_APPLES and (_phase_frames % 8) < 4) else -138.0
			_canopy_patch_sprite.position = Vector2(0.0, rustle_y)
