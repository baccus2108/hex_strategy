class_name Slug
extends RefCounted
## Görünen addan ascii snake_case kimlik üretir ("Avusturya-Macaristan" -> "avusturya_macaristan").

const FOLD: Dictionary = {
	"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u", "â": "a", "î": "i", "û": "u",
	"é": "e", "è": "e", "á": "a", "ó": "o", "ú": "u", "ñ": "n", "ä": "a", "å": "a", "ø": "o", "ß": "ss",
}
const FALLBACK := "kayit"


## Boş sonuç `fallback` olur. Türkçe büyük İ/I doğru küçültülür.
static func make(text: String, fallback: String = FALLBACK) -> String:
	var lowered := text.replace("İ", "i").replace("I", "ı").to_lower()
	var slug := ""
	for ch in lowered:
		var c: String = FOLD.get(ch, ch)
		for part in c:
			var is_alnum := (part >= "a" and part <= "z") or (part >= "0" and part <= "9")
			if is_alnum:
				slug += part
			elif not slug.ends_with("_"):
				slug += "_"
	slug = slug.trim_prefix("_").trim_suffix("_")
	return slug if slug != "" else fallback
