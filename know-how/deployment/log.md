# Dağıtım Kaydı

Bu sayfa yönlendirme sayfasıdır: ne olduğunu tablodan bulur, ayrıntı için
alt dosyaya gidersiniz. Buraya uzun anlatım yazılmaz.

## Sürümler

Ayrıntı: [changelog.md](changelog.md)

| Sürüm | Tarih | Özet |
|---|---|---|
| 1.2.0 | 2026-09-10 | Günün tahtası, hızlı eşleşme, yeniden başlatmayı atlatma, Redis |

## Olaylar

Şablon: [incident-template.md](incident-template.md)

| Tarih | Konu | Etki | Kayıt |
|---|---|---|---|
| 2026-09-07 | WAL modu üretimi kırdı | ~40 sn kesinti | [kayıt](incidents/2026-09-07-wal-salt-okunur-baglama.md) |

## Kararlar

Şablon: [decision-template.md](decision-template.md)

| No | Karar | Durum |
|---|---|---|
| 001 | [Paket imajları digest yerine sürüm etiketiyle taşınır](decisions/001-surum-etiketi.md) | Kabul |
| 002 | [Veritabanı imaja gömülmez, bind ile bağlanır](decisions/002-veritabani-bind.md) | Kabul |

## Nasıl kayıt eklenir

1. Şablonu kopyala: `cp incident-template.md incidents/YYYY-AA-GG-konu.md`
2. Doldur.
3. **Bu sayfadaki tabloya satır ekle** — yoksa kayıt kaybolur.
4. İlgili karar/olay varsa iki yönlü bağlantı ver.
