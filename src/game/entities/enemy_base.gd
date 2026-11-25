class_name EnemyBase
extends Node2D
## Deterministic 60 TPS World 1 enemy actor supporting authentic ROM actor_id spawns,
## inhale suction/capture, Copy Ability drops, patrol/hop/fly/attack AI, and ROM CHR rendering.

const Constants = preload("res://src/core/constants.gd")
const LevelMap = preload("res://src/game/level_map.gd")

enum EnemyType {
	WADDLE_DEE = 0,
	WADDLE_DOO = 1,
	POPPY_BROS_JR = 2,
	BLADE_KNIGHT = 3,
	HOT_HEAD = 4,
	SPARKY = 5,
	BRONTO_BURT = 6,
}

enum State {
	ACTIVE = 0,
	BEING_INHALED = 1,
	DEFEATED = 2,
}

const GRAVITY: float = 0.18
const MAX_FALL_SPEED: float = 3.2
const INHALE_PULL_SPEED: float = 3.0
const CAPTURE_RADIUS: float = 12.0
const HALF_WIDTH: float = 7.0
const BODY_HEIGHT: float = 15.0

var enemy_type: int = EnemyType.WADDLE_DEE
var copy_ability: int = Constants.CopyAbility.NONE
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var facing_dir: int = -1
var state: int = State.ACTIVE
var hp: int = 1
var max_hp: int = 1
var score_value: int = 200
var on_ground: bool = false

var _origin_pos: Vector2 = Vector2.ZERO
var _state_frames: int = 0
var _attack_timer: int = 0
var _attack_active_frames: int = 0
var _hit_cooldown: int = 0
var _room_sprite_chr_bank: int = 154
var _level_map: LevelMap = null
var _spawned_projectiles: Array[Dictionary] = []
var _sprite: Sprite2D = null
var _tex_frame_a: ImageTexture = null
var _tex_frame_b: ImageTexture = null


func _ready() -> void:
	_ensure_sprite()


func _ensure_sprite() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "EnemySprite"
		_sprite.centered = false
		_sprite.position = Vector2(-8.0, -16.0)
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
	_refresh_rom_textures()


static func map_rom_actor_id(actor_id: int) -> int:
	match actor_id:
		14:
			return EnemyType.WADDLE_DEE
		15:
			return EnemyType.WADDLE_DOO
		56:
			return EnemyType.POPPY_BROS_JR
		17:
			return EnemyType.BLADE_KNIGHT
		18:
			return EnemyType.HOT_HEAD
		16:
			return EnemyType.SPARKY
		41:
			return EnemyType.BRONTO_BURT
		# Secondary World 1 actors mapped cleanly to closest authentic behavior
		19, 27, 28, 34, 43, 60:
			return EnemyType.WADDLE_DEE
		23, 24, 32, 33, 44, 57, 65:
			return EnemyType.BRONTO_BURT
		_:
			return -1


static func default_ability_for_type(p_type: int) -> int:
	match p_type:
		EnemyType.WADDLE_DOO:
			return Constants.CopyAbility.BEAM
		EnemyType.BLADE_KNIGHT:
			return Constants.CopyAbility.SWORD
		EnemyType.HOT_HEAD:
			return Constants.CopyAbility.FIRE
		EnemyType.SPARKY:
			return Constants.CopyAbility.SPARK
		_:
			return Constants.CopyAbility.NONE


static func default_hp_for_type(p_type: int) -> int:
	if p_type == EnemyType.BLADE_KNIGHT:
		return 2
	return 1


static func default_score_for_type(p_type: int) -> int:
	match p_type:
		EnemyType.WADDLE_DEE:
			return 200
		EnemyType.BRONTO_BURT:
			return 300
		EnemyType.WADDLE_DOO, EnemyType.POPPY_BROS_JR:
			return 400
		EnemyType.BLADE_KNIGHT, EnemyType.HOT_HEAD, EnemyType.SPARKY:
			return 500
		_:
			return 200


func setup(
	p_type: int,
	spawn_pos: Vector2,
	level_map: LevelMap,
	p_facing_dir: int = -1,
	room_sprite_bank: int = 154
) -> void:
	enemy_type = p_type
	copy_ability = default_ability_for_type(p_type)
	max_hp = default_hp_for_type(p_type)
	hp = max_hp
	score_value = default_score_for_type(p_type)
	pos = spawn_pos
	_origin_pos = spawn_pos
	position = pos
	facing_dir = 1 if p_facing_dir > 0 else -1
	vel = Vector2.ZERO
	state = State.ACTIVE
	on_ground = false
	_state_frames = 0
	_attack_timer = 45
	_attack_active_frames = 0
	_hit_cooldown = 0
	_level_map = level_map
	_room_sprite_chr_bank = room_sprite_bank
	_spawned_projectiles.clear()
	_tex_frame_a = null
	_tex_frame_b = null
	_ensure_sprite()
	_sync_visual()


