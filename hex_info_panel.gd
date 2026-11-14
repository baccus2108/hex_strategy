class_name HexInfoPanel
extends PanelContainer
## Seçilen hex'in DEBUG kartı (sol üst): q,r, ülke, terrain, km². Editör açıkken kara/deniz ve ülke atama düğmeleri.
## Haritada ülke/şehir adı gösterilmez; ad sadece bu panelde görünür.

signal toggle_land_pressed
signal assign_country_pressed(country_id: String)

const FONT_BOLD := "res://assets/fonts/Barlow-SemiBold.ttf"
const FONT_BODY := "res://assets/fonts/Barlow-Medium.ttf"

const BG_COLOR := Color(0.05, 0.08, 0.13, 0.92)
const ACCENT := Color(0.80, 0.68, 0.36)
const KICKER_COLOR := Color(0.62, 0.68, 0.78)
const TEXT_COLOR := Color(0.93, 0.95, 0.98)
const MUTED_COLOR := Color(0.66, 0.72, 0.80)
const WARN_COLOR := Color(1.0, 0.65, 0.35)
const CARD_WIDTH := 264.0
const BUTTON_MIN_HEIGHT := 44.0
const TERRAIN_NAMES := {"ova": "Ova", "yayla": "Yayla", "daglik": "Dağlık", "col": "Çöl", "tundra": "Tundra"}
const SRC_NAMES := {"guarantee": "Küçük ülke koruması", "rescue": "Zincir kurtarma", "override": "Override (hex_overrides.json)", "editor": "Editör (az önce)"}

var _bold: Font
var _body: Font
var _kicker: Label
var _title: Label
var _swatch: ColorRect
var _meta: Label
var _terrain_value: Label
var _area_value: Label
var _others_value: Label
var _note: Label
var _edit_box: VBoxContainer
var _land_button: Button
var _country_picker: OptionButton
var _assign_button: Button
var _status: Label
var _choice_ids: PackedStringArray = []
var _info: Dictionary = {}


func _ready() -> void:
	_bold = load(FONT_BOLD) as Font
	_body = load(FONT_BODY) as Font
	position = Vector2(16, 16)
	custom_minimum_size.x = CARD_WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP

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

	_kicker = _make_label("", 11, _bold, KICKER_COLOR)
	box.add_child(_kicker)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(12, 12)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_swatch)
	_title = _make_label("", 22, _bold, TEXT_COLOR)
	row.add_child(_title)
	box.add_child(row)
	_meta = _make_label("", 13, _body, MUTED_COLOR)
	box.add_child(_meta)
	box.add_child(_make_separator())

	box.add_child(_make_label(tr("TERRAIN"), 11, _bold, KICKER_COLOR))
	_terrain_value = _make_wrapped(14, TEXT_COLOR)
	box.add_child(_terrain_value)
	box.add_child(_make_label(tr("ALAN (KM²)"), 11, _bold, KICKER_COLOR))
	_area_value = _make_wrapped(14, TEXT_COLOR)
	box.add_child(_area_value)
	_others_value = _make_wrapped(13, MUTED_COLOR)
	box.add_child(_others_value)
	_note = _make_wrapped(13, WARN_COLOR)
	box.add_child(_note)

	_edit_box = VBoxContainer.new()
	_edit_box.add_theme_constant_override("separation", 6)
	_edit_box.add_child(_make_separator())
	_edit_box.add_child(_make_label(tr("EDİTÖR"), 11, _bold, ACCENT))
	_land_button = _make_button(tr("Kara ↔ Deniz"))
	_land_button.pressed.connect(func() -> void: toggle_land_pressed.emit())
	_edit_box.add_child(_land_button)
	_country_picker = OptionButton.new()
	_country_picker.custom_minimum_size.y = BUTTON_MIN_HEIGHT
	_country_picker.focus_mode = Control.FOCUS_NONE
	_edit_box.add_child(_country_picker)
	_assign_button = _make_button(tr("Seçili ülkeyi ata"))
	_assign_button.pressed.connect(_on_assign_pressed)
	_edit_box.add_child(_assign_button)
	_status = _make_wrapped(12, MUTED_COLOR)
	_edit_box.add_child(_status)
	_edit_box.visible = false
	box.add_child(_edit_box)
	visible = false


## Editör için ülke listesi: [{id, name}, ...] (ada göre sıralı).
func set_country_choices(choices: Array) -> void:
	_country_picker.clear()
	_choice_ids = PackedStringArray()
	for c: Dictionary in choices:
		_country_picker.add_item(str(c["name"]))
		_choice_ids.append(str(c["id"]))


func set_editor(on: bool) -> void:
	_edit_box.visible = on
	reset_size.call_deferred()


func set_status(text: String) -> void:
	_status.text = text


func selected_country_id() -> String:
	var i := _country_picker.selected
	return _choice_ids[i] if i >= 0 and i < _choice_ids.size() else ""


func _on_assign_pressed() -> void:
	var cid := selected_country_id()
	if cid != "":
		assign_country_pressed.emit(cid)


## info: HexMap.describe_hex() sözlüğü.
func show_hex(info: Dictionary) -> void:
	_info = info
	var land: bool = info["land"]
	_kicker.text = "%s · q=%d, r=%d" % [tr("HEX"), info["q"], info["r"]]
	_swatch.color = info["color"]
	_swatch.visible = land
	_title.text = info["country_name"] if land else tr("Okyanus")
	_meta.text = "%s · %s%s" % [info["country_id"] if land else "—", tr("kara oranı %%%d") % roundi(float(info["frac"]) * 100.0),
			" · " + tr("kıyı") if info["coast"] else ""]

	if land and info["terrain"] != "":
		_terrain_value.text = "%s · %s" % [tr(TERRAIN_NAMES.get(info["terrain"], str(info["terrain"]))), tr("ort. %d m") % int(info["elev"])]
	elif land:
		_terrain_value.text = tr("bilinmiyor (betiği çalıştır)")
	else:
		_terrain_value.text = "—"

	if land:
		_area_value.text = "%s: %s\n%s: %s" % [tr("Ülke karası"), _fmt_km2(float(info["owner_km2"])),
				tr("Hex karası"), _fmt_km2(float(info["total_km2"]))]
	else:
		_area_value.text = "—"
	var others: Array = info["others"]
	_others_value.visible = not others.is_empty()
	var lines := PackedStringArray()
	for o: Dictionary in others:
		lines.append("+ %s: %s" % [o["name"], _fmt_km2(float(o["km2"]))])
	_others_value.text = "\n".join(lines)

	var notes := PackedStringArray()
	var src: String = info["src"]
	if SRC_NAMES.has(src):
		notes.append(tr(SRC_NAMES[src]))
	if bool(info["override"]) and src != "override" and src != "editor":
		notes.append(tr("Override var"))
	_note.text = "\n".join(notes)
	_note.visible = not notes.is_empty()

	var sug: String = info["suggested_country"]
	var pick := _choice_ids.find(info["country_id"] if land else sug)
	if pick >= 0:
		_country_picker.select(pick)
	_land_button.text = tr("Denize çevir") if land else tr("Karaya çevir (seçili ülke)")
	visible = true
	reset_size.call_deferred()


func hide_panel() -> void:
	visible = false


static func _fmt_km2(v: float) -> String:
	var s := str(int(roundf(v)))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += "."
		out += s[i]
	return out


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = BUTTON_MIN_HEIGHT
	return b


func _make_wrapped(size: int, color: Color) -> Label:
	var l := _make_label("", size, _body, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = CARD_WIDTH - 28.0
	return l


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
