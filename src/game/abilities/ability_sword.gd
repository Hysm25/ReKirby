class_name AbilitySword
extends "res://src/game/abilities/ability_base.gd"
## Sword Copy Ability: standing forward slash, midair 360-degree spin slash,
## and running dash slash. Cuts ropes/bushes and breaks star blocks.

enum Mode {
	SLASH = 0,
	AIR_SPIN = 1,
	DASH_SLASH = 2,
}

const SLASH_DURATION: int = 12
const AIR_SPIN_DURATION: int = 16
const DASH_SLASH_DURATION: int = 14
const DASH_IMPULSE_SPEED: float = 2.8

var _mode: int = Mode.SLASH


func get_ability_id() -> int:
	return Constants.CopyAbility.SWORD


func get_ability_name() -> String:
	return "SWORD"


func get_mode() -> int:
	return _mode


func is_movement_locked() -> bool:
	return _active and _mode == Mode.SLASH


func get_dash_impulse(facing_dir: int) -> float:
	if _active and _mode == Mode.DASH_SLASH and _frame <= 8:
		return float(1 if facing_dir >= 0 else -1) * DASH_IMPULSE_SPEED
	return 0.0


func start_attack(facing_dir: int, is_grounded: bool, is_running: bool, origin: Vector2) -> bool:
	super.start_attack(facing_dir, is_grounded, is_running, origin)
	if not is_grounded:
		_mode = Mode.AIR_SPIN
	elif is_running:
		_mode = Mode.DASH_SLASH
	else:
		_mode = Mode.SLASH
	return true


func step_attack(facing_dir: int, _is_grounded: bool, _is_running: bool, origin: Vector2, _b_held: bool) -> void:
	if not _active:
		return
	# Keep facing locked for slash/dash, but update origin cleanly
	_origin = origin
	if _mode == Mode.AIR_SPIN:
		_facing_dir = 1 if facing_dir >= 0 else -1
	_frame += 1

	var max_len: int = SLASH_DURATION
	if _mode == Mode.AIR_SPIN:
		max_len = AIR_SPIN_DURATION
	elif _mode == Mode.DASH_SLASH:
		max_len = DASH_SLASH_DURATION
	if _frame >= max_len:
		cancel_attack()


func get_active_hitboxes() -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	if not _active:
		return boxes
	if _mode == Mode.SLASH:
		var rx: float = _origin.x + 2.0 if _facing_dir > 0 else _origin.x - 30.0
		boxes.append({
			"active": true,
			"kind": "sword_slash",
			"ability": Constants.CopyAbility.SWORD,
			"damage": 2,
			"breaks_blocks": true,
			"passes_through_walls": false,
			"rect": Rect2(rx, _origin.y - 20.0, 28.0, 20.0),
		})
	elif _mode == Mode.AIR_SPIN:
		boxes.append({
			"active": true,
			"kind": "sword_air_spin",
			"ability": Constants.CopyAbility.SWORD,
			"damage": 2,
			"breaks_blocks": true,
			"passes_through_walls": false,
			"rect": Rect2(_origin.x - 18.0, _origin.y - 22.0, 36.0, 28.0),
		})
	else:
		var dx: float = _origin.x + 4.0 if _facing_dir > 0 else _origin.x - 36.0
		boxes.append({
			"active": true,
			"kind": "sword_dash",
			"ability": Constants.CopyAbility.SWORD,
			"damage": 3,
			"breaks_blocks": true,
			"passes_through_walls": false,
			"rect": Rect2(dx, _origin.y - 18.0, 32.0, 18.0),
		})
	return boxes


func _update_rom_visuals() -> void:
	_ensure_sprite_pool(1)
	var tex: ImageTexture = _get_rom_tile_texture(
		Constants.CHR_BANK_ABILITY_EFFECTS,
		PackedInt32Array([2, 3]),
		1,
		2,
		"hud_sp_star"
	)
	var spr: Sprite2D = _sprites[0]
	if tex == null:
		spr.visible = false
		return
	spr.texture = tex
	spr.visible = true
	spr.flip_h = _facing_dir < 0
	if _mode == Mode.AIR_SPIN:
		var side: float = 12.0 if (_frame % 4) < 2 else -12.0
		spr.flip_h = side < 0.0
		spr.position = Vector2(side, -8.0)
	else:
		spr.position = Vector2(float(_facing_dir) * 16.0, -10.0)
