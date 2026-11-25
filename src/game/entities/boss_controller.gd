class_name BossController
extends Node2D
## Worlds 2-7 & Final Boss 60 TPS State Machine (Paint Roller, Mr. Shine & Mr. Bright,
## Kracko, Heavy Mole, Meta Knight, King Dedede, Nightmare).
## Renders dynamically from ROM actor_id metasprites via ContentRegistry.

const Constants = preload("res://src/core/constants.gd")
const LevelMap = preload("res://src/game/level_map.gd")

enum Phase {
	INTRO = 0,
	IDLE = 1,
	ATTACK_PRIMARY = 2,
	ATTACK_SECONDARY = 3,
	DEFEATED = 4,
}

const DEFEAT_SCORE: int = 5000
const HIT_INVULN_FRAMES: int = 12
const GRAVITY: float = 0.18
const ARENA_LEFT: float = 28.0
const ARENA_RIGHT: float = 228.0

var boss_id: int = 2
var actor_id: int = 67
var boss_name: String = "PAINT ROLLER"
var pos: Vector2 = Vector2(180.0, 544.0)
var vel: Vector2 = Vector2.ZERO
var hp: int = 16
var max_hp: int = 16
var phase: int = Phase.INTRO
var facing_dir: int = -1

var _base_y: float = 544.0
var _is_aerial: bool = false
var _phase_frames: int = 0
var _cycle_step: int = 0
var _invuln_frames: int = 0
var _half_width: float = 16.0
var _body_height: float = 32.0
var _spawned_projectiles: Array[Dictionary] = []
var _level_map: LevelMap = null
var _sprite: Sprite2D = null
var _tex_a: ImageTexture = null
var _tex_b: ImageTexture = null
var _off_a: Vector2 = Vector2(-16.0, -32.0)
var _off_b: Vector2 = Vector2(-16.0, -32.0)


func _ready() -> void:
	_ensure_visual()


static func spec_for_room(room_id: int) -> Dictionary:
	match room_id:
		31, 8:
			return {"boss_id": 2, "actor_id": 67, "name": "PAINT ROLLER", "hp": 16, "aerial": false, "w": 14.0, "h": 30.0}
		32, 9:
			return {"boss_id": 3, "actor_id": 68, "name": "SHINE & BRIGHT", "hp": 18, "aerial": true, "w": 16.0, "h": 28.0}
		33, 10:
			return {"boss_id": 4, "actor_id": 69, "name": "KRACKO", "hp": 20, "aerial": true, "w": 18.0, "h": 28.0}
		34, 11:
			return {"boss_id": 5, "actor_id": 61, "name": "HEAVY MOLE", "hp": 22, "aerial": false, "w": 20.0, "h": 32.0}
		35, 12:
			return {"boss_id": 6, "actor_id": 70, "name": "META KNIGHT", "hp": 24, "aerial": false, "w": 14.0, "h": 24.0}
		36, 14:
			return {"boss_id": 7, "actor_id": 71, "name": "KING DEDEDE", "hp": 28, "aerial": false, "w": 18.0, "h": 36.0}
		15:
			return {"boss_id": 8, "actor_id": 63, "name": "NIGHTMARE", "hp": 32, "aerial": true, "w": 18.0, "h": 36.0}
		_:
			return {"boss_id": 2, "actor_id": 67, "name": "BOSS", "hp": 16, "aerial": false, "w": 16.0, "h": 32.0}


func setup_for_room(room_id: int, spawn_pos: Vector2, level_map: LevelMap = null) -> void:
	var spec: Dictionary = spec_for_room(room_id)
	boss_id = int(spec["boss_id"])
	actor_id = int(spec["actor_id"])
	boss_name = String(spec["name"])
	max_hp = int(spec["hp"])
	hp = max_hp
	_is_aerial = bool(spec["aerial"])
	_half_width = float(spec["w"])
	_body_height = float(spec["h"])
	_level_map = level_map
	pos = spawn_pos
	_base_y = spawn_pos.y
	if _is_aerial:
		pos.y = maxf(64.0, _base_y - 64.0)
	position = pos
	vel = Vector2.ZERO
	phase = Phase.INTRO
	facing_dir = -1
	_phase_frames = 0
	_cycle_step = 0
	_invuln_frames = 0
	_spawned_projectiles.clear()
	_tex_a = null
	_tex_b = null
	_ensure_visual()
	_sync_visual()
	EventBus.boss_hp_changed.emit(boss_id, hp, max_hp)


func _ensure_visual() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "BossSprite"
		_sprite.centered = false
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
	if _tex_a == null and ContentRegistry.is_ready():
		var room_id: int = _level_map.get_room_id() if _level_map != null else -1
		var pals: Array[PackedColorArray] = ContentRegistry.get_room_sprite_palettes(room_id)
		var sp_bank: int = 154
		if room_id >= 0 and ContentRegistry.has_room(room_id):
			sp_bank = int(ContentRegistry.get_room_data(room_id).get("sprite_chr_bank", 154))
		var frames: Array = ContentRegistry.get_actor_metasprite_frames(actor_id)
		var frame0: Dictionary = frames[0] as Dictionary if frames.size() >= 1 else {}
		var frame1: Dictionary = frames[1] as Dictionary if frames.size() >= 2 else frame0
		if not frame0.is_empty():
			var b0: Dictionary = ContentRegistry.build_rom_metasprite(frame0, pals, sp_bank, sp_bank, Constants.CHR_BANK_STAR_EFFECTS)
			if not b0.is_empty():
				_tex_a = b0["texture"] as ImageTexture
				_off_a = b0["offset"] as Vector2
		if not frame1.is_empty():
			var b1: Dictionary = ContentRegistry.build_rom_metasprite(frame1, pals, sp_bank, sp_bank, Constants.CHR_BANK_STAR_EFFECTS)
			if not b1.is_empty():
				_tex_b = b1["texture"] as ImageTexture
				_off_b = b1["offset"] as Vector2


