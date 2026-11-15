class_name ProgressWidgets
extends Object

class RoundTimelineBar extends Control:
	var current_round := 1
	var max_rounds := 20
	var outcomes: Array[int] = [] # +1 = gewonnen, -1 = verloren, 0 = offen

	func _init() -> void:
		custom_minimum_size = Vector2(0, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_progress(p_round: int, p_max: int, p_outcomes: Array = []) -> void:
		current_round = clampi(p_round, 1, maxi(1, p_max))
		max_rounds = maxi(1, p_max)
		outcomes.clear()
		for o in p_outcomes:
			outcomes.append(int(o))
		queue_redraw()

	func _draw() -> void:
		if max_rounds <= 0 or size.x < 20.0:
			return
		var gap := 3.0 if max_rounds <= 15 else 2.0
		var seg_w := (size.x - gap * float(max_rounds - 1)) / float(max_rounds)
		var h := size.y
		for i in range(max_rounds):
			var r_idx := i + 1
			var x := float(i) * (seg_w + gap)
			var rect := Rect2(x, 3.0, maxf(3.0, seg_w), maxf(5.0, h - 6.0))
			var col := Color(0.18, 0.20, 0.28, 0.65)
			var out_v := outcomes[i] if i < outcomes.size() else 0
			if r_idx < current_round or out_v != 0:
				if out_v > 0:
					col = Color("#10B981") # Gewonnen: Smaragdgrün
				elif out_v < 0:
					col = Color("#EF4444") # Verloren: Karmesinrot
				else:
					col = Color("#10B981") if r_idx < current_round else col
			elif r_idx == current_round:
				col = Color("#FBBF24")
				rect.position.y = 0.5
				rect.size.y = h - 1.0
			draw_rect(rect, col, true)
			if out_v != 0 or r_idx == current_round:
				var sheen := col.lightened(0.45)
				sheen.a = 0.75
				draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 1.5), sheen, true)

