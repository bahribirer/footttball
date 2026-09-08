# Altyapı

Üretim tek bir AWS EC2 makinesinde (2 vCPU / 1.9 GB) Docker Compose ile
koşuyor: `backend`, `nginx`, `certbot`.

## Betikler

| Betik | Ne yapar |
|---|---|
| `bootstrap.sh` | Sıfırdan sunucu kurar (Docker, dizinler, takas, güvenlik duvarı) |
| `deploy.sh` | Kodu günceller, imajı çeker, sağlık kontrolü yapar, düşerse geri alır |
| `run_job.sh` | Zamanlanmış işleri sarmalar; durumu `/health`'e taşır |
| `backup_offsite.sh` | Veritabanının tutarlı kopyasını S3'e yollar |
| `push_data_layers.sh` | Yerelde üretilen veri katmanlarını sunucuya aktarır |
| `testflight_release.py` | Yüklenen derlemeye sürüm notu yazıp testçilere açar |

## Dağıtım akışı

`main`'e backend değişikliği inince:

1. **CI** imajı derler, `ghcr.io/bahribirer/footttball-backend:<sha>` olarak iter
2. **Onay bekler** — `production` environment'ı gözden geçiren istiyor
3. Sunucu imajı çeker, `docker compose up -d`
4. Sağlık kontrolü + dışarıdan duman testi
5. Kontrol düşerse `deploy.sh` önceki imaja döner

Elle geri alma: Actions → **Rollback** → SHA gir (boşsa bir önceki commit).

## Neden imaj CI'da derleniyor

Eskiden `docker compose build` prod makinesinde koşuyordu: oyun oynanırken
CPU derlemeye gidiyordu, yarıda kalan derleme sunucuyu belirsiz durumda
bırakıyordu ve tek `latest` etiketi olduğu için geri dönülecek artefakt
yoktu. SHA etiketleri bunların üçünü de çözüyor.

## Zamanlanmış işler

Hepsi `run_job.sh` üzerinden koşar; sonuçları `backend/data/jobs/*.json`'a
yazılır ve `/health` üzerinden okunur. `uptime.yml` bunu 15 dakikada bir
dışarıdan yoklar.

| Ne zaman | İş |
|---|---|
| Pazartesi 04:00 | Güncel kadrolar (`sync_current_squads.py`) |
| Ayın 1'i 05:00 | Kulüp tarihçesi + uyruk doldurma + isim indeksi |
| Pazar 03:00 | Offsite yedek (`TTT_BACKUP_BUCKET` ayarlıysa) |

## production ortamı

Hem backend dağıtımı hem TestFlight yüklemesi `production` ortamından
geçiyor ve onay bekliyor. Dağıtım dalı kuralı **iki** girdi içermeli:

| Tür | Değer |
|---|---|
| branch | `main` |
| tag | `v*` |

Yalnızca "korumalı dallar" seçiliyken etiketten tetiklenen koşu tek adım
bile çalıştırmadan reddediliyor — etiket dal sayılmıyor. v1.2.0'da bu
yaşandı.

## Ortam değişkenleri

| Değişken | Ne işe yarar |
|---|---|
| `BACKEND_IMAGE` | Ayakta olan imaj etiketi; `.env`'de tutulur |
| `SENTRY_DSN` | Verilirse hata raporlama açılır |
| `MODES_DISABLED` | Virgüllü mod kimlikleri; bozulan modu kapatmak için |
| `TTT_BACKUP_BUCKET` | Offsite yedeğin gideceği S3 yolu |
| `KEEP_BACKUPS` | Yerelde tutulacak yedek sayısı (varsayılan 5) |

## Bir modu acilen kapatmak

```bash
ssh ubuntu@<host>
cd /srv/tikitakatoe
echo 'MODES_DISABLED=last_letter' >> .env
docker compose up -d
```

Uygulama mod listesini sunucudan aldığı için kapanan mod menüden düşer;
yeni sürüm ve App Review gerekmez.
