class_name KirbyController
extends Node2D
## Deterministic 60 TPS Kirby physics, slope traversal, hover, swim, inhale/spit,
## swallow, and damage/invulnerability controller.

const Constants = preload("res://src/core/constants.gd")
const LevelMap = preload("res://src/game/level_map.gd")

enum State {
	IDLE = 0,
	WALK = 1,
	RUN = 2,
	CROUCH = 3,
	SLIDE = 4,
	JUMP = 5,
	FALL = 6,
	HOVER = 7,
	EXHALE = 8,
	SWIM = 9,
	WATER_GUN = 10,
	INHALE = 11,
	MOUTH_FULL = 12,
	DAMAGE_KNOCKBACK = 13,
	DEFEAT = 14,
}

const MAX_HP: int = 6
const HALF_WIDTH: float = 6.0
const STAND_HEIGHT: float = 15.0
const CROUCH_HEIGHT: float = 9.0
const SLOPE_UP_TOLERANCE: float = 14.0
const SLOPE_DOWN_TOLERANCE: float = 8.0

const WALK_SPEED: float = 1.5
const RUN_SPEED: float = 2.65
const SLIDE_SPEED: float = 3.25
const GROUND_ACCEL: float = 0.25
const GROUND_DECEL: float = 0.22
const AIR_ACCEL: float = 0.16
const JUMP_VEL: float = -4.15
const JUMP_CUT_VEL: float = -1.6
const GRAVITY: float = 0.18
const MAX_FALL_SPEED: float = 3.6

const HOVER_PUFF_VEL: float = -2.1
const HOVER_GRAVITY: float = 0.055
const HOVER_MAX_FALL: float = 0.85

const SWIM_ACCEL: float = 0.14
const SWIM_MAX_SPEED: float = 1.35
const SWIM_BUOYANCY: float = 0.045
const SWIM_PADDLE_VEL: float = -1.9

const KNOCKBACK_VX: float = 1.6
const KNOCKBACK_VY: float = -2.4
const DASH_WINDOW_FRAMES: int = 14
const SLIDE_DURATION_FRAMES: int = 22
const EXHALE_FRAMES: int = 10
const WATER_GUN_FRAMES: int = 12
const DAMAGE_LOCK_FRAMES: int = 20
const INVULN_FRAMES: int = 120
const DROP_THROUGH_FRAMES: int = 10

var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var facing_dir: int = 1 # 1 = right, -1 = left
var state: int = State.IDLE
var on_ground: bool = false
var in_water: bool = false

var hp: int = MAX_HP
var max_hp: int = MAX_HP
var copy_ability: int = Constants.CopyAbility.NONE
var has_cargo: bool = false
var cargo_ability: int = Constants.CopyAbility.NONE

var invuln_frames: int = 0
var state_frames: int = 0
var _slide_frames: int = 0
var _drop_through_frames: int = 0
var _dash_tap_dir: int = 0
var _dash_tap_timer: int = 0
var _is_running: bool = false
var _hovering: bool = false
var _inhaling: bool = false

var _level_map: LevelMap = null
var _spawned_projectiles: Array[Dictionary] = []
var _sprite: Sprite2D = null
var _idle_tex: ImageTexture = null


func _ready() -> void:
	_ensure_visual_sprite()


func _ensure_visual_sprite() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "KirbySprite"
		_sprite.centered = false
		_sprite.position = Vector2(-8.0, -16.0)
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
	if _idle_tex == null and ContentRegistry.is_ready():
		_idle_tex = _build_kirby_rom_texture()
	if _idle_tex != null:
		_sprite.texture = _idle_tex


