class_name EqualEarth
extends RefCounted
## Equal Earth izdüşümü (Šavrič, Patterson, Jenny 2018) -- projenin TEK projeksiyonu. Eşit alanlıdır; sarma yoktur.
## Düzlem: x sağa, y AŞAĞI (ekran gibi); genişlik MAP_WIDTH birim; (0, 0) = (boylam 0, enlem 0).
## Python karşılığı: tools/build_world.py (aynı sabitler; testle doğrulanır).

const A1 := 1.340264
const A2 := -0.081106
const A3 := 0.000893
const A4 := 0.003796
const SQRT3 := 1.7320508075688772
const MAP_WIDTH := 4000.0
const EARTH_RADIUS_KM := 6371.0072
## Haritanın gösterdiği enlem bandı (Antarktika dışarıda).
const LAT_MIN := -60.0
const LAT_MAX := 80.0

const HALF_WIDTH_RAW := 2.0 * SQRT3 * PI / (3.0 * A1)
const SCALE := MAP_WIDTH / (2.0 * HALF_WIDTH_RAW)
const KM_PER_UNIT := EARTH_RADIUS_KM / SCALE
const KM2_PER_UNIT2 := KM_PER_UNIT * KM_PER_UNIT
const NEWTON_STEPS := 12


## (boylam, enlem) derece -> düzlem noktası.
static func forward(lon_deg: float, lat_deg: float) -> Vector2:
	var th := asin(SQRT3 / 2.0 * sin(deg_to_rad(lat_deg)))
	var th2 := th * th
	var th6 := th2 * th2 * th2
	var x := 2.0 * SQRT3 * deg_to_rad(lon_deg) * cos(th) / (3.0 * (9.0 * A4 * th6 * th2 + 7.0 * A3 * th6 + 3.0 * A2 * th2 + A1))
	var y := th * (A1 + A2 * th2 + th6 * (A3 + A4 * th2))
	return Vector2(x * SCALE, -y * SCALE)


## Düzlem noktası -> Vector2(boylam, enlem) derece. Kürenin dışındaki noktalar için boylam ±180'i aşar.
static func inverse(p: Vector2) -> Vector2:
	var big_x := p.x / SCALE
	var big_y := -p.y / SCALE
	var th := clampf(big_y / A1, -PI / 3.0, PI / 3.0)
	for _i in NEWTON_STEPS:
		var th2 := th * th
		var th6 := th2 * th2 * th2
		var f := th * (A1 + A2 * th2 + th6 * (A3 + A4 * th2)) - big_y
		var df := A1 + 3.0 * A2 * th2 + th6 * (7.0 * A3 + 9.0 * A4 * th2)
		th = clampf(th - f / df, -PI / 3.0, PI / 3.0)
	var th2 := th * th
	var th6 := th2 * th2 * th2
	var lat := rad_to_deg(asin(2.0 * sin(th) / SQRT3))
	var lon := rad_to_deg(3.0 * big_x * (A1 + 3.0 * A2 * th2 + th6 * (7.0 * A3 + 9.0 * A4 * th2)) / (2.0 * SQRT3 * cos(th)))
	return Vector2(lon, lat)


## Verilen y'de harita kenarının (boylam ±180) x değeri; harita bu yükseklikte [-w, +w] arasındadır.
static func half_width_at(y: float) -> float:
	return forward(180.0, inverse(Vector2(0.0, y)).y).x


## Haritanın enlem bandının üst (kuzey, küçük y) ve alt (güney, büyük y) düzlem sınırı.
static func band_top() -> float:
	return forward(0.0, LAT_MAX).y


static func band_bottom() -> float:
	return forward(0.0, LAT_MIN).y
