class_name HexGenerator
extends RefCounted
## Base raster -> ham hex verisi (kara, ülke, arazi, km²). Saf hesap; dosya yazmaz, düğüm kullanmaz.
##
## Yöntem: her hex için hex'in içine düzgün dağılmış ~60 örnek (ölçeğe uyarlı; hex büyüklüğünden bağımsız maliyet).
##  - kara: merkez karada VEYA örneklerin LAND_FRACTION_MIN'i kara
##  - sahip: karadaki örneklerde en çok görülen ülke
##  - arazi: karadaki örneklerin ortalama yükseklik/engebesi -> Terrain.classify
##  - küçük ülke garantisi: hex'i olmayan ülke, temsil noktasına en yakın uygun hex'i alır
## land_hex_target -> hex boyutu: kaba örneklemeyle sayım + oran düzeltmesi (en çok CALIBRATION_MAX_STEPS tur).

const LAND_FRACTION_MIN := 0.35
const SAMPLES_ACROSS := 9.0            # hex genişliği boyunca örnek sayısı (üretim)
const SAMPLES_ACROSS_FAST := 4.0       # kalibrasyon sayımı
const TERRAIN_SAMPLES_ACROSS := 5.0
const CALIBRATION_TOLERANCE := 0.01
const CALIBRATION_MAX_STEPS := 5
const GUARANTEE_SEARCH_RADIUS := 2

static var _size_cache: Dictionary = {}   # land_hex_target -> hex size


## Üretim çıktısı: hücre başına diziler (hücre kimliği = HexGrid kimliği).
class Cells:
	extends RefCounted
	var land := PackedByteArray()
	var country_index := PackedInt32Array()     # BaseMap raster indeksi; 0 = yok
	var terrain := PackedInt32Array()           # Terrain.*; kara değilse Terrain.NONE
	var elevation_m := PackedInt32Array()
	var land_km2 := PackedFloat32Array()        # hex içindeki gerçek kara alanı
	var owner_km2 := PackedFloat32Array()       # bunun sahip ülkeye ait kısmı
	var guaranteed := PackedByteArray()         # 1 = küçük ülke garantisiyle kara yapıldı

	func _init(n: int) -> void:
		land.resize(n)
		country_index.resize(n)
		terrain.resize(n)
		terrain.fill(Terrain.NONE)
		elevation_m.resize(n)
		land_km2.resize(n)
		owner_km2.resize(n)
		guaranteed.resize(n)

	func land_count() -> int:
		var n := 0
		for v in land:
			n += v
		return n


# ------------------------------------------------------------------ hedeften ızgara
## Kara hex sayısı ≈ target olan ızgara. Aynı hedef için boyut önbelleğe alınır.
static func grid_for_target(base: BaseMap, target: int) -> HexGrid:
	if _size_cache.has(target):
		return HexGrid.new(_size_cache[target])
	var size := sqrt(base.land_area_units() / float(target) / (1.5 * EqualEarth.SQRT3))
	var best: HexGrid = null
	var best_err := INF
	for _step in CALIBRATION_MAX_STEPS:
		var grid := HexGrid.new(size)
		var n := count_land(base, grid)
		var err := absf(n - target) / float(target)
		if err < best_err:
			best = grid
			best_err = err
		if err <= CALIBRATION_TOLERANCE:
			break
		size *= sqrt(float(maxi(n, 1)) / float(target))
	_size_cache[target] = best.size
	return best


## Kaba örneklemeyle kara hex sayısı (kalibrasyon için; sahip/arazi hesaplamaz).
static func count_land(base: BaseMap, grid: HexGrid) -> int:
	var offsets := _lattice(grid.size, SAMPLES_ACROSS_FAST, base.country_px_per_unit)
	var needed := ceili(LAND_FRACTION_MIN * offsets.size())
	var n := 0
	for i in grid.cell_count:
		var origin := (grid.center(i) - base.rect.position) * base.country_px_per_unit
		var land_n := 0
		var center_land := false
		for k in offsets.size():
			var v := _country_at(base, origin + offsets[k])
			if v != 0:
				land_n += 1
				center_land = center_land or k == 0
		if center_land or land_n >= needed:
			n += 1
	return n


# ------------------------------------------------------------------ üretim
static func generate(base: BaseMap, grid: HexGrid) -> Cells:
	var cells := Cells.new(grid.cell_count)
	var thresholds := Terrain.load_thresholds()
	var offsets := _lattice(grid.size, SAMPLES_ACROSS, base.country_px_per_unit)
	var terrain_offsets := _lattice(grid.size, TERRAIN_SAMPLES_ACROSS, 1.0)
	var counts := PackedInt32Array()
	counts.resize(base.country_ids.size())
	var hex_km2 := grid.area_km2()
	var total := float(offsets.size())
	for i in grid.cell_count:
		var center := grid.center(i)
		var origin := (center - base.rect.position) * base.country_px_per_unit
		var touched := PackedInt32Array()
		var land_n := 0
		var center_index := 0
		for k in offsets.size():
			var v := _country_at(base, origin + offsets[k])
			if v == 0:
				continue
			land_n += 1
			if k == 0:
				center_index = v
			if counts[v] == 0:
				touched.append(v)
			counts[v] += 1
		var owner := 0
		var owner_n := 0
		for v in touched:
			if counts[v] > owner_n:
				owner_n = counts[v]
				owner = v
			counts[v] = 0
		if center_index == 0 and land_n < LAND_FRACTION_MIN * total:
			continue
		cells.land[i] = 1
		cells.country_index[i] = owner
		cells.land_km2[i] = land_n / total * hex_km2
		cells.owner_km2[i] = owner_n / total * hex_km2
		_assign_terrain(base, cells, i, center, terrain_offsets, thresholds)
	_guarantee_small_countries(base, grid, cells, thresholds, terrain_offsets)
	return cells


