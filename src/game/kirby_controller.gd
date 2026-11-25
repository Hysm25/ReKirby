class_name KirbyController
extends Node2D
## Deterministic 60 TPS Kirby physics, slope traversal, hover, swim, inhale/spit,
## swallow, and damage/invulnerability controller.

const Constants = preload("res://src/core/constants.gd")
const LevelMap = preload("res://src/game/level_map.gd")
const AbilityBase = preload("res://src/game/abilities/ability_base.gd")
const AbilitySword = preload("res://src/game/abilities/ability_sword.gd")
const AbilityFire = preload("res://src/game/abilities/ability_fire.gd")
const AbilitySpark = preload("res://src/game/abilities/ability_spark.gd")
const AbilityBeam = preload("res://src/game/abilities/ability_beam.gd")

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
	ABILITY_ATTACK = 15,
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
var _anim_frame: int = 0
var _current_anim_key: String = "idle_0"
var _last_tex_facing: int = 1
var _abilities: Dictionary = {}
var _active_ability: AbilityBase = null


func _ready() -> void:
	_ensure_visual_sprite()
	_ensure_ability_nodes()


func _ensure_visual_sprite() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "KirbySprite"
		_sprite.centered = false
		_sprite.position = Vector2(-8.0, -16.0)
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
	_apply_kirby_anim_texture("idle_0")


func _get_kirby_pose_spec(anim_key: String) -> Dictionary:
	# NES 8x16 hardware sprite columns: left_col=(TL, BL), right_col=(TR, BR)
	match anim_key:
		"idle_0":
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT, "left": Vector2i(8, 9), "right": Vector2i(12, 13), "flip_r": false}
		"idle_blink":
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT, "left": Vector2i(8, 9), "right": Vector2i(14, 15), "flip_r": false}
		"walk_0":
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT, "left": Vector2i(4, 5), "right": Vector2i(16, 17), "flip_r": false}
		"walk_1":
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT, "left": Vector2i(8, 9), "right": Vector2i(18, 19), "flip_r": false}
		"walk_2":
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT, "left": Vector2i(10, 11), "right": Vector2i(16, 17), "flip_r": false}
		"walk_3":
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT, "left": Vector2i(6, 7), "right": Vector2i(24, 25), "flip_r": false}
		"crouch":
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT, "left": Vector2i(56, 57), "right": Vector2i(58, 59), "flip_r": false}
		"slide":
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT, "left": Vector2i(52, 53), "right": Vector2i(54, 55), "flip_r": false}
		"jump_flip":
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT, "left": Vector2i(40, 41), "right": Vector2i(40, 41), "flip_r": true}
		"hover_0":
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT + 1, "left": Vector2i(8, 9), "right": Vector2i(12, 13), "flip_r": false}
		"hover_1":
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT + 1, "left": Vector2i(14, 15), "right": Vector2i(16, 17), "flip_r": false}
		"hover_2":
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT + 1, "left": Vector2i(18, 19), "right": Vector2i(20, 21), "flip_r": false}
		"inhale":
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT + 1, "left": Vector2i(32, 33), "right": Vector2i(34, 35), "flip_r": false}
		"hurt":
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT + 1, "left": Vector2i(24, 25), "right": Vector2i(26, 27), "flip_r": false}
		"ability_atk":
			return {"bank": Constants.CHR_BANK_ABILITY_KIRBY, "left": Vector2i(8, 9), "right": Vector2i(16, 17), "flip_r": false}
		_:
			return {"bank": Constants.CHR_BANK_KIRBY_DEFAULT, "left": Vector2i(8, 9), "right": Vector2i(12, 13), "flip_r": false}