func _build_kirby_rom_texture() -> ImageTexture:
	# Compose 16x16 standing Kirby from ROM CHR bank 128 (0x80): left 8x16 (tiles 8,9) + right 8x16 (tiles 12,13)
	var bank_img: Image = ContentRegistry.get_chr_bank_image(128)
	if bank_img == null or bank_img.is_empty():
		return null
	var pal: PackedColorArray = ContentRegistry.get_palette_colors("kirby_default")
	if pal.size() < 4:
		return null

	var src_rgba: PackedByteArray = bank_img.get_data()
	var out_rgba: PackedByteArray = PackedByteArray()
	out_rgba.resize(16 * 16 * 4)

	var cols: PackedInt32Array = PackedInt32Array([8, 12, 9, 13])
	for q: int in range(4):
		var local_tile: int = cols[q]
		var tx0: int = (local_tile % 8) * Constants.TILE_SIZE
		var ty0: int = (local_tile / 8) * Constants.TILE_SIZE
		var dst_qx: int = (q & 1) * Constants.TILE_SIZE
		var dst_qy: int = ((q >> 1) & 1) * Constants.TILE_SIZE
		for py: int in range(Constants.TILE_SIZE):
			var src_row: int = ((ty0 + py) * Constants.CHR_1K_BANK_SHEET_WIDTH + tx0) * 4
			var dst_row: int = ((dst_qy + py) * 16 + dst_qx) * 4
			for px: int in range(Constants.TILE_SIZE):
				var gray: int = src_rgba[src_row + px * 4]
				var c_idx: int = clampi((gray + 42) / 85, 0, 3)
				var dst_off: int = dst_row + px * 4
				if c_idx == 0:
					out_rgba[dst_off] = 0
					out_rgba[dst_off + 1] = 0
					out_rgba[dst_off + 2] = 0
					out_rgba[dst_off + 3] = 0
				else:
					var col: Color = pal[c_idx]
					out_rgba[dst_off] = clampi(int(round(col.r * 255.0)), 0, 255)
					out_rgba[dst_off + 1] = clampi(int(round(col.g * 255.0)), 0, 255)
					out_rgba[dst_off + 2] = clampi(int(round(col.b * 255.0)), 0, 255)
					out_rgba[dst_off + 3] = 255

	var img: Image = Image.create_from_data(16, 16, false, Image.FORMAT_RGBA8, out_rgba)
	return ImageTexture.create_from_image(img)


func setup(level_map: LevelMap, spawn_pos: Vector2) -> void:
	_level_map = level_map
	pos = spawn_pos
	position = pos
	vel = Vector2.ZERO
	facing_dir = 1
	state = State.IDLE
	on_ground = false
	in_water = false
	hp = max_hp
	copy_ability = Constants.CopyAbility.NONE
	has_cargo = false
	cargo_ability = Constants.CopyAbility.NONE
	invuln_frames = 0
	state_frames = 0
	_slide_frames = 0
	_drop_through_frames = 0
	_dash_tap_dir = 0
	_dash_tap_timer = 0
	_is_running = false
	_hovering = false
	_inhaling = false
	_spawned_projectiles.clear()
	_ensure_visual_sprite()


func get_collision_height() -> float:
	if state == State.CROUCH or state == State.SLIDE:
		return CROUCH_HEIGHT
	return STAND_HEIGHT


func get_body_rect() -> Rect2:
	var h: float = get_collision_height()
	return Rect2(pos.x - HALF_WIDTH, pos.y - h, HALF_WIDTH * 2.0, h)


func get_active_hitbox() -> Dictionary:
	if state == State.INHALE:
		var box_x: float = pos.x + 4.0 if facing_dir > 0 else pos.x - 44.0
		return {
			"active": true,
			"kind": "inhale",
			"rect": Rect2(box_x, pos.y - 18.0, 40.0, 20.0),
		}
	if state == State.SLIDE:
		var sx: float = pos.x if facing_dir > 0 else pos.x - 14.0
		return {
			"active": true,
			"kind": "slide",
			"rect": Rect2(sx, pos.y - CROUCH_HEIGHT, 14.0, CROUCH_HEIGHT),
		}
	return {"active": false, "kind": "", "rect": Rect2()}


func consume_spawned_projectiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = _spawned_projectiles.duplicate(true)
	_spawned_projectiles.clear()
	return out


func capture_inhaled_cargo(ability_id: int = Constants.CopyAbility.NONE) -> bool:
	if state != State.INHALE:
		return false
	_inhaling = false
	has_cargo = true
	cargo_ability = ability_id
	state = State.MOUTH_FULL
	state_frames = 0
	return true


