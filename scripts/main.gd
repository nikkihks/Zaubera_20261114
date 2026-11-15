extends Control

const QR_CARD_SIZE := 224

enum Screen { HOME, LOBBY, TABLE }

var _server: WizardServer
var _client: WizardClient
var _audio: AudioFX

var _is_host := false
var _player_name := "Zauberer"
var _current_screen := Screen.HOME
var _last_state: Dictionary = {}
var _selected_card_id := -1

var _prev_phase := ""
var _prev_round := 0
var _prev_hand_size := 0
var _prev_trick_count := 0
var _prev_trick_winner := -1

# Screen containers
var _screens_root: Control
var _home_screen: Control
var _lobby_screen: Control
var _table_screen: Control

# Home UI
var _name_input: LineEdit
var _rooms_list: VBoxContainer
var _ip_input: LineEdit
var _home_status_lbl: Label

# Lobby UI
var _lobby_title_lbl: Label
var _lobby_count_lbl: Label
var _lobby_players_box: VBoxContainer
var _host_controls_box: VBoxContainer
var _quick_mode_check: CheckButton
var _plus_minus_check: CheckButton
var _start_game_btn: Button
var _qr_panel: PanelContainer
var _qr_tex: TextureRect
var _qr_url_lbl: Label
var _lobby_wait_lbl: Label

# Table UI
var _round_lbl: Label
var _trump_pill: Label
var _mute_btn: Button
var _round_timeline: ProgressWidgets.RoundTimelineBar
var _players_strip: GridContainer
var _arena_panel: PanelContainer
var _arena_style: StyleBoxFlat
var _turn_banner_panel: PanelContainer
var _turn_banner_style: StyleBoxFlat
var _status_banner_lbl: Label
var _rune_ring_rect: TextureRect
var _rune_glow_rect: TextureRect
var _fire_flicker_rect: TextureRect
var _swipe_drop_lbl: Label
var _trick_cards_box: HBoxContainer
var _lead_lbl: Label
var _phase_action_panel: PanelContainer
var _phase_action_box: VBoxContainer
var _hand_panel_style: StyleBoxFlat
var _hand_header_lbl: Label
var _play_selected_btn: Button
var _hand_fan: HandFan
var _hand_empty_lbl: Label
var _bid_buttons: Array[Button] = []
var _anim_time := 0.0
var _rune_dragging := false
var _rune_ready := false
var _rune_illegal := false
var _is_my_turn_pulse := false

# Particles & Toast
var _ambient_sparks: CPUParticles2D
var _burst_sparks: CPUParticles2D
var _toast_lbl: Label
var _toast_tween: Tween

# Modals
var _modal_backdrop: ColorRect
var _modal_title: Label
var _modal_scroll: ScrollContainer
var _modal_body_box: VBoxContainer
var _score_chart: ProgressWidgets.ScoreChart
var _rules_rich: RichTextLabel

static var _card_back_tex: Texture2D
static var _table_crest_tex: Texture2D
static var _campfire_bg_tex: Texture2D
static var _rune_ring_tex: Texture2D
static var _papyrus_btn_tex: Texture2D
static var _papyrus_panel_tex: Texture2D
static var _title_font: Font
static var _body_font: Font

const SUIT_BADGE_COLORS := {
	"red": Color("#B91C1C"),
	"blue": Color("#1D4ED8"),
	"green": Color("#15803D"),
	"yellow": Color("#B45309"),
	"none": Color("#3F352C")
}

func _ready() -> void:
	if _card_back_tex == null and ResourceLoader.exists("res://assets/cards/card_back.png"):
		_card_back_tex = load("res://assets/cards/card_back.png")
	if _table_crest_tex == null and ResourceLoader.exists("res://assets/cards/table_crest.png"):
		_table_crest_tex = load("res://assets/cards/table_crest.png")
	if _campfire_bg_tex == null and ResourceLoader.exists("res://assets/ui/campfire_table_bg.png"):
		_campfire_bg_tex = load("res://assets/ui/campfire_table_bg.png")
	if _rune_ring_tex == null and ResourceLoader.exists("res://assets/ui/arcane_rune_ring.png"):
		_rune_ring_tex = load("res://assets/ui/arcane_rune_ring.png")
	if _papyrus_btn_tex == null and ResourceLoader.exists("res://assets/ui/papyrus_btn.png"):
		_papyrus_btn_tex = load("res://assets/ui/papyrus_btn.png")
	if _papyrus_panel_tex == null and ResourceLoader.exists("res://assets/ui/papyrus_panel.png"):
		_papyrus_panel_tex = load("res://assets/ui/papyrus_panel.png")
	if _title_font == null and ResourceLoader.exists("res://assets/fonts/Cinzel-Bold.ttf"):
		_title_font = load("res://assets/fonts/Cinzel-Bold.ttf")
	if _body_font == null and ResourceLoader.exists("res://assets/fonts/CrimsonPro-SemiBold.ttf"):
		_body_font = load("res://assets/fonts/CrimsonPro-SemiBold.ttf")

	_audio = AudioFX.new()
	add_child(_audio)

	_server = WizardServer.new()
	add_child(_server)
	_server.state_updated.connect(_on_state_received)
	_server.local_error.connect(_on_error_msg)
	_server.server_log.connect(func(msg: String): print("[Server] ", msg))

	_client = WizardClient.new()
	add_child(_client)
	_client.state_received.connect(_on_state_received)
	_client.rooms_updated.connect(_on_rooms_updated)
	_client.connected_to_room.connect(_on_client_connected)
	_client.connection_error.connect(_on_error_msg)
	_client.disconnected.connect(_on_client_disconnected)

	_build_ui()
	_setup_particles()
	_show_screen(Screen.HOME)
	_client.start_discovery()

func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_anim_time += delta
	if _fire_flicker_rect != null:
		var fl := 0.24 + 0.06 * sin(_anim_time * 3.7) + 0.03 * cos(_anim_time * 7.3)
		_fire_flicker_rect.modulate = Color(1.0, 0.56, 0.20, fl)
	if _rune_ring_rect != null and _table_screen != null and _table_screen.visible:
		_rune_ring_rect.pivot_offset = _rune_ring_rect.size * 0.5
		var rot_spd := 0.65 if _rune_ready else (0.28 if _rune_dragging else 0.10)
		_rune_ring_rect.rotation += delta * rot_spd
		var target_scale := 1.14 if (_rune_ready and not _rune_illegal) else (1.05 if _rune_dragging else (1.0 + 0.025 * sin(_anim_time * 2.2)))
		_rune_ring_rect.scale = _rune_ring_rect.scale.lerp(Vector2(target_scale, target_scale), clampf(delta * 12.0, 0.0, 1.0))
		if _rune_illegal:
			_rune_ring_rect.modulate = Color(1.25, 0.35, 0.35, 0.92)
		elif _rune_ready:
			_rune_ring_rect.modulate = Color(1.38, 1.16, 0.62, 0.98)
		elif _rune_dragging:
			_rune_ring_rect.modulate = Color(1.15, 0.98, 0.72, 0.88)
		else:
			_rune_ring_rect.modulate = Color(1.0, 0.92, 0.78, 0.64)
		if _rune_glow_rect != null:
			_rune_glow_rect.pivot_offset = _rune_glow_rect.size * 0.5
			var ga := 0.55 if _rune_ready else (0.34 if _is_my_turn_pulse else 0.20)
			_rune_glow_rect.modulate = Color(1.0, 0.35, 0.28, 0.45) if _rune_illegal else Color(1.0, 0.68, 0.20, ga + 0.06 * sin(_anim_time * 3.1))
		if _hand_fan != null:
			_hand_fan.set_rune_target_global(_rune_ring_rect.global_position + _rune_ring_rect.size * 0.5)
	if _turn_banner_style != null and _is_my_turn_pulse:
		var tp := 0.5 + 0.5 * sin(_anim_time * 4.2)
		_turn_banner_style.border_color = Color("#F59E0B").lerp(Color("#FEF08A"), tp)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_server.stop_hosting()
		_client.disconnect_from_host()

# --- Style Helpers ---

func _make_panel_style(bg: Color, radius := 14, border := Color(0.82, 0.62, 0.28, 0.38), border_w := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border_w)
	s.border_color = border
	s.shadow_color = Color(0, 0, 0, 0.52)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 4)
	return s

func _make_papyrus_panel_style(_tint := Color(1.0, 0.95, 0.88, 0.96), pad := 16) -> StyleBox:
	# Dark smoked parchment container matching web/index.html for clean contrast & zero 9-slice distortion
	var s := _make_panel_style(Color(0.08, 0.055, 0.04, 0.93), 16, Color(0.72, 0.49, 0.18, 0.65), 2)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	s.shadow_size = 16
	s.shadow_offset = Vector2(0, 6)
	return s

func _make_papyrus_btn_style(tint: Color) -> StyleBox:
	if _papyrus_btn_tex == null:
		return _make_panel_style(tint, 10, Color("#D97706"), 1)
	var st := StyleBoxTexture.new()
	st.texture = _papyrus_btn_tex
	st.modulate_color = tint
	st.texture_margin_left = 26
	st.texture_margin_right = 26
	st.texture_margin_top = 14
	st.texture_margin_bottom = 14
	st.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	st.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	return st

func _make_fantasy_toggle_tex(is_on: bool) -> ImageTexture:
	var w := 52
	var h := 26
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := float(h) * 0.5
	var border_col := Color("#FBBF24") if is_on else Color("#6B4E2A")
	var track_col := Color(0.11, 0.24, 0.16, 1.0) if is_on else Color(0.09, 0.07, 0.05, 1.0)
	var knob_cx := float(w - r) if is_on else r
	var knob_col := Color("#FDE68A") if is_on else Color("#786652")
	var knob_core := Color("#FFFBEB") if is_on else Color("#9C876E")
	for y in range(h):
		for x in range(w):
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			var cx := clampf(px, r, float(w) - r)
			var d := Vector2(px - cx, py - r).length()
			if d > r:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var kd := Vector2(px - knob_cx, py - r).length()
			if kd <= r - 4.0:
				var col := knob_core if kd <= r - 7.5 else knob_col
				img.set_pixel(x, y, col)
			elif d >= r - 2.0:
				img.set_pixel(x, y, border_col)
			else:
				img.set_pixel(x, y, track_col)
	return ImageTexture.create_from_image(img)

