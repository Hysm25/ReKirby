class_name AbilityFire
extends "res://src/game/abilities/ability_base.gd"
## Fire Copy Ability: continuous forward flame jet stream while B is held.

const MIN_FLAME_FRAMES: int = 12
const MAX_FLAME_FRAMES: int = 180


func get_ability_id() -> int:
	return Constants.CopyAbility.FIRE


func get_ability_name() -> String:
	return "FIRE"


func start_attack(facing_dir: int, is_grounded: bool, is_running: bool, origin: Vector2) -> bool:
	return super.start_attack(facing_dir, is_grounded, is_running, origin)


func step_attack(facing_dir: int, _is_grounded: bool, _is_running: bool, origin: Vector2, b_held: bool) -> void:
	if not _active:
		return
	_facing_dir = 1 if facing_dir >= 0 else -1
	_origin = origin
	_frame += 1
	if (_frame >= MIN_FLAME_FRAMES and not b_held) or _frame >= MAX_FLAME_FRAMES:
		cancel_attack()


func get_active_hitboxes() -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	if not _active:
		return boxes
	var reach: float = 28.0 if _frame < 4 else 44.0
	var rx: float = _origin.x + 6.0 if _facing_dir > 0 else _origin.x - (6.0 + reach)
	boxes.append({
		"active": true,
		"kind": "fire_stream",
		"ability": Constants.CopyAbility.FIRE,
		"damage": 1,
		"breaks_blocks": true,
		"ignites": true,
		"passes_through_walls": false,
		"rect": Rect2(rx, _origin.y - 16.0, reach, 16.0),
	})
	return boxes


func _update_rom_visuals() -> void:
	_ensure_sprite_pool(3)
	var frame_pair: int = 4 if ((_frame / 3) % 2) == 0 else 6
	var tex: ImageTexture = _get_rom_tile_texture(
		Constants.CHR_BANK_ABILITY_EFFECTS,
		PackedInt32Array([frame_pair, frame_pair + 1]),
		1,
		2,
		"hud_sp_fire"
	)
	if tex == null:
		_hide_all_sprites()
		return
	for i: int in range(3):
		var spr: Sprite2D = _sprites[i]
		spr.texture = tex
		spr.flip_h = _facing_dir < 0
		var dist: float = 12.0 + float(i) * 12.0
		var bob: float = -8.0 + float(((i + _frame) % 3) - 1)
		spr.position = Vector2(float(_facing_dir) * dist, bob)
		spr.visible = true
