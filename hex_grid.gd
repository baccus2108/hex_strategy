class_name HexGrid
extends RefCounted
## Equal Earth düzleminde sivri uçlu (pointy-top) hex ızgarası -- YALNIZ geometri; sahiplik/kara durumu MapModel'de.
## Eksenel (q, r) koordinat: merkez x = size·√3·(q + r/2), y = size·1.5·r. Sarma yok; hücreler harita bandının içindeki
## (ve Equal Earth çerçevesi içine düşen) merkezlerdir. Hücre kimliği (id) satır sırasıyla sıralıdır.
##
## Komşu yönleri: 0=D, 1=GD, 2=GB, 3=B, 4=KB, 5=KD. d. kenar = köşe[d] -- köşe[(d+1) % 6].

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
const SQRT3 := EqualEarth.SQRT3

var size := 0.0                    # hex çemberi yarıçapı (düzlem birimi)
var cell_count := 0
var bounds := Rect2()              # tüm hex köşelerini kapsayan düzlem dikdörtgeni
var cell_q := PackedInt32Array()
var cell_r := PackedInt32Array()
var _row_r0 := 0
var _row_q0 := PackedInt32Array()
var _row_len := PackedInt32Array()
var _row_start := PackedInt32Array()


func _init(hex_size: float) -> void:
	size = hex_size
	_build_rows()


# ------------------------------------------------------------------ statik geometri (ızgara kurmadan, boyut verilerek)
static func axial_to_plane(hex_size: float, q: int, r: int) -> Vector2:
	return Vector2(hex_size * SQRT3 * (q + r * 0.5), hex_size * 1.5 * r)


## Düzlem noktasını içeren hex'in eksenel koordinatı (ızgara sınırının dışında da geçerli).
static func plane_to_axial(hex_size: float, p: Vector2) -> Vector2i:
	var fq := (SQRT3 / 3.0 * p.x - p.y / 3.0) / hex_size
	var fr := (2.0 / 3.0 * p.y) / hex_size
	var rq := roundf(fq)
	var rr := roundf(fr)
	var rs := roundf(-fq - fr)
	var dq := absf(rq - fq)
	var dr := absf(rr - fr)
	var ds := absf(rs - (-fq - fr))
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


static func corner_offset(hex_size: float, k: int) -> Vector2:
	var a := deg_to_rad(60.0 * k - 30.0)
	return Vector2(cos(a), sin(a)) * hex_size


# ------------------------------------------------------------------ kurulum
func _build_rows() -> void:
	var y_top := EqualEarth.band_top()
	var y_bottom := EqualEarth.band_bottom()
	var r_min := ceili(y_top / (1.5 * size))
	var r_max := floori(y_bottom / (1.5 * size))
	_row_r0 = r_min
	var step_x := size * SQRT3
	var total := 0
	var rect_min := Vector2(INF, INF)
	var rect_max := Vector2(-INF, -INF)
	for r in range(r_min, r_max + 1):
		var limit := EqualEarth.half_width_at(1.5 * size * r) + step_x * 0.5
		var q0 := ceili(-limit / step_x - r * 0.5)
		var q1 := floori(limit / step_x - r * 0.5)
		_row_q0.append(q0)
		_row_len.append(maxi(0, q1 - q0 + 1))
		_row_start.append(total)
		total += _row_len[_row_len.size() - 1]
		if q1 >= q0:
			rect_min = rect_min.min(axial_to_plane(size, q0, r))
			rect_max = rect_max.max(axial_to_plane(size, q1, r))
	cell_count = total
	cell_q.resize(total)
	cell_r.resize(total)
	for row in _row_len.size():
		for j in _row_len[row]:
			cell_q[_row_start[row] + j] = _row_q0[row] + j
			cell_r[_row_start[row] + j] = _row_r0 + row
	bounds = Rect2(rect_min - Vector2(step_x * 0.5, size), rect_max - rect_min + Vector2(step_x, size * 2.0))


# ------------------------------------------------------------------ geometri ve kimlik
func hex_width() -> float:
	return size * SQRT3


func area_units() -> float:
	return 1.5 * SQRT3 * size * size


func area_km2() -> float:
	return area_units() * EqualEarth.KM2_PER_UNIT2


## Gösterim için: hex'in düz kenardan düz kenara genişliği (km), eşit alan varsayımıyla (haritanın her yerinde aynı alan).
func width_km() -> float:
	return sqrt(area_km2() / (SQRT3 / 2.0))


func index_of(q: int, r: int) -> int:
	var row := r - _row_r0
	if row < 0 or row >= _row_len.size():
		return -1
	var j := q - _row_q0[row]
	return _row_start[row] + j if j >= 0 and j < _row_len[row] else -1


func center(i: int) -> Vector2:
	return axial_to_plane(size, cell_q[i], cell_r[i])


func corners(i: int) -> PackedVector2Array:
	var c := center(i)
	var out := PackedVector2Array()
	for k in 6:
		out.append(c + corner_offset(size, k))
	return out


## Düzlem noktasındaki hücre; ızgara dışındaysa -1.
func cell_at(p: Vector2) -> int:
	var a := plane_to_axial(size, p)
	return index_of(a.x, a.y)


func neighbor(i: int, d: int) -> int:
	return index_of(cell_q[i] + DIRS[d].x, cell_r[i] + DIRS[d].y)


## Var olan komşular (ızgara dışındakiler atlanır).
func neighbors(i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for d in 6:
		var n := neighbor(i, d)
		if n >= 0:
			out.append(n)
	return out


static func axial_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) >> 1


func distance(a: int, b: int) -> int:
	return axial_distance(Vector2i(cell_q[a], cell_r[a]), Vector2i(cell_q[b], cell_r[b]))


## Merkez dahil, merkeze ≤ radius adım uzaklıktaki hücreler (ızgara içindekiler).
func cells_within(i: int, radius: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var q0 := cell_q[i]
	var r0 := cell_r[i]
	for dq in range(-radius, radius + 1):
		for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			var n := index_of(q0 + dq, r0 + dr)
			if n >= 0:
				out.append(n)
	return out
