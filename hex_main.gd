extends Node2D
## ANA sahne (hex harita): HexMap + HUD (projeksiyon, kara hex hedefi slider'ı, wrap, arazi, editör) + FPS göstergesi.
## Bölge haritası (deney) ayrı sahnedir: "Bölge haritası (H)" düğmesi.
## Komut satırı: godot ... -- --hex-proj=behrmann --hex-target=900 --hex-wrap=1

const REGION_SCENE := "res://scenes/main.tscn"
const BUTTON_MIN_HEIGHT := 44.0   # parmakla basılabilir
const PANEL_BG := Color(0.05, 0.08, 0.13, 0.90)
const TEXT_COLOR := Color(0.93, 0.95, 0.98)
const MUTED_COLOR := Color(0.66, 0.72, 0.80)
const PROJECTION_LABELS := {"behrmann": "Behrmann", "equirect": "Enlem-Boylam", "equal_earth": "Equal Earth"}
const FPS_REFRESH := 0.25

@onready var hex_map: HexMap = $HexMap
@onready var camera: Camera2D = $Camera2D
@onready var info_panel: HexInfoPanel = $HUD/HexInfoPanel

var _counter: Label
var _stats: Label
var _projection_buttons: Dictionary = {}
var _target_slider: HSlider
var _target_label: Label
var _slider_dragging := false
var _wrap_toggle: CheckButton
var _terrain_toggle: CheckButton
var _editor_toggle: CheckButton
var _fps_timer := 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(HexMap.OCEAN_COLOR)
	var proj := hex_map.default_projection()
	var target := hex_map.default_target()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hex-proj="):
			proj = arg.get_slice("=", 1)
		elif arg.begins_with("--hex-target="):
			target = int(arg.get_slice("=", 1))
		elif arg.begins_with("--hex-wrap="):
			hex_map.set_wrap(arg.get_slice("=", 1) != "0")
	if not hex_map.set_variant(proj, target):
		hex_map.set_variant(hex_map.default_projection(), hex_map.default_target())
	hex_map.setup(camera)
	hex_map.hex_selected.connect(info_panel.show_hex)
	hex_map.hex_edited.connect(_on_hex_edited)
	hex_map.selection_cleared.connect(info_panel.hide_panel)
	hex_map.variant_changed.connect(_refresh_hud)
	hex_map.zoom_level_changed.connect(func(_l: int) -> void: _refresh_stats())
	info_panel.set_country_choices(hex_map.country_choices())
	info_panel.toggle_land_pressed.connect(_on_toggle_land)
	info_panel.assign_country_pressed.connect(_on_assign_country)
	_build_hud()
	_refresh_hud()


func _process(delta: float) -> void:
	_fps_timer += delta
	if _fps_timer >= FPS_REFRESH:
		_fps_timer = 0.0
		_refresh_stats()


func _build_hud() -> void:
	var hud: CanvasLayer = $HUD
	# Sağ üst: ayarlar
	var side := _make_panel()
	side.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud.add_child(side)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	side.add_child(box)

	box.add_child(_make_projection_row())

	_target_label = Label.new()
	_target_label.add_theme_color_override("font_color", MUTED_COLOR)
	_target_label.add_theme_font_size_override("font_size", 13)
	box.add_child(_target_label)
	var targets := hex_map.targets()
	_target_slider = HSlider.new()
	_target_slider.min_value = float(targets[0])
	_target_slider.max_value = float(targets[targets.size() - 1])
	_target_slider.step = float(targets[1]) - float(targets[0])
	_target_slider.tick_count = targets.size()
	_target_slider.ticks_on_borders = true
	_target_slider.focus_mode = Control.FOCUS_NONE
	_target_slider.custom_minimum_size = Vector2(260, BUTTON_MIN_HEIGHT)
	_target_slider.value_changed.connect(_on_target_changed)
	_target_slider.drag_started.connect(func() -> void: _slider_dragging = true)
	_target_slider.drag_ended.connect(_on_slider_drag_ended)
	box.add_child(_target_slider)

	_wrap_toggle = _make_toggle(tr("Yatay sarma (W)"), hex_map.wrap_preference(), hex_map.set_wrap)
	box.add_child(_wrap_toggle)
	_terrain_toggle = _make_toggle(tr("Arazi simgeleri (T)"), hex_map.terrain_visible, hex_map.set_terrain_visible)
	box.add_child(_terrain_toggle)
	_editor_toggle = _make_toggle(tr("Editör (E)"), false, _on_editor_toggled)
	box.add_child(_editor_toggle)

	var gameplay := Button.new()
	gameplay.text = tr("Oynanış yakınlığı (G)")
	gameplay.focus_mode = Control.FOCUS_NONE
	gameplay.custom_minimum_size.y = BUTTON_MIN_HEIGHT
	gameplay.pressed.connect(hex_map.zoom_to_gameplay)
	box.add_child(gameplay)

	var back := Button.new()
	back.text = tr("Bölge haritası – deney (H)")
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size.y = BUTTON_MIN_HEIGHT
	back.pressed.connect(_go_region_mode)
	box.add_child(back)

	# Sol alt: sayaç + FPS
	var panel := _make_panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pbox := VBoxContainer.new()
	panel.add_child(pbox)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 15)
	_stats.add_theme_color_override("font_color", Color(0.75, 0.95, 0.75))
	pbox.add_child(_stats)
	_counter = Label.new()
	_counter.add_theme_font_size_override("font_size", 13)
	_counter.add_theme_color_override("font_color", TEXT_COLOR)
	pbox.add_child(_counter)
	hud.add_child(panel)


