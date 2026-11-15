class_name HandFan
extends Control

signal card_scrubbed(index: int, card_data: Dictionary)
signal card_selected(card_id: int, card_data: Dictionary)
signal card_swipe_played(card_id: int, global_origin: Vector2)
signal illegal_swipe_attempted(card_id: int, global_origin: Vector2)
signal drag_state_changed(dragging: bool, ready_to_play: bool, legal: bool)

const CARD_W := 124.0
const CARD_H := 178.0
const SWIPE_LOCK_DY := 22.0
const SWIPE_PLAY_DY := 155.0
const RUNE_DROP_RADIUS := 175.0
const FLICK_MIN_VY := 680.0
const FLICK_MIN_DY := 38.0

var _cards: Array = []
var _legal_ids := {}
var _interactive := false
var _selected_card_id := -1

var _views: Array[CardView] = []
var _curr_pos: Array[Vector2] = []
var _curr_rot: Array[float] = []
var _curr_scale: Array[float] = []
var _shake_x: Array[float] = []

var _focus_idx := -1
var _pointer_down := false
var _press_pos := Vector2.ZERO
var _scrub_anchor_y := 0.0
var _last_pointer_pos := Vector2.ZERO
var _last_motion_us := 0
var _peak_vy_up := 0.0
var _drag_locked_idx := -1
var _drag_lift_y := 0.0
var _drag_offset_x := 0.0
var _rune_target_global := Vector2(360.0, 480.0)
var _has_rune_target := false
var _deal_anim_timer := 0.0

func set_rune_target_global(pos: Vector2) -> void:
	_rune_target_global = pos
	_has_rune_target = true

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	custom_minimum_size = Vector2(0, 224)

func set_hand(cards: Array, legal_ids: Array, interactive: bool, selected_id: int = -1, animate_deal: bool = false) -> void:
	_legal_ids.clear()
	for lid in legal_ids:
		_legal_ids[int(lid)] = true
	_interactive = interactive
	_selected_card_id = selected_id

	var old_count := _cards.size()
	_cards = cards.duplicate()

	if _cards.size() != old_count:
		_focus_idx = -1
		_drag_locked_idx = -1
		_pointer_down = false
		_drag_lift_y = 0.0

	# Rebuild CardView children if count changed
	if _views.size() != _cards.size():
		for v in _views:
			v.queue_free()
		_views.clear()
		_curr_pos.clear()
		_curr_rot.clear()
		_curr_scale.clear()
		_shake_x.clear()
		for i in range(_cards.size()):
			var cv := CardView.new()
			add_child(cv)
			_views.append(cv)
			var start_x := (size.x * 0.5 - CARD_W * 0.5) if size.x > 40.0 else 280.0
			_curr_pos.append(Vector2(start_x, 80.0 if animate_deal else 32.0))
			_curr_rot.append(0.0)
			_curr_scale.append(0.75 if animate_deal else 1.0)
			_shake_x.append(0.0)
		if animate_deal:
			_deal_anim_timer = 0.25

	for i in range(_cards.size()):
		var c: Dictionary = _cards[i]
		var cid := int(c.get("id", -1))
		var is_playable := (not _interactive) or _legal_ids.has(cid)
		var is_sel := (_selected_card_id != -1 and cid == _selected_card_id)
		_views[i].setup(c, is_playable, is_sel, _interactive, false, true)
		_views[i].size = Vector2(CARD_W, CARD_H)
		_views[i].pivot_offset = Vector2(CARD_W * 0.5, CARD_H * 0.5)

	_snap_if_idle()

func _snap_if_idle() -> void:
	if _cards.is_empty():
		return
	if _deal_anim_timer <= 0.0 and not _pointer_down:
		for i in range(_cards.size()):
			var target := _compute_card_target(i)
			_curr_pos[i] = target["pos"]
			_curr_rot[i] = target["rot"]
			_curr_scale[i] = target["scale"]
			_apply_view_transform(i)