func _resolve_anim_key() -> String:
	match state:
		State.IDLE:
			return "idle_blink" if (_anim_frame % 180) >= 170 else "idle_0"
		State.WALK:
			var step_w: int = (_anim_frame / 6) % 4
			return "walk_%d" % step_w
		State.RUN:
			var step_r: int = (_anim_frame / 3) % 4
			return "walk_%d" % step_r
		State.CROUCH:
			return "crouch"
		State.SLIDE:
			return "slide"
		State.JUMP:
			return "jump_flip" if ((_anim_frame / 4) % 2) == 0 else "walk_1"
		State.FALL:
			return "walk_3" if vel.y > 1.2 else "idle_0"
		State.HOVER:
			var step_h: int = (_anim_frame / 6) % 3
			return "hover_%d" % step_h
		State.EXHALE, State.INHALE:
			return "inhale"
		State.MOUTH_FULL:
			if absf(vel.x) > 0.1 and ((_anim_frame / 7) % 2) == 1:
				return "hover_1"
			return "hover_0"
		State.SWIM, State.WATER_GUN:
			return "hover_1" if ((_anim_frame / 8) % 2) == 0 else "hover_2"
		State.DAMAGE_KNOCKBACK, State.DEFEAT:
			return "hurt"
		State.ABILITY_ATTACK:
			return "ability_atk"
		_:
			return "idle_0"


func _apply_kirby_anim_texture(anim_key: String) -> void:
	_current_anim_key = anim_key
	_last_tex_facing = facing_dir
	if _sprite == null or not ContentRegistry.is_ready():
		return
	var spec: Dictionary = _get_kirby_pose_spec(anim_key)
	var bank_id: int = int(spec.get("bank", Constants.CHR_BANK_KIRBY_DEFAULT))
	var l_col: Vector2i = spec.get("left", Vector2i(8, 9)) as Vector2i
	var r_col: Vector2i = spec.get("right", Vector2i(12, 13)) as Vector2i
	var flip_r: bool = bool(spec.get("flip_r", false))
	var tex: ImageTexture = ContentRegistry.build_rom_oam_8x16(
		bank_id,
		l_col,
		r_col,
		"kirby_default",
		false,
		flip_r,
		false,
		facing_dir
	)
	if tex != null:
		_sprite.texture = tex


func get_current_anim_key() -> String:
	return _current_anim_key


func get_anim_frame() -> int:
	return _anim_frame


func setup(level_map: LevelMap, spawn_pos: Vector2, preserve_status: bool = false) -> void:
	_level_map = level_map
	pos = spawn_pos
	position = pos
	vel = Vector2.ZERO
	facing_dir = 1
	state = State.IDLE
	on_ground = false
	in_water = false
	if not preserve_status:
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
	_ensure_ability_nodes()
	_deactivate_active_ability()
	if preserve_status and _abilities.has(copy_ability):
		_active_ability = _abilities[copy_ability] as AbilityBase
	else:
		copy_ability = Constants.CopyAbility.NONE
		_active_ability = null
	_ensure_visual_sprite()
	_sync_visual()


func _ensure_ability_nodes() -> void:
	if not _abilities.is_empty():
		return
	var list: Array[AbilityBase] = [
		AbilitySword.new(),
		AbilityFire.new(),
		AbilitySpark.new(),
		AbilityBeam.new(),
	]
	for ab: AbilityBase in list:
		ab.name = "Ability_%s" % ab.get_ability_name()
		add_child(ab)
		_abilities[ab.get_ability_id()] = ab


func equip_copy_ability(ability_id: int) -> void:
	_ensure_ability_nodes()
	_deactivate_active_ability()
	if _abilities.has(ability_id):
		copy_ability = ability_id
		_active_ability = _abilities[ability_id] as AbilityBase
	else:
		copy_ability = Constants.CopyAbility.NONE
		_active_ability = null
	EventBus.copy_ability_changed.emit(copy_ability)


func drop_copy_ability() -> bool:
	if copy_ability == Constants.CopyAbility.NONE:
		return false
	var dropped_ability: int = copy_ability
	_deactivate_active_ability()
	copy_ability = Constants.CopyAbility.NONE
	_active_ability = null
	if state == State.ABILITY_ATTACK:
		state = State.IDLE if on_ground else State.FALL
		state_frames = 0
	EventBus.copy_ability_changed.emit(copy_ability)
	_spawned_projectiles.append({
		"kind": "ability_star",
		"ability": dropped_ability,
		"pos": Vector2(pos.x, pos.y - 8.0),
		"vel": Vector2(float(-facing_dir) * 1.4, -2.5),
	})
	return true