func _make_btn(text: String, bg: Color, height := 54, font_sz := 17, use_papyrus := true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", font_sz)
	if _title_font != null:
		b.add_theme_font_override("font", _title_font)

	# Light natural aged papyrus vs dark wax/dyed papyrus ink polarity for guaranteed readability
	var lum := bg.get_luminance()
	var ink_col := Color("#1E0F05") if lum > 0.62 else Color("#FFFBEB")
	b.add_theme_color_override("font_color", ink_col)
	b.add_theme_color_override("font_hover_color", ink_col)
	b.add_theme_color_override("font_pressed_color", ink_col)
	b.add_theme_color_override("font_disabled_color", Color(0.75, 0.70, 0.62, 0.72))

	if use_papyrus:
		b.add_theme_stylebox_override("normal", _make_papyrus_btn_style(bg))
		b.add_theme_stylebox_override("hover", _make_papyrus_btn_style(bg.lightened(0.14)))
		b.add_theme_stylebox_override("pressed", _make_papyrus_btn_style(bg.darkened(0.16)))
		b.add_theme_stylebox_override("disabled", _make_papyrus_btn_style(Color(0.28, 0.24, 0.20, 0.55)))
	else:
		var border := Color("#FBBF24") if lum > 0.62 else Color(bg.r, bg.g, bg.b, 0.85).lightened(0.35)
		var norm := _make_panel_style(bg, 10, border, 1)
		norm.content_margin_left = 12
		norm.content_margin_right = 12
		b.add_theme_stylebox_override("normal", norm)
		b.add_theme_stylebox_override("hover", _make_panel_style(bg.lightened(0.14), 10, border, 1))
		b.add_theme_stylebox_override("pressed", _make_panel_style(bg.darkened(0.14), 10, border, 1))
		b.add_theme_stylebox_override("disabled", _make_panel_style(Color(0.20, 0.18, 0.16, 0.55), 10, Color(0.3, 0.25, 0.2, 0.4), 1))
	return b

func _make_choice_tile_btn(text: String, bg: Color, border_col: Color, ink_col: Color, min_sz: Vector2, font_sz: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_sz
	b.add_theme_font_size_override("font_size", font_sz)
	if _title_font != null:
		b.add_theme_font_override("font", _title_font)
	b.add_theme_color_override("font_color", ink_col)
	b.add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	b.add_theme_color_override("font_pressed_color", Color("#FFFBEB"))
	b.add_theme_color_override("font_disabled_color", Color("#FCA5A5"))

	var mk := func(fill: Color, brd: Color) -> StyleBoxFlat:
		var st := _make_panel_style(fill, 12, brd, 2)
		st.content_margin_left = 12
		st.content_margin_right = 12
		st.content_margin_top = 8
		st.content_margin_bottom = 8
		return st

	b.add_theme_stylebox_override("normal", mk.call(bg, border_col))
	b.add_theme_stylebox_override("hover", mk.call(bg.lightened(0.14), border_col.lightened(0.20)))
	b.add_theme_stylebox_override("pressed", mk.call(bg.darkened(0.14), Color("#FEF08A")))
	b.add_theme_stylebox_override("disabled", mk.call(bg, border_col))
	return b

func _make_label(text: String, sz := 16, col := Color("#F5E6CA"), align := HORIZONTAL_ALIGNMENT_LEFT, use_title_font := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	if use_title_font and _title_font != null:
		l.add_theme_font_override("font", _title_font)
	elif _body_font != null:
		l.add_theme_font_override("font", _body_font)
	return l

# --- UI Construction ---

func _make_radial_tex(inner_col: Color, outer_col: Color, sz := 256) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, inner_col)
	grad.set_color(1, outer_col)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.45)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = sz
	tex.height = sz
	return tex

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("#050408")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	if _campfire_bg_tex != null:
		var table_bg := TextureRect.new()
		table_bg.texture = _campfire_bg_tex
		table_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		table_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		table_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		table_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(table_bg)

	# Warm flickering campfire core ambient glow
	_fire_flicker_rect = TextureRect.new()
	_fire_flicker_rect.texture = _make_radial_tex(Color(1.0, 0.55, 0.16, 0.95), Color(1.0, 0.28, 0.05, 0.0), 256)
	_fire_flicker_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fire_flicker_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fire_flicker_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_fire_flicker_rect.modulate = Color(1.0, 0.58, 0.22, 0.34)
	_fire_flicker_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fire_flicker_rect)

	# Soft nighttime darkness vignette keeping warm campfire wood visible around center
	var vig := TextureRect.new()
	vig.texture = _make_radial_tex(Color(0, 0, 0, 0.0), Color(0.01, 0.01, 0.03, 0.68), 256)
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)

	_screens_root = Control.new()
	_screens_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_screens_root)

	_build_home_screen()
	_build_lobby_screen()
	_build_table_screen()
	_build_modal()

	_toast_lbl = _make_label("", 15, Color("#FEF3C7"), HORIZONTAL_ALIGNMENT_CENTER, true)
	_toast_lbl.visible = false
	_toast_lbl.z_index = 400
	_toast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_lbl.add_theme_stylebox_override("normal", _make_panel_style(Color("#451A03"), 12, Color("#F59E0B"), 2))
	_toast_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast_lbl.offset_left = 20
	_toast_lbl.offset_right = -20
	_toast_lbl.offset_top = 82
	_toast_lbl.offset_bottom = 132
	add_child(_toast_lbl)

func _make_glow_texture() -> ImageTexture:
	var sz := 32
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := (sz - 1) * 0.5
	for y in range(sz):
		for x in range(sz):
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var r2 := dx * dx + dy * dy
			var alpha := 0.0 if r2 >= 1.0 else pow(1.0 - r2, 2.4)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)

func _setup_particles() -> void:
	var spark_tex := _make_glow_texture()
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	# Ambient drifting campfire embers across all screens
	_ambient_sparks = CPUParticles2D.new()
	_ambient_sparks.texture = spark_tex
	_ambient_sparks.material = add_mat
	_ambient_sparks.emitting = (DisplayServer.get_name() != "headless")
	_ambient_sparks.amount = 24
	_ambient_sparks.lifetime = 3.8
	_ambient_sparks.preprocess = 2.5
	_ambient_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_ambient_sparks.emission_rect_extents = Vector2(340, 420)
	_ambient_sparks.direction = Vector2(0, -1)
	_ambient_sparks.spread = 36.0
	_ambient_sparks.gravity = Vector2(0, -16)
	_ambient_sparks.initial_velocity_min = 14.0
	_ambient_sparks.initial_velocity_max = 38.0
	_ambient_sparks.scale_amount_min = 0.22
	_ambient_sparks.scale_amount_max = 0.48
	var amb_grad := Gradient.new()
	amb_grad.set_color(0, Color(1.0, 0.55, 0.14, 0.0))
	amb_grad.add_point(0.32, Color(1.0, 0.72, 0.24, 0.36))
	amb_grad.set_color(1, Color(0.85, 0.28, 0.08, 0.0))
	_ambient_sparks.color_ramp = amb_grad
	_ambient_sparks.position = Vector2(360, 620)
	_ambient_sparks.z_index = 0
	_screens_root.add_child(_ambient_sparks)
	_screens_root.move_child(_ambient_sparks, 0)

	# One-shot burst emitter for Wizard / Trick Win / Card Play!
	_burst_sparks = CPUParticles2D.new()
	_burst_sparks.texture = spark_tex
	_burst_sparks.material = add_mat
	_burst_sparks.emitting = false
	_burst_sparks.one_shot = true
	_burst_sparks.explosiveness = 0.92
	_burst_sparks.amount = 36
	_burst_sparks.lifetime = 0.72
	_burst_sparks.direction = Vector2(0, -1)
	_burst_sparks.spread = 180.0
	_burst_sparks.gravity = Vector2(0, 160)
	_burst_sparks.initial_velocity_min = 90.0
	_burst_sparks.initial_velocity_max = 260.0
	_burst_sparks.scale_amount_min = 0.32
	_burst_sparks.scale_amount_max = 0.75
	var burst_grad := Gradient.new()
	burst_grad.set_color(0, Color("#FEF08A"))
	burst_grad.add_point(0.45, Color("#F59E0B"))
	burst_grad.set_color(1, Color(0.65, 0.35, 0.95, 0.0))
	_burst_sparks.color_ramp = burst_grad
	_burst_sparks.z_index = 200
	add_child(_burst_sparks)

func _emit_sparks_at(global_pos: Vector2, primary_col := Color("#FBBF24"), amount := 32) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.add_point(0.35, primary_col)
	g.set_color(1, Color(primary_col.r, primary_col.g, primary_col.b, 0.0))
	_burst_sparks.color_ramp = g
	_burst_sparks.amount = amount
	_burst_sparks.global_position = global_pos
	_burst_sparks.restart()
	_burst_sparks.emitting = true

func _emit_sparks_arena(primary_col := Color("#FBBF24"), amount := 36) -> void:
	if DisplayServer.get_name() == "headless":
		return
	call_deferred("_do_emit_sparks_arena", primary_col, amount)

func _do_emit_sparks_arena(primary_col: Color, amount: int) -> void:
	if _arena_panel == null or not is_inside_tree():
		return
	var center := _arena_panel.global_position + _arena_panel.size * 0.5
	if _arena_panel.size.x < 10.0:
		center = Vector2(360, 480)
	_emit_sparks_at(center, primary_col, amount)

