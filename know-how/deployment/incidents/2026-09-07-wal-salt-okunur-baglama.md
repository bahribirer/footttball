# 2026-09-07 — WAL modu üretimi okuyamaz hâle getirdi

| | |
|---|---|
| **Tarih** | 2026-09-07 22:5x (UTC) |
| **Süre** | ~40 saniye |
| **Etki** | Tüm cevap doğrulama istekleri 500 döndü |
| **Fark ediliş** | Değişikliği yapan kişi hemen ardından kontrol ederken |

## Ne oldu

Veri aktarımı tamamlandıktan sonra SQLite `journal_mode=WAL` olarak
değiştirildi. Hemen ardından yapılan `guess_player` çağrısı
`Internal Server Error` döndü. `journal_mode=DELETE` ile geri alındı,
servis düzeldi.

## Kök neden

WAL modunda SQLite bir veritabanını **okurken bile** `-shm` paylaşımlı
bellek dosyasını açmak zorunda. O anda çalışan sürüm veri dizinini
container'a salt okunur (`:ro`) bağlıyordu; dosya oluşturulamayınca
`attempt to write a readonly database` alındı ve servis hiçbir sorguya
cevap veremez oldu.

İkinci bir katman daha vardı: bağlama yazılabilir yapıldıktan sonra da
çalışmadı, çünkü container `appuser` (uid 10001) olarak koşuyordu ama host
dizini `ubuntu`ya (uid 1000) aitti.

## Nasıl çözüldü

1. `journal_mode=DELETE` ile anında geri alındı.
2. Yazma yasağı bağlama noktasından bağlantı seviyesine taşındı: dizin
   yazılabilir bağlanıyor, uygulama `file:...?mode=ro` ile açıyor.
3. Container uid'si host sahibiyle hizalandı (`APP_UID`, varsayılan 1000).

## Tekrarını önlemek için ne yapıldı

- `deploy.sh`'ta WAL adımı sağlık kontrolünün **arkasına** alındı ve
  açıldıktan sonra gerçek bir sorguyla doğrulanıyor; sorgu düşerse WAL
  geri alınıp dağıtım hata veriyor.
- Uygulamanın veritabanına yazamadığını doğrulayan test eklendi
  (`tests/test_readonly_db.py`) — koruma sessizce kaybolamaz.

## İlgili

- Karar: [ADR-002](../decisions/002-veritabani-bind.md)