func is_alive() -> bool:
	return state != State.DEFEATED


func get_copy_ability() -> int:
	return copy_ability


func get_body_rect() -> Rect2:
	return Rect2(pos.x - HALF_WIDTH, pos.y - BODY_HEIGHT, HALF_WIDTH * 2.0, BODY_HEIGHT)


func get_attack_hitbox() -> Dictionary:
	if state != State.ACTIVE or _attack_active_frames <= 0:
		return {"active": false, "rect": Rect2()}
	if enemy_type == EnemyType.SPARKY:
		return {
			"active": true,
			"kind": "enemy_spark",
			"rect": Rect2(pos.x - 18.0, pos.y - 24.0, 36.0, 30.0),
		}
	if enemy_type == EnemyType.BLADE_KNIGHT:
		var sx: float = pos.x + 2.0 if facing_dir > 0 else pos.x - 24.0
		return {
			"active": true,
			"kind": "enemy_sword",
			"rect": Rect2(sx, pos.y - 16.0, 22.0, 16.0),
		}
	return {"active": false, "rect": Rect2()}


func consume_spawned_projectiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = _spawned_projectiles.duplicate(true)
	_spawned_projectiles.clear()
	return out


func begin_inhale_pull(kirby_mouth_pos: Vector2) -> void:
	if state == State.DEFEATED:
		return
	state = State.BEING_INHALED
	_attack_active_frames = 0
	var delta: Vector2 = kirby_mouth_pos - Vector2(pos.x, pos.y - 8.0)
	var dist: float = delta.length()
	if dist > 0.01:
		vel = (delta / dist) * INHALE_PULL_SPEED


func release_inhale_pull() -> void:
	if state == State.BEING_INHALED:
		state = State.ACTIVE
		vel = Vector2.ZERO


func is_ready_for_capture(kirby_mouth_pos: Vector2) -> bool:
	if state != State.BEING_INHALED:
		return false
	return Vector2(pos.x, pos.y - 8.0).distance_to(kirby_mouth_pos) <= CAPTURE_RADIUS


func mark_captured() -> void:
	state = State.DEFEATED
	_attack_active_frames = 0
	_sync_visual()


func take_damage(amount: int, knock_dir: int = 1) -> bool:
	if state == State.DEFEATED or _hit_cooldown > 0:
		return false
	hp = maxi(0, hp - maxi(1, amount))
	_hit_cooldown = 10
	if hp <= 0:
		state = State.DEFEATED
		_attack_active_frames = 0
		_sync_visual()
		return true
	vel = Vector2(float(knock_dir) * 1.3, -1.6)
	on_ground = false
	return true


func step_physics(kirby_pos: Vector2) -> void:
	if state == State.DEFEATED:
		return
	_state_frames += 1
	if _hit_cooldown > 0:
		_hit_cooldown -= 1

	if state == State.BEING_INHALED:
		pos += vel
		_sync_visual()
		return

	if _attack_active_frames > 0:
		_attack_active_frames -= 1

	match enemy_type:
		EnemyType.WADDLE_DEE:
			_step_walker(0.55)
		EnemyType.WADDLE_DOO:
			_step_waddle_doo(kirby_pos)
		EnemyType.POPPY_BROS_JR:
			_step_hopper(0.75, -2.6, 54, kirby_pos)
		EnemyType.BLADE_KNIGHT:
			_step_blade_knight(kirby_pos)
		EnemyType.HOT_HEAD:
			_step_hot_head(kirby_pos)
		EnemyType.SPARKY:
			_step_sparky(kirby_pos)
		EnemyType.BRONTO_BURT:
			_step_bronto_burt()
		_:
			_step_walker(0.55)

	_sync_visual()


func _step_walker(speed: float) -> void:
	vel.x = float(facing_dir) * speed
	_apply_ground_physics(true)


func _step_waddle_doo(kirby_pos: Vector2) -> void:
	_attack_timer -= 1
	if _attack_timer <= 0:
		facing_dir = 1 if kirby_pos.x >= pos.x else -1
		_attack_timer = 90
		_spawned_projectiles.append({
			"kind": "enemy_beam",
			"pos": Vector2(pos.x + float(facing_dir) * 10.0, pos.y - 8.0),
			"vel": Vector2(float(facing_dir) * 2.1, 0.35),
		})
	vel.x = float(facing_dir) * 0.55
	_apply_ground_physics(true)