class TrickPipsRow extends Control:
	var bid := -1
	var won := 0
	var max_pips := 10

	func _init() -> void:
		custom_minimum_size = Vector2(64, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_stats(p_bid: int, p_won: int) -> void:
		bid = p_bid
		won = p_won
		queue_redraw()

	func _draw() -> void:
		if bid < 0 and won == 0:
			# Not yet bid: draw faint dash pips
			draw_circle(Vector2(6, size.y * 0.5), 3.0, Color(0.55, 0.62, 0.72, 0.45))
			return
		var total := maxi(bid, won)
		if total == 0:
			# Zero-bid indicator: emerald shield ring if 0/0, red if busted
			var zero_col := Color("#10B981") if bid == 0 and won == 0 else Color("#EF4444")
			draw_arc(Vector2(8, size.y * 0.5), 4.5, 0.0, TAU, 16, zero_col, 2.0)
			return
		var count := mini(total, max_pips)
		var radius := 4.2 if count <= 7 else 3.2
		var spacing := radius * 2.0 + 3.0
		var cy := size.y * 0.5
		for i in range(count):
			var cx := radius + 1.0 + float(i) * spacing
			if cx + radius > size.x:
				break
			var fill_col := Color(0.45, 0.52, 0.65, 0.32)
			var border_col := Color(0.75, 0.82, 0.92, 0.45)
			if i < won and (bid < 0 or i < bid):
				fill_col = Color("#10B981") if won == bid else Color("#FBBF24")
				border_col = fill_col.lightened(0.25)
			elif i < won and bid >= 0 and i >= bid:
				fill_col = Color("#EF4444")
				border_col = Color("#FCA5A5")
			draw_circle(Vector2(cx, cy), radius, fill_col)
			draw_arc(Vector2(cx, cy), radius, 0.0, TAU, 14, border_col, 1.4)

class ScoreChart extends Control:
	const PLAYER_COLORS := [
		Color("#FBBF24"),
		Color("#38BDF8"),
		Color("#34D399"),
		Color("#F472B6"),
		Color("#A78BFA"),
		Color("#FB923C")
	]

	var _players: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(0, 224)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_players(p_players: Array) -> void:
		_players = p_players.duplicate()
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 80.0 or h < 60.0:
			return

		# Deep night-sky gradient bands ("Sternenhimmel") framed in warm brass/gold
		var sky_top := Color("#030611")
		var sky_bot := Color("#0D152C")
		var bands := 10
		for b in range(bands):
			var t0 := float(b) / float(bands)
			var bh := h / float(bands) + 1.0
			draw_rect(Rect2(0.0, t0 * h, w, bh), sky_top.lerp(sky_bot, t0), true)

		# Deterministic starry night sky with twinkling halos & 4-point glints
		var rng := RandomNumberGenerator.new()
		rng.seed = 94731
		var star_tints := [Color("#FFFBEB"), Color("#BAE6FD"), Color("#FDE68A"), Color("#E0E7FF")]
		for s in range(54):
			var sx := rng.randf_range(8.0, w - 8.0)
			var sy := rng.randf_range(16.0, h - 10.0)
			var sr := rng.randf_range(0.7, 2.0)
			var sc: Color = star_tints[s % star_tints.size()]
			var sa := rng.randf_range(0.25, 0.78)
			draw_circle(Vector2(sx, sy), sr * 2.4, Color(sc.r, sc.g, sc.b, sa * 0.18))
			draw_circle(Vector2(sx, sy), sr, Color(sc.r, sc.g, sc.b, sa))
			if s % 9 == 0:
				var arm := sr * 4.0
				var glint := Color(sc.r, sc.g, sc.b, sa * 0.65)
				draw_line(Vector2(sx - arm, sy), Vector2(sx + arm, sy), glint, 1.0)
				draw_line(Vector2(sx, sy - arm), Vector2(sx, sy + arm), glint, 1.0)

		draw_rect(Rect2(Vector2.ZERO, size), Color(0.76, 0.56, 0.24, 0.72), false, 1.8)

		var pad_l := 44.0
		var pad_r := 18.0
		var pad_t := 18.0
		var pad_b := 62.0
		var plot_w := maxf(20.0, w - pad_l - pad_r)
		var plot_h := maxf(20.0, h - pad_t - pad_b)
		# Keep Y-axis gutter and bottom legend clear of background stars
		draw_rect(Rect2(1.0, 1.0, pad_l - 2.0, h - 2.0), Color(0.03, 0.055, 0.13, 0.96), true)
		draw_rect(Rect2(1.0, pad_t + plot_h + 2.0, w - 2.0, pad_b - 3.0), Color(0.03, 0.055, 0.13, 0.94), true)

		var max_r := 0
		var min_s := 0.0
		var max_s := 40.0
		for p in _players:
			var hist: Array = p.get("round_history", [])
			max_r = maxi(max_r, hist.size())
			for entry in hist:
				var sc := float(entry.get("total", 0))
				min_s = minf(min_s, sc)
				max_s = maxf(max_s, sc)
		if max_s - min_s < 40.0:
			max_s = min_s + 40.0

		# Choose clean nice integer Y-axis step (10, 20, 25, 50, 100...)
		var raw_span := max_s - min_s
		var nice_step := 25.0
		for cand in [10.0, 20.0, 25.0, 50.0, 100.0, 200.0]:
			if raw_span / float(cand) <= 4.5:
				nice_step = float(cand)
				break
		min_s = floorf(min_s / nice_step) * nice_step
		max_s = ceilf(max_s / nice_step) * nice_step
		if is_equal_approx(min_s, max_s):
			max_s = min_s + nice_step

		var y_for := func(val: float) -> float:
			var t := (val - min_s) / maxf(1.0, max_s - min_s)
			return pad_t + plot_h * (1.0 - t)

		var font := ThemeDB.fallback_font
		var gv := min_s
		while gv <= max_s + 0.01:
			var gy: float = y_for.call(gv)
			var is_zero := is_equal_approx(gv, 0.0)
			var line_col := Color(0.98, 0.80, 0.35, 0.36) if is_zero else Color(0.55, 0.65, 0.85, 0.16)
			draw_line(Vector2(pad_l, gy), Vector2(w - pad_r, gy), line_col, 1.3 if is_zero else 1.0)
			if font:
				draw_string(font, Vector2(6, gy + 4), str(int(roundf(gv))), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.88, 0.82, 0.68, 0.90))
			gv += nice_step

		if max_r == 0:
			if font:
				draw_string(font, Vector2(w * 0.5 - 108, h * 0.5 - 6), "Noch keine abgeschlossene Runde", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.88, 0.82, 0.68))
			return

		var steps := maxi(1, max_r)
		if font:
			var r_step := maxi(1, ceili(float(steps) / 8.0))
			for r_i in range(0, steps, r_step):
				var rx := pad_l + plot_w * (float(r_i + 1) / float(steps))
				draw_line(Vector2(rx, pad_t), Vector2(rx, pad_t + plot_h), Color(0.55, 0.65, 0.85, 0.09), 1.0)
				draw_string(font, Vector2(rx - 10.0, pad_t + plot_h + 15.0), "R%d" % (r_i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.86, 0.80, 0.66, 0.85))

		for p_idx in range(_players.size()):
			var p: Dictionary = _players[p_idx]
			var col: Color = PLAYER_COLORS[p_idx % PLAYER_COLORS.size()]
			var hist: Array = p.get("round_history", [])
			var pts := PackedVector2Array()
			pts.append(Vector2(pad_l, float(y_for.call(0.0))))
			for r_i in range(hist.size()):
				var rx := pad_l + plot_w * (float(r_i + 1) / float(steps))
				var ry: float = y_for.call(float(hist[r_i].get("total", 0)))
				pts.append(Vector2(rx, ry))
			if pts.size() >= 2:
				# Outer celestial glow beam + bright star-bridge polyline
				draw_polyline(pts, Color(col.r, col.g, col.b, 0.24), 6.5, true)
				draw_polyline(pts, col.lightened(0.15), 2.4, true)
			for pt_idx in range(1, pts.size()):
				var pt := pts[pt_idx]
				var is_last := (pt_idx == pts.size() - 1)
				draw_circle(pt, 9.5 if is_last else 7.0, Color(col.r, col.g, col.b, 0.20))
				draw_circle(pt, 5.5 if is_last else 4.2, Color(col.r, col.g, col.b, 0.45))
				draw_circle(pt, 3.0 if is_last else 2.4, Color("#FFFBEB"))
				if is_last:
					draw_line(Vector2(pt.x - 9.0, pt.y), Vector2(pt.x + 9.0, pt.y), Color(1.0, 0.96, 0.78, 0.85), 1.3)
					draw_line(Vector2(pt.x, pt.y - 9.0), Vector2(pt.x, pt.y + 9.0), Color(1.0, 0.96, 0.78, 0.85), 1.3)
			if font:
				var col_idx := p_idx % 3
				var row_idx := p_idx / 3
				var lx := pad_l + float(col_idx) * (plot_w / 3.0)
				var ly := pad_t + plot_h + 33.0 + float(row_idx) * 16.0
				draw_circle(Vector2(lx + 4, ly - 4), 5.0, Color(col.r, col.g, col.b, 0.38))
				draw_circle(Vector2(lx + 4, ly - 4), 2.8, Color("#FFFBEB"))
				var label_txt := str(p.get("name", "?")).left(12)
				draw_string(font, Vector2(lx + 13, ly), label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.98, 0.95, 0.88))
