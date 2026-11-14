class_name InfoPanel
extends PanelContainer
## Seçilen bölgenin bilgi kartı (sol üst). Tüm görünüm kodla kurulur; sahnede sadece bu düğüm var.

const FONT_BOLD := "res://assets/fonts/Barlow-SemiBold.ttf"
const FONT_BODY := "res://assets/fonts/Barlow-Medium.ttf"

const BG_COLOR := Color(0.05, 0.08, 0.13, 0.90)
const ACCENT := Color(0.80, 0.68, 0.36)
const KICKER_COLOR := Color(0.62, 0.68, 0.78)
const TEXT_COLOR := Color(0.93, 0.95, 0.98)
const MUTED_COLOR := Color(0.66, 0.72, 0.80)
const CARD_WIDTH := 252.0

var _bold: Font
var _body: Font
var _title: Label
var _swatch: ColorRect
var _country: Label
var _continent: Label
var _tag_box: VBoxContainer
var _tag_value: Label
var _neighbors_kicker: Label
var _neighbors_value: Label


func _ready() -> void:
	_bold = load(FONT_BOLD) as Font
	_body = load(FONT_BODY) as Font
	position = Vector2(16, 16)
	custom_minimum_size.x = CARD_WIDTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = ACCENT
	style.border_width_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	add_child(box)

	box.add_child(_make_label("BÖLGE", 11, _bold, KICKER_COLOR))
	_title = _make_label("", 22, _bold, TEXT_COLOR)
	box.add_child(_title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(11, 11)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_swatch)
	_country = _make_label("", 15, _bold, TEXT_COLOR)
	row.add_child(_country)
	_continent = _make_label("", 13, _body, MUTED_COLOR)
	row.add_child(_continent)
	box.add_child(row)

	box.add_child(_make_separator())

	_tag_box = VBoxContainer.new()
	_tag_box.add_theme_constant_override("separation", 1)
	_tag_box.add_child(_make_label("ÖZELLİK", 11, _bold, KICKER_COLOR))
	_tag_value = _make_label("", 14, _body, TEXT_COLOR)
	_tag_box.add_child(_tag_value)
	box.add_child(_tag_box)

	_neighbors_kicker = _make_label("", 11, _bold, KICKER_COLOR)
	box.add_child(_neighbors_kicker)
	_neighbors_value = _make_label("", 14, _body, TEXT_COLOR)
	_neighbors_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_neighbors_value.custom_minimum_size.x = CARD_WIDTH - 28.0
	box.add_child(_neighbors_value)

	visible = false


func show_region(region: Dictionary, neighbor_names: PackedStringArray) -> void:
	_title.text = region["name"]
	_swatch.color = region["color"]
	_country.text = region["country_name"]
	_continent.text = "· %s" % region["continent"]
	var tag: Variant = region["tag"]
	_tag_box.visible = tag != null
	if tag != null:
		_tag_value.text = str(tag).capitalize()
	_neighbors_kicker.text = "KOMŞU BÖLGELER · %d" % neighbor_names.size()
	_neighbors_value.text = ", ".join(neighbor_names) if not neighbor_names.is_empty() else "Yok (ada)"
	visible = true
	reset_size.call_deferred()


func hide_panel() -> void:
	visible = false


func _make_label(text: String, size: int, font: Font, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _make_separator() -> HSeparator:
	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.14)
	line.thickness = 1
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", line)
	sep.add_theme_constant_override("separation", 10)
	return sep
