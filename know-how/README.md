# İnternetsiz kurulum paketleri

Docker imajlarını `docker save` ile tar'layıp USB ile taşınabilir,
versiyonlanmış ve doğrulanabilir paketler hâline getirir. Hedef makinenin
internete ya da kayıt defterine erişmesi gerekmez.

## Klasörler

```
know-how/
├── build_release.sh      paket üretir
├── templates/            update.sh, revert.sh, compose bölücü, not şablonu
├── deployment/           iç teknik kayıt: log, changelog, olaylar, kararlar
├── dokumanlar/           müşteriye giden belgeler
│   ├── bilgi-notlari/
│   └── guncelleme-notlari/md/
└── releases/
    └── release_X.Y.Z/    USB'ye kopyalanacak paket
```

## Paket üretmek

```bash
./know-how/build_release.sh 1.2.1                 # delta: yalnızca değişen servisler
./know-how/build_release.sh 1.2.1 --full          # tam paket (ilk kurulum)
./know-how/build_release.sh 1.2.1 --with-data     # futbolcu veritabanı dahil
./know-how/build_release.sh 1.2.1 --allow-dirty   # commit edilmemiş değişikliklerle
```

Çıktı `know-how/releases/release_1.2.1/`. USB'ye olduğu gibi kopyalanır.
Müşteri talimatı `know-how/dokumanlar/guncelleme-notlari/md/1.2.1.md`
olarak ayrıca üretilir.

### Delta paketleme

Her paket yalnızca bir öncekine göre **değişen** servisleri taşır. Tek
satır değişince gigabaytlarca imajı USB'ye kopyalamak hem zaman kaybı hem
gereksiz risk: dokunulmayan bir servisin imajını yeniden yüklemek onu
yeniden başlatır.

Karşılaştırma etiket adına değil **imaj kimliğine** bakar; etiket her
sürümde değiştiği için ad karşılaştırması her şeyi "değişmiş" gösterirdi.

Atlanan servisler `version.env`'de önceki sürümün etiketinde bırakılır.
Aksi halde paket, içinde taşımadığı bir imajı işaret eder ve hedefte
`--pull never` ile dağıtım patlar.

Betik commit edilmemiş değişiklik varsa durur: paketin hangi koddan
çıktığının belirsiz kalması, sahada "bu sürümde ne vardı" sorusunu
cevaplanamaz hâle getirir.

## Paketi uygulamak

Hedef makinede, USB'den kopyalanan dizinin içinden:

```bash
cd release_1.2.1
sudo ./update.sh /srv/tikitakatoe              # normal güncelleme
sudo ./update.sh /srv/tikitakatoe --dry-run    # ne yapacağını yazar, dokunmaz
sudo ./update.sh /srv/tikitakatoe --with-redis # çok süreçli çalışma
```

Geri dönmek için, paketin içindeki revert betiği:

```bash
sudo ./revert_1.2.0.sh /srv/tikitakatoe
```

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