func _process(delta: float) -> void:
	if _deal_anim_timer > 0.0:
		_deal_anim_timer = maxf(0.0, _deal_anim_timer - delta)
	var speed := clampf(delta * 18.0, 0.0, 1.0)
	for i in range(_views.size()):
		var target := _compute_card_target(i)
		_curr_pos[i] = _curr_pos[i].lerp(target["pos"], speed)
		_curr_rot[i] = lerpf(_curr_rot[i], target["rot"], speed)
		_curr_scale[i] = lerpf(_curr_scale[i], target["scale"], speed)
		_shake_x[i] = lerpf(_shake_x[i], 0.0, clampf(delta * 14.0, 0.0, 1.0))
		_apply_view_transform(i)

func _apply_view_transform(i: int) -> void:
	var v: CardView = _views[i]
	v.position = _curr_pos[i] + Vector2(_shake_x[i], 0.0)
	v.rotation_degrees = _curr_rot[i]
	v.scale = Vector2(_curr_scale[i], _curr_scale[i])
	if i == _drag_locked_idx:
		v.z_index = 120
	elif i == _focus_idx:
		v.z_index = 80
	elif _selected_card_id != -1 and int(_cards[i].get("id", -1)) == _selected_card_id:
		v.z_index = 60
	else:
		v.z_index = i

func _get_active_focus_index() -> int:
	if _drag_locked_idx >= 0 and _drag_locked_idx < _cards.size():
		return _drag_locked_idx
	if _focus_idx >= 0 and _focus_idx < _cards.size():
		return _focus_idx
	if _selected_card_id != -1:
		for i in range(_cards.size()):
			if int(_cards[i].get("id", -1)) == _selected_card_id:
				return i
	return -1

func _fan_metrics() -> Dictionary:
	var n := _cards.size()
	var w := size.x if size.x > 60.0 else 680.0
	var avail_w := maxf(240.0, w - 24.0)
	var step := 0.0
	if n > 1:
		step = clampf((avail_w - CARD_W) / float(n - 1), 16.0, 92.0)
	var total_span := CARD_W + step * float(maxi(0, n - 1))
	var start_x := (w - total_span) * 0.5
	return {"w": w, "step": step, "start_x": start_x, "n": n}

func _compute_card_target(i: int) -> Dictionary:
	var m := _fan_metrics()
	var n: int = m["n"]
	var w: float = m["w"]
	var step: float = m["step"]
	var start_x: float = m["start_x"]
	var base_y := 42.0

	var mid := float(n - 1) * 0.5
	var norm := 0.0 if n <= 1 else (float(i) - mid) / maxf(1.0, mid)
	var arc_y := (norm * norm) * 14.0
	var rot := norm * clampf(float(n) * 1.1, 2.0, 12.0)

	var x := start_x + float(i) * step
	var y := base_y + arc_y
	var sc := 1.0

	var active_idx := _get_active_focus_index()
	if active_idx >= 0:
		if n > 1:
			# Guaranteed non-burying wing allocation: keep left gap >= 22px and right gap past scaled focused card!
			var left_pad := 6.0
			var right_max := maxf(left_pad, w - CARD_W - 6.0)
			var avail_span := right_max - left_pad
			var focus_sc := 1.20 if _pointer_down else 1.12
			var right_cnt := n - 1 - active_idx
			var left_cnt := active_idx
			var need_focus_r := (CARD_W * focus_sc - 6.0) if right_cnt > 0 else 0.0
			var regular_gaps := maxi(1, (n - 1) - (1 if right_cnt > 0 else 0))
			var wing_step := minf(84.0, maxf(18.0, (avail_span - need_focus_r) / float(regular_gaps)))
			var used_span := wing_step * float(regular_gaps) + need_focus_r
			var fan_x0 := left_pad + maxf(0.0, (avail_span - used_span) * 0.5)
			if i < active_idx:
				x = fan_x0 + float(i) * wing_step
			elif i == active_idx:
				x = fan_x0 + float(left_cnt) * wing_step
			else:
				x = fan_x0 + float(left_cnt) * wing_step + need_focus_r + float(i - active_idx - 1) * wing_step

		var dist := i - active_idx
		if dist == 0:
			# Focused / scrubbed / last card pops out big and follows drag cleanly!
			rot = 0.0
			if i == _drag_locked_idx:
				y = base_y - 26.0 - _drag_lift_y
				x += _drag_offset_x
				sc = 1.15
			elif _pointer_down:
				y = base_y - 28.0
				sc = 1.20 if n > 1 else 1.14
			else:
				y = base_y - 16.0
				sc = 1.12 if n > 1 else 1.06
		elif _pointer_down and absi(dist) == 1:
			y -= 10.0
			sc = 1.03

	# Keep resting cards inside horizontal bounds, while dragged card may roam smoothly toward the Rune
	if i != _drag_locked_idx:
		x = clampf(x, 4.0, maxf(4.0, w - CARD_W - 4.0))
	else:
		x = clampf(x, -20.0, w - CARD_W + 20.0)
	return {"pos": Vector2(x, y), "rot": rot, "scale": sc}

