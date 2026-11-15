class_name CardView
extends PanelContainer

signal card_clicked(card_id: int)

var card_data: Dictionary = {}
var playable := true
var selected := false
var interactive := true
var compact := false
var managed_by_fan := false

var _top_lbl: Label
var _top_suit_lbl: Label
var _emblem_rect: TextureRect
var _center_val: Label
var _suit_lbl: Label
var _bottom_corner_lbl: Label
var _inner_panel: Panel
var _wood_frame_rect: TextureRect
var _glow_phase := 0.0
var _suit_glow_col := Color("#F59E0B")
var _style := StyleBoxFlat.new()
var _inner_style := StyleBoxFlat.new()
var _badge_style := StyleBoxFlat.new()

static var _tex_cache := {}
static var _wood_frame_tex: Texture2D = null
static var _title_font: Font = null
static var _body_font: Font = null

const SUIT_GLOW_COLORS := {
	"red": Color("#F97316"),
	"blue": Color("#38BDF8"),
	"green": Color("#34D399"),
	"yellow": Color("#FBBF24"),
	"wizard": Color("#C084FC"),
	"jester": Color("#2DD4BF")
}

const SUIT_TEXTURES := {
	"red": "res://assets/cards/suit_red.png",
	"blue": "res://assets/cards/suit_blue.png",
	"green": "res://assets/cards/suit_green.png",
	"yellow": "res://assets/cards/suit_yellow.png",
	"wizard": "res://assets/cards/special_wizard.png",
	"jester": "res://assets/cards/special_jester.png"
}

const SUIT_COLORS := {
	"red": Color("#C81E2B"),
	"blue": Color("#1D4ED8"),
	"green": Color("#15803D"),
	"yellow": Color("#D97706"),
	"wizard": Color("#5B21B6"),
	"jester": Color("#0F766E")
}

const SUIT_INNER_COLORS := {
	"red": Color("#991B1B"),
	"blue": Color("#1E3A8A"),
	"green": Color("#14532D"),
	"yellow": Color("#B45309"),
	"wizard": Color("#3B0764"),
	"jester": Color("#115E59")
}

const SUIT_SYMBOLS := {
	"red": "◆",
	"blue": "❄",
	"green": "♣",
	"yellow": "☀",
	"wizard": "★",
	"jester": "✦"
}

const SUIT_TEXT := {
	"red": "ROT",
	"blue": "BLAU",
	"green": "GRÜN",
	"yellow": "GELB",
	"wizard": "ZAUBERER",
	"jester": "NARR"
}

static func _get_emblem_texture(key: String) -> Texture2D:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var path: String = SUIT_TEXTURES.get(key, "")
	if not path.is_empty() and ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		_tex_cache[key] = tex
		return tex
	return null

static func _ensure_theme_res() -> void:
	if _wood_frame_tex == null and ResourceLoader.exists("res://assets/ui/wood_card_frame.png"):
		_wood_frame_tex = load("res://assets/ui/wood_card_frame.png")
	if _title_font == null and ResourceLoader.exists("res://assets/fonts/Cinzel-Bold.ttf"):
		_title_font = load("res://assets/fonts/Cinzel-Bold.ttf")
	if _body_font == null and ResourceLoader.exists("res://assets/fonts/CrimsonPro-SemiBold.ttf"):
		_body_font = load("res://assets/fonts/CrimsonPro-SemiBold.ttf")