func _build_home_screen() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_screens_root.add_child(scroll)
	_home_screen = scroll

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 32)
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	# Atmospheric Hero emblem + glowing rune halo
	var hero := VBoxContainer.new()
	hero.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_theme_constant_override("separation", 6)
	vbox.add_child(hero)

	var crest_wrap := Control.new()
	crest_wrap.custom_minimum_size = Vector2(128, 128)
	crest_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hero.add_child(crest_wrap)

	if _rune_ring_tex != null:
		var hero_ring := TextureRect.new()
		hero_ring.texture = _rune_ring_tex
		hero_ring.modulate = Color(1.0, 0.85, 0.55, 0.78)
		hero_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
		hero_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hero_ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crest_wrap.add_child(hero_ring)

	var logo := TextureRect.new()
	if ResourceLoader.exists("res://assets/cards/special_wizard.png"):
		logo.texture = load("res://assets/cards/special_wizard.png")
	logo.set_anchors_preset(Control.PRESET_CENTER)
	logo.offset_left = -38
	logo.offset_top = -38
	logo.offset_right = 38
	logo.offset_bottom = 38
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest_wrap.add_child(logo)

	var title_lbl := _make_label("✦ ZAUBERA ✦", 42, Color("#FDE68A"), HORIZONTAL_ALIGNMENT_CENTER, true)
	title_lbl.add_theme_color_override("font_outline_color", Color("#451A03"))
	title_lbl.add_theme_constant_override("outline_size", 6)
	hero.add_child(title_lbl)
	hero.add_child(_make_label("Magisches Wizard-Stichspiel am Lagerfeuer", 16, Color("#E7D3B0"), HORIZONTAL_ALIGNMENT_CENTER, false))

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_papyrus_panel_style(Color(1.0, 0.96, 0.90, 0.96), 18))
	vbox.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 12)
	card.add_child(cv)

	cv.add_child(_make_label("Dein Zauberer-Name", 15, Color("#E7D3B0"), HORIZONTAL_ALIGNMENT_LEFT, true))
	_name_input = LineEdit.new()
	_name_input.text = _player_name
	_name_input.placeholder_text = "Namen eingeben"
	_name_input.custom_minimum_size = Vector2(0, 52)
	_name_input.add_theme_font_size_override("font_size", 19)
	if _body_font != null:
		_name_input.add_theme_font_override("font", _body_font)
	var inp_norm := _make_panel_style(Color("#120C08"), 10, Color("#926B39"), 2)
	inp_norm.content_margin_left = 14
	inp_norm.content_margin_right = 14
	var inp_foc := _make_panel_style(Color("#1A110B"), 10, Color("#FBBF24"), 2)
	inp_foc.content_margin_left = 14
	inp_foc.content_margin_right = 14
	_name_input.add_theme_stylebox_override("normal", inp_norm)
	_name_input.add_theme_stylebox_override("focus", inp_foc)
	cv.add_child(_name_input)

	var host_btn := _make_btn("✦ Tisch eröffnen (Host) ✦", Color("#FFE8B0"), 64, 19)
	host_btn.pressed.connect(_on_host_pressed)
	cv.add_child(host_btn)

	# Nearby rooms
	var nearby_panel := PanelContainer.new()
	nearby_panel.add_theme_stylebox_override("panel", _make_papyrus_panel_style(Color(0.95, 0.90, 0.84, 0.95), 16))
	vbox.add_child(nearby_panel)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 10)
	nearby_panel.add_child(nv)
	nv.add_child(_make_label("Tische im selben WLAN / Hotspot", 17, Color("#FDE68A"), HORIZONTAL_ALIGNMENT_LEFT, true))
	_rooms_list = VBoxContainer.new()
	_rooms_list.add_theme_constant_override("separation", 8)
	nv.add_child(_rooms_list)
	_rooms_list.add_child(_make_label("Suche nach offenen Tischen im Netzwerk...", 15, Color("#CBB799")))

	# Manual IP join
	var join_panel := PanelContainer.new()
	join_panel.add_theme_stylebox_override("panel", _make_papyrus_panel_style(Color(0.95, 0.90, 0.84, 0.95), 16))
	vbox.add_child(join_panel)
	var jv := VBoxContainer.new()
	jv.add_theme_constant_override("separation", 10)
	join_panel.add_child(jv)
	jv.add_child(_make_label("Direkt per IP / QR-Code beitreten", 16, Color("#E7D3B0"), HORIZONTAL_ALIGNMENT_LEFT, true))
	var jrow := HBoxContainer.new()
	jrow.add_theme_constant_override("separation", 10)
	jv.add_child(jrow)
	_ip_input = LineEdit.new()
	_ip_input.placeholder_text = "z. B. 192.168.178.42"
	_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_input.custom_minimum_size = Vector2(0, 52)
	_ip_input.add_theme_font_size_override("font_size", 17)
	var ip_norm := _make_panel_style(Color("#120C08"), 10, Color("#78562C"), 2)
	ip_norm.content_margin_left = 14
	ip_norm.content_margin_right = 14
	var ip_foc := _make_panel_style(Color("#1A110B"), 10, Color("#FBBF24"), 2)
	ip_foc.content_margin_left = 14
	ip_foc.content_margin_right = 14
	_ip_input.add_theme_stylebox_override("normal", ip_norm)
	_ip_input.add_theme_stylebox_override("focus", ip_foc)
	jrow.add_child(_ip_input)
	var join_btn := _make_choice_tile_btn("Beitreten", Color("#15803D"), Color("#6EE7B7"), Color("#FFFBEB"), Vector2(154, 56), 17)
	join_btn.pressed.connect(_on_manual_join_pressed)
	jrow.add_child(join_btn)

	var util_row := HBoxContainer.new()
	util_row.add_theme_constant_override("separation", 12)
	vbox.add_child(util_row)
	var rules_btn := _make_btn("Wizard-Regeln", Color("#FFF8E8"), 56, 16)
	rules_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules_btn.pressed.connect(_show_rules_modal)
	util_row.add_child(rules_btn)
	var cross_btn := _make_btn("Android + iOS Info", Color("#FFF8E8"), 56, 16)
	cross_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cross_btn.pressed.connect(_show_crossplay_modal)
	util_row.add_child(cross_btn)

	_home_status_lbl = _make_label("", 14, Color("#E7D3B0"), HORIZONTAL_ALIGNMENT_CENTER)
	_home_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_home_status_lbl)

func _build_lobby_screen() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_screens_root.add_child(scroll)
	_lobby_screen = scroll

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 28)
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	vbox.add_child(hdr)
	_lobby_title_lbl = _make_label("Tisch", 24, Color("#FDE68A"), HORIZONTAL_ALIGNMENT_LEFT, true)
	_lobby_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hdr.add_child(_lobby_title_lbl)
	_lobby_count_lbl = _make_label("1 / 6 Spieler", 15, Color("#E7D3B0"), HORIZONTAL_ALIGNMENT_RIGHT, true)
	_lobby_count_lbl.custom_minimum_size = Vector2(128, 0)
	hdr.add_child(_lobby_count_lbl)

	# Players list
	var ppanel := PanelContainer.new()
	ppanel.add_theme_stylebox_override("panel", _make_papyrus_panel_style(Color(0.95, 0.90, 0.84, 0.95), 16))
	vbox.add_child(ppanel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	ppanel.add_child(pv)
	pv.add_child(_make_label("Spieler am Lagerfeuer", 16, Color("#FBBF24"), HORIZONTAL_ALIGNMENT_LEFT, true))
	_lobby_players_box = VBoxContainer.new()
	_lobby_players_box.add_theme_constant_override("separation", 6)
	pv.add_child(_lobby_players_box)

	# QR Invite card
	_qr_panel = PanelContainer.new()
	_qr_panel.add_theme_stylebox_override("panel", _make_papyrus_panel_style(Color(0.94, 0.89, 0.82, 0.96), 16))
	vbox.add_child(_qr_panel)
	var qv := VBoxContainer.new()
	qv.add_theme_constant_override("separation", 8)
	_qr_panel.add_child(qv)
	qv.add_child(_make_label("iPhone & Android per QR-Code einladen", 17, Color("#7DD3FC"), HORIZONTAL_ALIGNMENT_CENTER, true))
	var qhint := _make_label("Freunde im selben WLAN/Hotspot können den Code mit der iPhone-Kamera scannen und direkt im Safari spielen:", 14, Color("#E7D3B0"), HORIZONTAL_ALIGNMENT_CENTER)
	qhint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	qv.add_child(qhint)

	var qr_frame := PanelContainer.new()
	qr_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	qr_frame.add_theme_stylebox_override("panel", _make_panel_style(Color.WHITE, 10, Color("#D97706"), 5))
	qv.add_child(qr_frame)
	_qr_tex = TextureRect.new()
	_qr_tex.custom_minimum_size = Vector2(QR_CARD_SIZE, QR_CARD_SIZE)
	_qr_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	qr_frame.add_child(_qr_tex)

	_qr_url_lbl = _make_label("http://...", 14, Color("#FDE68A"), HORIZONTAL_ALIGNMENT_CENTER)
	_qr_url_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	qv.add_child(_qr_url_lbl)

	# Host controls (keeps Plus/Minus-Eins-Regel toggle intact!)
	_host_controls_box = VBoxContainer.new()
	_host_controls_box.add_theme_constant_override("separation", 12)
	vbox.add_child(_host_controls_box)

	var opts_panel := PanelContainer.new()
	opts_panel.add_theme_stylebox_override("panel", _make_papyrus_panel_style(Color(0.95, 0.90, 0.84, 0.95), 14))
	_host_controls_box.add_child(opts_panel)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 8)
	opts_panel.add_child(ov)

	var tog_on_tex := _make_fantasy_toggle_tex(true)
	var tog_off_tex := _make_fantasy_toggle_tex(false)
	var chk_box := _make_panel_style(Color(0.08, 0.06, 0.04, 0.88), 10, Color(0.55, 0.40, 0.20, 0.58), 1)
	chk_box.content_margin_left = 12
	chk_box.content_margin_right = 12
	chk_box.content_margin_top = 8
	chk_box.content_margin_bottom = 8

	_plus_minus_check = CheckButton.new()
	_plus_minus_check.text = "Plus/Minus-Eins-Regel (Summe ≠ Rundenstiche)  [AN]"
	_plus_minus_check.button_pressed = true
	_plus_minus_check.add_theme_font_size_override("font_size", 15)
	_plus_minus_check.add_theme_color_override("font_color", Color("#A7F3D0"))
	_plus_minus_check.add_theme_color_override("font_pressed_color", Color("#A7F3D0"))
	_plus_minus_check.add_theme_icon_override("checked", tog_on_tex)
	_plus_minus_check.add_theme_icon_override("unchecked", tog_off_tex)
	for st_name in ["normal", "hover", "focus", "pressed", "hover_pressed"]:
		_plus_minus_check.add_theme_stylebox_override(st_name, chk_box)
	_plus_minus_check.toggled.connect(func(on: bool):
		_audio.feedback("bid", 15, 0.5)
		_plus_minus_check.text = "Plus/Minus-Eins-Regel (Summe ≠ Rundenstiche)  [%s]" % ("AN" if on else "AUS")
		_plus_minus_check.add_theme_color_override("font_color", Color("#A7F3D0") if on else Color("#CBB799"))
		_server.host_toggle_plus_minus(on)
	)
	ov.add_child(_plus_minus_check)

	_quick_mode_check = CheckButton.new()
	_quick_mode_check.text = "Kurz-Partie (max. 10 Runden)  [AUS]"
	_quick_mode_check.add_theme_font_size_override("font_size", 15)
	_quick_mode_check.add_theme_color_override("font_color", Color("#CBB799"))
	_quick_mode_check.add_theme_color_override("font_pressed_color", Color("#FDE68A"))
	_quick_mode_check.add_theme_icon_override("checked", tog_on_tex)
	_quick_mode_check.add_theme_icon_override("unchecked", tog_off_tex)
	for st_name in ["normal", "hover", "focus", "pressed", "hover_pressed"]:
		_quick_mode_check.add_theme_stylebox_override(st_name, chk_box)
	_quick_mode_check.toggled.connect(func(on: bool):
		_audio.feedback("bid", 15, 0.5)
		_quick_mode_check.text = "Kurz-Partie (max. 10 Runden)  [%s]" % ("AN" if on else "AUS")
		_quick_mode_check.add_theme_color_override("font_color", Color("#FDE68A") if on else Color("#CBB799"))
		_server.host_toggle_quick_mode(on)
	)
	ov.add_child(_quick_mode_check)

	var bot_row := HBoxContainer.new()
	bot_row.add_theme_constant_override("separation", 10)
	_host_controls_box.add_child(bot_row)
	var add_bot := _make_btn("+ KI-Bot hinzufügen", Color("#6D28D9"), 56, 16, true)
	add_bot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_bot.pressed.connect(func():
		_audio.feedback("deal", 15, 0.5)
		_server.host_add_bot()
	)
	bot_row.add_child(add_bot)
	var rem_bot := _make_btn("- Bot entfernen", Color("#FFF8E8"), 56, 16, true)
	rem_bot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rem_bot.pressed.connect(func():
		_audio.feedback("scrub", 15, 0.5)
		_server.host_remove_last_bot()
	)
	bot_row.add_child(rem_bot)

	_start_game_btn = _make_btn("✦ Partie starten (mind. 3 Spieler) ✦", Color("#FFE8B0"), 62, 18, true)
	_start_game_btn.pressed.connect(func():
		_audio.feedback("wizard", 35, 0.85)
		_server.host_start_game()
	)
	_host_controls_box.add_child(_start_game_btn)

	_lobby_wait_lbl = _make_label("Warte darauf, dass der Gastgeber das Spiel startet...", 15, Color("#E7D3B0"), HORIZONTAL_ALIGNMENT_CENTER)
	_lobby_wait_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_lobby_wait_lbl)

	var leave_btn := _make_btn("Tisch verlassen", Color("#991B1B"), 52, 16, true)
	leave_btn.pressed.connect(_on_leave_pressed)
	vbox.add_child(leave_btn)

