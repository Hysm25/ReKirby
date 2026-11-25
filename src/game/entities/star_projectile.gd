class_name StarProjectile
extends Node2D
## Deterministic 60 TPS projectiles, inhalable ability stars/apples, and Goal Star Rod.
## Visuals are composed strictly from ROM CHR banks and palettes in ContentRegistry.

const Constants = preload("res://src/core/constants.gd")
const LevelMap = preload("res://src/game/level_map.gd")

enum Kind {
	STAR_SPIT = 0,
	AIR_PUFF = 1,
	WATER_GUN = 2,
	ABILITY_STAR = 3,
	APPLE = 4,
	BOSS_AIR_PUFF = 5,
	ENEMY_FIRE = 6,
	ENEMY_BEAM = 7,
	GOAL_STAR_ROD = 8,
}

const GRAVITY_APPLE: float = 0.12
const GRAVITY_STAR: float = 0.14
const MAX_FALL_SPEED: float = 3.2
const ABILITY_STAR_BOUNCE_VY: float = -2.4
const APPLE_BOUNCE_VY: float = -1.35

var kind: int = Kind.STAR_SPIT
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var ability_id: int = Constants.CopyAbility.NONE
var half_size: Vector2 = Vector2(7.0, 7.0)

var _alive: bool = true
var _age_frames: int = 0
var _max_age_frames: int = 180
var _being_inhaled: bool = false
var _bounces: int = 0
var _level_map: LevelMap = null
var _sprite: Sprite2D = null
var _tex_a: ImageTexture = null
var _tex_b: ImageTexture = null


func _ready() -> void:
	_ensure_sprite()


func _ensure_sprite() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "ProjectileSprite"
		_sprite.centered = true
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
	_refresh_rom_textures()


func setup(
	p_kind: int,
	spawn_pos: Vector2,
	initial_vel: Vector2,
	level_map: LevelMap,
	p_ability_id: int = Constants.CopyAbility.NONE
) -> void:
	kind = p_kind
	pos = spawn_pos
	vel = initial_vel
	_level_map = level_map
	ability_id = p_ability_id
	_alive = true
	_age_frames = 0
	_being_inhaled = false
	_bounces = 0
	position = pos

	match kind:
		Kind.STAR_SPIT:
			half_size = Vector2(8.0, 8.0)
			_max_age_frames = 150
		Kind.AIR_PUFF, Kind.WATER_GUN:
			half_size = Vector2(6.0, 6.0)
			_max_age_frames = 20
		Kind.ABILITY_STAR:
			half_size = Vector2(8.0, 8.0)
			_max_age_frames = 300
		Kind.APPLE:
			half_size = Vector2(7.0, 7.0)
			_max_age_frames = 240
		Kind.BOSS_AIR_PUFF:
			half_size = Vector2(7.0, 7.0)
			_max_age_frames = 140
		Kind.ENEMY_FIRE:
			half_size = Vector2(6.0, 6.0)
			_max_age_frames = 90
		Kind.ENEMY_BEAM:
			half_size = Vector2(5.0, 5.0)
			_max_age_frames = 24
		Kind.GOAL_STAR_ROD:
			half_size = Vector2(8.0, 8.0)
			_max_age_frames = -1
		_:
			half_size = Vector2(6.0, 6.0)
			_max_age_frames = 120

	_tex_a = null
	_tex_b = null
	_ensure_sprite()
	_sync_visual()


static func kind_from_string(kind_name: String) -> int:
	match kind_name:
		"star_spit":
			return Kind.STAR_SPIT
		"air_puff":
			return Kind.AIR_PUFF
		"water_gun":
			return Kind.WATER_GUN
		"ability_star":
			return Kind.ABILITY_STAR
		"apple":
			return Kind.APPLE
		"boss_air_puff":
			return Kind.BOSS_AIR_PUFF
		"enemy_fire":
			return Kind.ENEMY_FIRE
		"enemy_beam":
			return Kind.ENEMY_BEAM
		"goal_star_rod":
			return Kind.GOAL_STAR_ROD
		_:
			return Kind.STAR_SPIT


static func from_spawn_dict(data: Dictionary, level_map: LevelMap) -> StarProjectile:
	var proj: StarProjectile = StarProjectile.new()
	var k_str: String = String(data.get("kind", "star_spit"))
	var k_val: int = kind_from_string(k_str)
	var p_pos: Vector2 = data.get("pos", Vector2.ZERO) as Vector2
	var p_vel: Vector2 = data.get("vel", Vector2.ZERO) as Vector2
	var p_ab: int = int(data.get("ability", Constants.CopyAbility.NONE))
	proj.setup(k_val, p_pos, p_vel, level_map, p_ab)
	return proj


