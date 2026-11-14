class_name MapValidator
extends RefCounted
## Harita tutarlılık denetimi (saf mantık; paneli editör çizer). Her sorunun haritada gidilecek bir konumu olabilir.

enum Kind { EMPTY_COUNTRY, DISCONNECTED, NEUTRAL_LAND, UNNAMED_PLACE, DUPLICATE_PLACE, OVERLAPPING_PLACE, PLACE_OUTSIDE, ORPHAN_EDIT, CLOSE_COLORS }


class Issue:
	extends RefCounted
	var kind := Kind.EMPTY_COUNTRY
	var text := ""
	var point := Vector2(INF, INF)      # düzlem konumu; INF = gidilecek yer yok
	var data := {}                      # tür'e özel (örn. orphan_index, place_id)

	func has_point() -> bool:
		return is_finite(point.x)


static func validate(model: MapModel, countries: CountryBook, places: PlaceBook) -> Array[Issue]:
	var issues: Array[Issue] = []
	_check_countries(model, countries, issues)
	_check_neutral_land(model, issues)
	_check_places(model, places, issues)
	_check_orphans(model, issues)
	_check_colors(countries, issues)
	return issues


static func _make(kind: Kind, text: String, point := Vector2(INF, INF), data := {}) -> Issue:
	var issue := Issue.new()
	issue.kind = kind
	issue.text = text
	issue.point = point
	issue.data = data
	return issue


# ------------------------------------------------------------------ ülkeler
static func _check_countries(model: MapModel, countries: CountryBook, out: Array[Issue]) -> void:
	var cells_of: Dictionary = {}
	for i in model.grid.cell_count:
		if model.land[i] == 1 and model.owner[i] != "":
			if not cells_of.has(model.owner[i]):
				cells_of[model.owner[i]] = PackedInt32Array()
			(cells_of[model.owner[i]] as PackedInt32Array).append(i)
	for id in countries.ids_by_name(true):
		var entry := countries.get_entry(id)
		if not cells_of.has(id):
			out.append(_make(Kind.EMPTY_COUNTRY, TranslationServer.translate("%s: hiç hex'i yok") % entry.name, _anchor_of(model, id)))
		elif not entry.island:
			_report_pieces(model, entry, cells_of[id], out)


static func _anchor_of(model: MapModel, id: String) -> Vector2:
	var index := model.base.index_of_country(id)
	if index <= 0:
		return Vector2(INF, INF)
	return EqualEarth.forward(model.base.country_anchor[index].x, model.base.country_anchor[index].y)


## Ülkenin bağlı parçaları; en büyüğü dışındakiler "kopuk parça" olarak bildirilir.
static func _report_pieces(model: MapModel, entry: CountryBook.Entry, cells: PackedInt32Array, out: Array[Issue]) -> void:
	var pieces := _components(model, cells)
	if pieces.size() <= 1:
		return
	pieces.sort_custom(func(a: PackedInt32Array, b: PackedInt32Array) -> bool: return a.size() > b.size())
	for k in range(1, pieces.size()):
		var piece: PackedInt32Array = pieces[k]
		out.append(_make(Kind.DISCONNECTED, TranslationServer.translate("%s: kopuk parça (%d hex)") % [entry.name, piece.size()],
				model.grid.center(piece[0])))


static func _check_neutral_land(model: MapModel, out: Array[Issue]) -> void:
	var neutral := PackedInt32Array()
	for i in model.grid.cell_count:
		if model.land[i] == 1 and model.owner[i] == "":
			neutral.append(i)
	for piece: PackedInt32Array in _components(model, neutral):
		out.append(_make(Kind.NEUTRAL_LAND, TranslationServer.translate("Sahipsiz kara (%d hex)") % piece.size(), model.grid.center(piece[0])))


## `cells` kümesinin komşuluk bileşenleri.
static func _components(model: MapModel, cells: PackedInt32Array) -> Array[PackedInt32Array]:
	var left: Dictionary = {}
	for c in cells:
		left[c] = true
	var out: Array[PackedInt32Array] = []
	for c in cells:
		if not left.has(c):
			continue
		left.erase(c)
		var piece := PackedInt32Array([c])
		var head := 0
		while head < piece.size():
			for n in model.grid.neighbors(piece[head]):
				if left.has(n):
					left.erase(n)
					piece.append(n)
			head += 1
		out.append(piece)
	return out


# ------------------------------------------------------------------ yerler
static func _check_places(model: MapModel, places: PlaceBook, out: Array[Issue]) -> void:
	var by_name: Dictionary = {}
	for place in places.all_places():
		var cells := PlaceBook.cells_of(place, model.grid)
		var point := model.grid.center(cells[0]) if not cells.is_empty() else Vector2(INF, INF)
		var label := place.name if place.name.strip_edges() != "" else place.id
		if place.name.strip_edges() == "":
			out.append(_make(Kind.UNNAMED_PLACE, TranslationServer.translate("Adsız yer (%s)") % place.id, point, {"place_id": place.id}))
		else:
			var key := place.name.strip_edges().to_lower()
			by_name[key] = (by_name.get(key, []) as Array) + [place.id]
		if cells.size() < place.points.size():
			out.append(_make(Kind.PLACE_OUTSIDE, TranslationServer.translate("%s: hex'lerinin bir kısmı haritanın dışında veya aynı hex'e düşüyor") % label,
					point, {"place_id": place.id}))
	for key: String in by_name:
		var ids: Array = by_name[key]
		if ids.size() > 1:
			var first := places.get_place(ids[0])
			var cells := PlaceBook.cells_of(first, model.grid)
			out.append(_make(Kind.DUPLICATE_PLACE, TranslationServer.translate("Aynı ada sahip %d yer: %s") % [ids.size(), first.name],
					model.grid.center(cells[0]) if not cells.is_empty() else Vector2(INF, INF), {"place_id": ids[0]}))
	_check_overlaps(model, places, out)


static func _check_overlaps(model: MapModel, places: PlaceBook, out: Array[Issue]) -> void:
	var seen_pairs: Dictionary = {}
	var index := places.index_cells(model.grid)
	for cell: int in index:
		var ids: Array = index[cell]
		if ids.size() < 2:
			continue
		ids.sort()
		var key := ",".join(PackedStringArray(ids))
		if seen_pairs.has(key):
			continue
		seen_pairs[key] = true
		var names := PackedStringArray()
		for id: String in ids:
			names.append(places.get_place(id).name)
		out.append(_make(Kind.OVERLAPPING_PLACE, TranslationServer.translate("Çakışan yerler: %s") % ", ".join(names), model.grid.center(cell),
				{"place_id": ids[0]}))


# ------------------------------------------------------------------ düzenlemeler ve renkler
static func _check_orphans(model: MapModel, out: Array[Issue]) -> void:
	for k in model.overrides.orphans.size():
		var o: Dictionary = model.overrides.orphans[k]
		out.append(_make(Kind.ORPHAN_EDIT, "%s (%.2f, %.2f): %s" % [TranslationServer.translate("Taşınamayan düzenleme"), o["lon"], o["lat"], o["reason"]],
				EqualEarth.forward(float(o["lon"]), float(o["lat"])), {"orphan_index": k}))


static func _check_colors(countries: CountryBook, out: Array[Issue]) -> void:
	for pair: Array in countries.close_color_pairs():
		out.append(_make(Kind.CLOSE_COLORS, TranslationServer.translate("Renkler çok yakın: %s ve %s") % [countries.name_of(pair[0]), countries.name_of(pair[1])]))