func _build_table_screen() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 10)
	root.add_theme_constant_override("margin_right", 10)
	root.add_theme_constant_override("margin_top", 10)
	root.add_theme_constant_override("margin_bottom", 8)
	_screens_root.add_child(root)
	_table_screen = root

	var main_v := VBoxContainer.new()
	main_v.add_theme_constant_override("separation", 6)
	root.add_child(main_v)

	# 1) Top HUD bar + RoundTimeline
	var top_panel := PanelContainer.new()
	top_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.04, 0.03, 0.86), 14, Color(0.75, 0.56, 0.25, 0.45), 1))
	main_v.add_child(top_panel)
	var tm := MarginContainer.new()
	tm.add_theme_constant_override("margin_left", 12)
	tm.add_theme_constant_override("margin_right", 10)
	tm.add_theme_constant_override("margin_top", 8)
	tm.add_theme_constant_override("margin_bottom", 8)
	top_panel.add_child(tm)

	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 6)
	tm.add_child(tv)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 6)
	tv.add_child(top_bar)

	_round_lbl = _make_label("Runde 1 / 20", 18, Color("#FDE68A"), HORIZONTAL_ALIGNMENT_LEFT, true)
	_round_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(_round_lbl)

	_trump_pill = _make_label("Kein Trumpf", 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
	var ts := _make_panel_style(Color("#3F352C"), 10, Color(1, 0.85, 0.5, 0.45), 1)
	ts.content_margin_left = 12
	ts.content_margin_right = 12
	ts.content_margin_top = 5
	ts.content_margin_bottom = 5
	_trump_pill.add_theme_stylebox_override("normal", ts)
	top_bar.add_child(_trump_pill)

	var score_btn := _make_btn("Punkte", Color("#EAD2A8"), 42, 15, false)
	score_btn.pressed.connect(_show_scorecard_modal)
	top_bar.add_child(score_btn)

	_mute_btn = _make_btn("🔊", Color("#EAD2A8"), 42, 16, false)
	_mute_btn.custom_minimum_size = Vector2(44, 42)
	_mute_btn.pressed.connect(_on_toggle_mute)
	top_bar.add_child(_mute_btn)

	var help_btn := _make_btn("?", Color("#EAD2A8"), 42, 16, false)
	help_btn.custom_minimum_size = Vector2(42, 42)
	help_btn.pressed.connect(_show_rules_modal)
	top_bar.add_child(help_btn)

	var exit_btn := _make_btn("✕", Color("#991B1B"), 42, 15, false)
	exit_btn.custom_minimum_size = Vector2(42, 42)
	exit_btn.pressed.connect(_on_leave_pressed)
	top_bar.add_child(exit_btn)

	_round_timeline = ProgressWidgets.RoundTimelineBar.new()
	tv.add_child(_round_timeline)

	# 2) All players wrapped into automatic rows (NO horizontal scrollbars!)
	_players_strip = GridContainer.new()
	_players_strip.columns = 3
	_players_strip.add_theme_constant_override("h_separation", 6)
	_players_strip.add_theme_constant_override("v_separation", 6)
	_players_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_v.add_child(_players_strip)

	# 3) Center Campfire Dark Arena with Glowing Blender Arcane Rune Target
	_arena_panel = PanelContainer.new()
	_arena_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_arena_style = _make_panel_style(Color(0.03, 0.025, 0.03, 0.42), 18, Color(0.85, 0.60, 0.24, 0.35), 2)
	_arena_panel.add_theme_stylebox_override("panel", _arena_style)
	main_v.add_child(_arena_panel)

	var arena_root := Control.new()
	arena_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	arena_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena_panel.add_child(arena_root)

	# Radial additive ember halo under the Rune
	_rune_glow_rect = TextureRect.new()
	_rune_glow_rect.texture = _make_radial_tex(Color(1.0, 0.65, 0.16, 0.95), Color(0.95, 0.35, 0.05, 0.0), 256)
	_rune_glow_rect.modulate = Color(1.0, 0.68, 0.20, 0.24)
	_rune_glow_rect.set_anchors_preset(Control.PRESET_CENTER)
	_rune_glow_rect.offset_left = -185
	_rune_glow_rect.offset_top = -185
	_rune_glow_rect.offset_right = 185
	_rune_glow_rect.offset_bottom = 185
	_rune_glow_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rune_glow_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rune_glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena_root.add_child(_rune_glow_rect)

	# Blender Glowing Arcane Rune centerpiece
	_rune_ring_rect = TextureRect.new()
	_rune_ring_rect.texture = _rune_ring_tex if _rune_ring_tex != null else _table_crest_tex
	_rune_ring_rect.modulate = Color(1.0, 0.92, 0.78, 0.64)
	_rune_ring_rect.set_anchors_preset(Control.PRESET_CENTER)
	_rune_ring_rect.offset_left = -152
	_rune_ring_rect.offset_top = -152
	_rune_ring_rect.offset_right = 152
	_rune_ring_rect.offset_bottom = 152
	_rune_ring_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rune_ring_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rune_ring_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena_root.add_child(_rune_ring_rect)

	var am := MarginContainer.new()
	am.set_anchors_preset(Control.PRESET_FULL_RECT)
	am.add_theme_constant_override("margin_left", 10)
	am.add_theme_constant_override("margin_right", 10)
	am.add_theme_constant_override("margin_top", 10)
	am.add_theme_constant_override("margin_bottom", 10)
	arena_root.add_child(am)

	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 6)
	am.add_child(av)

	_turn_banner_panel = PanelContainer.new()
	_turn_banner_style = _make_panel_style(Color(0.08, 0.05, 0.04, 0.86), 12, Color("#78562C"), 2)
	_turn_banner_style.content_margin_left = 12
	_turn_banner_style.content_margin_right = 12
	_turn_banner_style.content_margin_top = 6
	_turn_banner_style.content_margin_bottom = 6
	_turn_banner_panel.add_theme_stylebox_override("panel", _turn_banner_style)
	av.add_child(_turn_banner_panel)

	_status_banner_lbl = _make_label("Runde wird vorbereitet...", 17, Color("#FDE68A"), HORIZONTAL_ALIGNMENT_CENTER, true)
	_status_banner_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_turn_banner_panel.add_child(_status_banner_lbl)

	_trick_cards_box = HBoxContainer.new()
	_trick_cards_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_trick_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_trick_cards_box.add_theme_constant_override("separation", 10)
	av.add_child(_trick_cards_box)

	_swipe_drop_lbl = _make_label("▲ Auf leuchtende Rune ziehen oder schnell hochwischen ▲", 15, Color(1.0, 0.88, 0.56, 0.88), HORIZONTAL_ALIGNMENT_CENTER)
	_swipe_drop_lbl.visible = false
	av.add_child(_swipe_drop_lbl)

	_lead_lbl = _make_label("", 15, Color("#E7D3B0"), HORIZONTAL_ALIGNMENT_CENTER)
	av.add_child(_lead_lbl)

	# 4) Context Action Bar (Trump choose / Bid / Round end)
	_phase_action_panel = PanelContainer.new()
	_phase_action_panel.add_theme_stylebox_override("panel", _make_papyrus_panel_style(Color(0.96, 0.90, 0.82, 0.96), 14))
	_phase_action_panel.visible = false
	main_v.add_child(_phase_action_panel)
	_phase_action_box = VBoxContainer.new()
	_phase_action_box.add_theme_constant_override("separation", 10)
	_phase_action_panel.add_child(_phase_action_box)

	# 5) UNO-Style Bottom Wooden Card Fan
	var hand_panel := PanelContainer.new()
	_hand_panel_style = _make_panel_style(Color(0.05, 0.035, 0.03, 0.88), 16, Color(0.62, 0.45, 0.22, 0.42), 2)
	hand_panel.add_theme_stylebox_override("panel", _hand_panel_style)
	main_v.add_child(hand_panel)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 8)
	hm.add_theme_constant_override("margin_right", 8)
	hm.add_theme_constant_override("margin_top", 8)
	hm.add_theme_constant_override("margin_bottom", 8)
	hand_panel.add_child(hm)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 4)
	hm.add_child(hv)

	var hand_hdr := HBoxContainer.new()
	hand_hdr.add_theme_constant_override("separation", 8)
	hv.add_child(hand_hdr)
	_hand_header_lbl = _make_label("Deine Hand (Daumen streichen = entzerren)", 15, Color("#E7D3B0"))
	_hand_header_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand_header_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hand_hdr.add_child(_hand_header_lbl)
	_play_selected_btn = _make_btn("Ausspielen", Color("#F3B85A"), 42, 15, false)
	_play_selected_btn.custom_minimum_size = Vector2(132, 42)
	_play_selected_btn.visible = false
	_play_selected_btn.pressed.connect(_on_play_selected_pressed)
	hand_hdr.add_child(_play_selected_btn)

	_hand_fan = HandFan.new()
	_hand_fan.card_scrubbed.connect(_on_hand_card_scrubbed)
	_hand_fan.card_selected.connect(_on_hand_card_selected)
	_hand_fan.card_swipe_played.connect(_on_hand_card_swiped)
	_hand_fan.illegal_swipe_attempted.connect(_on_illegal_swipe)
	_hand_fan.drag_state_changed.connect(_on_drag_state_changed)
	hv.add_child(_hand_fan)

	_hand_empty_lbl = _make_label("Alle Karten ausgespielt — warte auf Stichwertung.", 14, Color("#94A3B8"), HORIZONTAL_ALIGNMENT_CENTER)
	_hand_empty_lbl.visible = false
	_hand_empty_lbl.custom_minimum_size = Vector2(0, 60)
	hv.add_child(_hand_empty_lbl)