func is_alive() -> bool:
	return _alive


func kill() -> void:
	_alive = false
	if _sprite != null:
		_sprite.visible = false


func is_friendly() -> bool:
	return kind == Kind.STAR_SPIT or kind == Kind.AIR_PUFF or kind == Kind.WATER_GUN


func is_hostile() -> bool:
	if _being_inhaled:
		return false
	return kind == Kind.APPLE or kind == Kind.BOSS_AIR_PUFF or kind == Kind.ENEMY_FIRE or kind == Kind.ENEMY_BEAM


func is_inhalable() -> bool:
	return kind == Kind.ABILITY_STAR or kind == Kind.APPLE or kind == Kind.ENEMY_FIRE


func is_goal_pickup() -> bool:
	return kind == Kind.GOAL_STAR_ROD


func is_being_inhaled() -> bool:
	return _being_inhaled


func get_damage() -> int:
	if kind == Kind.STAR_SPIT:
		return 2
	if kind == Kind.AIR_PUFF or kind == Kind.WATER_GUN:
		return 1
	return 1


func get_ability_id() -> int:
	return ability_id


func get_hitbox_rect() -> Rect2:
	return Rect2(pos - half_size, half_size * 2.0)


func begin_inhale_pull(target_pos: Vector2) -> void:
	if not _alive or not is_inhalable():
		return
	_being_inhaled = true
	var delta: Vector2 = target_pos - pos
	var dist: float = delta.length()
	if dist > 0.01:
		var pull_speed: float = 3.2
		vel = (delta / dist) * pull_speed


func cancel_inhale_pull() -> void:
	_being_inhaled = false


func is_ready_for_capture(kirby_mouth_pos: Vector2) -> bool:
	if not _alive or not _being_inhaled:
		return false
	return pos.distance_to(kirby_mouth_pos) <= 12.0


func step_physics() -> void:
	if not _alive:
		return
	_age_frames += 1
	if _max_age_frames > 0 and _age_frames >= _max_age_frames:
		kill()
		return

	if _being_inhaled:
		pos += vel
		_sync_visual()
		return

	if kind == Kind.GOAL_STAR_ROD:
		pos.y += sin(float(_age_frames) * 0.1) * 0.25
		_sync_visual()
		return

	if kind == Kind.ABILITY_STAR:
		_step_bouncing_body(GRAVITY_STAR, ABILITY_STAR_BOUNCE_VY, true)
	elif kind == Kind.APPLE:
		_step_bouncing_body(GRAVITY_APPLE, APPLE_BOUNCE_VY, false)
	else:
		_step_linear_projectile()

	if _level_map != null:
		var w_px: float = float(_level_map.get_width_pixels())
		var h_px: float = float(_level_map.get_height_pixels())
		if w_px > 0.0 and (pos.x < -16.0 or pos.x > w_px + 16.0):
			kill()
			return
		if h_px > 0.0 and (pos.y < -32.0 or pos.y > h_px + 32.0):
			kill()
			return

	_sync_visual()


func _step_linear_projectile() -> void:
	pos += vel
	if _level_map == null:
		return
	var mx: int = int(floor(pos.x / float(Constants.METATILE_SIZE)))
	var my: int = int(floor(pos.y / float(Constants.METATILE_SIZE)))
	var col: int = _level_map.get_collision_at_tile(mx, my)
	if is_friendly() and (col == Constants.TileCollision.BREAKABLE_STAR or col == Constants.TileCollision.BOMB_BLOCK):
		_level_map.break_metatile_at(mx, my)
		kill()
		return
	if LevelMap.is_full_solid_collision(col):
		if kind != Kind.ENEMY_BEAM and kind != Kind.BOSS_AIR_PUFF:
			kill()


