class_name BaseMap
extends RefCounted
## Üretilmiş base veri (tools/build_base_map.py): ülke rasteri + arazi rasteri + ülke listesi. SALT OKUNUR.
## Raster Equal Earth düzleminde `rect` dikdörtgenini kaplar; piksel (x, y) = (düzlem - rect.position) · px_per_unit.

var rect := Rect2()
var relief_path := ""
var country_ids := PackedStringArray([""])     # raster indeksi -> ülke kimliği (0 = deniz)
var country_area_km2 := PackedFloat32Array([0.0])
var country_anchor := PackedVector2Array([Vector2.ZERO])   # (boylam, enlem)

var country_px := PackedByteArray()
var country_w := 0
var country_h := 0
var country_px_per_unit := 0.0

var terrain_px := PackedByteArray()            # RGB8: R = yükseklik/elev_step, G = engebe/rugged_step
var terrain_w := 0
var terrain_h := 0
var terrain_px_per_unit := 0.0
var elev_step_m := 32.0
var rugged_step_m := 16.0


## Yükleme başarısızsa null döner.
static func load_from(path: String = MapPaths.BASE) -> BaseMap:
	var meta: Variant = JsonIO.read(path)
	if not (meta is Dictionary) or not JsonIO.has_version(meta, MapPaths.SCHEMA_VERSION, path):
		return null
	var m := BaseMap.new()
	var r: Array = meta["rect"]
	m.rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	m.relief_path = str((meta["relief"] as Dictionary)["file"])
	for c: Dictionary in meta["countries"]:
		m.country_ids.append(str(c["id"]))
		m.country_area_km2.append(float(c["area_km2"]))
		var a: Dictionary = c["anchor"]
		m.country_anchor.append(Vector2(float(a["lon"]), float(a["lat"])))
	var cr: Dictionary = meta["country_raster"]
	var img := _load_pixels(str(cr["file"]), Image.FORMAT_L8)
	var tr_meta: Dictionary = meta["terrain_raster"]
	var timg := _load_pixels(str(tr_meta["file"]), Image.FORMAT_RGB8)
	if img == null or timg == null:
		return null
	m.country_px = img.get_data()
	m.country_w = img.get_width()
	m.country_h = img.get_height()
	m.country_px_per_unit = m.country_w / m.rect.size.x
	m.terrain_px = timg.get_data()
	m.terrain_w = timg.get_width()
	m.terrain_h = timg.get_height()
	m.terrain_px_per_unit = m.terrain_w / m.rect.size.x
	m.elev_step_m = float(tr_meta["elev_step_m"])
	m.rugged_step_m = float(tr_meta["rugged_step_m"])
	return m


## İçe aktarılmış dokudan (dışa aktarılan oyunda da çalışır) görüntü verisi.
static func _load_pixels(path: String, format: Image.Format) -> Image:
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("Raster yüklenemedi: %s" % path)
		return null
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	if img.get_format() != format:
		img.convert(format)
	return img


func country_count() -> int:
	return country_ids.size() - 1


func index_of_country(id: String) -> int:
	return country_ids.find(id)


## Düzlem noktasındaki ülke rasteri indeksi (0 = deniz veya raster dışı).
func country_index_at(p: Vector2) -> int:
	var x := int((p.x - rect.position.x) * country_px_per_unit)
	var y := int((p.y - rect.position.y) * country_px_per_unit)
	if x < 0 or y < 0 or x >= country_w or y >= country_h:
		return 0
	return country_px[y * country_w + x]


func land_area_units() -> float:
	var total := 0.0
	for a in country_area_km2:
		total += a
	return total / EqualEarth.KM2_PER_UNIT2