func _build_modal() -> void:
	_modal_backdrop = ColorRect.new()
	_modal_backdrop.color = Color(0, 0, 0, 0.78)
	_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.visible = false
	_modal_backdrop.z_index = 300
	add_child(_modal_backdrop)

	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.add_theme_constant_override("margin_left", 20)
	mc.add_theme_constant_override("margin_right", 20)
	mc.add_theme_constant_override("margin_top", 40)
	mc.add_theme_constant_override("margin_bottom", 40)
	_modal_backdrop.add_child(mc)

	var mp := PanelContainer.new()
	mp.add_theme_stylebox_override("panel", _make_papyrus_panel_style(Color(0.95, 0.90, 0.82, 0.98), 20))
	mc.add_child(mp)

	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 12)
	mp.add_child(mv)

	_modal_title = _make_label("Info", 22, Color("#FBBF24"), HORIZONTAL_ALIGNMENT_LEFT, true)
	mv.add_child(_modal_title)

	_modal_scroll = ScrollContainer.new()
	_modal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mv.add_child(_modal_scroll)

	_modal_body_box = VBoxContainer.new()
	_modal_body_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_body_box.add_theme_constant_override("separation", 10)
	_modal_scroll.add_child(_modal_body_box)

	var close_btn := _make_btn("Schließen", Color("#FFF8E8"), 56, 16, true)
	close_btn.pressed.connect(func():
		_audio.play("scrub", 0.05)
		_modal_backdrop.visible = false
	)
	mv.add_child(close_btn)

# --- Navigation & Actions ---

func _show_screen(scr: Screen) -> void:
	_current_screen = scr
	_home_screen.visible = (scr == Screen.HOME)
	_lobby_screen.visible = (scr == Screen.LOBBY)
	_table_screen.visible = (scr == Screen.TABLE)
	_ambient_sparks.emitting = (DisplayServer.get_name() != "headless")

func _on_host_pressed() -> void:
	var pname := _name_input.text.strip_edges()
	if pname.is_empty():
		pname = "Zauberer"
	_player_name = pname
	_is_host = true
	_audio.feedback("bid", 25, 0.7)
	if not _server.start_hosting(pname):
		_is_host = false
		_on_error_msg("Server konnte nicht gestartet werden (Ports 8080/8081 belegt?).")
		return
	_show_screen(Screen.LOBBY)

func _on_manual_join_pressed() -> void:
	var pname := _name_input.text.strip_edges()
	if pname.is_empty():
		pname = "Gast"
	_player_name = pname
	var ip := _ip_input.text.strip_edges()
	if ip.is_empty():
		_on_error_msg("Bitte eine Host-IP-Adresse eingeben.")
		return
	_is_host = false
	_audio.feedback("bid", 20, 0.6)
	_home_status_lbl.text = "Verbinde mit %s ..." % ip
	_client.connect_to_host(ip, pname)

func _join_discovered_room(room: Dictionary) -> void:
	var pname := _name_input.text.strip_edges()
	if pname.is_empty():
		pname = "Gast"
	_player_name = pname
	_is_host = false
	_audio.feedback("bid", 20, 0.6)
	_home_status_lbl.text = "Verbinde mit %s ..." % str(room.get("room", "Tisch"))
	_client.connect_to_host(str(room.get("ip", "")), pname, int(room.get("ws_port", 8081)))

func _on_leave_pressed() -> void:
	_audio.feedback("scrub", 15, 0.5)
	if _is_host:
		_server.stop_hosting()
		_is_host = false
	else:
		_client.disconnect_from_host()
		_client.reset_session_token()
	_last_state = {}
	_selected_card_id = -1
	_show_screen(Screen.HOME)

func _on_toggle_mute() -> void:
	_audio.muted = not _audio.muted
	_mute_btn.text = "🔇" if _audio.muted else "🔊"
	if not _audio.muted:
		_audio.feedback("bid", 15, 0.5)

func _on_server_player_joined(p_name: String) -> void:
	_audio.feedback("deal", 25, 0.65)
	_show_toast("%s ist dem Tisch beigetreten!" % p_name, Color("#065F46"), Color("#34D399"))

func _on_client_connected() -> void:
	_home_status_lbl.text = ""
	_audio.feedback("bid", 25, 0.7)
	_show_screen(Screen.LOBBY)

func _on_client_disconnected(reason: String) -> void:
	_home_status_lbl.text = reason
	_show_screen(Screen.HOME)

func _on_error_msg(msg: String) -> void:
	_audio.feedback("error", 55, 0.9)
	_show_toast(msg, Color("#7F1D1D"), Color("#F87171"))

func _show_toast(msg: String, bg := Color("#7C2D12"), border := Color("#F59E0B")) -> void:
	_toast_lbl.text = msg
	_toast_lbl.add_theme_stylebox_override("normal", _make_panel_style(bg, 12, border, 2))
	_toast_lbl.visible = true
	_toast_lbl.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.8)
	_toast_tween.tween_property(_toast_lbl, "modulate:a", 0.0, 0.35)
	_toast_tween.tween_callback(func(): _toast_lbl.visible = false)

# --- State Updates ---

func _on_rooms_updated(rooms: Array) -> void:
	for c in _rooms_list.get_children():
		c.queue_free()
	if rooms.is_empty():
		_rooms_list.add_child(_make_label("Noch keine Tische gefunden. Gleiches WLAN oder Handy-Hotspot nutzen.", 13, Color("#94A3B8")))
		return
	for r in rooms:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_rooms_list.add_child(row)
		var info := _make_label("%s  •  %d/%d  (%s)" % [str(r.get("room", "Tisch")), int(r.get("players", 1)), int(r.get("max", 6)), str(r.get("ip", ""))], 14)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var b := _make_btn("Beitreten", Color("#0F766E"), 40, 14)
		b.custom_minimum_size = Vector2(100, 40)
		var room_copy: Dictionary = r.duplicate()
		b.pressed.connect(func(): _join_discovered_room(room_copy))
		row.add_child(b)

func _on_state_received(state: Dictionary) -> void:
	var prev_round := _prev_round
	var prev_phase := _prev_phase
	var prev_hand_size := _prev_hand_size
	var prev_trick_cnt := _prev_trick_count
	var prev_trick_winner := _prev_trick_winner

	_last_state = state
	var phase: String = state.get("phase", "lobby")
	var round_num := int(state.get("round_number", 0))
	var hand: Array = state.get("your_hand", [])
	var trick_cards: Array = state.get("trick_cards", [])
	var winner_seat := int(state.get("trick_winner_seat", -1))

	_prev_phase = phase
	_prev_round = round_num
	_prev_hand_size = hand.size()
	_prev_trick_count = trick_cards.size()
	_prev_trick_winner = winner_seat

	if phase == "lobby":
		if _current_screen != Screen.LOBBY:
			_show_screen(Screen.LOBBY)
		_render_lobby(state)
	else:
		if _current_screen != Screen.TABLE:
			_show_screen(Screen.TABLE)
		var animate_deal := (round_num != prev_round) or (hand.size() > prev_hand_size)
		_render_table(state, animate_deal, prev_trick_cnt, prev_trick_winner, prev_phase)

func _render_lobby(state: Dictionary) -> void:
	_lobby_title_lbl.text = str(state.get("room_name", "Zaubera Tisch"))
	var players: Array = state.get("players", [])
	_lobby_count_lbl.text = "%d / 6 Spieler" % players.size()

	for c in _lobby_players_box.get_children():
		c.queue_free()
	for p in players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_lobby_players_box.add_child(row)
		var tag := ""
		if p.get("is_host", false):
			tag = "GASTGEBER"
		elif p.get("is_bot", false):
			tag = "BOT"
		elif p.get("connected", true):
			tag = "VERBUNDEN"
		else:
			tag = "GETRENNT"
		var dot_col := Color("#10B981") if p.get("connected", true) else Color("#EF4444")
		var name_lbl := _make_label("● " + str(p.get("name", "?")), 15, dot_col)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_lbl)
		var tag_lbl := _make_label(tag, 12, Color("#FBBF24") if p.get("is_host", false) else Color("#94A3B8"), HORIZONTAL_ALIGNMENT_RIGHT)
		tag_lbl.custom_minimum_size = Vector2(96, 0)
		row.add_child(tag_lbl)

	_host_controls_box.visible = _is_host
	_lobby_wait_lbl.visible = not _is_host
	_qr_panel.visible = _is_host

	if _is_host:
		var pm_on := bool(state.get("plus_minus_rule", true))
		_plus_minus_check.set_pressed_no_signal(pm_on)
		_plus_minus_check.text = "Plus/Minus-Eins-Regel (Summe ≠ Rundenstiche)  [%s]" % ("AN" if pm_on else "AUS")
		_plus_minus_check.add_theme_color_override("font_color", Color("#A7F3D0") if pm_on else Color("#CBB799"))

		var qm_on := bool(state.get("quick_mode", false))
		_quick_mode_check.set_pressed_no_signal(qm_on)
		_quick_mode_check.text = "Kurz-Partie (max. 10 Runden)  [%s]" % ("AN" if qm_on else "AUS")
		_quick_mode_check.add_theme_color_override("font_color", Color("#FDE68A") if qm_on else Color("#CBB799"))
		_start_game_btn.disabled = players.size() < 3
		_start_game_btn.text = "Partie starten (%d Spieler)" % players.size() if players.size() >= 3 else "Noch %d Spieler für Start nötig" % (3 - players.size())

		var ips: Array = state.get("host_ips", [])
		var http_port := int(state.get("http_port", 8080))
		var preferred_ip := "192.168.x.x"
		if not ips.is_empty():
			preferred_ip = str(ips[0])
		var join_url := "http://%s:%d" % [preferred_ip, http_port]
		_qr_url_lbl.text = "iOS / Browser: %s\n(Android-IP: %s)" % [join_url, preferred_ip]
		var tex: Texture2D = QRGenerator.create_texture(join_url, 6, 3)
		if tex != null:
			_qr_tex.texture = tex