func _scrub_slot_centers() -> PackedFloat32Array:
	var m := _fan_metrics()
	var n: int = m["n"]
	var step: float = m["step"]
	var start_x: float = m["start_x"]
	var centers := PackedFloat32Array()
	if n <= 0:
		return centers
	# Distribute active scrub columns monotonically from left edge of card 0 to center-right of card n-1
	var left_edge := start_x + 14.0
	var right_edge := start_x + step * float(maxi(0, n - 1)) + CARD_W * 0.65
	if n == 1:
		centers.append(start_x + CARD_W * 0.5)
		return centers
	for i in range(n):
		var frac := float(i) / float(n - 1)
		centers.append(lerpf(left_edge, right_edge, frac))
	return centers

func _scrub_pick_x(px: float, current_idx: int) -> int:
	var centers := _scrub_slot_centers()
	var n := centers.size()
	if n == 0:
		return -1
	if n == 1:
		return 0
	var best_idx := 0
	var best_dist := 99999.0
	for i in range(n):
		var d := absf(px - centers[i])
		if d < best_dist:
			best_dist = d
			best_idx = i
	# Hysteresis around current_idx prevents flicker when sliding smoothly between 15-20 cards
	if current_idx >= 0 and current_idx < n and best_idx != current_idx:
		var slot_w := (centers[n - 1] - centers[0]) / float(n - 1)
		var cur_d := absf(px - centers[current_idx])
		if cur_d - best_dist < maxf(4.0, slot_w * 0.22):
			return current_idx
	return best_idx

func _pick_card_at_pos(pos: Vector2) -> int:
	if _cards.is_empty():
		return -1
	var order: Array[int] = []
	var active := _get_active_focus_index()
	if active >= 0:
		order.append(active)
	for i in range(_cards.size() - 1, -1, -1):
		if i != active:
			order.append(i)

	for idx in order:
		var cpos := _curr_pos[idx]
		var cs := _curr_scale[idx]
		var center := cpos + Vector2(CARD_W * 0.5, CARD_H * 0.5)
		var half := Vector2(CARD_W * 0.5 * cs + 4.0, CARD_H * 0.5 * cs + 12.0)
		var rect := Rect2(center - half, half * 2.0)
		if rect.has_point(pos):
			return idx
	return _scrub_pick_x(pos.x, _focus_idx)

func _is_drag_ready_to_play(lift: float, idx: int) -> bool:
	if idx < 0 or idx >= _cards.size():
		return false
	if lift >= SWIPE_PLAY_DY:
		return true
	if _has_rune_target:
		var card_center := global_position + _curr_pos[idx] + Vector2(CARD_W * 0.5, CARD_H * 0.5)
		if card_center.distance_to(_rune_target_global) <= RUNE_DROP_RADIUS:
			return true
		if card_center.y <= _rune_target_global.y + 135.0 and lift >= 45.0:
			return true
	if _peak_vy_up >= FLICK_MIN_VY and lift >= FLICK_MIN_DY:
		return true
	return false

