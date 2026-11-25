extends Node
## Centralized 60 TPS NES controller input manager for keyboard, gamepad, and touch bitmasks.

const Constants = preload("res://src/core/constants.gd")

const ACTION_A: String = "nes_a"
const ACTION_B: String = "nes_b"
const ACTION_SELECT: String = "nes_select"
const ACTION_START: String = "nes_start"
const ACTION_UP: String = "nes_up"
const ACTION_DOWN: String = "nes_down"
const ACTION_LEFT: String = "nes_left"
const ACTION_RIGHT: String = "nes_right"

var _current_mask: int = 0
var _previous_mask: int = 0
var _touch_mask: int = 0
var _use_mock: bool = false
var _mock_mask: int = 0


func _ready() -> void:
	_ensure_default_input_map()


func _ensure_default_input_map() -> void:
	_register_key_action(ACTION_RIGHT, [KEY_RIGHT, KEY_D])
	_register_key_action(ACTION_LEFT, [KEY_LEFT, KEY_A])
	_register_key_action(ACTION_DOWN, [KEY_DOWN, KEY_S])
	_register_key_action(ACTION_UP, [KEY_UP, KEY_W])
	_register_key_action(ACTION_START, [KEY_ENTER, KEY_KP_ENTER])
	_register_key_action(ACTION_SELECT, [KEY_SHIFT, KEY_BACKSPACE])
	_register_key_action(ACTION_B, [KEY_Z, KEY_J])
	_register_key_action(ACTION_A, [KEY_X, KEY_K, KEY_SPACE])

	_register_joy_button(ACTION_RIGHT, JOY_BUTTON_DPAD_RIGHT)
	_register_joy_button(ACTION_LEFT, JOY_BUTTON_DPAD_LEFT)
	_register_joy_button(ACTION_DOWN, JOY_BUTTON_DPAD_DOWN)
	_register_joy_button(ACTION_UP, JOY_BUTTON_DPAD_UP)
	_register_joy_button(ACTION_START, JOY_BUTTON_START)
	_register_joy_button(ACTION_SELECT, JOY_BUTTON_BACK)
	_register_joy_button(ACTION_B, JOY_BUTTON_X)
	_register_joy_button(ACTION_A, JOY_BUTTON_A)


func _register_key_action(action_name: String, keys: Array[int]) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for key_code: int in keys:
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = key_code as Key
		if not InputMap.action_has_event(action_name, ev):
			InputMap.action_add_event(action_name, ev)


func _register_joy_button(action_name: String, joy_btn: JoyButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var ev: InputEventJoypadButton = InputEventJoypadButton.new()
	ev.button_index = joy_btn
	if not InputMap.action_has_event(action_name, ev):
		InputMap.action_add_event(action_name, ev)


func step_frame() -> void:
	_previous_mask = _current_mask
	if _use_mock:
		_current_mask = _apply_socd_neutral(_mock_mask)
		return
	if not InputMap.has_action(ACTION_RIGHT):
		_ensure_default_input_map()

	var mask: int = _touch_mask
	if Input.is_action_pressed(ACTION_RIGHT):
		mask |= Constants.NesButton.RIGHT
	if Input.is_action_pressed(ACTION_LEFT):
		mask |= Constants.NesButton.LEFT
	if Input.is_action_pressed(ACTION_DOWN):
		mask |= Constants.NesButton.DOWN
	if Input.is_action_pressed(ACTION_UP):
		mask |= Constants.NesButton.UP
	if Input.is_action_pressed(ACTION_START):
		mask |= Constants.NesButton.START
	if Input.is_action_pressed(ACTION_SELECT):
		mask |= Constants.NesButton.SELECT
	if Input.is_action_pressed(ACTION_B):
		mask |= Constants.NesButton.B
	if Input.is_action_pressed(ACTION_A):
		mask |= Constants.NesButton.A

	_current_mask = _apply_socd_neutral(mask)


func _apply_socd_neutral(mask: int) -> int:
	var cleaned: int = mask
	var lr: int = Constants.NesButton.LEFT | Constants.NesButton.RIGHT
	if (cleaned & lr) == lr:
		cleaned &= ~lr
	var ud: int = Constants.NesButton.UP | Constants.NesButton.DOWN
	if (cleaned & ud) == ud:
		cleaned &= ~ud
	return cleaned


func is_pressed(button: int) -> bool:
	return (_current_mask & button) != 0


func is_just_pressed(button: int) -> bool:
	return (_current_mask & button) != 0 and (_previous_mask & button) == 0


func is_just_released(button: int) -> bool:
	return (_current_mask & button) == 0 and (_previous_mask & button) != 0


func get_button_mask() -> int:
	return _current_mask


func set_touch_button(button: int, down: bool) -> void:
	if down:
		_touch_mask |= button
	else:
		_touch_mask &= ~button


func clear_touch_mask() -> void:
	_touch_mask = 0


func set_mock_mask(mask: int) -> void:
	_use_mock = true
	_mock_mask = mask


func clear_mock_mask() -> void:
	_use_mock = false
	_mock_mask = 0
	_current_mask = 0
	_previous_mask = 0
