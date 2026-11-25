class_name VirtualGamepad
extends CanvasLayer
## Cross-platform desktop & Android multi-touch NES controller overlay.
## Dynamically anchors controls to viewport margins clear of the centered 256x240 stage,
## auto-hides on physical keyboard/gamepad input, and re-shows on touch.

const Constants = preload("res://src/core/constants.gd")

var _root_control: Control = null
var _button_rects: Dictionary = {} # NesButton (int) -> Rect2
var _touch_fingers: Dictionary = {} # finger_index (int) -> NesButton (int)
var _overlay_visible: bool = false
var _last_viewport_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	name = "VirtualGamepad"
	layer = 20
	_build_overlay()
	var vp: Viewport = get_viewport()
	if vp != null:
		if not vp.size_changed.is_connected(_on_viewport_size_changed):
			vp.size_changed.connect(_on_viewport_size_changed)
		_on_viewport_size_changed()
	var is_touch_device: bool = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	set_overlay_visible(is_touch_device)


func _build_overlay() -> void:
	if _root_control != null:
		return
	_root_control = Control.new()
	_root_control.name = "TouchOverlayRoot"
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_control)
	var vp_size: Vector2 = Vector2(float(Constants.NATIVE_WIDTH), float(Constants.NATIVE_HEIGHT))
	var vp: Viewport = get_viewport()
	if vp != null:
		var vr: Rect2 = vp.get_visible_rect()
		if vr.size.x >= 256.0 and vr.size.y >= 240.0:
			vp_size = vr.size
	rebuild_for_viewport_size(vp_size)


func _on_viewport_size_changed() -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var vr: Rect2 = vp.get_visible_rect()
	if vr.size.x > 0.0 and vr.size.y > 0.0:
		rebuild_for_viewport_size(vr.size)


func rebuild_for_viewport_size(vp_size: Vector2) -> void:
	var w: float = maxf(256.0, vp_size.x)
	var h: float = maxf(240.0, vp_size.y)
	_last_viewport_size = Vector2(w, h)

	# D-Pad anchored to bottom-left margin centered around (38, h - 44)
	var dpad_center: Vector2 = Vector2(38.0, h - 44.0)
	var center_x: float = w * 0.5
	_button_rects = {
		Constants.NesButton.UP: Rect2(dpad_center + Vector2(-10.0, -30.0), Vector2(20.0, 20.0)),
		Constants.NesButton.DOWN: Rect2(dpad_center + Vector2(-10.0, 10.0), Vector2(20.0, 20.0)),
		Constants.NesButton.LEFT: Rect2(dpad_center + Vector2(-30.0, -10.0), Vector2(20.0, 20.0)),
		Constants.NesButton.RIGHT: Rect2(dpad_center + Vector2(10.0, -10.0), Vector2(20.0, 20.0)),
		Constants.NesButton.SELECT: Rect2(Vector2(center_x - 32.0, h - 20.0), Vector2(28.0, 14.0)),
		Constants.NesButton.START: Rect2(Vector2(center_x + 8.0, h - 20.0), Vector2(28.0, 14.0)),
		Constants.NesButton.B: Rect2(Vector2(w - 74.0, h - 42.0), Vector2(28.0, 28.0)),
		Constants.NesButton.A: Rect2(Vector2(w - 36.0, h - 54.0), Vector2(28.0, 28.0)),
	}
	_rebuild_visual_pads()


func get_last_viewport_size() -> Vector2:
	return _last_viewport_size


func set_overlay_visible(visible_flag: bool) -> void:
	_overlay_visible = visible_flag
	if _root_control != null:
		_root_control.visible = visible_flag
	if not visible_flag:
		clear_all_touches()


func is_overlay_visible() -> bool:
	return _overlay_visible


func get_button_rect(button: int) -> Rect2:
	if _button_rects.has(button):
		return _button_rects[button] as Rect2
	return Rect2()


func clear_all_touches() -> void:
	_touch_fingers.clear()
	InputManager.clear_touch_mask()


func _rebuild_visual_pads() -> void:
	if _root_control == null:
		return
	for child: Node in _root_control.get_children():
		_root_control.remove_child(child)
		child.free()

	var labels: Dictionary = {
		Constants.NesButton.UP: "U",
		Constants.NesButton.DOWN: "D",
		Constants.NesButton.LEFT: "L",
		Constants.NesButton.RIGHT: "R",
		Constants.NesButton.SELECT: "SEL",
		Constants.NesButton.START: "STA",
		Constants.NesButton.B: "B",
		Constants.NesButton.A: "A",
	}
	for btn_key: Variant in _button_rects.keys():
		var btn: int = int(btn_key)
		var rect: Rect2 = _button_rects[btn] as Rect2
		var pad: ColorRect = ColorRect.new()
		pad.position = rect.position
		pad.size = rect.size
		pad.color = Color(1.0, 0.72, 0.85, 0.28)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root_control.add_child(pad)

		var lbl: Label = Label.new()
		lbl.text = String(labels.get(btn, ""))
		lbl.position = Vector2.ZERO
		lbl.size = rect.size
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
		pad.add_child(lbl)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch_ev: InputEventScreenTouch = event as InputEventScreenTouch
		if touch_ev.pressed and not _overlay_visible:
			set_overlay_visible(true)
		if _overlay_visible:
			handle_touch_event(touch_ev)
	elif event is InputEventScreenDrag:
		if _overlay_visible:
			handle_drag_event(event as InputEventScreenDrag)
	elif event is InputEventKey:
		var key_ev: InputEventKey = event as InputEventKey
		if key_ev.pressed and not key_ev.echo and _overlay_visible:
			set_overlay_visible(false)
	elif event is InputEventJoypadButton:
		var pad_ev: InputEventJoypadButton = event as InputEventJoypadButton
		if pad_ev.pressed and _overlay_visible:
			set_overlay_visible(false)
	elif event is InputEventJoypadMotion:
		var mot_ev: InputEventJoypadMotion = event as InputEventJoypadMotion
		if absf(mot_ev.axis_value) > 0.35 and _overlay_visible:
			set_overlay_visible(false)


func handle_touch_event(ev: InputEventScreenTouch) -> void:
	if ev.pressed:
		var hit_btn: int = _find_button_at_point(ev.position)
		if hit_btn != 0:
			_touch_fingers[ev.index] = hit_btn
			_recompute_touch_mask()
	else:
		if _touch_fingers.has(ev.index):
			_touch_fingers.erase(ev.index)
			_recompute_touch_mask()


func handle_drag_event(ev: InputEventScreenDrag) -> void:
	var hit_btn: int = _find_button_at_point(ev.position)
	if hit_btn != 0:
		_touch_fingers[ev.index] = hit_btn
	elif _touch_fingers.has(ev.index):
		_touch_fingers.erase(ev.index)
	_recompute_touch_mask()


func _find_button_at_point(point: Vector2) -> int:
	for btn_key: Variant in _button_rects.keys():
		var btn: int = int(btn_key)
		var rect: Rect2 = _button_rects[btn] as Rect2
		if rect.has_point(point):
			return btn
	return 0


func _recompute_touch_mask() -> void:
	InputManager.clear_touch_mask()
	for finger_key: Variant in _touch_fingers.keys():
		var btn: int = int(_touch_fingers[finger_key])
		InputManager.set_touch_button(btn, true)