func _render_table(state: Dictionary, animate_deal: bool, prev_trick_cnt: int, prev_trick_winner: int, prev_phase: String) -> void:
	var phase: String = state.get("phase", "")
	var round_num := int(state.get("round_number", 1))
	var max_rounds := int(state.get("max_rounds", 20))
	var your_seat := int(state.get("your_seat", 0))
	var turn_seat := int(state.get("turn_seat", 0))
	var dealer_seat := int(state.get("dealer_seat", 0))
	var trump: String = state.get("trump_suit", "none")

	var players: Array = state.get("players", [])
	var outcomes: Array[int] = []
	if your_seat >= 0 and your_seat < players.size():
		var rh: Array = players[your_seat].get("round_history", [])
		for entry in rh:
			var d := int(entry.get("delta", 0))
			outcomes.append(1 if d > 0 else (-1 if d < 0 else 0))
	_round_lbl.text = "Runde %d / %d" % [round_num, max_rounds]
	_round_timeline.set_progress(round_num, max_rounds, outcomes)

	var trump_col: Color = SUIT_BADGE_COLORS.get(trump, Color("#3F352C"))
	var trump_style: StyleBoxFlat = _trump_pill.get_theme_stylebox("normal").duplicate()
	trump_style.bg_color = trump_col
	_trump_pill.add_theme_stylebox_override("normal", trump_style)
	if trump == "none":
		_trump_pill.text = "Kein Trumpf"
	elif trump == "pending":
		_trump_pill.text = "Trumpf: ? Wahl"
	else:
		var t_sym: String = CardView.SUIT_SYMBOLS.get(trump, "")
		_trump_pill.text = ("Trumpf: %s %s" % [t_sym, WizardRules.suit_label(trump)]).strip_edges()

	# SFX & Sparks transitions (burst on BOTH card landing & Rune center!)
	if animate_deal:
		_audio.play("deal")
	var trick_cards: Array = state.get("trick_cards", [])
	if trick_cards.size() > prev_trick_cnt and not trick_cards.is_empty():
		var newest: Dictionary = trick_cards[trick_cards.size() - 1]["card"]
		var nkind := str(newest.get("kind", "num"))
		if nkind == "wizard":
			_audio.feedback("wizard", 40, 0.85)
			_emit_sparks_arena(Color("#C084FC"), 48)
		elif nkind == "jester":
			_audio.play("jester")
			_emit_sparks_arena(Color("#2DD4BF"), 24)
		else:
			_audio.play("play")
			_emit_sparks_arena(Color("#F59E0B"), 22)
	var cur_winner := int(state.get("trick_winner_seat", -1))
	if cur_winner >= 0 and prev_trick_winner == -1:
		_audio.feedback("trick_win", 45, 0.9)
		_emit_sparks_arena(Color("#FBBF24"), 52)
	if (phase == "round_end" or phase == "game_end") and prev_phase != phase:
		if your_seat >= 0 and your_seat < players.size():
			var myp: Dictionary = players[your_seat]
			if int(myp.get("last_round_delta", 0)) > 0:
				_audio.feedback("trick_win", 50, 0.95)
				_emit_sparks_arena(Color("#34D399"), 56)

	# All players arranged cleanly across responsive wrapped rows (no scrollbars!)
	for c in _players_strip.get_children():
		c.queue_free()
	var vw := get_viewport_rect().size.x
	if vw < 10.0:
		vw = 720.0
	var pcount := players.size()
	var cols := 3
	if vw >= 920.0:
		cols = mini(maxi(1, pcount), 6)
	elif pcount == 4:
		cols = 2
	elif pcount <= 3:
		cols = maxi(1, pcount)
	else:
		cols = 3
	_players_strip.columns = cols

	for p in players:
		var seat_i := int(p.get("seat", 0))
		var active := (seat_i == turn_seat and phase != "round_end" and phase != "game_end")
		var is_me := (seat_i == your_seat)
		var border_col := Color("#FBBF24") if active else (Color(0.56, 0.80, 0.98, 0.45) if is_me else Color(0.75, 0.56, 0.28, 0.30))
		var bg_col := Color("#3B1D09") if active else Color(0.08, 0.055, 0.04, 0.88)
		var box := PanelContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.custom_minimum_size = Vector2(0, 74)
		box.add_theme_stylebox_override("panel", _make_panel_style(bg_col, 11, border_col, 3 if active else 1))
		_players_strip.add_child(box)

		var bm := MarginContainer.new()
		bm.add_theme_constant_override("margin_left", 8)
		bm.add_theme_constant_override("margin_right", 8)
		bm.add_theme_constant_override("margin_top", 6)
		bm.add_theme_constant_override("margin_bottom", 6)
		box.add_child(bm)

		var bv := VBoxContainer.new()
		bv.add_theme_constant_override("separation", 3)
		bm.add_child(bv)

		var top_r := HBoxContainer.new()
		top_r.add_theme_constant_override("separation", 4)
		bv.add_child(top_r)

		var d_tag := " [G]" if seat_i == dealer_seat else ""
		var turn_prefix := "▶ " if active else ""
		var nm_col := Color("#FDE047") if active else (Color("#BAE6FD") if is_me else Color("#F5E6CA"))
		var p_nm := _make_label(turn_prefix + str(p.get("name", "?")) + d_tag, 15, nm_col, HORIZONTAL_ALIGNMENT_LEFT, active)
		p_nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p_nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		top_r.add_child(p_nm)

		if active:
			var am_zug := _make_label("AM ZUG", 12, Color("#1E0F05"), HORIZONTAL_ALIGNMENT_CENTER, true)
			var az_st := _make_panel_style(Color("#F59E0B"), 6, Color("#FEF08A"), 1)
			az_st.content_margin_left = 7
			az_st.content_margin_right = 7
			az_st.content_margin_top = 2
			az_st.content_margin_bottom = 2
			am_zug.add_theme_stylebox_override("normal", az_st)
			top_r.add_child(am_zug)
		else:
			if _card_back_tex != null:
				var cb_icon := TextureRect.new()
				cb_icon.texture = _card_back_tex
				cb_icon.custom_minimum_size = Vector2(13, 17)
				cb_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				cb_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				top_r.add_child(cb_icon)
			var cnt_lbl := _make_label(str(int(p.get("card_count", 0))), 13, Color("#E7D3B0"))
			top_r.add_child(cnt_lbl)

		var bid_i := int(p.get("bid", -1))
		var won_i := int(p.get("tricks_won", 0))
		var bid_txt := "-" if bid_i < 0 else str(bid_i)
		var sc_lbl := _make_label("%d/%s St. • %d Pkt" % [won_i, bid_txt, int(p.get("score", 0))], 13, Color("#E2CFB4"))
		bv.add_child(sc_lbl)

		var pips := ProgressWidgets.TrickPipsRow.new()
		pips.set_stats(bid_i, won_i)
		bv.add_child(pips)

	# Unmistakable Turn Clarity Banner + Glowing Arena Highlight
	var is_my_turn := (turn_seat == your_seat and cur_winner == -1 and phase in ["choose_trump", "bidding", "playing"])
	_is_my_turn_pulse = is_my_turn
	var raw_banner := str(state.get("status_banner", ""))
	if is_my_turn:
		var action_hint := "Karte spielen!" if phase == "playing" else ("Stiche ansagen!" if phase == "bidding" else "Trumpf wählen!")
		_status_banner_lbl.text = "★ DU BIST AM ZUG — %s ★\n%s" % [action_hint, raw_banner]
		_status_banner_lbl.add_theme_color_override("font_color", Color("#FEF08A"))
		_turn_banner_style.bg_color = Color(0.32, 0.14, 0.02, 0.94)
		_turn_banner_style.border_color = Color("#FBBF24")
		if _hand_panel_style != null:
			_hand_panel_style.border_color = Color("#FBBF24")
	else:
		var active_name := "Jemand"
		if turn_seat >= 0 and turn_seat < players.size():
			active_name = str(players[turn_seat].get("name", "?"))
		_status_banner_lbl.text = ("⏳ %s ist am Zug • " % active_name + raw_banner) if phase in ["choose_trump", "bidding", "playing"] else raw_banner
		_status_banner_lbl.add_theme_color_override("font_color", Color("#E7D3B0"))
		_turn_banner_style.bg_color = Color(0.08, 0.05, 0.04, 0.86)
		_turn_banner_style.border_color = Color("#6B4E2A")
		if _hand_panel_style != null:
			_hand_panel_style.border_color = Color(0.62, 0.45, 0.22, 0.42)
	for c in _trick_cards_box.get_children():
		c.queue_free()
	var trump_card: Dictionary = state.get("trump_card", {})
	if phase == "choose_trump" or phase == "bidding":
		if not trump_card.is_empty():
			var tw_box := VBoxContainer.new()
			tw_box.alignment = BoxContainer.ALIGNMENT_CENTER
			tw_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tw_box.add_theme_constant_override("separation", 12)
			_trick_cards_box.add_child(tw_box)
			var tw_lbl := _make_label("Aufgedeckte Trumpfkarte", 15, Color("#FDE68A"), HORIZONTAL_ALIGNMENT_CENTER, true)
			var tw_pill := _make_panel_style(Color(0.03, 0.025, 0.05, 0.90), 99, Color(0.85, 0.62, 0.25, 0.58), 1)
			tw_pill.content_margin_left = 14
			tw_pill.content_margin_right = 14
			tw_pill.content_margin_top = 4
			tw_pill.content_margin_bottom = 4
			tw_lbl.add_theme_stylebox_override("normal", tw_pill)
			tw_lbl.z_index = 4
			tw_box.add_child(tw_lbl)
			var tcv := CardView.new()
			tcv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			tcv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tcv.setup(trump_card, true, false, false, false, false)
			tw_box.add_child(tcv)
	else:
		for i in range(trick_cards.size()):
			var entry: Dictionary = trick_cards[i]
			var slot := VBoxContainer.new()
			slot.alignment = BoxContainer.ALIGNMENT_CENTER
			slot.add_theme_constant_override("separation", 4)
			_trick_cards_box.add_child(slot)
			var cv := CardView.new()
			var p_seat := int(entry.get("seat", entry.get("player_idx", -1)))
			var is_win := (cur_winner != -1 and p_seat == cur_winner)
			cv.setup(entry.get("card", {}), true, is_win, false, true, false)
			cv.rotation_degrees = lerpf(-4.0, 4.0, float(i) / maxf(1.0, float(maxi(1, trick_cards.size() - 1))))
			slot.add_child(cv)
			var p_name := "?"
			if p_seat >= 0 and p_seat < players.size():
				p_name = str(players[p_seat]["name"])
			var who_lbl := _make_label(p_name, 14, Color("#FBBF24") if is_win else Color("#FFFBEB"), HORIZONTAL_ALIGNMENT_CENTER, true)
			var who_pill := _make_panel_style(Color(0.03, 0.025, 0.05, 0.88), 99, Color(0.75, 0.56, 0.24, 0.55), 1)
			who_pill.content_margin_left = 9
			who_pill.content_margin_right = 9
			who_pill.content_margin_top = 2
			who_pill.content_margin_bottom = 2
			who_lbl.add_theme_stylebox_override("normal", who_pill)
			slot.add_child(who_lbl)
			if i == trick_cards.size() - 1 and trick_cards.size() > prev_trick_cnt:
				cv.scale = Vector2(1.18, 1.18)
				cv.modulate.a = 0.55
				var ptw := cv.create_tween().set_parallel(true)
				ptw.tween_property(cv, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				ptw.tween_property(cv, "modulate:a", 1.0, 0.20)

	var lead_suit: String = state.get("lead_suit", "")
	if phase == "playing" and lead_suit != "" and lead_suit != "none":
		_lead_lbl.text = "Angespielte Farbe: %s" % WizardRules.suit_label(lead_suit)
	else:
		_lead_lbl.text = ""

	# Context Action Panel
	_render_phase_actions(state)

	# Player Hand Fan
	var my_turn_play := (phase == "playing" and turn_seat == your_seat and cur_winner == -1)
	_swipe_drop_lbl.visible = my_turn_play
	_swipe_drop_lbl.text = "▲ Auf leuchtende Rune ziehen oder schnell hochwischen ▲"
	_swipe_drop_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.56, 0.85))
	if not _rune_dragging:
		_arena_style.border_color = Color("#F59E0B") if is_my_turn else Color(0.85, 0.60, 0.24, 0.35)

	var hand: Array = state.get("your_hand", [])
	var legal_ids: Array = state.get("legal_card_ids", [])

	if your_seat >= 0 and your_seat < players.size():
		var me: Dictionary = players[your_seat]
		var my_bid := int(me.get("bid", -1))
		var my_won := int(me.get("tricks_won", 0))
		var my_score := int(me.get("score", 0))
		var b_str := "-" if my_bid < 0 else str(my_bid)
		_hand_header_lbl.text = "%s • Stiche %d/%s • %d Pkt" % [str(me.get("name", "Du")), my_won, b_str, my_score]

	# Validate current selection against current hand
	var still_present := false
	for ch in hand:
		if int(ch.get("id", -1)) == _selected_card_id:
			still_present = true
			break
	if not still_present:
		_selected_card_id = -1

	_hand_fan.visible = not hand.is_empty()
	_hand_empty_lbl.visible = hand.is_empty()
	if not hand.is_empty():
		_hand_fan.set_hand(hand, legal_ids, my_turn_play, _selected_card_id, animate_deal)

	_update_play_button(my_turn_play, legal_ids)