func get_active_ability() -> AbilityBase:
	return _active_ability


func _deactivate_active_ability() -> void:
	if _active_ability != null and _active_ability.is_active():
		_active_ability.cancel_attack()


func get_collision_height() -> float:
	if state == State.CROUCH or state == State.SLIDE:
		return CROUCH_HEIGHT
	return STAND_HEIGHT


func get_body_rect() -> Rect2:
	var h: float = get_collision_height()
	return Rect2(pos.x - HALF_WIDTH, pos.y - h, HALF_WIDTH * 2.0, h)


func get_active_hitboxes() -> Array[Dictionary]:
	if state == State.ABILITY_ATTACK and _active_ability != null and _active_ability.is_active():
		return _active_ability.get_active_hitboxes()
	var single: Dictionary = get_active_hitbox()
	if bool(single.get("active", false)):
		return [single]
	return []


func get_active_hitbox() -> Dictionary:
	if state == State.ABILITY_ATTACK and _active_ability != null and _active_ability.is_active():
		var boxes: Array[Dictionary] = _active_ability.get_active_hitboxes()
		if not boxes.is_empty():
			return boxes[0]
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


func take_damage(amount: int = 1, knock_dir: int = -1, bypass_barrier: bool = false) -> bool:
	if invuln_frames > 0 or state == State.DEFEAT:
		return false
	if not bypass_barrier and state == State.ABILITY_ATTACK and _active_ability != null and _active_ability.is_blocking_contact():
		return false

	hp = maxi(0, hp - maxi(1, amount))
	EventBus.hp_changed.emit(hp, max_hp)

	# Drop active Copy Ability as a bouncing Ability Star on hit
	if copy_ability != Constants.CopyAbility.NONE:
		var dropped_ability: int = copy_ability
		_deactivate_active_ability()
		copy_ability = Constants.CopyAbility.NONE
		_active_ability = null
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
	_anim_frame += 1
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

	# SELECT drops active Copy Ability
	if InputManager.is_just_pressed(Constants.NesButton.SELECT) and copy_ability != Constants.CopyAbility.NONE and not has_cargo:
		drop_copy_ability()

	# Handle damage lock state
	if state == State.DAMAGE_KNOCKBACK:
		vel.y = minf(vel.y + GRAVITY, MAX_FALL_SPEED)
		_move_and_collide()
		if state_frames >= DAMAGE_LOCK_FRAMES:
			state = State.IDLE if on_ground else State.FALL
			state_frames = 0
		_sync_visual()
		return

	# Active Copy Ability attack step
	if state == State.ABILITY_ATTACK and _active_ability != null:
		if in_water:
			_deactivate_active_ability()
		else:
			_active_ability.step_attack(facing_dir, on_ground, _is_running, pos, b_pressed)
			if _active_ability.is_active():
				var impulse_vx: float = _active_ability.get_dash_impulse(facing_dir)
				if impulse_vx != 0.0:
					vel.x = impulse_vx
				elif on_ground and _active_ability.is_movement_locked():
					vel.x = move_toward(vel.x, 0.0, GROUND_DECEL)
				elif not on_ground:
					_apply_air_horizontal(move_dir)
				if not on_ground:
					vel.y = minf(vel.y + GRAVITY, MAX_FALL_SPEED)
				_process_ability_block_breaks()
				_move_and_collide()
				_check_hazards()
				_sync_visual()
				return
			else:
				state = State.IDLE if on_ground else State.FALL
				state_frames = 0

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
		elif b_just and _active_ability != null:
			_active_ability.start_attack(facing_dir, true, _is_running, pos)
			state = State.ABILITY_ATTACK
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
		elif b_just and _active_ability != null:
			_active_ability.start_attack(facing_dir, false, _is_running, pos)
			state = State.ABILITY_ATTACK
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
		equip_copy_ability(gained)
	state = State.IDLE
	state_frames = 0


