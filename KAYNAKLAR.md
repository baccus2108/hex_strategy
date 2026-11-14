# Veri kaynakları ve lisanslar

| Veri | Kaynak | Lisans | Kullanıldığı yer |
|---|---|---|---|
| Ülke/kıyı sınırları | Natural Earth 1:50m Admin 0 – Countries | Kamu malı (public domain) | `data/world.json`, `data/regions_stats.json`, `data/adjacency.json` |
| Gölgeli rölyef | Natural Earth `SR_50M` (Shaded Relief) | Kamu malı | `assets/relief/relief_2048.png` (ayrıntı: `assets/relief/KAYNAK.md`) |
| Yükseklik (DEM) | AWS Terrain Tiles, Terrarium biçimi, zoom 4 (`s3.amazonaws.com/elevation-tiles-prod/terrarium`) | Verinin kendisi açık; kaynak veri setleri (SRTM, GMTED2010, ETOPO1, ulusal DEM'ler) için atıf gerekir: https://github.com/tilezen/joerd/blob/master/docs/attribution.md | `data/terrain.json` (yalnızca ortalama yükseklik ve engebe sayıları; ham karolar depoda **yok**, geçici önbellekte) |
| Projeksiyon | Equal Earth (Šavrič, Patterson, Jenny 2018) | Yayımlanmış denklem | `tools/build_world.py`, `tools/geo_common.py` |
| Equirectangular rölyef (hex deney modu) | Natural Earth `SR_50M`, yalnızca küçültülmüş (yeniden projeksiyon yok) | Kamu malı | `assets/relief/relief_equirect_2048.png` (`tools/build_relief_equirect.py`) |
| Hex ızgarası (deney modu) | Bizim türetmemiz: `world.json` + `countries.json` + Terrarium DEM'den | Kaynakların lisansları geçerli | `data/hexmap.json`, `data/hex_city_proposals.json` (`tools/build_hexmap.py`) |
| Ülke/şehir listesi | Proje sahibi (`data/countries.json`) | Proje sahibine ait | tüm veri hattı |
| Zirve koordinatları | Genel kamu bilgisi (Wikipedia/Wikidata değerleri, ~0,01°) | Olgusal veri | `data/landmarks.json` |
| Sıradağ çizgileri | Elle seçilmiş şematik omurga noktaları | Proje içi üretim | `data/landmarks.json` |
| Yazı tipi | Barlow (Jeremy Tribby) | SIL Open Font License 1.1 | `assets/fonts/` |

## Notlar
- Alan hesabı Equal Earth'ün eşit-alan özelliğine dayanır; küresel formülle çapraz kontrol: `tools/reports/areas.md`.
- Arazi etiketleri otomatik (ova/yayla/dağlık); çöl/tundra yalnızca onaylı öneriler (`data/terrain_overrides.json`) ile eklenir.