func _gui_input(event: InputEvent) -> void:
	if _cards.is_empty():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mpos: Vector2 = event.position
		if event.pressed:
			_pointer_down = true
			_press_pos = mpos
			_scrub_anchor_y = mpos.y
			_last_pointer_pos = mpos
			_last_motion_us = Time.get_ticks_usec()
			_peak_vy_up = 0.0
			_drag_locked_idx = -1
			_drag_lift_y = 0.0
			_drag_offset_x = 0.0
			var hit := _pick_card_at_pos(mpos)
			if hit >= 0:
				_set_focus(hit)
		else:
			_finish_pointer(mpos)

	elif event is InputEventMouseMotion and _pointer_down:
		var mpos: Vector2 = event.position
		var now_us := Time.get_ticks_usec()
		var dt := clampf(float(now_us - _last_motion_us) / 1000000.0, 0.004, 0.2)
		var prev_pos := _last_pointer_pos
		_last_pointer_pos = mpos
		_last_motion_us = now_us

		var vy_up := (prev_pos.y - mpos.y) / dt
		if vy_up > _peak_vy_up:
			_peak_vy_up = vy_up
		else:
			_peak_vy_up = lerpf(_peak_vy_up, maxf(0.0, vy_up), 0.25)

		if _drag_locked_idx == -1:
			var dy_up := _scrub_anchor_y - mpos.y
			var dx_step := absf(mpos.x - prev_pos.x)
			var lock_dy := 14.0 if _cards.size() == 1 else SWIPE_LOCK_DY
			var fast_flick_up := (_peak_vy_up >= FLICK_MIN_VY * 0.72 and dy_up >= 14.0)
			if (dy_up >= lock_dy or fast_flick_up) and _focus_idx >= 0 and (_cards.size() == 1 or dy_up > dx_step * 0.50):
				_drag_locked_idx = _focus_idx
				_drag_lift_y = clampf(dy_up, 0.0, 540.0)
				_drag_offset_x = clampf(mpos.x - _press_pos.x, -260.0, 260.0) * 0.75
				_emit_drag_state()
			else:
				# Stable X-column scrubbing with hysteresis so many cards never lose position!
				var hit := _scrub_pick_x(mpos.x, _focus_idx)
				if hit >= 0 and hit != _focus_idx:
					_set_focus(hit)
				if mpos.y > _scrub_anchor_y:
					_scrub_anchor_y = mpos.y
				elif absf(_scrub_anchor_y - mpos.y) < SWIPE_LOCK_DY * 0.7 and dx_step < 8.0:
					_scrub_anchor_y = lerpf(_scrub_anchor_y, mpos.y, 0.25)
		else:
			var lift := _scrub_anchor_y - mpos.y
			if lift < 6.0 and _peak_vy_up < FLICK_MIN_VY * 0.4:
				# Pulled card cleanly back into hand -> return to smooth scrubbing!
				_drag_locked_idx = -1
				_drag_lift_y = 0.0
				_drag_offset_x = 0.0
				_emit_drag_state()
			else:
				_drag_lift_y = clampf(lift, 0.0, 540.0)
				_drag_offset_x = clampf(mpos.x - _press_pos.x, -280.0, 280.0) * 0.85
				_emit_drag_state()

func _set_focus(idx: int) -> void:
	if idx < 0 or idx >= _cards.size():
		return
	var changed := (idx != _focus_idx)
	_focus_idx = idx
	var c: Dictionary = _cards[idx]
	var cid := int(c.get("id", -1))
	_selected_card_id = cid
	if changed:
		card_scrubbed.emit(idx, c)
		card_selected.emit(cid, c)

func _emit_drag_state() -> void:
	if _drag_locked_idx < 0 or _drag_locked_idx >= _cards.size():
		drag_state_changed.emit(false, false, false)
		return
	var cid := int(_cards[_drag_locked_idx].get("id", -1))
	var legal := _interactive and _legal_ids.has(cid)
	var ready := _is_drag_ready_to_play(_drag_lift_y, _drag_locked_idx)
	drag_state_changed.emit(true, ready, legal)

