class_name CountryBook
extends RefCounted
## countries.json: ülke kimliği (ascii, addan otomatik), ad, renk, dahil, ada, absorbs. Kimlik oluşturulunca DEĞİŞMEZ
## (ad değişse de), çünkü overrides/places dosyaları kimliğe bağlıdır.

const COLOR_WARN_DELTA_E := 12.0
const FALLBACK_COLOR := Color(0.62, 0.66, 0.72)

class Entry:
	extends RefCounted
	var id := ""
	var name := ""
	var color := FALLBACK_COLOR
	var included := true       # dahil: oyunda oynanabilir/yer alan ülke
	var island := false        # ada/takımada ülkesi: kopuk parça uyarısı verilmez
	var absorbs := PackedStringArray()   # katılan elenmiş ülkelerin adları (bilgi)

	func to_dict() -> Dictionary:
		return {"ad": name, "renk": "#" + color.to_html(false).to_upper(), "dahil": included, "ada": island, "absorbs": Array(absorbs)}

	static func from_dict(entry_id: String, d: Dictionary) -> Entry:
		var e := Entry.new()
		e.id = entry_id
		e.name = str(d.get("ad", entry_id))
		e.color = Color.html(str(d.get("renk", "#9AA3AD")))
		e.included = bool(d.get("dahil", true))
		e.island = bool(d.get("ada", false))
		e.absorbs = PackedStringArray(d.get("absorbs", []))
		return e

	func copy() -> Entry:
		return Entry.from_dict(id, to_dict())


var _entries: Dictionary = {}     # id -> Entry


# ------------------------------------------------------------------ dosya
static func load_file(path: String = MapPaths.COUNTRIES) -> CountryBook:
	var book := CountryBook.new()
	var data: Variant = JsonIO.read(path)
	if data is Dictionary and JsonIO.has_version(data, MapPaths.SCHEMA_VERSION, path):
		var countries: Dictionary = data["countries"]
		for id: String in countries:
			book._entries[id] = Entry.from_dict(id, countries[id])
	return book


func to_dict() -> Dictionary:
	var out := {}
	for id: String in _entries:
		out[id] = (_entries[id] as Entry).to_dict()
	return {"version": MapPaths.SCHEMA_VERSION, "countries": out}


func save_file(path: String = MapPaths.COUNTRIES) -> Error:
	return JsonIO.write(path, to_dict())


# ------------------------------------------------------------------ sorgu
func has(id: String) -> bool:
	return _entries.has(id)


func get_entry(id: String) -> Entry:
	return _entries.get(id) as Entry


func size() -> int:
	return _entries.size()


func color_of(id: String) -> Color:
	return (_entries[id] as Entry).color if _entries.has(id) else FALLBACK_COLOR


func name_of(id: String) -> String:
	return (_entries[id] as Entry).name if _entries.has(id) else id


## Ada göre (Türkçe duyarsız) sıralı kimlikler.
func ids_by_name(only_included := false) -> PackedStringArray:
	var list: Array = _entries.values().filter(func(e: Entry) -> bool: return e.included or not only_included)
	list.sort_custom(func(a: Entry, b: Entry) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	var out := PackedStringArray()
	for e: Entry in list:
		out.append(e.id)
	return out


# ------------------------------------------------------------------ değişiklik (komutlar bunları çağırır)
## Yeni ülke ekler; kimlik addan türetilir, çakışırsa _2, _3 eklenir.
func add(display_name: String, color: Color) -> Entry:
	var e := Entry.new()
	e.id = unique_id(Slug.make(display_name, "ulke"))
	e.name = display_name
	e.color = color
	_entries[e.id] = e
	return e


## Var olan bir kaydı olduğu gibi geri koyar (geri alma).
func put(entry: Entry) -> void:
	_entries[entry.id] = entry


func remove(id: String) -> void:
	_entries.erase(id)


func unique_id(base_id: String) -> String:
	if not _entries.has(base_id):
		return base_id
	var n := 2
	while _entries.has("%s_%d" % [base_id, n]):
		n += 1
	return "%s_%d" % [base_id, n]


# ------------------------------------------------------------------ yardımcılar
## CIE76 renk farkı (Lab uzayında Öklid). ~2 = fark edilemez, <12 = karıştırılabilir.
static func color_distance(a: Color, b: Color) -> float:
	return _to_lab(a).distance_to(_to_lab(b))


static func _to_lab(c: Color) -> Vector3:
	var lin := Color(_srgb_to_linear(c.r), _srgb_to_linear(c.g), _srgb_to_linear(c.b))
	var x := (0.4124564 * lin.r + 0.3575761 * lin.g + 0.1804375 * lin.b) / 0.95047
	var y := 0.2126729 * lin.r + 0.7151522 * lin.g + 0.0721750 * lin.b
	var z := (0.0193339 * lin.r + 0.1191920 * lin.g + 0.9503041 * lin.b) / 1.08883
	var fx := _lab_f(x)
	var fy := _lab_f(y)
	var fz := _lab_f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func _srgb_to_linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0


## Çok yakın renkli "dahil" ülke çiftleri: [[id_a, id_b, delta_e], ...] (en yakın önce).
func close_color_pairs(threshold: float = COLOR_WARN_DELTA_E) -> Array:
	var ids := ids_by_name(true)
	var out: Array = []
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var d := color_distance(color_of(ids[i]), color_of(ids[j]))
			if d < threshold:
				out.append([ids[i], ids[j], d])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
	return out


## Bir ülkenin rengi başka bir "dahil" ülkeye çok yakınsa o ülkenin kimliği, değilse "".
func closest_conflict(id: String, threshold: float = COLOR_WARN_DELTA_E) -> String:
	var worst := ""
	var worst_d := threshold
	for other in ids_by_name(true):
		if other == id:
			continue
		var d := color_distance(color_of(id), color_of(other))
		if d < worst_d:
			worst_d = d
			worst = other
	return worst
