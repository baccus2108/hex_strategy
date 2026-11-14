class_name Terrain
extends RefCounted
## Arazi türleri ve otomatik sınıflandırma. Kimlikler ascii; görünen adlar Türkçe (tr()).
## Çöl ve tundra ASLA otomatik atanmaz; yalnız elle (editör) verilir.

const NONE := -1
const OVA := 0
const YAYLA := 1
const DAGLIK := 2
const COL := 3
const TUNDRA := 4

const IDS: PackedStringArray = ["ova", "yayla", "daglik", "col", "tundra"]
const THRESHOLDS_PATH := "res://data/terrain_thresholds.json"


static func id_of(terrain: int) -> String:
	return IDS[terrain] if terrain >= 0 and terrain < IDS.size() else ""


static func from_id(id: String) -> int:
	return IDS.find(id)


static func display_name(terrain: int) -> String:
	match terrain:
		OVA: return tr_text("Ova")
		YAYLA: return tr_text("Yayla")
		DAGLIK: return tr_text("Dağlık")
		COL: return tr_text("Çöl")
		TUNDRA: return tr_text("Tundra")
	return "—"


static func tr_text(text: String) -> String:
	return TranslationServer.translate(text)


## Eşikler: data/terrain_thresholds.json (bölge modu ile ortak). Yoksa boş sözlük döner (sınıflandırma ova verir).
static func load_thresholds() -> Dictionary:
	var parsed: Variant = JsonIO.read(THRESHOLDS_PATH)
	return parsed if parsed is Dictionary else {}


## Ortalama yükseklik (m) ve engebe (m) -> ova / yayla / dağlık.
static func classify(mean_elevation_m: float, ruggedness_m: float, thresholds: Dictionary) -> int:
	if thresholds.is_empty():
		return OVA
	var m: Dictionary = thresholds["daglik"]
	if ruggedness_m >= float(m["min_ruggedness_m"]) \
			or (mean_elevation_m >= float(m["min_mean_elevation_m"]) and ruggedness_m >= float(m["min_ruggedness_if_high_m"])):
		return DAGLIK
	var y: Dictionary = thresholds["yayla"]
	if mean_elevation_m >= float(y["min_mean_elevation_m"]) or ruggedness_m >= float(y["min_ruggedness_m"]):
		return YAYLA
	return OVA