func _process_ability_block_breaks() -> void:
	if _level_map == null or _active_ability == null or not _active_ability.is_active():
		return
	var boxes: Array[Dictionary] = _active_ability.get_active_hitboxes()
	for box: Dictionary in boxes:
		if not bool(box.get("active", false)) or not bool(box.get("breaks_blocks", false)):
			continue
		var rect: Rect2 = box["rect"] as Rect2
		var min_mx: int = int(floor(rect.position.x / float(Constants.METATILE_SIZE)))
		var max_mx: int = int(floor((rect.position.x + rect.size.x) / float(Constants.METATILE_SIZE)))
		var min_my: int = int(floor(rect.position.y / float(Constants.METATILE_SIZE)))
		var max_my: int = int(floor((rect.position.y + rect.size.y) / float(Constants.METATILE_SIZE)))
		for my: int in range(min_my, max_my + 1):
			for mx: int in range(min_mx, max_mx + 1):
				var col: int = _level_map.get_collision_at_tile(mx, my)
				if col == Constants.TileCollision.BREAKABLE_STAR or col == Constants.TileCollision.BOMB_BLOCK:
					_level_map.break_metatile_at(mx, my)


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
				var tile_top_y: float = float(check_my * Constants.METATILE_SIZE)
				var on_slope_ramp: bool = on_ground and LevelMap.is_slope_collision(
					_level_map.get_collision_at_pixel(int(roundf(pos.x - vel.x)), int(roundf(pos.y - 1.0)))
				) and not LevelMap.is_full_solid_collision(_level_map.get_collision_at_tile(mx, check_my - 1))
				var step_tol: float = HALF_WIDTH + 2.0 if on_slope_ramp else 2.0
				if on_ground and check_my == y_bot and pos.y - tile_top_y <= step_tol:
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
		var slope_center_y: float = _find_slope_center_surface_y(
			base_my - 1,
			base_my + 1,
			pos.y - SLOPE_UP_TOLERANCE,
			pos.y + SLOPE_DOWN_TOLERANCE,
			allow_one_way
		)
		var best_y: float = 1e9
		var found_support: bool = false
		if slope_center_y >= 0.0:
			best_y = slope_center_y
			found_support = true
		else:
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
			var slope_land_y: float = _find_slope_center_surface_y(
				min_my,
				max_my,
				prev_y - 2.0,
				pos.y,
				allow_one_way
			)
			var best_land_y: float = 1e9
			var landed: bool = false
			if slope_land_y >= 0.0:
				best_land_y = slope_land_y
				landed = true
			else:
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


func _find_slope_center_surface_y(min_my: int, max_my: int, min_y: float, max_y: float, allow_one_way: bool) -> float:
	var best_y: float = 1e9
	var cx: int = int(roundf(pos.x))
	var cmx: int = int(floor(float(cx) / float(Constants.METATILE_SIZE)))
	for check_my: int in range(min_my, max_my + 1):
		var col_type: int = _level_map.get_collision_at_tile(cmx, check_my)
		if not LevelMap.is_slope_collision(col_type):
			continue
		var surf: int = _level_map.get_floor_surface_y(cx, check_my, allow_one_way)
		if surf < 0:
			continue
		var surf_f: float = float(surf)
		if surf_f >= min_y and surf_f <= max_y and surf_f < best_y:
			best_y = surf_f
	return best_y if best_y < 1e8 else -1.0


func _check_hazards() -> void:
	if _level_map == null or invuln_frames > 0:
		return
	var cy: float = pos.y - get_collision_height() * 0.5
	if _level_map.is_hazard_at_pixel(int(pos.x), int(cy)) or _level_map.is_hazard_at_pixel(int(pos.x), int(pos.y - 1.0)):
		take_damage(1, -facing_dir)


func _sync_visual() -> void:
	position = Vector2(roundf(pos.x), roundf(pos.y))
	if _active_ability != null:
		_active_ability.position = Vector2.ZERO
		_active_ability.sync_visuals()
	var next_key: String = _resolve_anim_key()
	if next_key != _current_anim_key or facing_dir != _last_tex_facing or (_sprite != null and _sprite.texture == null):
		_apply_kirby_anim_texture(next_key)
	if _sprite != null:
		_sprite.flip_h = false
		if invuln_frames > 0:
			_sprite.visible = (invuln_frames % 4) < 2
		else:
			_sprite.visible = true