func _step_bouncing_body(grav: float, bounce_vy: float, bounce_walls: bool) -> void:
	vel.y = minf(vel.y + grav, MAX_FALL_SPEED)
	pos.x += vel.x
	if _level_map != null:
		var edge_x: float = pos.x + half_size.x if vel.x >= 0.0 else pos.x - half_size.x
		var mx: int = int(floor(edge_x / float(Constants.METATILE_SIZE)))
		var my: int = int(floor(pos.y / float(Constants.METATILE_SIZE)))
		if LevelMap.is_full_solid_collision(_level_map.get_collision_at_tile(mx, my)):
			if bounce_walls:
				vel.x = -vel.x
				pos.x += vel.x
			else:
				vel.x = 0.0

	pos.y += vel.y
	if _level_map != null and vel.y >= 0.0:
		var foot_y: float = pos.y + half_size.y
		var mx: int = int(floor(pos.x / float(Constants.METATILE_SIZE)))
		var my: int = int(floor(foot_y / float(Constants.METATILE_SIZE)))
		var surf_y: int = _level_map.get_floor_surface_y(int(pos.x), my, true)
		if surf_y >= 0 and foot_y >= float(surf_y):
			pos.y = float(surf_y) - half_size.y
			if kind == Kind.ABILITY_STAR:
				vel.y = bounce_vy
			elif _bounces < 2:
				_bounces += 1
				vel.y = bounce_vy * (0.6 if _bounces > 1 else 1.0)
				if absf(vel.x) < 0.05:
					vel.x = 0.35 if (_age_frames % 2 == 0) else -0.35
			else:
				vel.y = 0.0
				vel.x = move_toward(vel.x, 0.0, 0.08)


func _refresh_rom_textures() -> void:
	if not ContentRegistry.is_ready():
		return
	var pal_key: String = "hud_sp_star"
	if _level_map != null:
		var room_pal_key: String = "room_%d_sp_1" % _level_map.get_room_id()
		if not ContentRegistry.get_palette_indices(room_pal_key).is_empty():
			pal_key = room_pal_key

	match kind:
		Kind.STAR_SPIT, Kind.ABILITY_STAR, Kind.GOAL_STAR_ROD:
			_tex_a = ContentRegistry.build_rom_oam_8x16(
				Constants.CHR_BANK_STAR_EFFECTS,
				Vector2i(16, 17), Vector2i(18, 19),
				pal_key
			)
			_tex_b = ContentRegistry.build_rom_oam_8x16(
				Constants.CHR_BANK_STAR_EFFECTS,
				Vector2i(20, 21), Vector2i(22, 23),
				pal_key
			)
		Kind.AIR_PUFF, Kind.WATER_GUN, Kind.BOSS_AIR_PUFF:
			_tex_a = ContentRegistry.build_rom_oam_8x16(
				Constants.CHR_BANK_STAR_EFFECTS,
				Vector2i(8, 9), Vector2i(10, 11),
				pal_key
			)
			_tex_b = _tex_a
		Kind.APPLE:
			var apple_pal: String = "hud_sp_fire"
			if _level_map != null:
				var r_sp2: String = "room_%d_sp_2" % _level_map.get_room_id()
				if not ContentRegistry.get_palette_indices(r_sp2).is_empty():
					apple_pal = r_sp2
			_tex_a = ContentRegistry.build_rom_oam_8x16(
				154,
				Vector2i(24, 25), Vector2i(24, 25),
				apple_pal, false, true
			)
			_tex_b = ContentRegistry.build_rom_oam_8x16(
				154,
				Vector2i(26, 27), Vector2i(26, 27),
				apple_pal, false, true
			)
		Kind.ENEMY_FIRE:
			_tex_a = ContentRegistry.build_rom_oam_8x16(
				Constants.CHR_BANK_ABILITY_EFFECTS,
				Vector2i(4, 5), Vector2i(6, 7),
				"hud_sp_fire"
			)
			_tex_b = _tex_a
		Kind.ENEMY_BEAM:
			_tex_a = ContentRegistry.build_rom_sprite_texture(
				Constants.CHR_BANK_ABILITY_EFFECTS,
				PackedInt32Array([12, 13]),
				1, 2,
				"hud_sp_beam"
			)
			_tex_b = _tex_a
		_:
			pass


func _sync_visual() -> void:
	position = pos
	if _sprite == null:
		return
	_sprite.visible = _alive
	if not _alive:
		return
	if _tex_a == null and ContentRegistry.is_ready():
		_refresh_rom_textures()
	if _tex_b != null and ((_age_frames / 4) % 2) == 1:
		_sprite.texture = _tex_b
	elif _tex_a != null:
		_sprite.texture = _tex_a
	_sprite.flip_h = vel.x < 0.0
	if kind == Kind.ABILITY_STAR and _max_age_frames - _age_frames < 60:
		_sprite.visible = (_age_frames % 4) < 2
