class_name HexMap
extends Node2D
## Hex ANA harita görünümü ve girdisi. Durum HexGrid'de (saf veri); bu düğüm onu okuyup çizer, oyun kuralı içermez.
## Veri: data/hexmap.json (tools/build_hexmap.py). Ayarlar: data/hex_config.json. Editör çıktısı: data/hex_overrides.json.
##
## Çizim (hex başına düğüm YOK, hepsi toplu):
##   Kopya düğümler (wrap için x = -W, 0, +W):  Base = okyanus hex'leri (tek mesh) + rölyef dokusu (alfa = kara maskesi)
##                                               Fill = kara hex dolguları (tek mesh) -- shader ile GERÇEK kara maskesine kırpılır
##                                               Border = ülke sınırı (hex kenarları) -- aynı shader ile kırpılır
##   Overlay (tek düğüm, görünür kaydırmalar için): ızgara çizgileri, arazi simgeleri, seçim, yakın zoom ayrıntısı
## Ülke ve şehir ADI haritada gösterilmez; bilgi dokununca debug panelinde açılır.
## Kamera ve girdi: dokunma ve fare tek yoldan (kaydır, tekerlek/iki parmak yakınlaştır, dokun = seç).

signal hex_selected(info: Dictionary)
signal selection_cleared
signal variant_changed
signal hex_edited(info: Dictionary)
signal zoom_level_changed(level: int)

enum Lod { FAR, MID, NEAR }

const DATA_PATH := "res://data/hexmap.json"
const CONFIG_PATH := "res://data/hex_config.json"
const COLORS_PATH := "res://data/country_colors.json"
const VIEW_PATH := "res://data/map_view.json"
const MANIFEST_PATH := "res://assets/relief/relief_manifest.json"
const OVERRIDES_RES_PATH := "res://data/hex_overrides.json"
const OVERRIDES_USER_PATH := "user://hex_overrides.json"
const MASK_SHADER := preload("res://shaders/hex_land_mask.gdshader")
const FONT_BODY_PATH := "res://assets/fonts/Barlow-Medium.ttf"

const MAX_ZOOM := 8.0
const TAP_SLOP := 8.0
## Oynanış zoom'unda hex bu kadar dp geniş (dokunma hedefi). dp = viewport birimi (canvas_items stretch).
const TOUCH_TARGET_DP := 40.0
## Zoom seviyesi eşikleri, oynanış zoom'unun katı: uzak < FAR_BELOW <= orta < NEAR_FROM <= yakın.
const FAR_BELOW := 0.7
const NEAR_FROM := 1.8

const OCEAN_COLOR := Color(0.09, 0.15, 0.24)
const FALLBACK_COLOR := Color(0.62, 0.66, 0.72)
const OCEAN_TINTS: Array[Color] = [Color(0.30, 0.45, 0.65, 0.030), Color(0.30, 0.45, 0.65, 0.060), Color(0.30, 0.45, 0.65, 0.090)]
const OCEAN_LINE_COLOR := Color(0.55, 0.70, 0.90, 0.10)
const LAND_LINE_COLOR := Color(0.05, 0.07, 0.11, 0.50)
const BORDER_COLOR := Color(0.04, 0.06, 0.10, 0.95)
const BORDER_WIDTH_PX: Array[float] = [1.6, 2.4, 3.2]
const GRID_LINE_PX := 1.0
const SELECT_COLOR := Color(1.0, 0.85, 0.3)
const OVERRIDE_COLOR := Color(1.0, 0.55, 0.2)
const GUARANTEE_COLOR := Color(0.95, 0.85, 0.35)
const RESCUE_COLOR := Color(0.45, 0.85, 0.95)
const GLYPH_MIN_HEX_PX := 22.0
const COORD_FONT := 10

var grid: HexGrid
var config: Dictionary = {}
var countries: Dictionary = {}          # ülke id -> {name, region_count, area_km2}
var variant_id := ""
var projection := ""
var land_hex_target := 0
var wrap_enabled := false
var terrain_visible := true
var editor_mode := false
var selected := -1
var lod: int = Lod.FAR
var camera: Camera2D
var view_limits := Rect2()
var last_override_path := ""

