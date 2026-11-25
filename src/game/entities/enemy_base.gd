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
	MID_BOSS = 7,
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
var actor_id: int = 14
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
var _frames_left: Array[Dictionary] = []
var _frames_right: Array[Dictionary] = []
var _tex_a_right: ImageTexture = null
var _tex_b_right: ImageTexture = null
var _tex_a_left: ImageTexture = null
var _tex_b_left: ImageTexture = null


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
		# Secondary World 1-7 actors mapped cleanly to closest authentic behavior
		19, 27, 28, 34, 43, 60:
			return EnemyType.WADDLE_DEE
		10, 11, 20, 22, 25, 26, 29, 30, 31, 35, 36, 37, 38, 40, 42, 45, 46, 47, 48, 54, 55, 58, 59, 61, 63, 64, 66, 67, 68, 69, 70, 71:
			return EnemyType.WADDLE_DEE
		72, 73, 74, 75, 76, 77, 79:
			return EnemyType.MID_BOSS
		23, 24, 32, 33, 44, 57, 65:
			return EnemyType.BRONTO_BURT
		_:
			return -1


static func ability_for_actor_id(p_actor_id: int) -> int:
	match p_actor_id:
		15:
			return Constants.CopyAbility.BEAM
		17:
			return Constants.CopyAbility.SWORD
		18:
			return Constants.CopyAbility.FIRE
		16:
			return Constants.CopyAbility.SPARK
		19:
			return Constants.CopyAbility.CUTTER
		20, 22:
			return Constants.CopyAbility.ICE
		23:
			return Constants.CopyAbility.WHEEL
		24:
			return Constants.CopyAbility.PARASOL
		25:
			return Constants.CopyAbility.STONE
		26:
			return Constants.CopyAbility.NEEDLE
		27:
			return Constants.CopyAbility.SLEEP
		28:
			return Constants.CopyAbility.HI_JUMP
		29:
			return Constants.CopyAbility.BALL
		30:
			return Constants.CopyAbility.TORNADO
		31:
			return Constants.CopyAbility.LASER
		32:
			return Constants.CopyAbility.FREEZE
		33:
			return Constants.CopyAbility.UFO
		34, 35:
			return Constants.CopyAbility.HAMMER
		36:
			return Constants.CopyAbility.MIKE
		37:
			return Constants.CopyAbility.CRASH
		38:
			return Constants.CopyAbility.THROW
		40:
			return Constants.CopyAbility.BACKDROP
		42:
			return Constants.CopyAbility.LIGHT
		72:
			return Constants.CopyAbility.CRASH
		73:
			return Constants.CopyAbility.ICE
		74:
			return Constants.CopyAbility.HAMMER
		75:
			return Constants.CopyAbility.BACKDROP
		76:
			return Constants.CopyAbility.THROW
		77:
			return Constants.CopyAbility.WHEEL
		79:
			return Constants.CopyAbility.FIRE
		_:
			return Constants.CopyAbility.NONE


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
	if p_type == EnemyType.MID_BOSS:
		return 6
	if p_type == EnemyType.BLADE_KNIGHT:
		return 2
	return 1


static func default_score_for_type(p_type: int) -> int:
	match p_type:
		EnemyType.MID_BOSS:
			return 1500
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


static func default_actor_id_for_type(p_type: int) -> int:
	match p_type:
		EnemyType.WADDLE_DEE:
			return 14
		EnemyType.WADDLE_DOO:
			return 15
		EnemyType.POPPY_BROS_JR:
			return 56
		EnemyType.BLADE_KNIGHT:
			return 17
		EnemyType.HOT_HEAD:
			return 18
		EnemyType.SPARKY:
			return 16
		EnemyType.BRONTO_BURT:
			return 41
		_:
			return 14