func take_damage(amount: int = 1, knock_dir: int = -1) -> bool:
	if invuln_frames > 0 or state == State.DEFEAT:
		return false

	hp = maxi(0, hp - maxi(1, amount))
	EventBus.hp_changed.emit(hp, max_hp)

	# Drop active Copy Ability as a bouncing Ability Star on hit
	if copy_ability != Constants.CopyAbility.NONE:
		var dropped_ability: int = copy_ability
		copy_ability = Constants.CopyAbility.NONE
		EventBus.copy_ability_changed.emit(copy_ability)
		_spawned_projectiles.append({
			"kind": "ability_star",
			"ability": dropped_ability,
			"pos": Vector2(pos.x, pos.y - 8.0),
			"vel": Vector2(float(-knock_dir) * 1.4, -2.5),
		})

	_inhaling = false
	_hovering = false
	_is_running = false
	_slide_frames = 0
	invuln_frames = INVULN_FRAMES
	state_frames = 0

	if hp <= 0:
		state = State.DEFEAT
		vel = Vector2(0.0, -3.0)
	else:
		state = State.DAMAGE_KNOCKBACK
		var kdir: int = knock_dir if knock_dir != 0 else -facing_dir
		vel = Vector2(float(kdir) * KNOCKBACK_VX, KNOCKBACK_VY)
		on_ground = false
	return true


