class_name AbilityGeneric
extends "res://src/game/abilities/ability_base.gd"
## Data-driven 60 TPS Copy Ability implementation for World 1-7 abilities
## (Cutter, Ice, Freeze, Wheel, Stone, Hammer, Parasol, Needle, Tornado,
##  Hi-Jump, Ball, Fireball, Laser, Mike, Crash, Throw, Backdrop, Light, UFO, Sleep).

const ABILITY_SPECS: Dictionary = {
	Constants.CopyAbility.CUTTER: {"name": "CUTTER", "duration": 20, "range_x": 36.0, "half_h": 8.0, "damage": 2, "blocks": false, "dash": 0.0, "tiles": [0x00, 0x01, 0x10, 0x11], "palette": "hud_sp_star"},
	Constants.CopyAbility.ICE: {"name": "ICE", "duration": 24, "range_x": 28.0, "half_h": 10.0, "damage": 2, "blocks": false, "dash": 0.0, "tiles": [0x02, 0x03, 0x12, 0x13], "palette": "hud_sp_beam"},
	Constants.CopyAbility.FREEZE: {"name": "FREEZE", "duration": 22, "range_x": 0.0, "half_h": 18.0, "damage": 2, "blocks": true, "dash": 0.0, "tiles": [0x04, 0x05, 0x14, 0x15], "palette": "hud_sp_beam"},
	Constants.CopyAbility.WHEEL: {"name": "WHEEL", "duration": 36, "range_x": 12.0, "half_h": 10.0, "damage": 2, "blocks": true, "dash": 3.2, "tiles": [0x06, 0x07, 0x16, 0x17], "palette": "hud_sp_fire"},
	Constants.CopyAbility.STONE: {"name": "STONE", "duration": 36, "range_x": 0.0, "half_h": 12.0, "damage": 3, "blocks": true, "dash": 0.0, "tiles": [0x08, 0x09, 0x18, 0x19], "palette": "hud_sp_star"},
	Constants.CopyAbility.HAMMER: {"name": "HAMMER", "duration": 18, "range_x": 22.0, "half_h": 12.0, "damage": 4, "blocks": false, "dash": 0.0, "tiles": [0x0A, 0x0B, 0x1A, 0x1B], "palette": "hud_sp_fire"},
	Constants.CopyAbility.PARASOL: {"name": "PARASOL", "duration": 20, "range_x": 20.0, "half_h": 12.0, "damage": 2, "blocks": true, "dash": 0.0, "tiles": [0x0C, 0x0D, 0x1C, 0x1D], "palette": "hud_sp_fire"},
	Constants.CopyAbility.NEEDLE: {"name": "NEEDLE", "duration": 24, "range_x": 0.0, "half_h": 16.0, "damage": 2, "blocks": true, "dash": 0.0, "tiles": [0x0E, 0x0F, 0x1E, 0x1F], "palette": "hud_sp_star"},
	Constants.CopyAbility.TORNADO: {"name": "TORNADO", "duration": 32, "range_x": 0.0, "half_h": 16.0, "damage": 2, "blocks": true, "dash": 2.4, "tiles": [0x20, 0x21, 0x30, 0x31], "palette": "hud_sp_beam"},
	Constants.CopyAbility.HI_JUMP: {"name": "HI-JUMP", "duration": 22, "range_x": 0.0, "half_h": 16.0, "damage": 2, "blocks": true, "dash": 0.0, "tiles": [0x22, 0x23, 0x32, 0x33], "palette": "hud_sp_fire"},
	Constants.CopyAbility.BALL: {"name": "BALL", "duration": 28, "range_x": 0.0, "half_h": 12.0, "damage": 2, "blocks": true, "dash": 2.6, "tiles": [0x24, 0x25, 0x34, 0x35], "palette": "hud_sp_star"},
	Constants.CopyAbility.FIREBALL: {"name": "FIREBALL", "duration": 24, "range_x": 10.0, "half_h": 10.0, "damage": 2, "blocks": true, "dash": 3.0, "tiles": [0x26, 0x27, 0x36, 0x37], "palette": "hud_sp_fire"},
	Constants.CopyAbility.LASER: {"name": "LASER", "duration": 18, "range_x": 48.0, "half_h": 6.0, "damage": 2, "blocks": false, "dash": 0.0, "tiles": [0x28, 0x29, 0x38, 0x39], "palette": "hud_sp_beam"},
	Constants.CopyAbility.MIKE: {"name": "MIKE", "duration": 30, "range_x": 64.0, "half_h": 48.0, "damage": 5, "blocks": true, "dash": 0.0, "tiles": [0x2A, 0x2B, 0x3A, 0x3B], "palette": "hud_sp_fire"},
	Constants.CopyAbility.CRASH: {"name": "CRASH", "duration": 34, "range_x": 96.0, "half_h": 64.0, "damage": 8, "blocks": true, "dash": 0.0, "tiles": [0x2C, 0x2D, 0x3C, 0x3D], "palette": "hud_sp_fire"},
	Constants.CopyAbility.THROW: {"name": "THROW", "duration": 20, "range_x": 28.0, "half_h": 10.0, "damage": 3, "blocks": false, "dash": 0.0, "tiles": [0x2E, 0x2F, 0x3E, 0x3F], "palette": "hud_sp_star"},
	Constants.CopyAbility.BACKDROP: {"name": "BACKDROP", "duration": 22, "range_x": 22.0, "half_h": 12.0, "damage": 3, "blocks": true, "dash": 0.0, "tiles": [0x00, 0x02, 0x10, 0x12], "palette": "hud_sp_star"},
	Constants.CopyAbility.LIGHT: {"name": "LIGHT", "duration": 20, "range_x": 40.0, "half_h": 32.0, "damage": 1, "blocks": false, "dash": 0.0, "tiles": [0x04, 0x06, 0x14, 0x16], "palette": "hud_sp_star"},
	Constants.CopyAbility.UFO: {"name": "UFO", "duration": 18, "range_x": 40.0, "half_h": 8.0, "damage": 3, "blocks": false, "dash": 1.2, "tiles": [0x08, 0x0A, 0x18, 0x1A], "palette": "hud_sp_beam"},
	Constants.CopyAbility.SLEEP: {"name": "SLEEP", "duration": 45, "range_x": 0.0, "half_h": 0.0, "damage": 0, "blocks": false, "dash": 0.0, "tiles": [0x0C, 0x0E, 0x1C, 0x1E], "palette": "kirby_default"},
}

