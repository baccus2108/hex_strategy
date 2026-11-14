class_name MapProject
extends RefCounted
## Harita verisinin tamamı: base (salt okunur) + ülkeler + düzenlemeler + yerler. Oyun ve editör aynı yükleme/kurma yolunu
## kullanır. Dosyaları yalnız save_*() yazar; base'e asla dokunulmaz.

const TARGET_MIN := 500
const TARGET_MAX := 2000
const TARGET_STEP := 50
const TARGET_DEFAULT := 1000

var base: BaseMap
var countries: CountryBook
var overrides: OverrideBook
var places: PlaceBook
var land_hex_target := TARGET_DEFAULT


## Dosyalardan yükler; base yüklenemezse null.
static func load_all() -> MapProject:
	var project := MapProject.new()
	project.base = BaseMap.load_from()
	if project.base == null:
		return null
	project.countries = CountryBook.load_file()
	project.overrides = OverrideBook.load_file()
	project.places = PlaceBook.load_file()
	project.land_hex_target = clamp_target(project.overrides.land_hex_target if project.overrides.land_hex_target > 0 else TARGET_DEFAULT)
	return project


static func clamp_target(target: int) -> int:
	return clampi(roundi(float(target) / TARGET_STEP) * TARGET_STEP, TARGET_MIN, TARGET_MAX)


## Verilen hedefle haritayı kurar (düzenlemeler yeni ızgaraya taşınır).
func build(target: int) -> MapBuilder.Result:
	land_hex_target = clamp_target(target)
	return MapBuilder.build(base, countries, overrides, land_hex_target)


func save_all() -> Error:
	for save: Callable in [countries.save_file, overrides.save_file, places.save_file]:
		var err: Error = save.call()
		if err != OK:
			return err
	return OK