static func map_museum_card_to_ability(card_idx: int) -> int:
	match card_idx:
		1:
			return Constants.CopyAbility.FIRE
		2:
			return Constants.CopyAbility.SPARK
		3:
			return Constants.CopyAbility.CUTTER
		4:
			return Constants.CopyAbility.SWORD
		5:
			return Constants.CopyAbility.FIREBALL
		6:
			return Constants.CopyAbility.LASER
		7:
			return Constants.CopyAbility.MIKE
		8:
			return Constants.CopyAbility.WHEEL
		9:
			return Constants.CopyAbility.HAMMER
		10:
			return Constants.CopyAbility.PARASOL
		12:
			return Constants.CopyAbility.NEEDLE
		13:
			return Constants.CopyAbility.ICE
		14:
			return Constants.CopyAbility.FREEZE
		15:
			return Constants.CopyAbility.HI_JUMP
		16:
			return Constants.CopyAbility.BEAM
		17:
			return Constants.CopyAbility.STONE
		_:
			return Constants.CopyAbility.NONE


func setup(
	p_type: int,
	spawn_pos: Vector2,
	level_map: LevelMap,
	p_facing_dir: int = -1,
	room_sprite_bank: int = 154,
	p_actor_id: int = -1,
	p_subtype: int = 0
) -> void:
	enemy_type = p_type
	actor_id = p_actor_id if p_actor_id >= 0 else default_actor_id_for_type(p_type)
	var actor_ab: int = map_museum_card_to_ability(p_subtype) if actor_id == 10 else ability_for_actor_id(actor_id)
	copy_ability = actor_ab if actor_ab != Constants.CopyAbility.NONE else default_ability_for_type(p_type)
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
	_frames_left.clear()
	_frames_right.clear()
	_tex_a_right = null
	_tex_b_right = null
	_tex_a_left = null
	_tex_b_left = null
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
	if state == State.DEFEATED or enemy_type == EnemyType.MID_BOSS:
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
		if enemy_type == EnemyType.MID_BOSS and copy_ability != Constants.CopyAbility.NONE:
			_spawned_projectiles.append({
				"kind": "ability_star",
				"pos": pos + Vector2(0.0, -10.0),
				"vel": Vector2(float(-facing_dir) * 1.1, -2.0),
				"ability": copy_ability,
			})
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
			_step_walker(0.0 if actor_id == 10 else 0.55)
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
		EnemyType.MID_BOSS:
			_step_mid_boss(kirby_pos)
		_:
			_step_walker(0.55)

	_sync_visual()


func _step_walker(speed: float) -> void:
	vel.x = float(facing_dir) * speed
	_apply_ground_physics(true)


