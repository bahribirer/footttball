# İnternetsiz kurulum paketleri

Docker imajlarını `docker save` ile tar'layıp USB ile taşınabilir,
versiyonlanmış ve doğrulanabilir paketler hâline getirir. Hedef makinenin
internete ya da kayıt defterine erişmesi gerekmez.

## Paket üretmek

```bash
./know-how/build_release.sh 1.2.0                 # yalnızca imajlar (~180 MB)
./know-how/build_release.sh 1.2.0 --with-data     # oyuncu veritabanı dahil (~230 MB)
./know-how/build_release.sh 1.2.0 --allow-dirty   # commit edilmemiş değişikliklerle
```

Çıktı `know-how/releases/1.2.0/`. USB'ye olduğu gibi kopyalanır.

Betik commit edilmemiş değişiklik varsa durur: paketin hangi koddan
çıktığının belirsiz kalması, sahada "bu sürümde ne vardı" sorusunu
cevaplanamaz hâle getirir.

## Paketi uygulamak

Hedef makinede, USB'den kopyalanan dizinin içinden:

```bash
cd 1.2.0
sudo ./update.sh /srv/tikitakatoe             # normal güncelleme
sudo ./update.sh /srv/tikitakatoe --dry-run   # ne yapacağını yazar, dokunmaz
sudo ./update.sh /srv/tikitakatoe --with-redis # çok süreçli çalışma
```

Sıra: **doğrula → yedekle → imajları yükle → .env yaz → başlat → sağlık
kontrolü.** Sağlık kontrolü düşerse önceki imaj kilidine dönülür.

## Paketin içi

| Dosya | Ne işe yarar |
|---|---|
| `version.env` | Her servisin imaj etiketi. `update.sh` bunu `.env`'e yazar |
| `manifest.json` | Köken bilgisi: hangi imaj nereden çekildi, digest'i ne, git commit'i |
| `checksums.sha256` | Bozuk USB kopyasını **yüklemeden önce** yakalar |
| `services/*.yml` | Servis tanımları; `docker-compose.yml`'dan türetilir |
| `images/*.tar.gz` | `docker save` çıktıları |
| `data/` | `--with-data` verilirse oyuncu veritabanı |

## Neden böyle

**Servis tanımları türetiliyor, elle yazılmıyor.** Elle yazılsalardı
compose'da bir port ya da ortam değişkeni değiştiğinde USB'yle giden tanım
eski kalırdı ve fark ancak sahada anlaşılırdı.

**İmajlar sürüme özel etiketle taşınıyor** (`ttt-nginx:1.2.0`), digest
referansıyla değil. Digest cazip görünüyor ama `docker save`/`load` ile
taşınan bir imajın digest'ini geri kazanmak Docker'ın imaj deposuna bağlı:
yeni sürümler (containerd) koruyor, eskiler korumuyor. Korumadığında
compose imajı kayıt defterinden çekmeye kalkar — internetsiz makinede tam
olarak olmaması gereken şey. Digest köken bilgisi olarak `manifest.json`'da
duruyor.

**`update.sh` compose'u `--project-directory` ve `--env-file` ile
çağırıyor.** Compose proje dizinini ilk `-f` dosyasının konumundan
belirliyor; bu bayraklar olmadan `.env` hiç okunmuyor, imaj değişkenleri
boş kalıyor ve compose varsayılan kayıt defteri adresine düşüp imajı
çekmeye çalışıyor. Denemede tam olarak bu yaşandı.

**`--pull never` veriliyor.** Paket kendi kendine yetmeli; compose bir imajı
çekmeye kalkıyorsa bu bir yapılandırma hatasıdır ve sessizce internete
gitmek yerine yüksek sesle düşmelidir.

## Hedef makinede olması gerekenler

Paket bunları **taşımaz**, önceden orada olmalı:

| Ne | Neden |
|---|---|
| Docker + compose eklentisi | `infra/bootstrap.sh` kurar |
| `infra/nginx/` yapılandırması | Depodan gelir |
| **TLS sertifikaları** (`infra/certbot/conf/live/`) | Yoksa nginx açılmaz |
| Oyuncu veritabanı | `--with-data` kullanılmadıysa |

### TLS ve internetsiz makine

`certbot` sertifikayı Let's Encrypt'ten alır, bu da internet ister.
İnternetsiz kurulumda iki yol var: sertifikayı başka bir makinede alıp
`infra/certbot/conf/` içine kopyalamak, ya da kurum içi bir sertifika
kullanmak. Paket certbot imajını taşır ama **sertifika üretemez**.

Sertifika yoksa nginx yeniden başlama döngüsüne girer. `update.sh` bunu
yakalar ve sebebini yazar; backend ayakta olsa bile başarısız sayar.

## Geri dönmek

Her uygulama öncesi `.env` ve veritabanı `know-how-backups/<zaman-damgası>/`
altına yedeklenir. Önceki sürüme dönmek için o dizindeki `.env` geri
kopyalanıp `docker compose up -d` çalıştırılır — `update.sh` çıktısında tam
komut yazıyor. Eski sürümün imajları makinede durduğu sürece geri dönüş
saniyeler sürer, bu yüzden bir önceki paketi silmeden önce yenisinin
oturduğundan emin olun.

## Sürüm listesi

| Sürüm | Tarih | İçerik |
|---|---|---|
| 1.2.0 | 2026-09-10 | Günün tahtası, hızlı eşleşme, yeniden başlatmayı atlatma, Redis |