func is_defeated() -> bool:
	return phase == Phase.DEFEATED


func get_body_rect() -> Rect2:
	return Rect2(pos.x - _half_width, pos.y - _body_height, _half_width * 2.0, _body_height)


func consume_spawned_projectiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = _spawned_projectiles.duplicate(true)
	_spawned_projectiles.clear()
	return out


func take_damage(amount: int) -> bool:
	if phase == Phase.DEFEATED or _invuln_frames > 0:
		return false
	hp = maxi(0, hp - maxi(1, amount))
	_invuln_frames = HIT_INVULN_FRAMES
	EventBus.boss_hp_changed.emit(boss_id, hp, max_hp)
	if hp <= 0:
		_enter_defeat()
	return true


func _enter_defeat() -> void:
	phase = Phase.DEFEATED
	_phase_frames = 0
	vel = Vector2.ZERO
	_spawned_projectiles.append({
		"kind": "goal_star_rod",
		"pos": Vector2(clampf(pos.x, 48.0, 208.0), _base_y - 24.0),
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
			if _is_aerial:
				pos.x = clampf(pos.x + float(facing_dir) * 0.9, ARENA_LEFT, ARENA_RIGHT)
				pos.y = (_base_y - 68.0) + sin(float(_phase_frames) * 0.12) * 18.0
			if _phase_frames >= 40:
				_phase_frames = 0
				_cycle_step = (_cycle_step + 1) % 2
				phase = Phase.ATTACK_PRIMARY if _cycle_step == 1 else Phase.ATTACK_SECONDARY
				if phase == Phase.ATTACK_PRIMARY and not _is_aerial:
					vel = Vector2(float(facing_dir) * (1.8 + float(boss_id) * 0.15), -3.2 if boss_id >= 6 else 0.0)
		Phase.ATTACK_PRIMARY:
			if _is_aerial:
				pos.x = clampf(pos.x + cos(float(_phase_frames) * 0.1) * 2.2, ARENA_LEFT, ARENA_RIGHT)
				pos.y = (_base_y - 54.0) + sin(float(_phase_frames) * 0.15) * 24.0
				if _phase_frames == 16 or _phase_frames == 36:
					var aim: Vector2 = (kirby_pos - pos).normalized() * 2.1
					if aim.length_squared() < 0.01:
						aim = Vector2(float(facing_dir) * 2.0, 0.5)
					_spawned_projectiles.append({
						"kind": "enemy_fire" if boss_id == 3 or boss_id == 8 else "enemy_beam",
						"pos": pos + Vector2(0.0, -8.0),
						"vel": aim,
					})
			else:
				pos.x = clampf(pos.x + vel.x, ARENA_LEFT, ARENA_RIGHT)
				if pos.x <= ARENA_LEFT or pos.x >= ARENA_RIGHT:
					vel.x = -vel.x
				vel.y = minf(3.6, vel.y + GRAVITY)
				pos.y = minf(_base_y, pos.y + vel.y)
				if pos.y >= _base_y:
					vel.y = 0.0
			if _phase_frames >= 54:
				vel = Vector2.ZERO
				phase = Phase.IDLE
				_phase_frames = 0
		Phase.ATTACK_SECONDARY:
			if _phase_frames == 12 or _phase_frames == 36:
				# Drop/fire an inhalable projectile (apple / star-convertible) + ranged attack
				_spawned_projectiles.append({
					"kind": "apple",
					"pos": Vector2(clampf(kirby_pos.x + (24.0 if _phase_frames == 12 else -24.0), ARENA_LEFT, ARENA_RIGHT), maxf(48.0, _base_y - 120.0)),
					"vel": Vector2(0.0, 0.3),
				})
				_spawned_projectiles.append({
					"kind": "boss_air_puff",
					"pos": Vector2(pos.x + float(facing_dir) * 20.0, pos.y - 16.0),
					"vel": Vector2(float(facing_dir) * 2.2, 0.0),
				})
			if _phase_frames >= 52:
				phase = Phase.IDLE
				_phase_frames = 0

	_sync_visual()


func _sync_visual() -> void:
	position = pos
	if _sprite == null:
		return
	if _tex_a == null and ContentRegistry.is_ready():
		_ensure_visual()
	if phase == Phase.DEFEATED:
		_sprite.visible = (_phase_frames < 30) and ((_phase_frames % 4) < 2)
		return
	var use_b: bool = (_phase_frames / 10) % 2 == 1 and _tex_b != null
	if use_b:
		_sprite.texture = _tex_b
		_sprite.position = _off_b
	elif _tex_a != null:
		_sprite.texture = _tex_a
		_sprite.position = _off_a
	_sprite.flip_h = facing_dir > 0
	if _invuln_frames > 0:
		_sprite.visible = (_invuln_frames % 2) == 0
	else:
		_sprite.visible = true