var _data: Dictionary = {}
var _colors: Dictionary = {}
var _fill_alpha := 0.55
var _wrap_pref := true
var _font: Font
var _overrides: Dictionary = {"variants": {}}
var _override_cells: Dictionary = {}    # hücre id -> true
var _manifest: Dictionary = {}
var _relief: Texture2D
var _relief_rect := Rect2()
var _mask_material: ShaderMaterial
var _fill_mesh: ArrayMesh
var _ocean_mesh: ArrayMesh
var _centers := PackedVector2Array()
var _edges_border := PackedVector2Array()
var _edges_land := PackedVector2Array()
var _edges_ocean := PackedVector2Array()
var _copies: Array[Node2D] = []
var _bases: Array[Node2D] = []
var _fills: Array[Node2D] = []
var _borders: Array[Node2D] = []
var _overlay: Node2D
var _min_zoom := 0.3

var _press_pos := Vector2.ZERO
var _pressing := false
var _moved := false
var _touches: Dictionary = {}
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO
var _pinching := false


func _ready() -> void:
	_font = load(FONT_BODY_PATH) as Font
	if _font == null:
		_font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_data = _read_json(DATA_PATH) as Dictionary
	config = _read_json(CONFIG_PATH) as Dictionary
	_colors = _read_json(COLORS_PATH) as Dictionary
	_manifest = _read_json(MANIFEST_PATH) as Dictionary
	countries = _data["countries"]
	_wrap_pref = bool(config.get("wrap_x", true))
	var view_cfg: Variant = _read_json(VIEW_PATH)
	if view_cfg is Dictionary:
		_fill_alpha = clampf(float(view_cfg.get("region_fill_alpha", 0.55)), 0.0, 1.0)
	_load_overrides()
	_mask_material = ShaderMaterial.new()
	_mask_material.shader = MASK_SHADER
	for k in [-1, 0, 1]:
		var copy := Node2D.new()
		copy.name = "Kopya%d" % (k + 1)
		add_child(copy)
		_copies.append(copy)
		_bases.append(_make_layer(copy, null, _draw_base))
		_fills.append(_make_layer(copy, _mask_material, _draw_fill))
		_borders.append(_make_layer(copy, _mask_material, _draw_border))
	_overlay = Node2D.new()
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _make_layer(parent: Node2D, material: Material, drawer: Callable) -> Node2D:
	var n := Node2D.new()
	n.material = material
	parent.add_child(n)
	n.draw.connect(drawer.bind(n))
	return n


static func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Dosya açılamadı: %s" % path)
		return null
	return JSON.parse_string(file.get_as_text())


## Ana sahne kamerayı verir. Önce set_variant çağrılmış olmalı.
func setup(cam: Camera2D) -> void:
	camera = cam
	_min_zoom = _fit_zoom()
	camera.zoom = Vector2(_min_zoom, _min_zoom)
	camera.position = view_limits.get_center()
	_clamp_camera()
	_update_lod()
	_redraw_all()


# ------------------------------------------------------------------ ayarlar ve varyant
func projection_ids() -> Array:
	return (_data["meta"] as Dictionary)["projeksiyonlar"]


func targets() -> Array:
	var out: Array = []
	for t in (_data["meta"] as Dictionary)["hedefler"]:
		out.append(int(t))
	return out


func default_projection() -> String:
	return str((config["projection"] as Dictionary)["default"])


func default_target() -> int:
	return int((config["land_hex_target"] as Dictionary)["default"])


func wrap_preference() -> bool:
	return _wrap_pref


## Projeksiyon + kara hex hedefi (hex boyutu bundan türetilmiş, veri hazır). Başarılıysa true.
func set_variant(new_projection: String, new_target: int) -> bool:
	var id := "%s_%d" % [new_projection, new_target]
	var variants: Dictionary = _data["variants"]
	if not variants.has(id):
		return false
	var ids := PackedStringArray(countries.keys())
	grid = HexGrid.from_variant(variants[id], ids)
	variant_id = id
	projection = new_projection
	land_hex_target = new_target
	grid.wrap_enabled = _wrap_pref and grid.built_wrap
	wrap_enabled = grid.wrap_enabled
	_apply_saved_overrides()
	selected = -1
	view_limits = Rect2(-grid.plane_width / 2.0, grid.y_min, grid.plane_width, grid.y_max - grid.y_min)
	_load_relief()
	_build_geometry()
	if camera != null:
		_min_zoom = _fit_zoom()
		var z := clampf(camera.zoom.x, _min_zoom, MAX_ZOOM)
		camera.zoom = Vector2(z, z)
		_clamp_camera()
		_update_lod()
	_redraw_all()
	variant_changed.emit()
	selection_cleared.emit()
	return true