func _update_play_button(my_turn_play: bool, legal_ids: Array) -> void:
	if not my_turn_play or _selected_card_id == -1:
		_play_selected_btn.visible = false
		return
	var legal := false
	for lid in legal_ids:
		if int(lid) == _selected_card_id:
			legal = true
			break
	_play_selected_btn.visible = legal
	_play_selected_btn.disabled = false

func _render_phase_actions(state: Dictionary) -> void:
	for c in _phase_action_box.get_children():
		c.queue_free()
	_bid_buttons.clear()

	var phase: String = state.get("phase", "")
	var your_seat := int(state.get("your_seat", 0))
	var turn_seat := int(state.get("turn_seat", 0))
	var round_num := int(state.get("round_number", 1))
	var forbidden_bid := int(state.get("forbidden_bid", -1))
	var bids_sum := int(state.get("bids_sum", 0))
	var plus_minus := bool(state.get("plus_minus_rule", true))

	if phase == "choose_trump" and turn_seat == your_seat:
		_phase_action_panel.visible = true
		var t_lbl := _make_label("Zauberer als Trumpf! Wähle die Trumpffarbe:", 17, Color("#FDE68A"), HORIZONTAL_ALIGNMENT_CENTER, true)
		t_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_phase_action_box.add_child(t_lbl)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		_phase_action_box.add_child(grid)
		var sym_map := {"red": "♦", "blue": "❄", "green": "♣", "yellow": "☀"}
		for suit in WizardRules.SUITS:
			var sc_col: Color = SUIT_BADGE_COLORS[suit]
			var s_txt := "%s  %s" % [sym_map.get(suit, "✦"), WizardRules.suit_label(suit).to_upper()]
			var b := _make_choice_tile_btn(s_txt, sc_col, Color("#FBBF24"), Color("#FFFBEB"), Vector2(0, 66), 20)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var s_copy: String = suit
			b.pressed.connect(func(): _send_choose_trump(s_copy))
			grid.add_child(b)

	elif phase == "bidding" and turn_seat == your_seat:
		_phase_action_panel.visible = true
		var hdr_lbl := _make_label("Deine Stichansage (bisher getippt: %d von %d)" % [bids_sum, round_num], 17, Color("#FDE68A"), HORIZONTAL_ALIGNMENT_CENTER, true)
		hdr_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_phase_action_box.add_child(hdr_lbl)
		if plus_minus and forbidden_bid >= 0:
			var warn_lbl := _make_label("Plus/Minus-Eins-Regel: %d ist verboten (Summe ≠ %d)!" % [forbidden_bid, round_num], 15, Color("#FCA5A5"), HORIZONTAL_ALIGNMENT_CENTER)
			warn_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_phase_action_box.add_child(warn_lbl)

		var flow := HFlowContainer.new()
		flow.alignment = FlowContainer.ALIGNMENT_CENTER
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		_phase_action_box.add_child(flow)
		var tile_sz := Vector2(72, 58) if round_num <= 10 else Vector2(62, 52)
		var tile_font := 23 if round_num <= 10 else 20
		for k in range(round_num + 1):
			var is_forbidden := (plus_minus and k == forbidden_bid)
			var b_label := ("%d ✕" % k) if is_forbidden else str(k)
			var b := _make_choice_tile_btn(
				b_label,
				Color("#3F0D0D") if is_forbidden else Color("#2A190C"),
				Color("#F87171") if is_forbidden else Color("#F59E0B"),
				Color("#FCA5A5") if is_forbidden else Color("#FFFBEB"),
				tile_sz,
				tile_font
			)
			b.disabled = is_forbidden
			if is_forbidden:
				b.tooltip_text = "Summe aller Ansagen darf nicht gleich %d sein!" % round_num
			else:
				var bid_val := k
				b.pressed.connect(func(): _send_bid(bid_val))
			flow.add_child(b)
			_bid_buttons.append(b)

	elif phase == "round_end" or phase == "game_end":
		_phase_action_panel.visible = true
		var players: Array = state.get("players", [])
		var title := "Spielende! Endstand:" if phase == "game_end" else "Rundenwertung"
		_phase_action_box.add_child(_make_label(title, 18, Color("#FDE68A"), HORIZONTAL_ALIGNMENT_CENTER, true))
		var sorted_p := players.duplicate()
		if phase == "game_end":
			sorted_p.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
		for i in range(sorted_p.size()):
			var p: Dictionary = sorted_p[i]
			var delta := int(p.get("last_round_delta", 0))
			var sign_str := "+%d" % delta if delta > 0 else str(delta)
			var col := Color("#34D399") if delta > 0 else Color("#F87171")
			var medal := "🏆 " if (phase == "game_end" and i == 0) else ""
			_phase_action_box.add_child(_make_label("%s%s: %d/%d Stiche (%s) → %d Pkt" % [medal, str(p["name"]), int(p["tricks_won"]), int(p["bid"]), sign_str, int(p["score"])], 15, col, HORIZONTAL_ALIGNMENT_CENTER))

		if _is_host:
			if phase == "round_end":
				var next_btn := _make_btn("Nächste Runde starten", Color("#15803D"), 56, 17)
				next_btn.pressed.connect(func():
					_audio.feedback("deal", 25, 0.7)
					_server.process_next_round()
				)
				_phase_action_box.add_child(next_btn)
			else:
				var again_btn := _make_btn("Zurück in die Lobby", Color("#6D28D9"), 56, 17)
				again_btn.pressed.connect(func():
					_audio.feedback("bid", 25, 0.7)
					_server.host_return_to_lobby()
				)
				_phase_action_box.add_child(again_btn)
		else:
			_phase_action_box.add_child(_make_label("Warte auf den Gastgeber...", 13, Color("#94A3B8"), HORIZONTAL_ALIGNMENT_CENTER))
	else:
		_phase_action_panel.visible = false

# --- HandFan Callbacks & Play Actions ---

func _on_hand_card_scrubbed(_idx: int, _card_data: Dictionary) -> void:
	_audio.play("scrub", 0.08)
	_audio.haptic(8, 0.35)

func _on_hand_card_selected(card_id: int, _card_data: Dictionary) -> void:
	_selected_card_id = card_id
	var phase: String = _last_state.get("phase", "")
	var your_seat := int(_last_state.get("your_seat", 0))
	var turn_seat := int(_last_state.get("turn_seat", 0))
	var my_turn_play := (phase == "playing" and turn_seat == your_seat and int(_last_state.get("trick_winner_seat", -1)) == -1)
	_update_play_button(my_turn_play, _last_state.get("legal_card_ids", []))

