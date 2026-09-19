# Tiki Taka Toe

Futbol bilgisi üzerine kurulu, iki kişilik gerçek zamanlı mobil oyun.
Oyuncular oda koduyla buluşur ve dört moddan birinde yarışır.

```
footttball/
├── lib/                 Flutter uygulaması
├── backend/             FastAPI sunucusu (bkz. backend/README.md)
├── infra/nginx/         Ters vekil yapılandırması
├── integration_test/    Uçtan uca arayüz testleri
├── docker-compose.yml   Üretim yığını (backend + nginx + certbot)
└── docker-compose.dev.yml
```

## Oyun modları

| Mod | Nasıl oynanır | Süre / ceza |
|-----|---------------|-------------|
| **Tiki Taka Toe** | 3x3 tahtada kulüp × millet kesişimine uyan futbolcuyu yaz, üç taşı tamamla | Tur başına 30 sn |
| **Oyuncu Tahmin** | Biri 5 milli takımdan, diğeri 5 kulüpten seçer; eşleşmeye uyan futbolcuyu ilk bilen turu alır | 5 tur, tur başına 3 deneme |
| **Kariyer Yolu** | Futbolcunun kulüp yolu kısmen açık gelir; kim olduğunu ilk bilen turu alır. Maç boyunca 3 ipucu hakkı | Tur başına 60 sn, 10 sn'de bir kulüp açılır |
| **Kategori Yarışı** | Verilen kategoriye uyan futbolcular sırayla yazılır | Oyuncu başına 50 sn, yanlışta −3 sn |

Süre tabanlı modlarda saat yalnızca sırası gelen oyuncu için işler; süresi
ilk biten kaybeder. Tüm cevaplar 161.888 kayıtlık oyuncu veritabanına karşı
doğrulanır; 110 bin oyunculuk kulüp tarihçesi katmanı efsaneleri de kapsar.

Her mod rakip beklemeden **bota karşı** da oynanabilir (kolay / orta / zor).
Bot çözümü okumaz; veritabanından, insan gibi tahmin eder. Online
maçlar ve günün tahtası **skor tablosuna** puan yazar (galibiyet 10,
beraberlik 4, mağlubiyet 1; bota karşı galibiyet zorluğa göre 1–3).

## Mobil taraf

```
lib/
├── main.dart
├── app/app.dart               MaterialApp ve tema
├── core/
│   ├── config/app_config.dart Sunucu adresleri (--dart-define ile değişir)
│   ├── session.dart           Oyuncu adı, seçili mod, lig
│   └── theme/app_colors.dart
├── data/
│   ├── models/                GameMode, TeamModel, oda ve oyun durumları
│   └── services/
│       ├── api_service.dart   REST istemcisi
│       ├── game_socket.dart   WebSocket istemcisi (protokol v2)
│       └── league_catalog.dart
├── features/
│   ├── splash/ onboarding/ profile/   Açılış akışı
│   ├── modes/                 Oyun modu menüsü
│   ├── lobby/                 Oda kur / katıl / bekle / VS ekranı
│   └── games/                 Dört oyun modu + ortak saat iskeleti
└── shared/widgets/            Arka plan, diyaloglar, oyuncu arama
```

Ekran akışı: Splash → Onboarding → İsim → **Oyun Modu** → Oda kur/katıl →
Bekleme odası → VS → Oyun.

### Çalıştırma

```bash
flutter pub get
flutter run                                   # üretim sunucusuna bağlanır

# yerel backend ile
flutter run --dart-define=API_BASE=http://127.0.0.1:8000 \
            --dart-define=WS_BASE=ws://127.0.0.1:8000
```

### Testler

```bash
flutter analyze
flutter test integration_test/game_flow_test.dart -d <cihaz> \
  --dart-define=API_BASE=http://127.0.0.1:8000 \
  --dart-define=WS_BASE=ws://127.0.0.1:8000
```

`integration_test/game_flow_test.dart` açılış akışını ve dört modun tamamını
uçtan uca doğrular; rakip oyuncu testin içinden WebSocket ile bağlanarak
taklit edilir. `visual_check_test.dart` ekranları görsel kontrol için
yavaşlatılmış biçimde gezer.

## Sunucu

Ayrıntılar için [backend/README.md](backend/README.md).

```bash
docker compose -f docker-compose.dev.yml up --build   # geliştirme
docker compose up -d --build                          # üretim (AWS EC2)
```

Üretim yığını nginx arkasında çalışır: TLS sonlandırma, HTTP→HTTPS
yönlendirme, güvenlik başlıkları, uç bazlı hız sınırları (API / arama /
WebSocket ayrı bölgeler), kulüp logoları için disk önbelleği ve
`/docs` ile `/health` uçlarının dışarıya kapatılması.

> **Not:** `backend/data/tikitakapi.db` (~33 MB) depoya dahil değildir;
> sunucudaki kopya elle yerleştirilir.