func set_wrap(on: bool) -> void:
	_wrap_pref = on
	if grid == null:
		return
	grid.wrap_enabled = on and grid.built_wrap
	wrap_enabled = grid.wrap_enabled
	_build_geometry()
	if camera != null:
		_clamp_camera()
	_redraw_all()


func set_terrain_visible(on: bool) -> void:
	terrain_visible = on
	_overlay.queue_redraw()


func set_editor_mode(on: bool) -> void:
	editor_mode = on
	_overlay.queue_redraw()


func _load_relief() -> void:
	_relief = null
	var m: Variant = _manifest.get(projection, null)
	if m is Dictionary and ResourceLoader.exists(str(m["file"])):
		_relief = load(str(m["file"])) as Texture2D
		var r: Array = m["rect"]
		_relief_rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	for n in _bases + _fills + _borders:
		n.material = null if n in _bases else (_mask_material if _relief != null else null)
	if _relief != null:
		_mask_material.set_shader_parameter("land_mask", _relief)
		_mask_material.set_shader_parameter("rect", Vector4(_relief_rect.position.x, _relief_rect.position.y, _relief_rect.size.x, _relief_rect.size.y))
		_mask_material.set_shader_parameter("wrap_x", wrap_enabled)


func gameplay_zoom() -> float:
	return TOUCH_TARGET_DP / grid.hex_width()


func zoom_to_gameplay() -> void:
	if camera == null:
		return
	var vs := get_viewport_rect().size
	var before := _to_world(vs / 2.0)
	var z := clampf(gameplay_zoom(), _min_zoom, MAX_ZOOM)
	camera.zoom = Vector2(z, z)
	camera.position = before if selected < 0 else grid.center(selected)
	_clamp_camera()
	_update_lod()
	_redraw_all()


func lod_name() -> String:
	return [tr("Uzak"), tr("Orta"), tr("Yakın")][lod]


# ------------------------------------------------------------------ sorgular
func country_color(id: String) -> Color:
	if _colors.has(id):
		return Color.html(_colors[id])
	return FALLBACK_COLOR


func country_name(id: String) -> String:
	return str((countries.get(id, {}) as Dictionary).get("name", id))