func _step_mid_boss(kirby_pos: Vector2) -> void:
	_attack_timer -= 1
	if on_ground:
		if _attack_timer <= 0:
			facing_dir = 1 if kirby_pos.x >= pos.x else -1
			_attack_timer = 72
			vel.x = float(facing_dir) * 1.55
			vel.y = -2.8
			on_ground = false
			if copy_ability != Constants.CopyAbility.NONE:
				_spawned_projectiles.append({
					"kind": "apple",
					"pos": pos + Vector2(float(facing_dir) * 12.0, -12.0),
					"vel": Vector2(float(facing_dir) * 1.4, -1.2),
				})
		else:
			vel.x = float(facing_dir) * 0.8
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
	_frames_left.clear()
	_frames_right.clear()
	var room_id: int = _level_map.get_room_id() if _level_map != null else -1
	var room_pals: Array[PackedColorArray] = ContentRegistry.get_room_sprite_palettes(room_id)
	var rom_frames: Array = ContentRegistry.get_actor_metasprite_frames(actor_id)
	if not rom_frames.is_empty():
		if actor_id == 16 and rom_frames.size() >= 6:
			# Sparky (actor 16): [0]=front idle, [1,2]=left hop, [4]=front idle, [5,6]=right hop
			for l_i: int in [1, 2]:
				var built_l: Dictionary = ContentRegistry.build_rom_metasprite(rom_frames[l_i] as Dictionary, room_pals, Constants.CHR_BANK_KIRBY_DEFAULT, _room_sprite_chr_bank)
				if not built_l.is_empty():
					_frames_left.append(built_l)
			for r_i: int in [5, 6]:
				var built_r: Dictionary = ContentRegistry.build_rom_metasprite(rom_frames[r_i] as Dictionary, room_pals, Constants.CHR_BANK_KIRBY_DEFAULT, _room_sprite_chr_bank)
				if not built_r.is_empty():
					_frames_right.append(built_r)
		else:
			var pair_limit: int = mini(rom_frames.size() / 2, 3)
			if pair_limit >= 1:
				for p_i: int in range(pair_limit):
					var f_l: Dictionary = ContentRegistry.build_rom_metasprite(rom_frames[p_i * 2] as Dictionary, room_pals, Constants.CHR_BANK_KIRBY_DEFAULT, _room_sprite_chr_bank)
					var f_r: Dictionary = ContentRegistry.build_rom_metasprite(rom_frames[p_i * 2 + 1] as Dictionary, room_pals, Constants.CHR_BANK_KIRBY_DEFAULT, _room_sprite_chr_bank)
					if not f_l.is_empty():
						_frames_left.append(f_l)
					if not f_r.is_empty():
						_frames_right.append(f_r)
			else:
				var f_0: Dictionary = ContentRegistry.build_rom_metasprite(rom_frames[0] as Dictionary, room_pals, Constants.CHR_BANK_KIRBY_DEFAULT, _room_sprite_chr_bank)
				if not f_0.is_empty():
					_frames_left.append(f_0)
					_frames_right.append(f_0)

	if not _frames_right.is_empty():
		_tex_a_right = _frames_right[0]["texture"] as ImageTexture
		_tex_b_right = (_frames_right[mini(1, _frames_right.size() - 1)]["texture"]) as ImageTexture
	if not _frames_left.is_empty():
		_tex_a_left = _frames_left[0]["texture"] as ImageTexture
		_tex_b_left = (_frames_left[mini(1, _frames_left.size() - 1)]["texture"]) as ImageTexture
	if not _frames_right.is_empty() or not _frames_left.is_empty():
		return

	# Clean OAM 8x16 fallback if metasprite catalog was omitted by synthetic unit setup
	var pal_key: String = "room_%d_sp_2" % room_id if room_id >= 0 and not ContentRegistry.get_palette_indices("room_%d_sp_2" % room_id).is_empty() else "hud_sp_fire"
	_tex_a_right = ContentRegistry.build_rom_oam_8x16(_room_sprite_chr_bank, Vector2i(4, 5), Vector2i(16, 17), pal_key, false, false, false, 1)
	_tex_b_right = ContentRegistry.build_rom_oam_8x16(_room_sprite_chr_bank, Vector2i(18, 19), Vector2i(20, 21), pal_key, false, false, false, 1)
	_tex_a_left = ContentRegistry.build_rom_oam_8x16(_room_sprite_chr_bank, Vector2i(4, 5), Vector2i(16, 17), pal_key, false, false, false, -1)
	_tex_b_left = ContentRegistry.build_rom_oam_8x16(_room_sprite_chr_bank, Vector2i(18, 19), Vector2i(20, 21), pal_key, false, false, false, -1)


func get_current_anim_frame_index() -> int:
	if _attack_active_frames > 0:
		if _frames_right.size() >= 3:
			return 2
		return 1
	return (_state_frames / 8) % 2


func _sync_visual() -> void:
	position = Vector2(roundf(pos.x), roundf(pos.y))
	if _sprite == null:
		return
	if state == State.DEFEATED:
		_sprite.visible = false
		return
	if _frames_right.is_empty() and _tex_a_right == null and ContentRegistry.is_ready():
		_refresh_rom_textures()
	var frame_idx: int = get_current_anim_frame_index()
	var use_left: bool = facing_dir < 0
	var active_list: Array[Dictionary] = _frames_left if use_left else _frames_right
	if not active_list.is_empty():
		var clamped_idx: int = clampi(frame_idx, 0, active_list.size() - 1)
		var entry: Dictionary = active_list[clamped_idx]
		_sprite.texture = entry["texture"] as ImageTexture
		_sprite.position = entry["offset"] as Vector2
	else:
		var tex: ImageTexture = (_tex_b_left if frame_idx == 1 else _tex_a_left) if use_left else (_tex_b_right if frame_idx == 1 else _tex_a_right)
		if tex != null:
			_sprite.texture = tex
		_sprite.position = Vector2(-8.0, -16.0)
	_sprite.flip_h = false
	if _hit_cooldown > 0:
		_sprite.visible = (_hit_cooldown % 2) == 0
	else:
		_sprite.visible = true