func _step_hopper(hop_vx: float, hop_vy: float, interval_frames: int, kirby_pos: Vector2) -> void:
	if on_ground:
		_attack_timer -= 1
		if _attack_timer <= 0:
			facing_dir = 1 if kirby_pos.x >= pos.x else -1
			vel.x = float(facing_dir) * hop_vx
			vel.y = hop_vy
			on_ground = false
			_attack_timer = interval_frames
		else:
			vel.x = 0.0
	_apply_ground_physics(false)


func _step_blade_knight(kirby_pos: Vector2) -> void:
	var dist_x: float = absf(kirby_pos.x - pos.x)
	var dist_y: float = absf(kirby_pos.y - pos.y)
	_attack_timer -= 1
	if _attack_active_frames > 0:
		vel.x = float(facing_dir) * 1.1
	elif dist_x <= 36.0 and dist_y <= 24.0 and _attack_timer <= 0:
		facing_dir = 1 if kirby_pos.x >= pos.x else -1
		_attack_active_frames = 16
		_attack_timer = 64
		vel.x = float(facing_dir) * 1.4
	else:
		vel.x = float(facing_dir) * 0.65
	_apply_ground_physics(true)


func _step_hot_head(kirby_pos: Vector2) -> void:
	_attack_timer -= 1
	if _attack_timer <= 0:
		facing_dir = 1 if kirby_pos.x >= pos.x else -1
		_attack_timer = 100
		_spawned_projectiles.append({
			"kind": "enemy_fire",
			"pos": Vector2(pos.x + float(facing_dir) * 10.0, pos.y - 8.0),
			"vel": Vector2(float(facing_dir) * 2.2, 0.0),
			"ability": Constants.CopyAbility.FIRE,
		})
	vel.x = float(facing_dir) * 0.5
	_apply_ground_physics(true)


func _step_sparky(kirby_pos: Vector2) -> void:
	_attack_timer -= 1
	if _attack_timer <= 0 and on_ground:
		facing_dir = 1 if kirby_pos.x >= pos.x else -1
		_attack_active_frames = 24
		_attack_timer = 96
		vel.x = 0.0
	elif _attack_active_frames <= 0 and on_ground and _attack_timer > 25 and (_state_frames % 30) == 0:
		facing_dir = 1 if kirby_pos.x >= pos.x else -1
		vel.x = float(facing_dir) * 0.75
		vel.y = -2.1
		on_ground = false
	elif on_ground and _attack_active_frames <= 0:
		vel.x = 0.0
	_apply_ground_physics(false)


func _step_bronto_burt() -> void:
	vel.x = float(facing_dir) * 0.85
	pos.x += vel.x
	pos.y = _origin_pos.y + sin(float(_state_frames) * 0.09) * 14.0
	if _level_map != null:
		var room_w: float = float(_level_map.get_width_pixels())
		if pos.x <= 12.0:
			pos.x = 12.0
			facing_dir = 1
		elif room_w > 0.0 and pos.x >= room_w - 12.0:
			pos.x = room_w - 12.0
			facing_dir = -1


func _apply_ground_physics(turn_on_ledge: bool) -> void:
	if _level_map == null:
		pos += vel
		return

	vel.y = minf(vel.y + GRAVITY, MAX_FALL_SPEED)
	var prev_y: float = pos.y

	pos.x += vel.x
	var room_w: float = float(_level_map.get_width_pixels())
	var hit_wall: bool = false
	if pos.x < HALF_WIDTH:
		pos.x = HALF_WIDTH
		hit_wall = true
	elif room_w > 0.0 and pos.x > room_w - HALF_WIDTH:
		pos.x = room_w - HALF_WIDTH
		hit_wall = true
	elif vel.x != 0.0:
		var edge_x: float = pos.x + HALF_WIDTH if vel.x > 0.0 else pos.x - HALF_WIDTH
		var mx: int = int(floor(edge_x / float(Constants.METATILE_SIZE)))
		var my_mid: int = int(floor((pos.y - 7.0) / float(Constants.METATILE_SIZE)))
		if LevelMap.is_full_solid_collision(_level_map.get_collision_at_tile(mx, my_mid)):
			pos.x -= vel.x
			hit_wall = true

	if hit_wall:
		facing_dir = -facing_dir
		vel.x = 0.0

	pos.y += vel.y
	if vel.y >= 0.0:
		var base_my: int = int(floor(pos.y / float(Constants.METATILE_SIZE)))
		var landed: bool = false
		var best_y: float = 1e9
		for check_my: int in [base_my - 1, base_my, base_my + 1]:
			var surf: int = _level_map.get_floor_surface_y(int(pos.x), check_my, true)
			if surf >= 0 and prev_y <= float(surf) + 4.0 and pos.y >= float(surf):
				if float(surf) < best_y:
					best_y = float(surf)
					landed = true
		if landed:
			pos.y = best_y
			vel.y = 0.0
			on_ground = true
		else:
			on_ground = false

	if turn_on_ledge and on_ground and vel.x != 0.0:
		var ahead_x: int = int(pos.x + float(facing_dir) * (HALF_WIDTH + 3.0))
		var ahead_my: int = int(floor((pos.y + 4.0) / float(Constants.METATILE_SIZE)))
		var ahead_surf: int = _level_map.get_floor_surface_y(ahead_x, ahead_my, true)
		var ahead_above: int = _level_map.get_floor_surface_y(ahead_x, ahead_my - 1, true)
		if ahead_surf < 0 and ahead_above < 0:
			facing_dir = -facing_dir