func _init() -> void:
	_ensure_theme_res()
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	_glow_phase = randf() * TAU

	_style.set_corner_radius_all(14)
	_style.set_border_width_all(2)
	_style.border_color = Color(0.85, 0.62, 0.25, 0.45)
	_style.shadow_color = Color(0.96, 0.62, 0.14, 0.35)
	_style.shadow_size = 12
	_style.shadow_offset = Vector2(0, 3)
	add_theme_stylebox_override("panel", _style)

	# Rich stained-enamel interior inside carved wooden card frame
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_inner_panel = Panel.new()
	_inner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inner_panel.offset_left = 7
	_inner_panel.offset_top = 7
	_inner_panel.offset_right = -7
	_inner_panel.offset_bottom = -7
	_inner_style.set_corner_radius_all(10)
	_inner_style.set_border_width_all(1)
	_inner_style.border_color = Color(0.96, 0.80, 0.42, 0.35)
	_inner_panel.add_theme_stylebox_override("panel", _inner_style)
	root.add_child(_inner_panel)

	# Dark obsidian arcane oval behind 3D Blender emblem
	var emblem_badge := Panel.new()
	emblem_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem_badge.set_anchors_preset(Control.PRESET_CENTER)
	emblem_badge.offset_left = -33
	emblem_badge.offset_top = -48
	emblem_badge.offset_right = 33
	emblem_badge.offset_bottom = 18
	_badge_style.bg_color = Color(0.05, 0.04, 0.08, 0.46)
	_badge_style.set_corner_radius_all(33)
	_badge_style.set_border_width_all(1)
	_badge_style.border_color = Color(0.95, 0.78, 0.35, 0.38)
	emblem_badge.add_theme_stylebox_override("panel", _badge_style)
	root.add_child(emblem_badge)

	_emblem_rect = TextureRect.new()
	_emblem_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblem_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_emblem_rect.offset_left = 4
	_emblem_rect.offset_top = 4
	_emblem_rect.offset_right = -4
	_emblem_rect.offset_bottom = -4
	_emblem_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem_badge.add_child(_emblem_rect)

	# Blender Carved Oak Wood Frame overlay with brass rivets
	_wood_frame_rect = TextureRect.new()
	_wood_frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wood_frame_rect.texture = _wood_frame_tex
	_wood_frame_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wood_frame_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wood_frame_rect.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(_wood_frame_rect)

	# Top-left corner stack tucked neatly inside the brass bevel
	var corner_box := VBoxContainer.new()
	corner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	corner_box.offset_left = 13
	corner_box.offset_top = 11
	corner_box.offset_right = 58
	corner_box.offset_bottom = 62
	corner_box.add_theme_constant_override("separation", -3)
	root.add_child(corner_box)

	_top_lbl = Label.new()
	_top_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_top_lbl.add_theme_font_size_override("font_size", 21)
	_top_lbl.add_theme_color_override("font_color", Color("#FFFBEB"))
	_top_lbl.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.01, 0.85))
	_top_lbl.add_theme_constant_override("outline_size", 4)
	if _title_font != null:
		_top_lbl.add_theme_font_override("font", _title_font)
	corner_box.add_child(_top_lbl)

	_top_suit_lbl = Label.new()
	_top_suit_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_suit_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_top_suit_lbl.add_theme_font_size_override("font_size", 13)
	_top_suit_lbl.add_theme_color_override("font_color", Color("#FEF3C7"))
	corner_box.add_child(_top_suit_lbl)

	# Bottom centerpiece number & German suit title
	var bottom_box := VBoxContainer.new()
	bottom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_box.offset_left = 8
	bottom_box.offset_top = -54
	bottom_box.offset_right = -8
	bottom_box.offset_bottom = -10
	bottom_box.add_theme_constant_override("separation", -2)
	root.add_child(bottom_box)

	_center_val = Label.new()
	_center_val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_val.add_theme_font_size_override("font_size", 24)
	_center_val.add_theme_color_override("font_color", Color("#FFFBEB"))
	_center_val.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.01, 0.85))
	_center_val.add_theme_constant_override("outline_size", 4)
	if _title_font != null:
		_center_val.add_theme_font_override("font", _title_font)
	bottom_box.add_child(_center_val)

	_suit_lbl = Label.new()
	_suit_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_suit_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_suit_lbl.add_theme_font_size_override("font_size", 11)
	_suit_lbl.add_theme_color_override("font_color", Color("#FDE68A"))
	if _body_font != null:
		_suit_lbl.add_theme_font_override("font", _body_font)
	bottom_box.add_child(_suit_lbl)

	# Subtle bottom-right mirrored corner index
	_bottom_corner_lbl = Label.new()
	_bottom_corner_lbl.visible = false
	_bottom_corner_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_corner_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_bottom_corner_lbl.offset_left = -38
	_bottom_corner_lbl.offset_top = -30
	_bottom_corner_lbl.offset_right = -11
	_bottom_corner_lbl.offset_bottom = -9
	_bottom_corner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bottom_corner_lbl.add_theme_font_size_override("font_size", 14)
	_bottom_corner_lbl.add_theme_color_override("font_color", Color(1.0, 0.96, 0.85, 0.82))
	if _title_font != null:
		_bottom_corner_lbl.add_theme_font_override("font", _title_font)
	root.add_child(_bottom_corner_lbl)

	resized.connect(_sync_pivot)

func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_glow_phase += delta * (3.2 if selected else 1.8)
	var pulse := 0.5 + 0.5 * sin(_glow_phase)
	if selected:
		_style.shadow_color = Color("#FBBF24").lerp(Color("#FEF08A"), pulse * 0.45)
		_style.shadow_color.a = lerpf(0.55, 0.82, pulse)
		_style.shadow_size = int(lerpf(14.0, 20.0, pulse))
	elif playable:
		var base_a := 0.42 if (card_data.get("kind", "num") == "wizard" or not interactive) else 0.30
		_style.shadow_color = Color(_suit_glow_col.r, _suit_glow_col.g, _suit_glow_col.b, lerpf(base_a * 0.65, base_a * 1.15, pulse))
		_style.shadow_size = int(lerpf(9.0, 15.0, pulse))
	else:
		_style.shadow_color = Color(0, 0, 0, 0.25)
		_style.shadow_size = 5

