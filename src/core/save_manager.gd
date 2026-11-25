class_name SaveManager
extends RefCounted
## 3-Slot Persistent Progression Save Manager (user://save_data.json).
## Tracks unlocked Worlds (1..7), cleared Worlds/Bosses, lives, score, and completion %.

const Constants = preload("res://src/core/constants.gd")

const SLOT_COUNT: int = 3
const MAX_WORLDS: int = 7


static func create_empty_slot(slot_idx: int) -> Dictionary:
	return {
		"slot": clampi(slot_idx, 0, SLOT_COUNT - 1),
		"occupied": false,
		"unlocked_world": 1,
		"cleared_worlds": [],
		"lives": 4,
		"score": 0,
		"copy_ability": Constants.CopyAbility.NONE,
		"percent": 0,
	}


static func load_all_slots(save_path: String = Constants.SAVE_DATA_PATH) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for i: int in range(SLOT_COUNT):
		slots.append(create_empty_slot(i))

	if not FileAccess.file_exists(save_path):
		return slots

	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return slots
	var raw_text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return slots
	var root: Dictionary = parsed as Dictionary
	var raw_slots: Variant = root.get("slots", [])
	if typeof(raw_slots) != TYPE_ARRAY:
		return slots

	var arr: Array = raw_slots as Array
	for i: int in range(mini(SLOT_COUNT, arr.size())):
		if typeof(arr[i]) == TYPE_DICTIONARY:
			var src: Dictionary = arr[i] as Dictionary
			var cleared: Array[int] = []
			var raw_cl: Variant = src.get("cleared_worlds", [])
			if typeof(raw_cl) == TYPE_ARRAY:
				for w_var: Variant in (raw_cl as Array):
					var w: int = int(w_var)
					if w >= 1 and w <= MAX_WORLDS and not cleared.has(w):
						cleared.append(w)
			cleared.sort()
			slots[i] = {
				"slot": i,
				"occupied": bool(src.get("occupied", false)),
				"unlocked_world": clampi(int(src.get("unlocked_world", 1)), 1, MAX_WORLDS),
				"cleared_worlds": cleared,
				"lives": clampi(int(src.get("lives", 4)), 1, 99),
				"score": maxi(0, int(src.get("score", 0))),
				"copy_ability": int(src.get("copy_ability", Constants.CopyAbility.NONE)),
				"percent": clampi(int(roundf((float(cleared.size()) / float(MAX_WORLDS)) * 100.0)), 0, 100),
			}
	return slots


static func save_all_slots(slots: Array[Dictionary], save_path: String = Constants.SAVE_DATA_PATH) -> bool:
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	var payload: Dictionary = {
		"version": 1,
		"slots": slots,
	}
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


static func record_world_clear(
	slot_idx: int,
	world_num: int,
	score: int,
	lives: int,
	ability: int,
	save_path: String = Constants.SAVE_DATA_PATH
) -> Dictionary:
	var idx: int = clampi(slot_idx, 0, SLOT_COUNT - 1)
	var slots: Array[Dictionary] = load_all_slots(save_path)
	var slot: Dictionary = slots[idx]
	slot["occupied"] = true
	var cleared: Array = slot.get("cleared_worlds", []) as Array
	if world_num >= 1 and world_num <= MAX_WORLDS and not cleared.has(world_num):
		cleared.append(world_num)
	cleared.sort()
	slot["cleared_worlds"] = cleared
	slot["unlocked_world"] = clampi(maxi(int(slot.get("unlocked_world", 1)), world_num + 1), 1, MAX_WORLDS)
	slot["score"] = maxi(0, score)
	slot["lives"] = clampi(lives, 1, 99)
	slot["copy_ability"] = ability
	slot["percent"] = clampi(int(roundf((float(cleared.size()) / float(MAX_WORLDS)) * 100.0)), 0, 100)
	slots[idx] = slot
	save_all_slots(slots, save_path)
	return slot


static func erase_slot(slot_idx: int, save_path: String = Constants.SAVE_DATA_PATH) -> bool:
	var idx: int = clampi(slot_idx, 0, SLOT_COUNT - 1)
	var slots: Array[Dictionary] = load_all_slots(save_path)
	slots[idx] = create_empty_slot(idx)
	return save_all_slots(slots, save_path)
