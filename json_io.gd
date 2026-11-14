class_name JsonIO
extends RefCounted
## Sürüm alanlı, anahtarları sıralı (git dostu) JSON okuma/yazma. Yazma atomiktir (önce .tmp, sonra yeniden adlandırma).

const INDENT := "  "


## Dosyayı çözümler; yoksa veya bozuksa null döner (hata push_error ile bildirilir, yoksa sessiz).
static func read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("JSON hatası %s satır %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func stringify(data: Variant) -> String:
	return JSON.stringify(data, INDENT, true) + "\n"


static func write(path: String, data: Variant) -> Error:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(stringify(data))
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))


## Sözlükte "version" beklenen değerde mi? Değilse push_error ve false.
static func has_version(data: Dictionary, expected: int, label: String) -> bool:
	if int(data.get("version", -1)) == expected:
		return true
	push_error("%s: desteklenmeyen sürüm %s (beklenen %d)" % [label, str(data.get("version", "yok")), expected])
	return false


## Koordinatları git farkını küçük tutmak için yuvarlar (1e-4 derece ~ 11 m).
static func round_coord(v: float) -> float:
	return snappedf(v, 0.0001)
