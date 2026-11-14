class_name MapModel
extends RefCounted
## Çözülmüş harita durumu: ızgara + hücre başına kara/ülke/arazi (= üretilmiş base + düzenlemeler). SAF VERİ, düğüm yok.
## Görüntü (MapView) bunu okuyup çizer; editör set_state() ile değiştirir. set_state() değişikliği otomatik olarak
## `overrides` içine (base'e göre fark) yazar; böylece kayıt/yükleme durumdan türer.

var base: BaseMap
var grid: HexGrid
var land_hex_target := 0
var overrides: OverrideBook

var land := PackedByteArray()
var owner := PackedStringArray()          # ülke kimliği; "" = sahipsiz / deniz
var terrain := PackedInt32Array()         # Terrain.*; kara değilse NONE

var base_land := PackedByteArray()
var base_owner := PackedStringArray()
var base_terrain := PackedInt32Array()
var elevation_m := PackedInt32Array()
var land_km2 := PackedFloat32Array()
var owner_km2 := PackedFloat32Array()
var guaranteed := PackedByteArray()


## Bir hücrenin düzenlenebilir durumu.
class CellState:
	extends RefCounted
	var land := false
	var owner := ""
	var terrain := Terrain.NONE

	func _init(is_land := false, owner_id := "", terrain_id := Terrain.NONE) -> void:
		land = is_land
		owner = owner_id
		terrain = terrain_id

	func equals(other: CellState) -> bool:
		return land == other.land and owner == other.owner and terrain == other.terrain

	## Kara değilse sahip/arazi yok; karaysa arazi en az "ova".
	func normalized() -> CellState:
		if not land:
			return CellState.new(false, "", Terrain.NONE)
		return CellState.new(true, owner, Terrain.OVA if terrain == Terrain.NONE else terrain)


## `overrides` bu ızgaraya göre (migrate_to uygulanmış) olmalı. Tanımsız ülkeye bağlı düzenlemeler orphans'a gider.
static func create(base_map: BaseMap, hex_grid: HexGrid, target: int, gen: HexGenerator.Cells, countries: CountryBook, override_book: OverrideBook) -> MapModel:
	var m := MapModel.new()
	m.base = base_map
	m.grid = hex_grid
	m.land_hex_target = target
	m.overrides = override_book
	var n := hex_grid.cell_count
	m.base_land = gen.land
	m.base_terrain = gen.terrain
	m.elevation_m = gen.elevation_m
	m.land_km2 = gen.land_km2
	m.owner_km2 = gen.owner_km2
	m.guaranteed = gen.guaranteed
	m.base_owner.resize(n)
	for i in n:
		var id := base_map.country_ids[gen.country_index[i]]
		m.base_owner[i] = id if countries.has(id) else ""
	m.land = m.base_land.duplicate()
	m.owner = m.base_owner.duplicate()
	m.terrain = m.base_terrain.duplicate()
	m._apply_overrides(countries)
	return m


func _apply_overrides(countries: CountryBook) -> void:
	for key: Vector2i in overrides.cells.keys():
		var i := grid.index_of(key.x, key.y)
		var edit: Dictionary = overrides.cells[key]
		var unknown_country := edit.has("country") and str(edit["country"]) != "" and not countries.has(str(edit["country"]))
		if i < 0 or unknown_country:
			overrides.cells.erase(key)
			var at := EqualEarth.inverse(HexGrid.axial_to_plane(overrides.hex_size, key.x, key.y))
			overrides.add_orphan(at, edit, TranslationServer.translate("Hex veya ülke artık yok"))
			continue
		var state := CellState.new(bool(edit.get("land", base_land[i] == 1)),
				str(edit.get("country", base_owner[i])), Terrain.from_id(str(edit.get("terrain", ""))) if edit.has("terrain") else base_terrain[i])
		_write_cell(i, state.normalized())


# ------------------------------------------------------------------ okuma
func cell_state(i: int) -> CellState:
	return CellState.new(land[i] == 1, owner[i], terrain[i])


func base_state(i: int) -> CellState:
	return CellState.new(base_land[i] == 1, base_owner[i], base_terrain[i])


func is_land(i: int) -> bool:
	return land[i] == 1


func is_overridden(i: int) -> bool:
	return overrides.cells.has(axial_of(i))


func axial_of(i: int) -> Vector2i:
	return Vector2i(grid.cell_q[i], grid.cell_r[i])


## Hex merkezinin (boylam, enlem)'i.
func lon_lat_of(i: int) -> Vector2:
	return EqualEarth.inverse(grid.center(i))


func land_count() -> int:
	var n := 0
	for v in land:
		n += v
	return n


## Ülke -> {hexes: int, km2: float}. Ülke payı: hex'in base sahibiyse onun payı, başka ülke aldıysa hex'teki tüm gerçek kara.
func country_stats() -> Dictionary:
	var stats: Dictionary = {}
	for i in grid.cell_count:
		if land[i] == 0 or owner[i] == "":
			continue
		if not stats.has(owner[i]):
			stats[owner[i]] = {"hexes": 0, "km2": 0.0}
		var s: Dictionary = stats[owner[i]]
		s["hexes"] += 1
		s["km2"] += owner_km2[i] if owner[i] == base_owner[i] else land_km2[i]
	return stats


## `start` ile aynı (kara, sahip) değerine sahip bağlı hücreler (komşuluk üzerinden).
func region_of(start: int) -> PackedInt32Array:
	var out := PackedInt32Array([start])
	var seen: Dictionary = {start: true}
	var head := 0
	while head < out.size():
		for n in grid.neighbors(out[head]):
			if not seen.has(n) and land[n] == land[start] and owner[n] == owner[start]:
				seen[n] = true
				out.append(n)
		head += 1
	return out


## Hücrenin kara komşularında en çok görülen ülke (yoksa "").
func dominant_neighbor_owner(i: int) -> String:
	var counts: Dictionary = {}
	for n in grid.neighbors(i):
		if land[n] == 1 and owner[n] != "":
			counts[owner[n]] = int(counts.get(owner[n], 0)) + 1
	var best := ""
	var best_n := 0
	for id: String in counts:
		if counts[id] > best_n:
			best_n = counts[id]
			best = id
	return best


# ------------------------------------------------------------------ yazma
## Hücre durumunu ayarlar (normalize eder) ve düzenleme kaydını base'e göre günceller.
func set_state(i: int, new_state: CellState) -> void:
	var s := new_state.normalized()
	_write_cell(i, s)
	_sync_override(i, s)


func _write_cell(i: int, s: CellState) -> void:
	land[i] = 1 if s.land else 0
	owner[i] = s.owner
	terrain[i] = s.terrain


func _sync_override(i: int, s: CellState) -> void:
	var edit := {}
	if s.land != (base_land[i] == 1):
		edit["land"] = s.land
	if s.land:
		if s.owner != base_owner[i]:
			edit["country"] = s.owner
		if s.terrain != base_terrain[i]:
			edit["terrain"] = Terrain.id_of(s.terrain)
	var key := axial_of(i)
	if edit.is_empty():
		overrides.cells.erase(key)
	else:
		overrides.cells[key] = edit