## Editör için (id, ad) listesi, ada göre sıralı.
func country_choices() -> Array:
	var out: Array = []
	for id: String in countries:
		out.append({"id": id, "name": str((countries[id] as Dictionary)["name"])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return out


## Seçim kartı için hex bilgisi (saf veri sözlüğü).
func describe_hex(id: int) -> Dictionary:
	if grid == null or id < 0 or id >= grid.cell_count:
		return {}
	var land := grid.is_land(id)
	var cid := grid.owner_id(id)
	var others: Array = []
	for k: String in (grid.km2.get(id, {}) as Dictionary):
		if k != cid:
			others.append({"name": country_name(k), "km2": float(grid.km2[id][k])})
	return {
		"id": id, "q": grid.cell_q[id], "r": grid.cell_r[id], "land": land, "coast": grid.coast[id] != 0,
		"country_id": cid, "country_name": country_name(cid) if cid != "" else "",
		"color": country_color(cid) if cid != "" else OCEAN_COLOR,
		"terrain": grid.terrain_id(id), "elev": grid.elev[id], "frac": grid.frac[id],
		"owner_km2": grid.owner_km2(id), "total_km2": grid.total_km2(id), "others": others,
		"income": grid.income(id), "src": str(grid.src.get(id, "")), "override": _override_cells.has(id),
		"suggested_country": suggest_country(id),
	}


## Komşu kara hücrelerinde en çok görülen ülke (editörde öntanımlı seçim); yoksa "".
func suggest_country(id: int) -> String:
	var votes: Dictionary = {}
	for n in grid.neighbors(id):
		if n >= 0 and grid.is_land(n):
			var c := grid.owner_id(n)
			votes[c] = int(votes.get(c, 0)) + 1
	var best := ""
	var best_n := 0
	for c: String in votes:
		if int(votes[c]) > best_n:
			best_n = int(votes[c])
			best = c
	return best


func cell_at_world(p: Vector2) -> int:
	if grid == null:
		return -1
	if not wrap_enabled and (p.x < view_limits.position.x or p.x > view_limits.end.x):
		return -1
	return grid.world_to_cell(p)


# ------------------------------------------------------------------ editör (hex_overrides.json)
func edit_set_land(id: int, cid: String) -> bool:
	if grid == null or id < 0 or not grid.set_land(id, cid, "editor"):
		return false
	var o := _override_of(id)
	o["land"] = true
	o["country"] = cid
	_after_edit(id)
	return true


func edit_set_ocean(id: int) -> void:
	if grid == null or id < 0:
		return
	grid.set_ocean(id, "editor")
	var o := _override_of(id)
	o["land"] = false
	o.erase("country")
	_after_edit(id)


## Kara <-> deniz. Denizi karaya çevirirken ülke: verilen, yoksa komşuların çoğunluğu; ikisi de yoksa false.
func edit_toggle_land(id: int, country_for_new_land := "") -> bool:
	if grid == null or id < 0:
		return false
	if grid.is_land(id):
		edit_set_ocean(id)
		return true
	var cid := country_for_new_land if country_for_new_land != "" else suggest_country(id)
	return cid != "" and edit_set_land(id, cid)


func _override_of(id: int) -> Dictionary:
	var variants: Dictionary = _overrides["variants"]
	if not variants.has(variant_id):
		variants[variant_id] = {}
	var key := "%d,%d" % [grid.cell_q[id], grid.cell_r[id]]
	var per: Dictionary = variants[variant_id]
	if not per.has(key):
		per[key] = {}
	return per[key]


func _after_edit(id: int) -> void:
	_override_cells[id] = true
	last_override_path = _save_overrides()
	_build_geometry()
	_redraw_all()
	hex_edited.emit(describe_hex(id))


func _load_overrides() -> void:
	_overrides = {"variants": {}}
	for path in [OVERRIDES_USER_PATH, OVERRIDES_RES_PATH]:
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary and (parsed as Dictionary).has("variants"):
				_overrides = parsed
				return


func _apply_saved_overrides() -> void:
	_override_cells.clear()
	var per: Dictionary = (_overrides["variants"] as Dictionary).get(variant_id, {})
	for key: String in per:
		var parts := key.split(",")
		var id := grid.cell_id(int(parts[0]), int(parts[1]))
		if id < 0:
			continue
		var o: Dictionary = per[key]
		if o.get("land", true) == false:
			grid.set_ocean(id, "override")
		else:
			var cid := str(o.get("country", grid.owner_id(id)))
			if cid == "":
				cid = suggest_country(id)
			if cid == "" or not grid.set_land(id, cid, "override"):
				continue
		_override_cells[id] = true


## res://data/hex_overrides.json (python betiği bunu okur); yazılamıyorsa (dışa aktarılmış oyun) user://. Kullanılan yolu döndürür.
func _save_overrides() -> String:
	var out := {"_aciklama": "Hex editörü çıktısı. tools/build_hexmap.py yeniden çalışınca uygulanır ve korunur. Anahtar: varyant -> \"q,r\" -> {land: bool, country: id}. Koordinatlar varyanta özeldir.",
			"variants": _overrides["variants"]}
	var text := JSON.stringify(out, "  ") + "\n"
	for path in [OVERRIDES_RES_PATH, OVERRIDES_USER_PATH]:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
			if path == OVERRIDES_RES_PATH and FileAccess.file_exists(OVERRIDES_USER_PATH):
				DirAccess.remove_absolute(OVERRIDES_USER_PATH)
			return path
	push_error("hex_overrides.json yazılamadı")
	return ""


# ------------------------------------------------------------------ geometri (toplu)
func _build_geometry() -> void:
	var n := grid.cell_count
	_centers.resize(n)
	var fill_v := PackedVector2Array()
	var fill_c := PackedColorArray()
	var fill_i := PackedInt32Array()
	var oc_v := PackedVector2Array()
	var oc_c := PackedColorArray()
	var oc_i := PackedInt32Array()
	_edges_border = PackedVector2Array()
	_edges_land = PackedVector2Array()
	_edges_ocean = PackedVector2Array()
	for i in n:
		var corners := grid.corners(i)
		_centers[i] = grid.center(i)
		var land := grid.is_land(i)
		if land:
			var color := Color(country_color(grid.owner_id(i)), _fill_alpha)
			var base := fill_v.size()
			fill_v.append(_centers[i])
			fill_c.append(color)
			for k in 6:
				fill_v.append(corners[k])
				fill_c.append(color)
				fill_i.append(base)
				fill_i.append(base + 1 + k)
				fill_i.append(base + 1 + (k + 1) % 6)
		else:
			var color := OCEAN_TINTS[posmod(grid.cell_q[i] - grid.cell_r[i], 3)]
			var base := oc_v.size()
			oc_v.append(_centers[i])
			oc_c.append(color)
			for k in 6:
				oc_v.append(corners[k])
				oc_c.append(color)
				oc_i.append(base)
				oc_i.append(base + 1 + k)
				oc_i.append(base + 1 + (k + 1) % 6)
		for d in 6:
			var ni := grid.neighbor(i, d)
			var a := corners[5 - d]
			var b := corners[(6 - d) % 6]
			var n_land := ni >= 0 and grid.is_land(ni)
			if land and n_land and grid.owner[ni] != grid.owner[i]:
				if ni > i:  # ortak kenar bir kez; ülke sınırı (kalın)
					_edges_border.append(a)
					_edges_border.append(b)
			elif ni < 0 or ni > i:
				if land or n_land:
					_edges_land.append(a)
					_edges_land.append(b)
				else:
					_edges_ocean.append(a)
					_edges_ocean.append(b)
	_fill_mesh = _make_mesh(fill_v, fill_c, fill_i)
	_ocean_mesh = _make_mesh(oc_v, oc_c, oc_i)
	for k in 3:
		_copies[k].position = Vector2((k - 1) * grid.plane_width, 0.0)
		_copies[k].visible = k == 1 or wrap_enabled
	if _relief != null:
		_mask_material.set_shader_parameter("wrap_x", wrap_enabled)

static func _make_mesh(v: PackedVector2Array, c: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:
	if v.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _redraw_all() -> void:
	for n in _bases + _fills + _borders:
		n.queue_redraw()
	_overlay.queue_redraw()


func _draw_base(node: Node2D) -> void:
	if _ocean_mesh != null:
		node.draw_mesh(_ocean_mesh, null)
	if _relief != null:
		node.draw_texture_rect(_relief, _relief_rect, false)


func _draw_fill(node: Node2D) -> void:
	if _fill_mesh != null:
		node.draw_mesh(_fill_mesh, null)


func _draw_border(node: Node2D) -> void:
	if camera == null or _edges_border.size() < 2:
		return
	node.draw_multiline(_edges_border, BORDER_COLOR, BORDER_WIDTH_PX[lod] / camera.zoom.x)


# ------------------------------------------------------------------ overlay (ızgara, simgeler, seçim, ayrıntı)
func _view_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var zoom := camera.zoom.x
	return Rect2(camera.position - vs / (2.0 * zoom), vs / zoom)


func _visible_shifts(view: Rect2) -> Array[int]:
	var out: Array[int] = []
	if not wrap_enabled:
		out.append(0)
		return out
	var w := grid.plane_width
	for k in [-1, 0, 1]:
		var lo: float = k * w - w / 2.0 - grid.hex_width()
		var hi: float = k * w + w / 2.0 + grid.hex_width()
		if view.end.x >= lo and view.position.x <= hi:
			out.append(k)
	return out


func _draw_overlay() -> void:
	if camera == null or grid == null:
		return
	var zoom := camera.zoom.x
	var u := 1.0 / zoom
	var view := _view_rect()
	var hex_px := grid.hex_width() * zoom
	for k in _visible_shifts(view):
		var off := Vector2(k * grid.plane_width, 0.0)
		_overlay.draw_set_transform(off, 0.0, Vector2.ONE)
		var v := Rect2(view.position - off, view.size)
		# 1) Izgara: sadece orta ve yakın zoom (uzakta kapalı). Okyanus çok silik.
		if lod != Lod.FAR:
			if _edges_ocean.size() >= 2:
				_overlay.draw_multiline(_edges_ocean, OCEAN_LINE_COLOR, GRID_LINE_PX * u)
			if _edges_land.size() >= 2:
				_overlay.draw_multiline(_edges_land, LAND_LINE_COLOR, GRID_LINE_PX * u)
		# 2) Editör: override'lı hex'ler
		if editor_mode or lod == Lod.NEAR:
			for id: int in _override_cells:
				if v.grow(grid.hex_size).has_point(_centers[id]):
					_draw_outline(grid.corners(id), OVERRIDE_COLOR, 2.4 * u)
		# 3) Arazi simgeleri (orta ve yakın)
		if terrain_visible and lod != Lod.FAR and hex_px >= GLYPH_MIN_HEX_PX:
			_draw_terrain_glyphs(v, u)
		# 4) Yakın: q,r ve kaynak işaretleri
		if lod == Lod.NEAR:
			_draw_detail(v, zoom, off)
		# 5) Seçim
		if selected >= 0:
			var sel_corners := grid.corners(selected)
			for nb in grid.neighbors(selected):
				if nb >= 0:
					_overlay.draw_colored_polygon(grid.corners(nb), Color(1, 1, 1, 0.14))
			_overlay.draw_colored_polygon(sel_corners, Color(1, 1, 1, 0.28))
			_draw_outline(sel_corners, Color(0.04, 0.05, 0.08, 0.85), 6.0 * u)
			_draw_outline(sel_corners, SELECT_COLOR, 3.0 * u)
	_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_outline(corners: PackedVector2Array, color: Color, width: float) -> void:
	var line := corners.duplicate()
	line.append(line[0])
	_overlay.draw_polyline(line, color, width, true)


func _draw_terrain_glyphs(v: Rect2, u: float) -> void:
	var pad := v.grow(24.0 * u)
	for i in grid.cell_count:
		if not grid.is_land(i) or grid.terrain[i] <= 0:
			continue
		var p := _centers[i] + Vector2(0.0, grid.hex_size * 0.30)
		if not pad.has_point(p):
			continue
		match grid.terrain_id(i):
			"daglik":
				_draw_peak(p + Vector2(-3.8, 0.0) * u, 4.4 * u, true)
				_draw_peak(p + Vector2(3.8, 0.0) * u, 4.4 * u, true)
			"yayla":
				_draw_peak(p, 4.0 * u, false)
			"col":
				for dx in [-4.0, 0.0, 4.0]:
					_overlay.draw_circle(p + Vector2(dx, (absf(dx) * 0.4 - 1.0)) * u, 1.5 * u, Color(0.98, 0.9, 0.6, 0.95))
			"tundra":
				var s := 3.4 * u
				_overlay.draw_line(p + Vector2(-s, 0), p + Vector2(s, 0), Color(0.92, 0.97, 1.0, 0.95), 1.5 * u)
				_overlay.draw_line(p + Vector2(0, -s), p + Vector2(0, s), Color(0.92, 0.97, 1.0, 0.95), 1.5 * u)


func _draw_peak(pos: Vector2, size: float, filled: bool) -> void:
	var tri := PackedVector2Array([pos + Vector2(0, -size), pos + Vector2(size * 0.95, size * 0.7), pos + Vector2(-size * 0.95, size * 0.7)])
	if filled:
		_overlay.draw_colored_polygon(tri, Color(0.16, 0.11, 0.06, 0.85))
	_overlay.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0.97, 0.90, 0.72, 0.95), size * 0.28, true)


func _draw_detail(v: Rect2, zoom: float, off: Vector2) -> void:
	var u := 1.0 / zoom
	var pad := v.grow(grid.hex_size)
	for i in grid.cell_count:
		if not grid.is_land(i) or not pad.has_point(_centers[i]):
			continue
		var text := "%d,%d" % [grid.cell_q[i], grid.cell_r[i]]
		_overlay.draw_set_transform(off + _centers[i], 0.0, Vector2.ONE * u)
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, COORD_FONT).x
		var at := Vector2(-w / 2.0, -grid.hex_size * zoom * 0.52)
		_overlay.draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, COORD_FONT, 3, Color(0.04, 0.06, 0.1, 0.8))
		_overlay.draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, COORD_FONT, Color(1, 1, 1, 0.85))
		var src := str(grid.src.get(i, ""))
		if src != "" and src != "area":
			var col := RESCUE_COLOR if src == "rescue" else (GUARANTEE_COLOR if src == "guarantee" else OVERRIDE_COLOR)
			var m := Vector2(0.0, grid.hex_size * zoom * 0.62)
			_overlay.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -4), m + Vector2(4, 0), m + Vector2(0, 4), m + Vector2(-4, 0)]), col)
		if grid.coast[i] != 0:
			_overlay.draw_circle(Vector2(grid.hex_size * zoom * 0.5, -grid.hex_size * zoom * 0.1), 1.8, Color(0.55, 0.8, 1.0, 0.9))
	_overlay.draw_set_transform(off, 0.0, Vector2.ONE)


