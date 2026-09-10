# ADR-002 — Futbolcu veritabanı imaja gömülmez, bind ile bağlanır

| | |
|---|---|
| **Durum** | Kabul |
| **Tarih** | 2026-09-10 |

## Bağlam

Futbolcu veritabanı 152 MB ve haftalık/aylık cron işleriyle host tarafında
güncelleniyor. İmaja gömülseydi her veri tazelemesi yeni imaj derlemeyi ve
yeniden dağıtımı gerektirirdi.

## Karar

Veritabanı host dizininden bind ile bağlanır. Paketlere yalnızca
`--with-data` verildiğinde girer.

## Gerekçe

Veri ve kod farklı hızlarda değişiyor: kod sürümle, veri haftalık cron'la.
Aynı artefakta bağlamak ikisini de yavaşlatır. Ayrıca her pakette 152 MB
taşımak, çoğu güncellemede boşuna kopyalama demek.

Bind yolu ortam değişkeninden geliyor (`BACKEND_DATA_DIR`), böylece hedef
makinede veritabanı büyük diske taşınabiliyor ve sonraki güncelleme bunu
geri almıyor.

## Sonuçları

- İlk kurulumda veritabanı ayrıca taşınmalı (`--with-data` ya da elle).
- Bağlama yazılabilir olmak zorunda ve container kullanıcısının uid'si host
  sahibiyle uyuşmalı — bu uyumsuzluk bir kez üretimi kırdı.

## İlgili

- Olay: [2026-09-07](../incidents/2026-09-07-wal-salt-okunur-baglama.md)