func _finish_pointer(pos: Vector2) -> void:
	if not _pointer_down:
		return
	var was_locked := _drag_locked_idx
	var lift := _drag_lift_y
	var hit_idx := was_locked if was_locked >= 0 else _focus_idx
	var ready := (was_locked >= 0 and _is_drag_ready_to_play(lift, hit_idx))

	_pointer_down = false
	_drag_locked_idx = -1
	_drag_lift_y = 0.0
	_drag_offset_x = 0.0
	_peak_vy_up = 0.0
	drag_state_changed.emit(false, false, false)

	if hit_idx < 0 or hit_idx >= _cards.size():
		return

	var c: Dictionary = _cards[hit_idx]
	var cid := int(c.get("id", -1))
	var is_legal := _interactive and _legal_ids.has(cid)
	var card_center_global := global_position + _curr_pos[hit_idx] + Vector2(CARD_W * 0.5, CARD_H * 0.5)

	# Only swipe into Center Rune OR fast upward flick plays the card; NO double-tap-to-play!
	if ready:
		if is_legal:
			card_swipe_played.emit(cid, card_center_global)
		else:
			trigger_shake(hit_idx)
			illegal_swipe_attempted.emit(cid, card_center_global)
		return

	# Clean tap just keeps focus/selection on the card
	if pos.distance_to(_press_pos) < 18.0:
		_selected_card_id = cid
		card_selected.emit(cid, c)

func trigger_shake(idx: int) -> void:
	if idx < 0 or idx >= _shake_x.size():
		return
	_shake_x[idx] = -18.0
	var tw := create_tween()
	tw.tween_method(func(val: float):
		if idx < _shake_x.size():
			_shake_x[idx] = val
	, -16.0, 0.0, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func trigger_shake_by_id(card_id: int) -> void:
	for i in range(_cards.size()):
		if int(_cards[i].get("id", -1)) == card_id:
			trigger_shake(i)
			return

func get_selected_card_id() -> int:
	return _selected_card_id

func get_card_count() -> int:
	return _cards.size()

func get_card_view(idx: int) -> CardView:
	if idx >= 0 and idx < _views.size():
		return _views[idx]
	return null

# Helper for automated testing: pick which card index sits at a local coordinate
func debug_pick_card_at(pos: Vector2) -> int:
	_snap_if_idle()
	return _pick_card_at_pos(pos)

# Helper for automated testing: simulate swipe-to-rune gesture on card index `idx`
func debug_simulate_swipe_play(idx: int) -> void:
	_snap_if_idle()
	if idx < 0 or idx >= _cards.size():
		return
	var start := _curr_pos[idx] + Vector2(20.0, 60.0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	_gui_input(press)

	var mid_move := InputEventMouseMotion.new()
	mid_move.position = start + Vector2(0.0, -70.0)
	_gui_input(mid_move)

	var high_move := InputEventMouseMotion.new()
	high_move.position = start + Vector2(0.0, -175.0)
	_gui_input(high_move)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = start + Vector2(0.0, -175.0)
	_gui_input(release)

func debug_simulate_fast_flick_play(idx: int) -> void:
	_snap_if_idle()
	if idx < 0 or idx >= _cards.size():
		return
	var start := _curr_pos[idx] + Vector2(20.0, 60.0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	_gui_input(press)

	# Simulate rapid velocity spike via tiny elapsed motion delta
	_last_motion_us = Time.get_ticks_usec() - 25000
	var flick_move := InputEventMouseMotion.new()
	flick_move.position = start + Vector2(0.0, -48.0)
	_gui_input(flick_move)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = start + Vector2(0.0, -48.0)
	_gui_input(release)

func debug_simulate_drag_hold(idx: int, lift_dy: float = 280.0) -> void:
	_snap_if_idle()
	if idx < 0 or idx >= _cards.size():
		return
	var start := _curr_pos[idx] + Vector2(20.0, 60.0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	_gui_input(press)

	var drag_move := InputEventMouseMotion.new()
	drag_move.position = start + Vector2(0.0, -lift_dy)
	_gui_input(drag_move)
	_process(0.25)
	_process(0.25)
