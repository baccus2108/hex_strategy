# Rölyef (hillshade) görseli

**Dosya:** `relief_2048.png` (2048×1024, 8 bit gri)

## Kaynak ve lisans
- **Natural Earth, "Shaded Relief Basic" (1:50m, sürüm 2.0.0)** — https://www.naturalearthdata.com/downloads/50m-raster-data/50m-shaded-relief/
- İndirme: https://naciscdn.org/naturalearth/50m/raster/SR_50M.zip (10800×5400, WGS84 enlem-boylam, sadece kara gölgelendirmesi; su düz gri)
- Natural Earth verisi **kamu malıdır (public domain)**; izin veya atıf zorunlu değil. Yine de kullanıcıya görünen bir "Hakkında" ekranına şu satır eklenebilir: *"Made with Natural Earth."*
- Natural Earth'ün belirttiği asıl veri: SRTM Plus yükseklik verisi, 1:50m kıyı çizgisine kırpılmış.

## Bizim yaptığımız değişiklikler (`tools/build_relief.py`)
1. **Yeniden projeksiyon:** enlem-boylam → oyunun Equal Earth projeksiyonu (ters projeksiyon + 4× süper örnekleme, kutu filtresiyle küçültme).
2. **Kontrast:** su/düz arazi grisi 150'ye çekildi, sapmalar ×2.0 büyütüldü (bölgeler %55 saydam bindirildiğinde gölgeler görünsün diye). Kaynak gibi istenirse `--gain 1.0`.

## Hizalama sözleşmesi
Görüntü oyun koordinatlarında `x: [-2000, 2000]`, `y: [-1000, 1000]` dikdörtgenini kaplar (harita sınırı `y: ±973.4` bunun içinde; üst/alt ~26 birim fazlalık). Piksel kare olur. `tools/build_relief.py` çalışırken kıyı maskesi ile `data/world.json` poligonlarının çakışmasını ve ±2 piksel kaydırma testini yapar (en iyi kaydırma 0,0 olmalı).

## Yeniden üretme
```
tools\.venv\Scripts\python.exe tools\build_relief.py
```

## Hex deney modu için equirectangular sürüm
`relief_equirect_2048.png` (2048×1024): aynı kaynak ve aynı kontrast ayarı (su grisi 150, ×2.0), ama yeniden projeksiyon yok; kaynak zaten enlem-boylam olduğu için sadece küçültüldü. Hex modunun equirectangular düzleminde (x = boylam·4000/360, y = −enlem·4000/360) `x: [-2000, 2000], y: [-1000, 1000]` dikdörtgenini kaplar. Üretim: `tools\.venv\Scripts\python.exe tools\build_relief_equirect.py`
