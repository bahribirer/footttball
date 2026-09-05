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
