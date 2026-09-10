# Değişiklik Kaydı

Biçim: [keepachangelog](https://keepachangelog.com/tr/1.1.0/).
Sürümleme: [semver](https://semver.org/lang/tr/).

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
