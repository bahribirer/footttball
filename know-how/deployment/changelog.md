# Değişiklik Kaydı

Biçim: [keepachangelog](https://keepachangelog.com/tr/1.1.0/).
Sürümleme: [semver](https://semver.org/lang/tr/).

## [1.3.0] - 2026-09-19

### Eklendi
- Kariyer Yolu modu: futbolcunun kulüp yolu kısmen açık gelir, iki oyuncu
  da kim olduğunu bulmaya çalışır; maç boyunca toplam 3 ipucu hakkı
- Bot rakip: dört modda da oda kurup beklemeden oynanır (kolay/orta/zor),
  hızlı eşleşme zaman aşımında da teklif edilir; bot çözümü asla okumaz
- Skor tablosu: online galibiyet/beraberlik/mağlubiyet ve bota karşı
  galibiyet puanları, günün tahtası puanı; genel ve mod bazlı sıralama,
  kendi sıran ve mod dağılımın (`GET /api/v1/leaderboard`)
- Efsane oyuncular (yalnız tarihçede olanlar: Ronaldinho, Van Basten,
  Maldini...) öneri listesinde ve doğrulamada
- 87 dünya kulübü (Napoli, Atlético, Boca, Flamengo, Al Nassr...) kulüp
  tarihçesine eklendi: +21.285 kayıt
- Günün tahtasında doğru kutuda oyuncu fotoğrafı

### Değişti
- Son Harf modu kaldırıldı (yerine Kariyer Yolu)
- Günün tahtası cevap girişi klavyeye yapışık alt sayfa; metin alanı artık
  ekranın tepesine fırlamıyor
- Günün tahtası paylaşım metni WhatsApp'a göre biçimlendi (kalın başlık,
  değerlendirme satırı, davet)
- Skorlar ayrı `scores.db` dosyasında; oyuncu veritabanı salt okunur kalır

### Düzeltildi
- Çok kelimeli soyadlar ("Del Piero", "De Bruyne", "Van Dijk") ad
  indeksinde bulunuyor

## [1.2.0] - 2026-09-10

### Eklendi
- Günün tahtası: rakip gerektirmeyen, herkese aynı gelen 3x3 bulmaca ve
  paylaşılabilir sonuç
- Hızlı eşleşme: aynı modu bekleyen iki oyuncuyu eşleştiren kuyruk
- Oyuncu Tahmin'de pas teklifi
- Redis ile çok süreçli çalışma (`REDIS_URL` verilince)
- İnternetsiz kurulum paketleri (`know-how/build_release.sh`)

### Değişti
- Dağıtım artık oynanan maçları öldürmüyor; odalar yeniden başlatmayı
  atlatıyor
- İsim araması indeksli: `verify_player` 110 ms → 2.6 ms
- Mod listesi sunucudan geliyor; bozulan mod App Review beklemeden
  kapatılabiliyor

### Düzeltildi
- `club_history`'de 20.073 satır uyruk çözüldü; İskoç/Galli/K.İrlandalı
  futbolcular kendi kutularında geçiyor, İngiltere kutusunda geçmiyor
- Varlık adları dosya sistemiyle aynı yazıma getirildi (Android derlemesini
  kıracaktı)

## [1.1.0] - 2026-09-06

### Eklendi
- Kategorilere zorluk etiketi ve kolay ağırlıklı yeni aileler
- Bağlantı durumu şeridi

### Değişti
- Tur sayısı "en çok kazanan" değil, "hedefe ilk ulaşan"

### Düzeltildi
- Soyadla arama ("Messi") kabul ediliyor
- Öneri listesi yerleşimi itmiyor
- Bağlantı koptuğunda oyuncu belirteciyle geri dönebiliyor
