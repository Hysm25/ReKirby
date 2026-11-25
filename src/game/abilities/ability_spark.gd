class_name AbilitySpark
extends "res://src/game/abilities/ability_base.gd"
## Spark Copy Ability: 360-degree crackling electric barrier surrounding Kirby
## that damages adjacent enemies and protects against contact hits.

const MIN_SPARK_FRAMES: int = 12
const MAX_SPARK_FRAMES: int = 180
const BARRIER_RADIUS_X: float = 20.0
const BARRIER_RADIUS_Y: float = 20.0


func get_ability_id() -> int:
	return Constants.CopyAbility.SPARK


func get_ability_name() -> String:
	return "SPARK"


func is_blocking_contact() -> bool:
	return _active


func start_attack(facing_dir: int, is_grounded: bool, is_running: bool, origin: Vector2) -> bool:
	return super.start_attack(facing_dir, is_grounded, is_running, origin)


func step_attack(facing_dir: int, _is_grounded: bool, _is_running: bool, origin: Vector2, b_held: bool) -> void:
	if not _active:
		return
	_facing_dir = 1 if facing_dir >= 0 else -1
	_origin = origin
	_frame += 1
	if (_frame >= MIN_SPARK_FRAMES and not b_held) or _frame >= MAX_SPARK_FRAMES:
		cancel_attack()


func get_active_hitboxes() -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	if not _active:
		return boxes
	boxes.append({
		"active": true,
		"kind": "spark_barrier",
		"ability": Constants.CopyAbility.SPARK,
		"damage": 1,
		"breaks_blocks": true,
		"passes_through_walls": false,
		"rect": Rect2(
			_origin.x - BARRIER_RADIUS_X,
			_origin.y - 8.0 - BARRIER_RADIUS_Y,
			BARRIER_RADIUS_X * 2.0,
			BARRIER_RADIUS_Y * 2.0
		),
	})
	return boxes


func _update_rom_visuals() -> void:
	_ensure_sprite_pool(4)
	var tex: ImageTexture = _get_rom_tile_texture(
		Constants.CHR_BANK_STAR_EFFECTS,
		PackedInt32Array([4, 5]),
		1,
		2,
		"hud_sp_star"
	)
	if tex == null:
		_hide_all_sprites()
		return
	for i: int in range(4):
		var spr: Sprite2D = _sprites[i]
		var angle: float = float(i) * (PI * 0.5) + float(_frame) * 0.45
		spr.texture = tex
		spr.position = Vector2(cos(angle) * 14.0, -8.0 + sin(angle) * 14.0)
		spr.visible = ((_frame + i) % 2) == 0
