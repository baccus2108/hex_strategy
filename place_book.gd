class_name PlaceBook
extends RefCounted
## places.json: yer adları. Bir yer = ad + tür (şehir / bölge / ada) + bir veya daha fazla hex (coğrafi merkezle:
## boylam, enlem). Kara/okyanus fark etmez; herhangi bir hex'e ad verilebilir. Izgara değişince noktalar yeni ızgarada
## "noktayı içeren hex" kuralıyla çözülür (dosyadaki noktalar değişmez).

const KINDS: PackedStringArray = ["sehir", "bolge", "ada"]


class Place:
	extends RefCounted
	var id := ""
	var name := ""
	var kind := "sehir"
	var points := PackedVector2Array()     # (boylam, enlem), hex merkezleri

	func to_dict() -> Dictionary:
		var hexes: Array = []
		for p in points:
			hexes.append({"lon": JsonIO.round_coord(p.x), "lat": JsonIO.round_coord(p.y)})
		hexes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["lat"] > b["lat"] or (a["lat"] == b["lat"] and a["lon"] < b["lon"]))
		return {"ad": name, "tur": kind, "hexler": hexes}

	static func from_dict(place_id: String, d: Dictionary) -> Place:
		var p := Place.new()
		p.id = place_id
		p.name = str(d.get("ad", ""))
		p.kind = str(d.get("tur", "sehir"))
		for h: Dictionary in d.get("hexler", []):
			p.points.append(Vector2(float(h["lon"]), float(h["lat"])))
		return p

	func copy() -> Place:
		return Place.from_dict(id, to_dict())


var _places: Dictionary = {}      # id -> Place


static func kind_label(kind: String) -> String:
	match kind:
		"sehir": return TranslationServer.translate("Şehir")
		"bolge": return TranslationServer.translate("Bölge")
		"ada": return TranslationServer.translate("Ada")
	return kind


static func load_file(path: String = MapPaths.PLACES) -> PlaceBook:
	var book := PlaceBook.new()
	var data: Variant = JsonIO.read(path)
	if data is Dictionary and JsonIO.has_version(data, MapPaths.SCHEMA_VERSION, path):
		var places: Dictionary = data["places"]
		for id: String in places:
			book._places[id] = Place.from_dict(id, places[id])
	return book


func to_dict() -> Dictionary:
	var out := {}
	for id: String in _places:
		out[id] = (_places[id] as Place).to_dict()
	return {"version": MapPaths.SCHEMA_VERSION, "places": out}


func save_file(path: String = MapPaths.PLACES) -> Error:
	return JsonIO.write(path, to_dict())


# ------------------------------------------------------------------ sorgu
func has(id: String) -> bool:
	return _places.has(id)


func get_place(id: String) -> Place:
	return _places.get(id) as Place


func size() -> int:
	return _places.size()


## Ada göre sıralı yerler.
func all_places() -> Array[Place]:
	var out: Array[Place] = []
	for p: Place in _places.values():
		out.append(p)
	out.sort_custom(func(a: Place, b: Place) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	return out


## Noktaları geçerli ızgarada hücrelere çözer (tekrarsız; ızgara dışı noktalar atlanır).
static func cells_of(place: Place, grid: HexGrid) -> PackedInt32Array:
	var out := PackedInt32Array()
	for p in place.points:
		var cell := grid.cell_at(EqualEarth.forward(p.x, p.y))
		if cell >= 0 and not out.has(cell):
			out.append(cell)
	return out


## hücre -> yer kimlikleri listesi (çakışma tespiti ve etiket çizimi için).
func index_cells(grid: HexGrid) -> Dictionary:
	var index: Dictionary = {}
	for id: String in _places:
		for cell in cells_of(_places[id], grid):
			if not index.has(cell):
				index[cell] = []
			(index[cell] as Array).append(id)
	return index


# ------------------------------------------------------------------ değişiklik (komutlar çağırır)
func add(display_name: String, kind: String, points: PackedVector2Array) -> Place:
	var p := Place.new()
	p.id = unique_id(Slug.make(display_name, "yer"))
	p.name = display_name
	p.kind = kind
	p.points = points
	_places[p.id] = p
	return p


func put(place: Place) -> void:
	_places[place.id] = place


func remove(id: String) -> void:
	_places.erase(id)


func unique_id(base_id: String) -> String:
	if not _places.has(base_id):
		return base_id
	var n := 2
	while _places.has("%s_%d" % [base_id, n]):
		n += 1
	return "%s_%d" % [base_id, n]
