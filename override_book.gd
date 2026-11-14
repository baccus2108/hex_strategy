class_name OverrideBook
extends RefCounted
## overrides.json: editör çıktısı (base'e göre FARKLAR). Düzenlemeler hex kimliğine (q, r) değil, hex'in coğrafi
## merkezine (boylam, enlem) ve ızgara parametrelerine (land_hex_target, hex_size, projeksiyon) bağlı kaydedilir.
## Bellekte anahtar eksenel (q, r)'dir ve `hex_size` ızgarasına göredir. Izgara değişince migrate_to() eski düzenlemeleri
## "yeni hex merkezi eski hex'in içine düşer" kuralıyla taşır; taşınamayanlar `orphans` listesine düşer ve dosyada kalır.
##
## Düzenleme alanları (hepsi isteğe bağlı): "land": bool, "country": ülke id ("" = sahipsiz), "terrain": arazi id.

const PROJECTION := "equal_earth"
const SIZE_TOLERANCE := 1e-3

var land_hex_target := 0
var hex_size := 0.0
var cells: Dictionary = {}       # Vector2i(q, r) -> Dictionary (düzenleme)
var orphans: Array = []          # {lon, lat, edit: Dictionary, reason: String}


static func load_file(path: String = MapPaths.OVERRIDES) -> OverrideBook:
	var book := OverrideBook.new()
	var data: Variant = JsonIO.read(path)
	if not (data is Dictionary) or not JsonIO.has_version(data, MapPaths.SCHEMA_VERSION, path):
		return book
	var grid: Dictionary = data["grid"]
	if str(grid.get("projection", PROJECTION)) != PROJECTION:
		push_error("%s: desteklenmeyen projeksiyon" % path)
		return book
	book.land_hex_target = int(grid["land_hex_target"])
	book.hex_size = float(grid["hex_size"])
	for entry: Dictionary in data.get("cells", []):
		var plane := EqualEarth.forward(float(entry["lon"]), float(entry["lat"]))
		book.cells[HexGrid.plane_to_axial(book.hex_size, plane)] = _edit_of(entry)
	book.orphans = data.get("orphans", [])
	return book


func to_dict() -> Dictionary:
	var list: Array = []
	for key: Vector2i in cells:
		var center := EqualEarth.inverse(HexGrid.axial_to_plane(hex_size, key.x, key.y))
		var entry: Dictionary = (cells[key] as Dictionary).duplicate()
		entry["lon"] = JsonIO.round_coord(center.x)
		entry["lat"] = JsonIO.round_coord(center.y)
		list.append(entry)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["lat"] > b["lat"] or (a["lat"] == b["lat"] and a["lon"] < b["lon"]))
	var sorted_orphans := orphans.duplicate()
	sorted_orphans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["lat"] > b["lat"] or (a["lat"] == b["lat"] and a["lon"] < b["lon"]))
	return {
		"version": MapPaths.SCHEMA_VERSION,
		"grid": {"land_hex_target": land_hex_target, "hex_size": snappedf(hex_size, 0.0001), "projection": PROJECTION},
		"cells": list,
		"orphans": sorted_orphans,
	}


func save_file(path: String = MapPaths.OVERRIDES) -> Error:
	return JsonIO.write(path, to_dict())


static func _edit_of(entry: Dictionary) -> Dictionary:
	var edit := {}
	for key in ["land", "country", "terrain"]:
		if entry.has(key):
			edit[key] = entry[key]
	return edit


# ------------------------------------------------------------------ ızgara değişimi
func matches_size(size: float) -> bool:
	return hex_size > 0.0 and absf(hex_size - size) <= SIZE_TOLERANCE


## Düzenlemeleri `grid`e taşır. Rapor: {moved: taşınan eski düzenleme, lost: kaybolan, produced: yeni ızgaradaki düzenleme}.
## Kaybolanlar `orphans`a eklenir (coğrafi konumlarıyla). Dosya yazmaz; çağıran kaydeder.
func migrate_to(grid: HexGrid, target: int) -> Dictionary:
	var report := {"moved": 0, "lost": 0, "produced": 0}
	if cells.is_empty() or matches_size(grid.size):
		hex_size = grid.size
		land_hex_target = target
		report["moved"] = cells.size()
		report["produced"] = cells.size()
		return report
	var moved_cells: Dictionary = {}
	var hit: Dictionary = {}
	for i in grid.cell_count:
		var old_key := HexGrid.plane_to_axial(hex_size, grid.center(i))
		if cells.has(old_key):
			moved_cells[Vector2i(grid.cell_q[i], grid.cell_r[i])] = (cells[old_key] as Dictionary).duplicate()
			hit[old_key] = true
	for old_key: Vector2i in cells:
		if hit.has(old_key):
			report["moved"] += 1
		else:
			report["lost"] += 1
			add_orphan(EqualEarth.inverse(HexGrid.axial_to_plane(hex_size, old_key.x, old_key.y)), cells[old_key],
					TranslationServer.translate("Izgara değişince taşınamadı"))
	cells = moved_cells
	hex_size = grid.size
	land_hex_target = target
	report["produced"] = cells.size()
	return report


## Konumu (boylam, enlem) olan ama uygulanamayan düzenleme; doğrulama panelinde görünür.
func add_orphan(lon_lat: Vector2, edit: Dictionary, reason: String) -> void:
	orphans.append({"lon": JsonIO.round_coord(lon_lat.x), "lat": JsonIO.round_coord(lon_lat.y), "edit": edit.duplicate(), "reason": reason})