func step_physics() -> void:
	state_frames += 1
	if invuln_frames > 0:
		invuln_frames -= 1
	if _drop_through_frames > 0:
		_drop_through_frames -= 1
	if _dash_tap_timer > 0:
		_dash_tap_timer -= 1
	else:
		_dash_tap_dir = 0

	if state == State.DEFEAT:
		vel.y = minf(vel.y + GRAVITY, MAX_FALL_SPEED)
		pos += vel
		_sync_visual()
		return

	var move_dir: int = 0
	if InputManager.is_pressed(Constants.NesButton.LEFT):
		move_dir -= 1
	if InputManager.is_pressed(Constants.NesButton.RIGHT):
		move_dir += 1

	var a_pressed: bool = InputManager.is_pressed(Constants.NesButton.A)
	var a_just: bool = InputManager.is_just_pressed(Constants.NesButton.A)
	var a_rel: bool = InputManager.is_just_released(Constants.NesButton.A)
	var b_pressed: bool = InputManager.is_pressed(Constants.NesButton.B)
	var b_just: bool = InputManager.is_just_pressed(Constants.NesButton.B)
	var up_pressed: bool = InputManager.is_pressed(Constants.NesButton.UP)
	var up_just: bool = InputManager.is_just_pressed(Constants.NesButton.UP)
	var down_pressed: bool = InputManager.is_pressed(Constants.NesButton.DOWN)
	var down_just: bool = InputManager.is_just_pressed(Constants.NesButton.DOWN)

	# Check water state from center pixel
	if _level_map != null:
		in_water = _level_map.is_water_at_pixel(int(pos.x), int(pos.y - 7.0))
	else:
		in_water = false

	# Handle damage lock state
	if state == State.DAMAGE_KNOCKBACK:
		vel.y = minf(vel.y + GRAVITY, MAX_FALL_SPEED)
		_move_and_collide()
		if state_frames >= DAMAGE_LOCK_FRAMES:
			state = State.IDLE if on_ground else State.FALL
			state_frames = 0
		_sync_visual()
		return

	# Check double-tap dash initiation on ground (track both tap press and release)
	if on_ground and not in_water:
		if InputManager.is_just_pressed(Constants.NesButton.RIGHT):
			if _dash_tap_dir == 1 and _dash_tap_timer > 0:
				_is_running = true
			else:
				_dash_tap_dir = 1
				_dash_tap_timer = DASH_WINDOW_FRAMES
		elif InputManager.is_just_pressed(Constants.NesButton.LEFT):
			if _dash_tap_dir == -1 and _dash_tap_timer > 0:
				_is_running = true
			else:
				_dash_tap_dir = -1
				_dash_tap_timer = DASH_WINDOW_FRAMES
		if InputManager.is_just_released(Constants.NesButton.RIGHT):
			_dash_tap_dir = 1
			_dash_tap_timer = DASH_WINDOW_FRAMES
		elif InputManager.is_just_released(Constants.NesButton.LEFT):
			_dash_tap_dir = -1
			_dash_tap_timer = DASH_WINDOW_FRAMES
	if move_dir == 0 or (move_dir != facing_dir and _is_running):
		if move_dir == 0:
			_is_running = false

	# Timed action states
	if state == State.SLIDE:
		_slide_frames -= 1
		vel.x = float(facing_dir) * SLIDE_SPEED
		vel.y = 0.0
		_move_and_collide()
		if _slide_frames <= 0 or not on_ground:
			state = State.CROUCH if (on_ground and down_pressed) else (State.IDLE if on_ground else State.FALL)
			state_frames = 0
		_check_hazards()
		_sync_visual()
		return

	if state == State.EXHALE:
		_apply_air_horizontal(move_dir)
		vel.y = minf(vel.y + GRAVITY, MAX_FALL_SPEED)
		_move_and_collide()
		if state_frames >= EXHALE_FRAMES:
			state = State.IDLE if on_ground else State.FALL
			state_frames = 0
		_check_hazards()
		_sync_visual()
		return

	if state == State.WATER_GUN:
		_apply_swim_physics(move_dir, up_pressed, down_pressed, a_just)
		_move_and_collide()
		if state_frames >= WATER_GUN_FRAMES:
			state = State.SWIM if in_water else State.FALL
			state_frames = 0
		_check_hazards()
		_sync_visual()
		return

	# Water swimming mode (overrides hover/inhale when submerged)
	if in_water:
		_hovering = false
		_inhaling = false
		if has_cargo and b_just:
			_fire_star_spit()
		elif not has_cargo and b_just:
			state = State.WATER_GUN
			state_frames = 0
			_spawned_projectiles.append({
				"kind": "water_gun",
				"pos": Vector2(pos.x + float(facing_dir) * 8.0, pos.y - 8.0),
				"vel": Vector2(float(facing_dir) * 2.8, 0.0),
			})
		else:
			state = State.SWIM
		_apply_swim_physics(move_dir, up_pressed, down_pressed, a_just)
		_move_and_collide()
		_check_hazards()
		_sync_visual()
		return

	# Mouth-Full mode (cannot hover or inhale until spit/swallow)
	if has_cargo:
		if move_dir != 0:
			facing_dir = move_dir
		if b_just:
			_fire_star_spit()
		elif down_just and on_ground:
			_swallow_cargo()
		else:
			if on_ground:
				_apply_ground_horizontal(move_dir, WALK_SPEED)
				if a_just:
					_start_jump()
				else:
					state = State.MOUTH_FULL
			else:
				_apply_air_horizontal(move_dir)
				if a_rel and vel.y < JUMP_CUT_VEL:
					vel.y = JUMP_CUT_VEL
				vel.y = minf(vel.y + GRAVITY, MAX_FALL_SPEED)
				state = State.MOUTH_FULL
		_move_and_collide()
		_check_hazards()
		_sync_visual()
		return

	# Inhale active (holding B when normal)
	if state == State.INHALE:
		if not b_pressed:
			_inhaling = false
			state = State.IDLE if on_ground else State.FALL
			state_frames = 0
		else:
			vel.x = move_toward(vel.x, 0.0, GROUND_DECEL) if on_ground else move_toward(vel.x, 0.0, AIR_ACCEL)
			if not on_ground:
				vel.y = minf(vel.y + GRAVITY, MAX_FALL_SPEED)
			_process_inhale_blocks()
			_move_and_collide()
			_check_hazards()
			_sync_visual()
			return

	# Hover mode (midair inflation)
	if _hovering:
		if move_dir != 0:
			facing_dir = move_dir
		if b_just:
			_hovering = false
			state = State.EXHALE
			state_frames = 0
			_spawned_projectiles.append({
				"kind": "air_puff",
				"pos": Vector2(pos.x + float(facing_dir) * 8.0, pos.y - 8.0),
				"vel": Vector2(float(facing_dir) * 2.75, 0.0),
			})
		else:
			_apply_air_horizontal(move_dir, WALK_SPEED * 0.85)
			if a_just or up_just or (a_pressed and vel.y > 0.25):
				vel.y = HOVER_PUFF_VEL
			else:
				vel.y = minf(vel.y + HOVER_GRAVITY, HOVER_MAX_FALL)
			state = State.HOVER
		_move_and_collide()
		if on_ground:
			_hovering = false
			state = State.IDLE
		_check_hazards()
		_sync_visual()
		return

	# Standard Ground / Airborne state machine
	if on_ground:
		if move_dir != 0 and not down_pressed:
			facing_dir = move_dir

		# Crouch / Drop-through / Slide
		if down_pressed:
			vel.x = move_toward(vel.x, 0.0, GROUND_DECEL)
			state = State.CROUCH
			if a_just or b_just:
				if _is_standing_on_one_way():
					_drop_through_frames = DROP_THROUGH_FRAMES
					on_ground = false
					pos.y += 2.0
					vel.y = 0.6
					state = State.FALL
					state_frames = 0
				elif a_just or b_just:
					state = State.SLIDE
					state_frames = 0
					_slide_frames = SLIDE_DURATION_FRAMES
					vel.x = float(facing_dir) * SLIDE_SPEED
		elif b_just and copy_ability == Constants.CopyAbility.NONE:
			_inhaling = true
			state = State.INHALE
			state_frames = 0
		elif a_just:
			_start_jump()
		else:
			var target_spd: float = RUN_SPEED if _is_running else WALK_SPEED
			_apply_ground_horizontal(move_dir, target_spd)
			if absf(vel.x) > 0.05:
				state = State.RUN if _is_running else State.WALK
			else:
				state = State.IDLE
	else:
		if move_dir != 0:
			facing_dir = move_dir
		if b_just and copy_ability == Constants.CopyAbility.NONE:
			_inhaling = true
			state = State.INHALE
			state_frames = 0
		elif up_just or a_just:
			_hovering = true
			vel.y = HOVER_PUFF_VEL
			state = State.HOVER
			state_frames = 0
		else:
			if a_rel and vel.y < JUMP_CUT_VEL:
				vel.y = JUMP_CUT_VEL
			_apply_air_horizontal(move_dir)
			vel.y = minf(vel.y + GRAVITY, MAX_FALL_SPEED)
			state = State.JUMP if vel.y < 0.0 else State.FALL

	_move_and_collide()
	_check_hazards()
	_sync_visual()