var _ability_id: int = Constants.CopyAbility.CUTTER


func configure_ability(ability_id: int) -> void:
	_ability_id = ability_id


func _get_spec() -> Dictionary:
	if ABILITY_SPECS.has(_ability_id):
		return ABILITY_SPECS[_ability_id] as Dictionary
	return ABILITY_SPECS[Constants.CopyAbility.CUTTER] as Dictionary


func get_ability_id() -> int:
	return _ability_id


func get_ability_name() -> String:
	return String(_get_spec().get("name", "ABILITY"))


func is_blocking_contact() -> bool:
	return _active and bool(_get_spec().get("blocks", false))


func get_dash_impulse(facing_dir: int) -> float:
	var spd: float = float(_get_spec().get("dash", 0.0))
	if spd <= 0.0:
		return 0.0
	var dir: int = 1 if facing_dir >= 0 else -1
	return float(dir) * spd


func start_attack(facing_dir: int, is_grounded: bool, is_running: bool, origin: Vector2) -> bool:
	super.start_attack(facing_dir, is_grounded, is_running, origin)
	return true


func step_attack(facing_dir: int, is_grounded: bool, is_running: bool, origin: Vector2, _b_held: bool) -> void:
	if not _active:
		return
	super.step_attack(facing_dir, is_grounded, is_running, origin, _b_held)
	var duration: int = int(_get_spec().get("duration", 20))
	if _frame >= duration:
		cancel_attack()


func get_active_hitboxes() -> Array[Dictionary]:
	if not _active:
		return []
	var spec: Dictionary = _get_spec()
	var dmg: int = int(spec.get("damage", 2))
	if dmg <= 0:
		return []
	var range_x: float = float(spec.get("range_x", 24.0))
	var half_h: float = float(spec.get("half_h", 10.0))
	var center_x: float = _origin.x + (float(_facing_dir) * (range_x * 0.5) if range_x > 0.0 else 0.0)
	var half_w: float = maxf(12.0, range_x * 0.5)
	return [{
		"rect": Rect2(center_x - half_w, _origin.y - 8.0 - half_h, half_w * 2.0, half_h * 2.0),
		"damage": dmg,
		"breaks_blocks": true,
		"source": get_ability_name().to_lower(),
	}]


func _update_rom_visuals() -> void:
	var spec: Dictionary = _get_spec()
	var offset_x: float = float(_facing_dir) * minf(16.0, float(spec.get("range_x", 24.0)) * 0.5)
	if ContentRegistry.is_ready():
		var eff_key: String = "air_puff" if _ability_id in [Constants.CopyAbility.TORNADO, Constants.CopyAbility.ICE, Constants.CopyAbility.FREEZE] else "star"
		var eff_spec: Dictionary = ContentRegistry.get_effect_metasprite_frame(eff_key, _frame & 1)
		if eff_spec.is_empty():
			eff_spec = ContentRegistry.get_effect_metasprite_frame("star", 0)
		if not eff_spec.is_empty():
			var pals: Array[PackedColorArray] = ContentRegistry.get_room_sprite_palettes(-1)
			var built: Dictionary = ContentRegistry.build_rom_metasprite(
				eff_spec,
				pals,
				Constants.CHR_BANK_ABILITY_EFFECTS,
				154,
				Constants.CHR_BANK_STAR_EFFECTS
			)
			if not built.is_empty():
				_ensure_sprite_pool(1)
				var spr_rom: Sprite2D = _sprites[0]
				spr_rom.texture = built["texture"] as ImageTexture
				spr_rom.flip_h = _facing_dir < 0
				spr_rom.position = _origin + Vector2(offset_x, -12.0)
				spr_rom.visible = true
				return

	var raw_tiles: Array = spec.get("tiles", [0x00, 0x01, 0x10, 0x11]) as Array
	var tile_ids: PackedInt32Array = PackedInt32Array()
	for t_var: Variant in raw_tiles:
		tile_ids.append(int(t_var))
	var tex: ImageTexture = _get_rom_tile_texture(
		Constants.CHR_BANK_ABILITY_EFFECTS,
		tile_ids,
		2,
		2,
		String(spec.get("palette", "hud_sp_star"))
	)
	if tex == null:
		_hide_all_sprites()
		return
	_ensure_sprite_pool(1)
	var spr: Sprite2D = _sprites[0]
	spr.texture = tex
	spr.flip_h = _facing_dir < 0
	spr.position = _origin + Vector2(offset_x, -8.0)
	spr.visible = true
