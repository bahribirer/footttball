# İnternetsiz kurulum paketleri

Docker imajlarını `docker save` ile tar'layıp USB ile taşınabilir,
versiyonlanmış ve doğrulanabilir paketler hâline getirir. Hedef makinenin
internete ya da kayıt defterine erişmesi gerekmez.

## Klasörler

```
know-how/
├── build.sh              üç adımlı paketleyici
├── templates/
│   ├── targets.env         hedef kataloğu: mimari + kurulum dizini
│   ├── variables.env.example
│   ├── update.sh           sahada çalışan güncelleyici
│   ├── revert.sh           geri dönüş şablonu
│   ├── split_compose.py    compose → servis başına yml
│   └── render_note.py      müşteri talimatı
├── deployment/           iç teknik kayıt: log, changelog, olaylar, kararlar
├── dokumanlar/           müşteriye giden belgeler
└── releases/
    └── release_X.Y.Z/    USB'ye giden paket (tar.gz + .sha256 içinde)
```

## Paket üretmek — üç adım

```bash
./know-how/build.sh 1.3.0 --init       # 1. iskelet
vim know-how/releases/release_1.3.0/variables.env   # 2. doldur
./know-how/build.sh 1.3.0 --dry-run    # 3. plan doğru mu
./know-how/build.sh 1.3.0              # 4. üret
```

Akış bilerek bölünmüş: **karar** (hangi servis, hangi commit, hangi hedef)
insana ait ve `variables.env`'de yazılı kalıyor; **derleme ve paketleme**
makineye ait. `--dry-run` ikisinin arasında bir kapı.

### variables.env

```bash
TARGET=production                    # templates/targets.env'den çözülür

BACKEND_SOURCE=build:backend@a1b2c3d # o commit'ten derle
NGINX_SOURCE=skip                    # bu sürümde girmez, önceki etiket devralınır
REDIS_SOURCE=skip
CERTBOT_SOURCE=image:certbot/certbot:latest   # hazır imaj (üçüncü parti)

WITH_DATA=0
```

| Kaynak | Anlamı |
|---|---|
| `build:<dizin>` | çalışma ağacından derle — dizin temiz olmalı |
| `build:<dizin>@<ref>` | o commit/etiket/daldan derle — ağacın hâli önemsiz |
| `image:<ad:etiket>` | hazır imajı çek, sürüm etiketiyle yeniden etiketle |
| `skip` | pakete girmez; `version.env`'de önceki sürümün etiketi kalır |

`--init` değişmeyen servisleri `skip` ile **önceden doldurur**: kaynak
parmak izini önceki sürümle karşılaştırır (derlenen için git ağaç özeti,
hazır imaj için upstream digest). Sen yalnızca hedefi ve istisnaları
yazarsın.

### Hedef kataloğu

Mimari ve kurulum dizini `templates/targets.env`'den gelir, `variables.env`'e
yol yazılmaz. Bu Mac arm64, üretim sunucusu amd64: hedefi yanlış seçersen
paket yüklenir ama konteyner `exec format error` ile ölür. Hedef katalogdan
çözüldüğü için TARGET ile yol çelişemez.

### Çıktı

```
release_1.3.0/
├── release_1.3.0.tar.gz          ← USB'ye giden
├── release_1.3.0.tar.gz.sha256   ← yanında gider
├── containers/                   yalnız pakete giren servisler
├── images/*.tar.gz + SHA256SUMS
├── version.env                   imaj kilidi + parmak izleri
├── update.sh · revert_1.2.0.sh · version_1.2.0.env
├── MANIFEST.txt                  köken: hangi commit, hangi digest
└── checksums.sha256
```

Müşteri talimatı `dokumanlar/guncelleme-notlari/md/1.3.0.md` olarak ayrıca
üretilir.

## Paketi uygulamak

Hedef makinede, USB'den kopyalanan dizinin içinden:

```bash
sha256sum -c release_1.3.0.tar.gz.sha256       # USB kopyası bozuk mu
tar xzf release_1.3.0.tar.gz && cd release_1.3.0
sudo ./update.sh /srv/tikitakatoe              # normal güncelleme
sudo ./update.sh /srv/tikitakatoe --dry-run    # ne yapacağını yazar, dokunmaz
sudo ./update.sh /srv/tikitakatoe --with-redis # çok süreçli çalışma
```

Geri dönmek için, paketin içindeki revert betiği:

```bash
sudo ./revert_1.2.0.sh /srv/tikitakatoe
```

`update.sh` sırayla: paket checksum → mimari → yedek → imaj SHA256SUMS →
`docker load` → `.env` → `compose up --pull never` → sağlık → tüm
servisler kararlı mı. Herhangi biri düşerse durur; sağlık düşerse geri
döner.

Geri dönüş imaj yüklemez — önceki sürümün imajları hedefte zaten duruyor,
yalnızca kilit geri yazılır. O imajlar silinmişse betik uyarır ve durur.

Sıra: **doğrula → yedekle → imajları yükle → .env yaz → başlat → sağlık
kontrolü.** Sağlık kontrolü düşerse önceki imaj kilidine dönülür.

## Paketin içi

| Dosya | Ne işe yarar |
|---|---|
| `version.env` | Her servisin imaj etiketi. `update.sh` bunu `.env`'e yazar |
| `manifest.json` | Köken bilgisi: hangi imaj nereden çekildi, digest'i ne, git commit'i |
| `checksums.sha256` | Bozuk USB kopyasını **yüklemeden önce** yakalar |
| `containers/<servis>/<servis>.yml` | Servis tanımları; `docker-compose.yml`'dan türetilir |
| `containers/bind_defaults.env` | Bind yolları ve portlar; `update.sh` bunları `.env`'e doldurur |
| `revert_X.Y.Z.sh` | Önceki sürüme dönüş |
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

**Bind yolları ve portlar değişkenden geliyor.** Kaynakta sabit yazılı
(`./infra/certbot/conf`, `80:80`); hedef makinenin dizin yapısı farklı
olabilir. `update.sh` bunları ilk kurulumda `.env`'e mutlak yollarla
yazar, sonraki güncellemelerde **var olan değeri korur** — operatör
veritabanını başka diske taşımışsa güncelleme onu geri almaz.

Değişken adı servisten değil yoldan türetilir: aynı host dizini birden
fazla serviste geçebiliyor (certbot yapılandırması hem nginx'te hem
certbot'ta) ve servise göre adlandırılsaydı aynı dizin iki ad alırdı.

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

Ayrıntı: [deployment/changelog.md](deployment/changelog.md) ·
Kayıtlar: [deployment/log.md](deployment/log.md)