func _start_jump() -> void:
	on_ground = false
	vel.y = JUMP_VEL
	state = State.JUMP
	state_frames = 0


func _fire_star_spit() -> void:
	has_cargo = false
	cargo_ability = Constants.CopyAbility.NONE
	state = State.IDLE if on_ground else State.FALL
	state_frames = 0
	_spawned_projectiles.append({
		"kind": "star_spit",
		"pos": Vector2(pos.x + float(facing_dir) * 10.0, pos.y - 8.0),
		"vel": Vector2(float(facing_dir) * 4.5, 0.0),
	})


func _swallow_cargo() -> void:
	var gained: int = cargo_ability
	has_cargo = false
	cargo_ability = Constants.CopyAbility.NONE
	if gained != Constants.CopyAbility.NONE:
		copy_ability = gained
		EventBus.copy_ability_changed.emit(copy_ability)
	state = State.IDLE
	state_frames = 0


func _apply_ground_horizontal(move_dir: int, max_speed: float) -> void:
	if move_dir != 0:
		vel.x = move_toward(vel.x, float(move_dir) * max_speed, GROUND_ACCEL)
	else:
		vel.x = move_toward(vel.x, 0.0, GROUND_DECEL)


func _apply_air_horizontal(move_dir: int, max_speed: float = WALK_SPEED) -> void:
	var cap: float = RUN_SPEED if _is_running else max_speed
	if move_dir != 0:
		vel.x = move_toward(vel.x, float(move_dir) * cap, AIR_ACCEL)
	else:
		vel.x = move_toward(vel.x, 0.0, AIR_ACCEL * 0.5)