func _on_drag_state_changed(dragging: bool, ready_to_play: bool, legal: bool) -> void:
	_rune_dragging = dragging
	_rune_ready = (dragging and ready_to_play and legal)
	_rune_illegal = (dragging and not legal)
	if not dragging:
		var my_turn_play: bool = (_last_state.get("phase", "") == "playing" and int(_last_state.get("turn_seat", 0)) == int(_last_state.get("your_seat", 0)))
		_swipe_drop_lbl.visible = my_turn_play
		_swipe_drop_lbl.text = "▲ Auf leuchtende Rune ziehen oder schnell hochwischen ▲"
		_swipe_drop_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.56, 0.82))
		_arena_style.border_color = Color("#F59E0B") if my_turn_play else Color(0.85, 0.60, 0.24, 0.35)
		_update_play_button(my_turn_play, _last_state.get("legal_card_ids", []))
		return
	_play_selected_btn.visible = false
	_swipe_drop_lbl.visible = true
	if not legal:
		_swipe_drop_lbl.text = "✕ Nicht spielbar / Nicht an der Reihe ✕"
		_swipe_drop_lbl.add_theme_color_override("font_color", Color("#FCA5A5"))
		_arena_style.border_color = Color("#EF4444")
	elif ready_to_play:
		_swipe_drop_lbl.text = "✦ AUF RUNE FALLEN LASSEN! ✦"
		_swipe_drop_lbl.add_theme_color_override("font_color", Color("#FEF08A"))
		_arena_style.border_color = Color("#FDE047")
	else:
		_swipe_drop_lbl.text = "▲ Weiter zur leuchtenden Rune ziehen... ▲"
		_swipe_drop_lbl.add_theme_color_override("font_color", Color("#FCD34D"))
		_arena_style.border_color = Color("#F59E0B")

func _on_hand_card_swiped(card_id: int, global_origin: Vector2) -> void:
	_emit_sparks_at(global_origin, Color("#F59E0B"), 28)
	_emit_sparks_arena(Color("#38BDF8"), 34)
	_audio.haptic(25, 0.75)
	_play_card_by_id(card_id)

func _on_illegal_swipe(_card_id: int, _global_origin: Vector2) -> void:
	_audio.feedback("error", 50, 0.85)
	var phase: String = _last_state.get("phase", "")
	if phase != "playing":
		_show_toast("Erst ansagen — danach werden Karten gespielt!")
	elif int(_last_state.get("trick_winner_seat", -1)) != -1:
		_show_toast("Stich wird gerade ausgewertet...")
	elif int(_last_state.get("turn_seat", -1)) != int(_last_state.get("your_seat", 0)):
		_show_toast("Du bist gerade nicht an der Reihe.")
	else:
		_show_toast("Bedienpflicht! Du musst die angespielte Farbe bedienen (oder Zauberer/Narr spielen).")

func _on_play_selected_pressed() -> void:
	if _selected_card_id == -1:
		return
	_audio.haptic(22, 0.7)
	_play_card_by_id(_selected_card_id)

func _play_card_by_id(cid: int) -> void:
	_selected_card_id = -1
	if _is_host:
		_server.process_play_card(0, cid)
	else:
		_client.send_play_card(cid)

func _send_choose_trump(suit: String) -> void:
	_audio.feedback("wizard", 30, 0.8)
	if _is_host:
		_server.process_choose_trump(0, suit)
	else:
		_client.send_choose_trump(suit)

func _send_bid(amount: int) -> void:
	_audio.feedback("bid", 22, 0.65)
	if _is_host:
		_server.process_bid(0, amount)
	else:
		_client.send_bid(amount)

# --- Modals ---

func _clear_modal_body() -> void:
	for c in _modal_body_box.get_children():
		c.queue_free()

func _show_scorecard_modal() -> void:
	_audio.play("scrub", 0.05)
	_modal_title.text = "Sternenhimmel der Wahrheit"
	_clear_modal_body()

	var players: Array = _last_state.get("players", [])
	if players.is_empty():
		_modal_body_box.add_child(_make_label("Noch keine Spieldaten.", 15))
		_modal_backdrop.visible = true
		return

	_score_chart = ProgressWidgets.ScoreChart.new()
	_score_chart.set_players(players)
	_modal_body_box.add_child(_score_chart)

	# Crisp 5-column summary table matching web companion
	var sorted_p := players.duplicate()
	sorted_p.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))
	var tbl_panel := PanelContainer.new()
	tbl_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.04, 0.03, 0.82), 10, Color(0.55, 0.40, 0.20, 0.45), 1))
	_modal_body_box.add_child(tbl_panel)

	var tbl := GridContainer.new()
	tbl.columns = 5
	tbl.add_theme_constant_override("h_separation", 10)
	tbl.add_theme_constant_override("v_separation", 6)
	tbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tbl_panel.add_child(tbl)

	for hdr_txt in ["Spieler", "Tipp", "Stiche", "+/-", "Gesamt"]:
		var h_align := HORIZONTAL_ALIGNMENT_LEFT if hdr_txt == "Spieler" else HORIZONTAL_ALIGNMENT_RIGHT
		var hl := _make_label(hdr_txt, 15, Color("#F59E0B"), h_align, true)
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tbl.add_child(hl)

	var phase := str(_last_state.get("phase", ""))
	for idx in range(sorted_p.size()):
		var p: Dictionary = sorted_p[idx]
		var nm := str(p.get("name", "?"))
		if phase == "game_end" and idx == 0:
			nm = "🏆 " + nm
		var bid_i := int(p.get("bid", -1))
		var bid_str := "-" if bid_i < 0 else str(bid_i)
		var delta := int(p.get("last_round_delta", 0))
		var d_str := ("+%d" % delta) if delta > 0 else str(delta)
		var d_col := Color("#34D399") if delta > 0 else (Color("#F87171") if delta < 0 else Color("#E7D3B0"))

		var c0 := _make_label(nm, 15, Color("#FFFBEB"), HORIZONTAL_ALIGNMENT_LEFT)
		c0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c1 := _make_label(bid_str, 15, Color("#E7D3B0"), HORIZONTAL_ALIGNMENT_RIGHT)
		var c2 := _make_label(str(int(p.get("tricks_won", 0))), 15, Color("#E7D3B0"), HORIZONTAL_ALIGNMENT_RIGHT)
		var c3 := _make_label(d_str, 15, d_col, HORIZONTAL_ALIGNMENT_RIGHT, true)
		var c4 := _make_label(str(int(p.get("score", 0))), 15, Color("#FDE68A"), HORIZONTAL_ALIGNMENT_RIGHT, true)
		tbl.add_child(c0)
		tbl.add_child(c1)
		tbl.add_child(c2)
		tbl.add_child(c3)
		tbl.add_child(c4)

	var rounds_done: int = players[0].get("round_history", []).size()
	if rounds_done > 0:
		var lines := "\nRunden-Protokoll:\n"
		for r_idx in range(rounds_done):
			var row_txt := "R%d: " % (r_idx + 1)
			var parts: Array[String] = []
			for p in players:
				var h: Array = p.get("round_history", [])
				if r_idx < h.size():
					var item: Dictionary = h[r_idx]
					var d := int(item.get("delta", 0))
					var s := "+%d" % d if d > 0 else str(d)
					parts.append("%s %d/%d (%s→%d)" % [str(p.get("name", "?")).left(12), int(item.get("won", 0)), int(item.get("bid", 0)), s, int(item.get("total", 0))])
			lines += row_txt + " · ".join(parts) + "\n"
		var r_lbl := _make_label(lines, 14, Color("#E2CFB4"))
		r_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_modal_body_box.add_child(r_lbl)

	_modal_backdrop.visible = true

func _show_rules_modal() -> void:
	_audio.play("scrub", 0.05)
	_modal_title.text = "Offizielle Wizard-Regeln"
	_clear_modal_body()
	_rules_rich = RichTextLabel.new()
	_rules_rich.fit_content = true
	_rules_rich.add_theme_font_size_override("normal_font_size", 14)
	_rules_rich.add_theme_color_override("default_color", Color("#E2E8F0"))
	_rules_rich.text = """BLATT (60 KARTEN)
• 4 Farben (Rot, Blau, Grün, Gelb) je Werte 1–13
• 4 Zauberer (stechen jede Karte)
• 4 Narren (verlieren jeden Stich, außer alle spielen Narren)

RUNDEN & TRUMPF
• Runde R teilt R Karten pro Spieler aus (60 / Spieleranzahl Runden; z. B. 20 bei 3, 15 bei 4, 12 bei 5, 10 bei 6).
• Die nächste Karte bestimmt Trumpf:
  - Farbzahl → diese Farbe ist Trumpf
  - Zauberer → der Geber wählt die Trumpffarbe
  - Narr oder letzte Runde → Kein Trumpf

STICHANSAGE & PLUS/MINUS-EINS-REGEL
• Jeder tippt vorab, wie viele Stiche er in dieser Runde gewinnt.
• Offizielle Turnierregel: Die Summe aller Ansagen darf NICHT gleich der Rundenzahl sein! Der letzte Spieler darf den fehlenden Wert deshalb nicht ansagen (lässt sich in der Lobby umschalten).

STICH REGELN
• Zauberer & Narren dürfen immer gespielt werden.
• Ansonsten muss die erste angespielte Farbe bedient werden (Bedienpflicht).
• Wird ein Narr angespielt, gibt die erste danach gespielte Farbkarte die Farbe vor.
• Wird ein Zauberer angespielt, gibt es keine Bedienpflicht.
• Der erste gespielte Zauberer gewinnt den Stich. Sonst sticht der höchste Trumpf, sonst die höchste Karte der angespielten Farbe. Spielen alle Narren, gewinnt der erste Narr.

WERTUNG
• Exakt getippt: +20 Punkte + 10 Punkte je gewonnenem Stich.
• Daneben getippt: -10 Punkte pro Stich Abweichung."""
	_modal_body_box.add_child(_rules_rich)
	_modal_backdrop.visible = true

func _show_crossplay_modal() -> void:
	_audio.play("scrub", 0.05)
	_modal_title.text = "Android & iOS gemeinsam spielen"
	_clear_modal_body()
	var info := _make_label("""So funktioniert Crossplay zwischen Android & iOS ganz ohne App-Store oder Internet-Server:

1. ALLE Geräte verbinden sich mit demselben WLAN oder einem mobilen Handy-Hotspot (funktioniert sogar offline im Zug oder Garten).
2. Ein Android-Gerät tippt auf "Tisch eröffnen (Host)".
3. Andere Android-Spieler mit dieser App sehen den Tisch sofort unter "Tische im selben WLAN".
4. iPhone-/iPad-Kollegen scannen einfach den QR-Code in der Lobby mit ihrer Kamera-App: Safari öffnet den vollwertigen Zaubera-Begleiter automatisch mit identischen Regeln, UNO-Kartenfächer, Hochwischen und Sound!""", 14, Color("#E2E8F0"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_body_box.add_child(info)
	_modal_backdrop.visible = true

# --- Test Helpers ---

func get_server() -> WizardServer:
	return _server

func get_hand_fan() -> HandFan:
	return _hand_fan

func get_bid_buttons() -> Array[Button]:
	return _bid_buttons

func get_qr_panel() -> PanelContainer:
	return _qr_panel

func trigger_host_for_test(host_name: String) -> void:
	_name_input.text = host_name
	_on_host_pressed()