# ------------------------------------------------------------------ zoom seviyesi ve kamera
func _update_lod() -> void:
	var gp := gameplay_zoom()
	var z := camera.zoom.x
	var new_lod: int = Lod.FAR if z < gp * FAR_BELOW else (Lod.MID if z < gp * NEAR_FROM else Lod.NEAR)
	if new_lod != lod:
		lod = new_lod
		for n in _borders:
			n.queue_redraw()
		zoom_level_changed.emit(lod)


func _fit_zoom() -> float:
	var vs := get_viewport_rect().size
	return minf(vs.x / view_limits.size.x, vs.y / view_limits.size.y)


func _on_viewport_resized() -> void:
	if camera == null or grid == null:
		return
	_min_zoom = _fit_zoom()
	var z := clampf(camera.zoom.x, _min_zoom, MAX_ZOOM)
	camera.zoom = Vector2(z, z)
	_clamp_camera()
	_update_lod()
	_redraw_all()


func _to_world(screen: Vector2) -> Vector2:
	return camera.position + (screen - get_viewport_rect().size / 2.0) / camera.zoom.x


func _zoom_at(factor: float, screen: Vector2) -> void:
	var before := _to_world(screen)
	var z := clampf(camera.zoom.x * factor, _min_zoom, MAX_ZOOM)
	camera.zoom = Vector2(z, z)
	camera.position += before - _to_world(screen)
	_clamp_camera()
	_update_lod()
	for n in _borders:
		n.queue_redraw()
	_overlay.queue_redraw()