func _apply_swim_physics(move_dir: int, up_pressed: bool, down_pressed: bool, a_just: bool) -> void:
	if move_dir != 0:
		facing_dir = move_dir
		vel.x = move_toward(vel.x, float(move_dir) * SWIM_MAX_SPEED, SWIM_ACCEL)
	else:
		vel.x = move_toward(vel.x, 0.0, SWIM_ACCEL * 0.7)

	if a_just:
		vel.y = SWIM_PADDLE_VEL
	elif up_pressed:
		vel.y = move_toward(vel.y, -SWIM_MAX_SPEED, SWIM_ACCEL)
	elif down_pressed:
		vel.y = move_toward(vel.y, SWIM_MAX_SPEED, SWIM_ACCEL)
	else:
		vel.y = move_toward(vel.y, 0.35, SWIM_BUOYANCY)


func _process_inhale_blocks() -> void:
	if _level_map == null or state_frames < 6:
		return
	var hb: Dictionary = get_active_hitbox()
	if not bool(hb.get("active", false)):
		return
	var rect: Rect2 = hb["rect"] as Rect2
	var min_mx: int = int(floor(rect.position.x / float(Constants.METATILE_SIZE)))
	var max_mx: int = int(floor((rect.position.x + rect.size.x) / float(Constants.METATILE_SIZE)))
	var min_my: int = int(floor(rect.position.y / float(Constants.METATILE_SIZE)))
	var max_my: int = int(floor((rect.position.y + rect.size.y) / float(Constants.METATILE_SIZE)))
	for my: int in range(min_my, max_my + 1):
		for mx: int in range(min_mx, max_mx + 1):
			if _level_map.get_collision_at_tile(mx, my) == Constants.TileCollision.BREAKABLE_STAR:
				if _level_map.break_metatile_at(mx, my):
					capture_inhaled_cargo(Constants.CopyAbility.NONE)
					return


func _is_standing_on_one_way() -> bool:
	if _level_map == null or not on_ground:
		return false
	var my: int = int(floor(pos.y / float(Constants.METATILE_SIZE)))
	var sample_xs: PackedFloat32Array = PackedFloat32Array([pos.x - HALF_WIDTH + 1.0, pos.x, pos.x + HALF_WIDTH - 1.0])
	var saw_one_way: bool = false
	for sx: float in sample_xs:
		var mx: int = int(floor(sx / float(Constants.METATILE_SIZE)))
		var col: int = _level_map.get_collision_at_tile(mx, my)
		if col == Constants.TileCollision.ONE_WAY:
			saw_one_way = true
		elif LevelMap.is_full_solid_collision(col) or LevelMap.is_slope_collision(col):
			return false
	return saw_one_way