func _refresh_rom_textures() -> void:
	if not ContentRegistry.is_ready():
		return
	var fh: int = Constants.OAM_FLIP_H
	var fv: int = Constants.OAM_FLIP_V
	var bank_id: int = _room_sprite_chr_bank
	var tiles_a: PackedInt32Array = PackedInt32Array([4, 4 | fh, 5, 5 | fh])
	var tiles_b: PackedInt32Array = PackedInt32Array([0, 4 | fh, 1, 5 | fh])
	var pal_key: String = "hud_sp_fire"
	if _level_map != null:
		var r_sp2: String = "room_%d_sp_2" % _level_map.get_room_id()
		if not ContentRegistry.get_palette_indices(r_sp2).is_empty():
			pal_key = r_sp2

	match enemy_type:
		EnemyType.WADDLE_DEE:
			bank_id = 154
			tiles_a = PackedInt32Array([4, 4 | fh, 5, 5 | fh])
			tiles_b = PackedInt32Array([0, 4 | fh, 1, 5 | fh])
		EnemyType.WADDLE_DOO:
			bank_id = 154
			tiles_a = PackedInt32Array([14, 14 | fh, 15, 15 | fh])
			tiles_b = PackedInt32Array([12, 14 | fh, 13, 15 | fh])
		EnemyType.POPPY_BROS_JR:
			bank_id = 154
			tiles_a = PackedInt32Array([32, 34 | fh, 33, 35 | fh])
			tiles_b = PackedInt32Array([48, 50, 49, 51])
		EnemyType.BLADE_KNIGHT:
			bank_id = 158
			tiles_a = PackedInt32Array([42, 42 | fh, 43, 43 | fh])
			tiles_b = PackedInt32Array([40, 40 | fh, 41, 41 | fh])
		EnemyType.HOT_HEAD:
			bank_id = 158
			tiles_a = PackedInt32Array([32, 32 | fh, 33, 33 | fh])
			tiles_b = PackedInt32Array([34, 34 | fh, 35, 35 | fh])
		EnemyType.SPARKY:
			bank_id = 158
			tiles_a = PackedInt32Array([38, 38 | fh, 39, 39 | fh])
			tiles_b = PackedInt32Array([36, 36 | fh, 37, 37 | fh])
		EnemyType.BRONTO_BURT:
			bank_id = 154
			tiles_a = PackedInt32Array([28, 30, 29, 31])
			tiles_b = PackedInt32Array([28, 30 | fv, 29, 31])

	_tex_frame_a = ContentRegistry.build_rom_sprite_texture(bank_id, tiles_a, 2, 2, pal_key)
	_tex_frame_b = ContentRegistry.build_rom_sprite_texture(bank_id, tiles_b, 2, 2, pal_key)


func get_current_anim_frame_index() -> int:
	if _attack_active_frames > 0:
		return 1
	return (_state_frames / 8) % 2


func _sync_visual() -> void:
	position = pos
	if _sprite == null:
		return
	if state == State.DEFEATED:
		_sprite.visible = false
		return
	if _tex_frame_a == null and ContentRegistry.is_ready():
		_refresh_rom_textures()
	var frame_idx: int = get_current_anim_frame_index()
	if _tex_frame_b != null and frame_idx == 1:
		_sprite.texture = _tex_frame_b
	elif _tex_frame_a != null:
		_sprite.texture = _tex_frame_a
	_sprite.flip_h = facing_dir > 0
	if _hit_cooldown > 0:
		_sprite.visible = (_hit_cooldown % 2) == 0
	else:
		_sprite.visible = true
