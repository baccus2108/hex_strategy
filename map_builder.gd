class_name MapBuilder
extends RefCounted
## (base, ülkeler, düzenlemeler, land_hex_target) -> MapModel. Oyun ve editör aynı yolu kullanır (MapProject.build).
## Düzenlemeler yeni ızgaraya taşınır (OverrideBook.migrate_to); rapor çağırana döner. Dosya yazmaz.


class Result:
	extends RefCounted
	var model: MapModel
	var migration := {"moved": 0, "lost": 0, "produced": 0}
	var elapsed_ms := 0


static func build(base: BaseMap, countries: CountryBook, overrides: OverrideBook, target: int) -> Result:
	var started := Time.get_ticks_msec()
	var result := Result.new()
	var grid := HexGenerator.grid_for_target(base, target)
	var gen := HexGenerator.generate(base, grid)
	result.migration = overrides.migrate_to(grid, target)
	result.model = MapModel.create(base, grid, target, gen, countries, overrides)
	result.elapsed_ms = Time.get_ticks_msec() - started
	return result