func _sync_pivot() -> void:
	pivot_offset = size * 0.5

func setup(p_card: Dictionary, p_playable: bool = true, p_selected: bool = false, p_interactive: bool = true, p_compact: bool = false, p_managed_by_fan: bool = false) -> void:
	card_data = p_card
	playable = p_playable
	selected = p_selected
	interactive = p_interactive
	compact = p_compact
	managed_by_fan = p_managed_by_fan

	mouse_filter = Control.MOUSE_FILTER_IGNORE if managed_by_fan else Control.MOUSE_FILTER_STOP

	if compact:
		custom_minimum_size = Vector2(96, 138)
		size = Vector2(96, 138)
		_top_lbl.add_theme_font_size_override("font_size", 17)
		_top_suit_lbl.add_theme_font_size_override("font_size", 11)
		_center_val.add_theme_font_size_override("font_size", 21)
		_suit_lbl.add_theme_font_size_override("font_size", 10)
		_bottom_corner_lbl.add_theme_font_size_override("font_size", 12)
	else:
		custom_minimum_size = Vector2(124, 178)
		size = Vector2(124, 178)
		_top_lbl.add_theme_font_size_override("font_size", 22)
		_top_suit_lbl.add_theme_font_size_override("font_size", 14)
		_center_val.add_theme_font_size_override("font_size", 26)
		_suit_lbl.add_theme_font_size_override("font_size", 11)
		_bottom_corner_lbl.add_theme_font_size_override("font_size", 15)
	pivot_offset = size * 0.5

	var kind: String = card_data.get("kind", "num")
	var key := kind if (kind == "wizard" or kind == "jester") else str(card_data.get("suit", "red"))
	var bg: Color = SUIT_COLORS.get(key, Color("#334155"))
	var inner_bg: Color = SUIT_INNER_COLORS.get(key, Color("#1E293B"))
	var sym: String = SUIT_SYMBOLS.get(key, "?")
	var s_txt: String = SUIT_TEXT.get(key, "")

	_emblem_rect.texture = _get_emblem_texture(key)

	if kind == "wizard":
		_top_lbl.text = "Z"
		_center_val.text = "ZAU"
		_center_val.add_theme_font_size_override("font_size", 21)
		_bottom_corner_lbl.text = "Z"
	elif kind == "jester":
		_top_lbl.text = "N"
		_center_val.text = "NARR"
		_center_val.add_theme_font_size_override("font_size", 19)
		_bottom_corner_lbl.text = "N"
	else:
		var val_str := str(int(card_data.get("value", 0)))
		_top_lbl.text = val_str
		_center_val.text = val_str
		_center_val.add_theme_font_size_override("font_size", 25)
		_bottom_corner_lbl.text = val_str

	_top_suit_lbl.text = sym
	_suit_lbl.text = s_txt

	_style.bg_color = bg
	_inner_style.bg_color = inner_bg
	_suit_glow_col = SUIT_GLOW_COLORS.get(key, Color("#F59E0B"))

	if selected:
		_style.border_color = Color("#FBBF24")
		_style.set_border_width_all(3)
		_style.shadow_color = Color(0.98, 0.75, 0.14, 0.72)
		_style.shadow_size = 18
		modulate = Color.WHITE
		if not managed_by_fan:
			position.y = -18.0
	elif not playable and interactive:
		_style.border_color = Color(0.28, 0.24, 0.20, 0.70)
		_style.set_border_width_all(1)
		_style.shadow_color = Color(0, 0, 0, 0.35)
		_style.shadow_size = 5
		# Keep alpha 1.0 so overlapping dimmed cards never bleed through each other
		modulate = Color(0.46, 0.44, 0.48, 1.0)
		if not managed_by_fan:
			position.y = 0.0
	else:
		_style.border_color = Color("#FDE68A") if kind == "wizard" else Color(_suit_glow_col.r, _suit_glow_col.g, _suit_glow_col.b, 0.65)
		_style.set_border_width_all(2)
		_style.shadow_color = Color(_suit_glow_col.r, _suit_glow_col.g, _suit_glow_col.b, 0.42)
		_style.shadow_size = 12
		modulate = Color.WHITE
		if not managed_by_fan:
			position.y = 0.0

func _gui_input(event: InputEvent) -> void:
	if managed_by_fan or not interactive or not playable:
		return
	# Note: project has emulate_touch_from_mouse=true, so handle left-click only to prevent touch+mouse double-fire
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_clicked.emit(int(card_data.get("id", -1)))