## Hex'in kara örneklerinin ortalama yükseklik/engebesinden arazi (kara örneği yoksa tüm örnekler).
static func _assign_terrain(base: BaseMap, cells: Cells, i: int, center: Vector2, offsets: PackedVector2Array, thresholds: Dictionary) -> void:
	var sums := [0.0, 0.0, 0, 0.0, 0.0, 0]   # kara: yükseklik, engebe, adet; hepsi: yükseklik, engebe, adet
	for o in offsets:
		var p := center + o
		var tx := int((p.x - base.rect.position.x) * base.terrain_px_per_unit)
		var ty := int((p.y - base.rect.position.y) * base.terrain_px_per_unit)
		if p.x < base.rect.position.x or p.y < base.rect.position.y or tx >= base.terrain_w or ty >= base.terrain_h:
			continue
		var at := (ty * base.terrain_w + tx) * 3
		var elev: float = base.terrain_px[at]
		var rug: float = base.terrain_px[at + 1]
		sums[3] += elev
		sums[4] += rug
		sums[5] += 1
		if base.country_index_at(p) != 0:
			sums[0] += elev
			sums[1] += rug
			sums[2] += 1
	var offset := 0 if sums[2] > 0 else 3
	var n: int = sums[offset + 2]
	var mean_elev := 0.0 if n == 0 else sums[offset] / n * base.elev_step_m
	var mean_rug := 0.0 if n == 0 else sums[offset + 1] / n * base.rugged_step_m
	cells.elevation_m[i] = int(mean_elev)
	cells.terrain[i] = Terrain.classify(mean_elev, mean_rug, thresholds)


## Hex'i olmayan her ülke, temsil noktasına en yakın "alınabilir" hex'i alır (okyanus veya birden çok hex'li başka ülke).
static func _guarantee_small_countries(base: BaseMap, grid: HexGrid, cells: Cells, thresholds: Dictionary, terrain_offsets: PackedVector2Array) -> void:
	var counts := PackedInt32Array()
	counts.resize(base.country_ids.size())
	for i in grid.cell_count:
		counts[cells.country_index[i]] += cells.land[i]
	for index in range(1, base.country_ids.size()):
		if counts[index] > 0:
			continue
		var anchor := EqualEarth.forward(base.country_anchor[index].x, base.country_anchor[index].y)
		var home := grid.cell_at(anchor)
		if home < 0:
			continue
		var pick := _nearest_takeable(grid, cells, counts, home, anchor)
		if pick < 0:
			continue
		var previous := cells.country_index[pick]
		counts[previous] -= cells.land[pick]
		counts[index] = 1
		var area := minf(base.country_area_km2[index], grid.area_km2())
		cells.land[pick] = 1
		cells.country_index[pick] = index
		cells.guaranteed[pick] = 1
		cells.owner_km2[pick] = area
		cells.land_km2[pick] = maxf(cells.land_km2[pick], area)
		_assign_terrain(base, cells, pick, grid.center(pick), terrain_offsets, thresholds)


static func _nearest_takeable(grid: HexGrid, cells: Cells, counts: PackedInt32Array, home: int, anchor: Vector2) -> int:
	var best := -1
	var best_d := INF
	for c in grid.cells_within(home, GUARANTEE_SEARCH_RADIUS):
		var takeable := cells.land[c] == 0 or counts[cells.country_index[c]] > 1
		var d := grid.center(c).distance_squared_to(anchor)
		if takeable and d < best_d:
			best = c
			best_d = d
	return best


# ------------------------------------------------------------------ örnekleme yardımcıları
## Hex içinde düzgün örnek ızgarası (ilk eleman merkez). Çıktı `unit_scale` ile çarpılmış (raster pikseli ya da düzlem birimi).
static func _lattice(size: float, across: float, unit_scale: float) -> PackedVector2Array:
	var step := size * EqualEarth.SQRT3 / across
	var half_w := size * EqualEarth.SQRT3 * 0.5
	var out := PackedVector2Array([Vector2.ZERO])
	var n := ceili(size / step)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var p := Vector2(i * step, j * step)
			if (i != 0 or j != 0) and absf(p.x) <= half_w and absf(p.y) + absf(p.x) / EqualEarth.SQRT3 <= size:
				out.append(p * unit_scale)
	return out


## Piksel koordinatındaki ülke indeksi (0 = deniz / raster dışı).
static func _country_at(base: BaseMap, px: Vector2) -> int:
	if px.x < 0.0 or px.y < 0.0:
		return 0
	var x := int(px.x)
	var y := int(px.y)
	if x >= base.country_w or y >= base.country_h:
		return 0
	return base.country_px[y * base.country_w + x]