func _pan(screen_delta: Vector2) -> void:
	camera.position -= screen_delta / camera.zoom.x
	_clamp_camera()
	_overlay.queue_redraw()


## Dikey: görünür alan view_limits (enlem -60..80) içinde. Yatay: wrap açıkken dolaşır, kapalıyken sınırlanır.
func _clamp_camera() -> void:
	var half := get_viewport_rect().size / (2.0 * camera.zoom.x)
	var lo := view_limits.position + half
	var hi := view_limits.end - half
	if wrap_enabled:
		camera.position.x = wrapf(camera.position.x, view_limits.position.x, view_limits.end.x)
	else:
		camera.position.x = view_limits.get_center().x if lo.x > hi.x else clampf(camera.position.x, lo.x, hi.x)
	camera.position.y = view_limits.get_center().y if lo.y > hi.y else clampf(camera.position.y, lo.y, hi.y)


# ------------------------------------------------------------------ girdi (dokunma ve fare tek yoldan)
func _unhandled_input(event: InputEvent) -> void:
	if camera == null or grid == null:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
			if _touches.size() == 2:
				_pinching = true
				_pinch_dist = _pinch_distance()
				_pinch_mid = _pinch_midpoint()
		else:
			_touches.erase(t.index)
			if _touches.is_empty():
				_pinching = false
		return
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touches[d.index] = d.position
		if _touches.size() == 2:
			var dist := _pinch_distance()
			var mid := _pinch_midpoint()
			if _pinch_dist > 0.0:
				_zoom_at(dist / _pinch_dist, mid)
			_pan(mid - _pinch_mid)
			_pinch_dist = dist
			_pinch_mid = mid
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(1.15, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(1.0 / 1.15, mb.position)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_pressing = true
					_moved = false
					_press_pos = mb.position
				else:
					if _pressing and not _moved and not _pinching:
						_select_at(mb.position)
					_pressing = false
	elif event is InputEventMouseMotion and _pressing and not _pinching:
		var mm := event as InputEventMouseMotion
		if not _moved and mm.position.distance_to(_press_pos) > TAP_SLOP:
			_moved = true
		if _moved:
			_pan(mm.relative)


func _pinch_distance() -> float:
	var pts := _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


func _pinch_midpoint() -> Vector2:
	var pts := _touches.values()
	return ((pts[0] as Vector2) + (pts[1] as Vector2)) / 2.0


# ------------------------------------------------------------------ seçim
func _select_at(screen: Vector2) -> void:
	var i := cell_at_world(_to_world(screen))
	if i < 0:
		clear_selection()
		return
	select_hex(i)


func select_hex(i: int) -> void:
	selected = i
	_overlay.queue_redraw()
	hex_selected.emit(describe_hex(i))


func clear_selection() -> void:
	selected = -1
	_overlay.queue_redraw()
	selection_cleared.emit()
