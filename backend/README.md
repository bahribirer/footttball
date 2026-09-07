# Tiki Taka Toe — Backend

FastAPI + SQLite üzerinde çalışan oyun sunucusu. REST uçları içerik (tahta,
oyuncu arama, logo, kategori) sağlar; WebSocket katmanı oda ve oyun akışını
yönetir.

## Dizin yapısı

```
backend/
├── app/
│   ├── main.py                 FastAPI uygulaması, yaşam döngüsü
│   ├── core/config.py          Ortam değişkenleri ve oyun sabitleri
│   ├── db/
│   │   ├── database.py         Bağlantı yardımcıları (context manager)
│   │   └── reference_data.py   Kulüp/bayrak eşlemeleri, büyük takımlar
│   ├── models/schemas.py       Pydantic istek/yanıt şemaları
│   ├── services/               İş mantığı (veritabanına dokunan katman)
│   │   ├── grid_service.py     Tiki Taka Toe 3x3 tahtası
│   │   ├── pool_service.py     Oyuncu Tahmin 5x5 tahtası
│   │   ├── player_service.py   Arama ve tahmin doğrulama
│   │   ├── category_service.py Kategori havuzu ve doğrulama
│   │   ├── logo_service.py     Logo indirme/önbellek
│   │   └── country_service.py  Ülke -> ISO kodu
│   ├── api/v1/                 HTTP uçları
│   └── realtime/               WebSocket katmanı
│       ├── gateway.py          /ws/v2/{code} — protokol v2
│       ├── legacy.py           /ws/{room_id} — eski istemciler
│       ├── hub.py              Oda kayıt defteri ve temizlik
│       ├── room.py             Oda/oyuncu durumu
│       ├── protocol.py         Mesaj tipleri
│       └── modes/              Oyun modu motorları
├── scripts/                    Tek seferlik veri betikleri (import, düzeltme)
├── data/tikitakapi.db          Oyuncu veritabanı (depoya dahil değil)
└── static/logos/               Logo önbelleği (çalışma sırasında dolar)
```

## Veritabanı

`data/tikitakapi.db` (~33 MB) depoya dahil edilmez. Sunucudaki kopyayı
indirin ya da mevcut kopyayı bu dizine koyun:

```bash
scp -i ~/tikitaka.pem ubuntu@<sunucu>:/srv/tikitakatoe/backend/data/tikitakapi.db backend/data/
```

Tablolar: `players` (161.888 satır), `clubs` (573 satır).

## Yerel çalıştırma

```bash
cd backend
python3.12 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn app.main:app --reload --port 8000
```

Docker ile:

```bash
docker compose -f docker-compose.dev.yml up --build     # kök dizinde
```

Mobil uygulamayı yerel sunucuya bağlamak için:

```bash
flutter run --dart-define=API_BASE=http://127.0.0.1:8000 \
            --dart-define=WS_BASE=ws://127.0.0.1:8000
```

## WebSocket protokolü (v2)

Bağlantı: `wss://tikitakatoe.com/ws/v2/{oda_kodu}?name=<ad>&mode=<mod>`

İstemci → sunucu:

| type      | açıklama                                              |
|-----------|-------------------------------------------------------|
| `ping`    | canlılık sinyali (20 sn'de bir)                        |
| `relay`   | ham aktarım — yalnızca Tiki Taka Toe                   |
| `action`  | oyun hamlesi (`pick`, `guess`, `answer`, `next_round`) |
| `rematch` | rövanş oyu                                             |
| `leave`   | odadan ayrıl                                           |

Sunucu → istemci: `joined`, `room`, `start`, `state`, `event`, `over`,
`relay`, `opponent_left`, `error`, `pong`.

Eski `/ws/{room_id}` uç noktası mağazadaki eski sürümler için korunmuştur.

## Oyun modları

| Mod              | Oyun mantığı | Süre                    | Ceza |
|------------------|--------------|-------------------------|------|
| `tiki_taka_toe`  | istemci      | tur başına 30 sn        | —    |
| `player_guess`   | sunucu       | 5 tur, cevap için 30 sn | deneme hakkı (3) |
| `last_letter`    | sunucu       | oyuncu başına 50 sn     | 3 sn |
| `category_race`  | sunucu       | oyuncu başına 50 sn     | 3 sn |

## Ortam değişkenleri

| Değişken               | Varsayılan                  |
|------------------------|-----------------------------|
| `ENVIRONMENT`          | `development`               |
| `DEBUG`                | `false`                     |
| `DB_PATH`              | `backend/data/tikitakapi.db`|
| `LOGO_DIR`             | `backend/static/logos`      |
| `WS_IDLE_TIMEOUT_SECONDS` | `90`                     |
| `EMPTY_ROOM_TTL_SECONDS`  | `120`                    |

## Yeni oyun modu eklemek

İskeleti üreteç kurar:

```bash
python backend/scripts/new_mode.py son_dakika "Son Dakika"
```

Ürettikleri: mod motoru, testi, Flutter ekranı. Kaydettikleri: `protocol.py`
enum'u, `hub.py` motor eşlemesi, `mode_service.py` etiket ve sürüm eşiği,
`game_mode.dart` enum girdisi.

Kalan elle işler (ilk ikisi zaten derleme hatası verir):

1. `lib/features/lobby/vs_screen.dart` — ekranı yönlendir
2. `lib/features/lobby/waiting_room_screen.dart` — kural özeti
3. `lib/features/lobby/create_room_screen.dart` — oda ayarları
4. `test/responsive_test.dart` — ekran boyutu testi

Doğrulama: `pytest tests/test_mode_registry.py` — her modun motoru, etiketi,
sürüm eşiği ve katalog kaydı var mı bakar, ayrıca `protocol.py` ile
`game_mode.dart` id'lerini karşılaştırır.

### Modu açıp kapatmak

Mod listesi `GET /api/v1/modes` ile sunucudan geliyor. Yeni modu kapalı
gönderip hazır olunca açabilir, bozulursa App Review beklemeden
kapatabilirsiniz:

```bash
# sunucuda
echo 'MODES_DISABLED=son_dakika' >> .env && docker compose up -d
```

## Veri katmanları

Cevap doğrulaması üç katmana sırayla bakar:

| Katman | Kaynak | Ne için |
|---|---|---|
| `players` | sezon anlık görüntüleri | ana veri |
| `squad_updates` | Wikipedia, haftalık | son transfer dönemi |
| `club_history` | Wikidata, aylık | eski kadrolar ve uyruklar |

`name_tokens` bunların isimlerini kelimelerine ayırıp indeksler. Katmanlar
değiştiğinde yeniden kurulmalı:

```bash
python backend/scripts/build_name_tokens.py
```

Atlanırsa aramalar doğru çalışır ama tam taramaya düşer — ölçümde
`verify_player` 2.6 ms yerine ~110 ms.