func _make_projection_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for id: String in hex_map.projection_ids():
		var b := Button.new()
		b.text = tr(PROJECTION_LABELS.get(id, id))
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(86, BUTTON_MIN_HEIGHT)
		b.pressed.connect(_on_projection_pressed.bind(id))
		row.add_child(b)
		_projection_buttons[id] = b
	return row


func _make_toggle(text: String, on: bool, handler: Callable) -> CheckButton:
	var t := CheckButton.new()
	t.text = text
	t.button_pressed = on
	t.focus_mode = Control.FOCUS_NONE
	t.custom_minimum_size.y = BUTTON_MIN_HEIGHT
	t.toggled.connect(handler)
	return t


func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_content_margin_all(10)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _refresh_hud() -> void:
	var g := hex_map.grid
	_target_slider.set_value_no_signal(float(hex_map.land_hex_target))
	_target_label.text = tr("Kara hex hedefi: %d  (gerçek %d)") % [hex_map.land_hex_target, g.land_count()]
	for id: String in _projection_buttons:
		(_projection_buttons[id] as Button).set_pressed_no_signal(id == hex_map.projection)
	_wrap_toggle.disabled = not g.built_wrap
	_wrap_toggle.set_pressed_no_signal(hex_map.wrap_enabled)
	_refresh_stats()


func _refresh_stats() -> void:
	var g := hex_map.grid
	if g == null or _stats == null:
		return
	_stats.text = "FPS %d  ·  %s  ·  %.2f×" % [Engine.get_frames_per_second(), hex_map.lod_name(), camera.zoom.x]
	_counter.text = "%s\n%s" % [
		tr("Kara: %d · Okyanus: %d · Toplam: %d") % [g.land_count(), g.cell_count - g.land_count(), g.cell_count],
		tr("%s · hex %.1f · sarma: %s") % [tr(PROJECTION_LABELS.get(hex_map.projection, hex_map.projection)), g.hex_size,
				tr("açık") if hex_map.wrap_enabled else tr("kapalı")],
	]


func _on_projection_pressed(id: String) -> void:
	hex_map.set_variant(id, hex_map.land_hex_target)


func _on_target_changed(value: float) -> void:
	_target_label.text = tr("Kara hex hedefi: %d") % int(value)
	if not _slider_dragging:
		hex_map.set_variant(hex_map.projection, int(value))


func _on_slider_drag_ended(_changed: bool) -> void:
	_slider_dragging = false
	if int(_target_slider.value) != hex_map.land_hex_target:
		hex_map.set_variant(hex_map.projection, int(_target_slider.value))


func _on_editor_toggled(on: bool) -> void:
	hex_map.set_editor_mode(on)
	info_panel.set_editor(on)
	info_panel.set_status("")
	if on and hex_map.selected >= 0:
		info_panel.show_hex(hex_map.describe_hex(hex_map.selected))


func _on_toggle_land() -> void:
	var id := hex_map.selected
	if id < 0:
		return
	if hex_map.grid.is_land(id):
		hex_map.edit_toggle_land(id)
	elif not hex_map.edit_toggle_land(id, info_panel.selected_country_id()):
		info_panel.set_status(tr("Ülke seçilemedi."))


func _on_assign_country(cid: String) -> void:
	if hex_map.selected >= 0:
		hex_map.edit_set_land(hex_map.selected, cid)


func _on_hex_edited(info: Dictionary) -> void:
	info_panel.show_hex(info)
	info_panel.set_status(tr("Kaydedildi: %s") % hex_map.last_override_path.get_file())


func _go_region_mode() -> void:
	get_tree().change_scene_to_file(REGION_SCENE)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_P:
			var ids := hex_map.projection_ids()
			hex_map.set_variant(ids[(ids.find(hex_map.projection) + 1) % ids.size()], hex_map.land_hex_target)
		KEY_W:
			if not _wrap_toggle.disabled:
				_wrap_toggle.button_pressed = not _wrap_toggle.button_pressed
		KEY_T:
			_terrain_toggle.button_pressed = not _terrain_toggle.button_pressed
		KEY_E:
			_editor_toggle.button_pressed = not _editor_toggle.button_pressed
		KEY_G:
			hex_map.zoom_to_gameplay()
		KEY_H:
			_go_region_mode()
		KEY_ESCAPE:
			hex_map.clear_selection()