func _move_and_collide() -> void:
	if _level_map == null:
		pos += vel
		return

	var prev_y: float = pos.y
	var cur_h: float = get_collision_height()

	# 1. Horizontal movement and solid wall resolution
	pos.x += vel.x
	if vel.x != 0.0:
		var edge_x: float = pos.x + HALF_WIDTH if vel.x > 0.0 else pos.x - HALF_WIDTH
		var mx: int = int(floor(edge_x / float(Constants.METATILE_SIZE)))
		var y_top: int = int(floor((pos.y - cur_h + 2.0) / float(Constants.METATILE_SIZE)))
		var y_mid: int = int(floor((pos.y - cur_h * 0.5) / float(Constants.METATILE_SIZE)))
		var y_bot: int = int(floor((pos.y - 2.0) / float(Constants.METATILE_SIZE)))

		var blocked: bool = false
		for check_my: int in [y_top, y_mid, y_bot]:
			var col_type: int = _level_map.get_collision_at_tile(mx, check_my)
			if LevelMap.is_full_solid_collision(col_type):
				if state == State.SLIDE and col_type == Constants.TileCollision.BREAKABLE_STAR:
					_level_map.break_metatile_at(mx, check_my)
					continue
				# Allow climbing onto a solid step only if it's already below slope tolerance? No, full solid blocks horizontally unless feet are already above its surface
				var tile_top_y: float = float(check_my * Constants.METATILE_SIZE)
				if on_ground and check_my == y_bot and pos.y - tile_top_y <= 2.0:
					continue
				blocked = true
				break
			elif LevelMap.is_slope_collision(col_type):
				var surf_y: int = _level_map.get_floor_surface_y(int(edge_x), check_my, false)
				if surf_y >= 0 and pos.y - float(surf_y) > SLOPE_UP_TOLERANCE:
					blocked = true
					break

		if blocked:
			if vel.x > 0.0:
				pos.x = float(mx * Constants.METATILE_SIZE) - HALF_WIDTH - 0.01
			else:
				pos.x = float((mx + 1) * Constants.METATILE_SIZE) + HALF_WIDTH + 0.01
			vel.x = 0.0

	# Clamp to room horizontal boundaries
	var room_w_px: float = float(_level_map.get_width_pixels())
	if room_w_px > 0.0:
		pos.x = clampf(pos.x, HALF_WIDTH, room_w_px - HALF_WIDTH)

	# 2. Vertical movement & slope snapping
	var sample_xs: PackedFloat32Array = PackedFloat32Array([
		pos.x - HALF_WIDTH + 1.0,
		pos.x,
		pos.x + HALF_WIDTH - 1.0,
	])
	var allow_one_way: bool = _drop_through_frames == 0

	if on_ground and vel.y >= 0.0:
		var base_my: int = int(floor(pos.y / float(Constants.METATILE_SIZE)))
		var best_y: float = 1e9
		var found_support: bool = false
		for sx: float in sample_xs:
			for check_my: int in [base_my - 1, base_my, base_my + 1]:
				var surf: int = _level_map.get_floor_surface_y(int(sx), check_my, allow_one_way)
				if surf < 0:
					continue
				var surf_f: float = float(surf)
				if surf_f >= pos.y - SLOPE_UP_TOLERANCE and surf_f <= pos.y + SLOPE_DOWN_TOLERANCE:
					if surf_f < best_y:
						best_y = surf_f
						found_support = true
		if found_support:
			pos.y = best_y
			vel.y = 0.0
			on_ground = true
		else:
			on_ground = false
	else:
		pos.y += vel.y
		if vel.y < 0.0:
			var head_y: float = pos.y - cur_h
			var head_my: int = int(floor(head_y / float(Constants.METATILE_SIZE)))
			var hit_ceiling: bool = false
			for sx: float in sample_xs:
				var col_type: int = _level_map.get_collision_at_tile(int(floor(sx / float(Constants.METATILE_SIZE))), head_my)
				if LevelMap.is_full_solid_collision(col_type):
					hit_ceiling = true
					break
			if hit_ceiling:
				pos.y = float((head_my + 1) * Constants.METATILE_SIZE) + cur_h
				vel.y = 0.0
		else:
			var min_my: int = int(floor(prev_y / float(Constants.METATILE_SIZE))) - 1
			var max_my: int = int(floor(pos.y / float(Constants.METATILE_SIZE))) + 1
			var best_land_y: float = 1e9
			var landed: bool = false
			for sx: float in sample_xs:
				for check_my: int in range(min_my, max_my + 1):
					var surf: int = _level_map.get_floor_surface_y(int(sx), check_my, allow_one_way)
					if surf < 0:
						continue
					var surf_f: float = float(surf)
					if prev_y <= surf_f + 2.0 and pos.y >= surf_f:
						if surf_f < best_land_y:
							best_land_y = surf_f
							landed = true
			if landed:
				pos.y = best_land_y
				vel.y = 0.0
				on_ground = true
				_hovering = false


func _check_hazards() -> void:
	if _level_map == null or invuln_frames > 0:
		return
	var cy: float = pos.y - get_collision_height() * 0.5
	if _level_map.is_hazard_at_pixel(int(pos.x), int(cy)) or _level_map.is_hazard_at_pixel(int(pos.x), int(pos.y - 1.0)):
		take_damage(1, -facing_dir)


func _sync_visual() -> void:
	position = pos
	if _sprite != null:
		_sprite.flip_h = facing_dir < 0
		if invuln_frames > 0:
			_sprite.visible = (invuln_frames % 4) < 2
		else:
			_sprite.visible = true
