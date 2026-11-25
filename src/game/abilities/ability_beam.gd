class_name AbilityBeam
extends "res://src/game/abilities/ability_base.gd"
## Beam Copy Ability: 5-orb curved energy whip sweeping overhead downward
## in front of Kirby, passing through thin walls.

const SWEEP_DURATION: int = 20
const ORB_COUNT: int = 5
const START_ANGLE_RAD: float = -1.309 # ~ -75 deg (overhead)
const END_ANGLE_RAD: float = 0.5236 # ~ +30 deg (low front)


func get_ability_id() -> int:
	return Constants.CopyAbility.BEAM


func get_ability_name() -> String:
	return "BEAM"


func start_attack(facing_dir: int, is_grounded: bool, is_running: bool, origin: Vector2) -> bool:
	return super.start_attack(facing_dir, is_grounded, is_running, origin)


func step_attack(_facing_dir: int, _is_grounded: bool, _is_running: bool, origin: Vector2, _b_held: bool) -> void:
	if not _active:
		return
	_origin = origin
	_frame += 1
	if _frame >= SWEEP_DURATION:
		cancel_attack()


func get_orb_positions() -> Array[Vector2]:
	var points: Array[Vector2] = []
	if not _active:
		return points
	var t: float = clampf(float(_frame) / float(maxi(1, SWEEP_DURATION - 1)), 0.0, 1.0)
	var base_angle: float = lerpf(START_ANGLE_RAD, END_ANGLE_RAD, t)
	var pivot: Vector2 = Vector2(_origin.x, _origin.y - 8.0)
	for i: int in range(ORB_COUNT):
		var radius: float = 10.0 + float(i) * 8.0
		# Slight whip lag curve on outer orbs
		var orb_angle: float = base_angle - float(i) * 0.08
		var dx: float = cos(orb_angle) * radius * float(_facing_dir)
		var dy: float = sin(orb_angle) * radius
		points.append(pivot + Vector2(dx, dy))
	return points


func get_active_hitboxes() -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	if not _active:
		return boxes
	var orbs: Array[Vector2] = get_orb_positions()
	for i: int in range(orbs.size()):
		var p: Vector2 = orbs[i]
		boxes.append({
			"active": true,
			"kind": "beam_orb",
			"ability": Constants.CopyAbility.BEAM,
			"orb_index": i,
			"damage": 1,
			"breaks_blocks": true,
			"passes_through_walls": true,
			"rect": Rect2(p.x - 4.0, p.y - 4.0, 8.0, 8.0),
		})
	return boxes


func _update_rom_visuals() -> void:
	_ensure_sprite_pool(ORB_COUNT)
	var tex: ImageTexture = _get_rom_tile_texture(
		Constants.CHR_BANK_ABILITY_EFFECTS,
		PackedInt32Array([12, 13]),
		1,
		2,
		"hud_sp_beam"
	)
	if tex == null:
		_hide_all_sprites()
		return
	var orbs: Array[Vector2] = get_orb_positions()
	for i: int in range(ORB_COUNT):
		var spr: Sprite2D = _sprites[i]
		if i < orbs.size():
			spr.texture = tex
			spr.position = orbs[i] - _origin
			spr.visible = true
		else:
			spr.visible = false
