#!/usr/bin/env bash
# Üretim sunucusunda (AWS EC2) dağıtım.
#
# Kullanım (sunucuda):
#   cd /srv/tikitakatoe && ./infra/deploy.sh
#
# Yeni yapı eski kurulumdan iki noktada farklı:
#   * uygulama kodu backend/ altında, nginx yapılandırması infra/nginx/ altında
#   * oyuncu veritabanı imaja gömülmez, backend/data/ dizininden bağlanır
#
# Bu betik veritabanını ve sertifikaları yerinde bırakır; yalnızca kodu
# günceller ve servisleri yeniden başlatır.

set -euo pipefail

BRANCH="${1:-main}"
DB_PATH="backend/data/tikitakapi.db"

# Sağlık kontrolü düşerse dönülecek sürüm.
#
# `|| true` şart: .env yoksa ya da içinde BACKEND_IMAGE geçmiyorsa grep
# sıfırdan farklı döner ve `set -euo pipefail` betiği daha tek satır çıktı
# vermeden öldürür. İlk dağıtımda tam olarak bu oldu.
PREVIOUS_IMAGE="$(grep '^BACKEND_IMAGE=' .env 2>/dev/null | tail -1 | cut -d= -f2- || true)"
export PREVIOUS_IMAGE

echo "▶ Dal: $BRANCH"

# --- Ön koşullar ------------------------------------------------------
if [ ! -f "docker-compose.yml" ]; then
  echo "✗ docker-compose.yml bulunamadı. Proje kökünde çalıştırın." >&2
  exit 1
fi

if [ ! -f "$DB_PATH" ]; then
  echo "✗ $DB_PATH yok. Oyuncu veritabanı depoya dahil değildir;" >&2
  echo "  eski kurulumdaki kopyayı bu yola taşıyın." >&2
  exit 1
fi

if [ ! -d "infra/certbot/conf/live" ]; then
  echo "⚠ infra/certbot/conf/live yok — TLS sertifikaları eski konumdan" >&2
  echo "  taşınmalı, aksi halde nginx başlamaz." >&2
  exit 1
fi

# --- Kod --------------------------------------------------------------
echo "▶ Kod güncelleniyor"
git fetch origin "$BRANCH"
git checkout "$BRANCH"
git pull --ff-only origin "$BRANCH"

# --- Yedek ------------------------------------------------------------
BACKUP="backend/data/tikitakapi.$(date +%Y%m%d-%H%M%S).db"
echo "▶ Veritabanı yedekleniyor: $BACKUP"
cp "$DB_PATH" "$BACKUP"

# Dağıtım artık her main itmesinde otomatik; yedekler birikirse disk dolar.
# En yeni KEEP_BACKUPS tanesi tutulur, gerisi silinir.
KEEP_BACKUPS="${KEEP_BACKUPS:-5}"
ls -1t backend/data/tikitakapi.*.db 2>/dev/null \
  | grep -vE "tikitakapi\.(db|db-wal|db-shm)$" \
  | tail -n +$((KEEP_BACKUPS + 1)) \
  | while read -r old_backup; do
      echo "  eski yedek siliniyor: $old_backup"
      rm -f "$old_backup"
    done


# --- İmaj ve başlatma -------------------------------------------------
# İmaj CI'da derlenip GHCR'a itiliyor. BACKEND_IMAGE verilmişse o sürüm
# çekilir; verilmemişse .env'deki mevcut sürüm korunur. Kayıt defterine
# ulaşılamazsa (ya da imaj henüz itilmemişse) yerelde derlemeye düşülür,
# böylece elle çalıştırılan dağıtım da çalışmaya devam eder.
if [ -n "${BACKEND_IMAGE:-}" ]; then
  echo "▶ İmaj: $BACKEND_IMAGE"
  if docker pull "$BACKEND_IMAGE"; then
    # Bir sonraki dağıtımın ve geri almanın referans alacağı sürüm.
    grep -v '^BACKEND_IMAGE=' .env 2>/dev/null > .env.tmp || true
    echo "BACKEND_IMAGE=$BACKEND_IMAGE" >> .env.tmp
    mv .env.tmp .env
  else
    echo "⚠ İmaj çekilemedi, yerelde derleniyor" >&2
    docker compose build backend
  fi
else
  echo "▶ BACKEND_IMAGE verilmedi, yerelde derleniyor"
  docker compose build backend
fi

echo "▶ Servisler yeniden başlatılıyor"
docker compose up -d

# nginx yapılandırması bind mount ile geliyor; `up -d` onu tazelemiyor.
# Yapılandırma sınandıktan sonra yeniden yüklenir — hatalıysa çalışan
# nginx olduğu gibi kalır.
if docker compose exec -T nginx nginx -t > /dev/null 2>&1; then
  docker compose exec -T nginx nginx -s reload > /dev/null 2>&1 \
    && echo "✓ nginx yapılandırması yeniden yüklendi"
else
  echo "⚠ nginx yapılandırması geçersiz, yeniden yükleme atlandı" >&2
  docker compose exec -T nginx nginx -t || true
fi

# --- Doğrulama --------------------------------------------------------
echo "▶ Sağlık kontrolü"
for i in $(seq 1 30); do
  if docker compose exec -T backend python -c \
      "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/ping', timeout=3).status==200 else 1)" 2>/dev/null; then
    echo "✓ Backend ayakta"
    break
  fi
  [ "$i" = "30" ] && {
    echo "✗ Backend sağlık kontrolünden geçmedi"
    docker compose logs --tail=50 backend
    # Bozuk sürümü ayakta bırakma: bir önceki imaja dön.
    if [ -n "${PREVIOUS_IMAGE:-}" ] && [ "${PREVIOUS_IMAGE}" != "${BACKEND_IMAGE:-}" ]; then
      echo "↩ Önceki sürüme dönülüyor: $PREVIOUS_IMAGE"
      grep -v '^BACKEND_IMAGE=' .env 2>/dev/null > .env.tmp || true
      echo "BACKEND_IMAGE=$PREVIOUS_IMAGE" >> .env.tmp
      mv .env.tmp .env
      docker compose up -d
    fi
    exit 1
  }
  sleep 2
done

# --- Günlük modu ------------------------------------------------------
# WAL, okuyucuyu yazıcıdan ayırır: aylık tazeleme sürerken oyuncular cevap
# doğrulaması yapabilsin diye gerekli.
#
# Sırası kritik. WAL'da SQLite bir veritabanını OKURKEN bile -shm dosyasını
# açmak zorunda; container data dizinini salt okunur bağlıyorsa bu "attempt
# to write a readonly database" verir ve servis tümden okuyamaz hale gelir.
# Bu yüzden yalnızca yazılabilir bağlama yapan sürüm ayağa kalkıp sağlık
# kontrolünden geçtikten SONRA açılır, açıldıktan sonra da doğrulanır.
# (Canlıda bir kez bu sırayla yanılıp kısa kesinti yaşandı.)
echo "▶ Günlük modu"
python3 - "$DB_PATH" <<'WALPY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1], timeout=30, isolation_level=None)
mode = con.execute("PRAGMA journal_mode").fetchone()[0]
if str(mode).lower() != "wal":
    print("  gunluk modu:", mode, "->", con.execute("PRAGMA journal_mode=WAL").fetchone()[0])
else:
    print("  gunluk modu: wal")
con.close()
WALPY

echo "▶ WAL sonrası sorgu doğrulaması"
if curl -fsS --max-time 15 -X POST https://tikitakatoe.com/api/v1/guess_player/ \
     -H 'Content-Type: application/json' \
     -d '{"player_name":"Messi","nationality":"Argentina","club":"Paris Saint-Germain"}' \
     2>/dev/null | grep -q true; then
  echo "✓ WAL sonrası sorgular çalışıyor"
else
  echo "✗ WAL sonrası sorgular bozuldu — geri alınıyor" >&2
  python3 - "$DB_PATH" <<'UNWALPY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1], timeout=30, isolation_level=None)
con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
print("  geri alindi:", con.execute("PRAGMA journal_mode=DELETE").fetchone()[0])
con.close()
UNWALPY
  exit 1
fi

# --- Güncel kadrolar --------------------------------------------------
# Oyuncu veritabanı sezon anlık görüntülerinden oluşuyor ve son transfer
# dönemini kapsamıyor. Kadro katmanı Wikipedia'dan haftalık tazelenir;
# container veritabanını salt okunur bağladığı için betik host'ta çalışır.
CRON_LINE="0 4 * * 1 cd $(pwd) && ./infra/run_job.sh squads /usr/bin/python3 backend/scripts/sync_current_squads.py"
if ! crontab -l 2>/dev/null | grep -qF "run_job.sh squads"; then
  echo "▶ Haftalık kadro güncellemesi zamanlanıyor"
  (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
  echo "✓ Pazartesi 04:00 için cron kaydı eklendi"
else
  echo "✓ Kadro güncelleme cron kaydı zaten var"
fi

# Kulüp tarihçesi ayda bir tazelenir: eski kadrolar ve uyruklar yavaş
# değişir, ama yeni oyuncular geldikçe katman büyür.
HIST_LINE="0 5 1 * * cd $(pwd) && ./infra/run_job.sh history bash -c 'backend/scripts/sync_club_history.py && backend/scripts/backfill_player_gaps.py && backend/scripts/build_name_tokens.py'"
if ! crontab -l 2>/dev/null | grep -qF "run_job.sh history"; then
  echo "▶ Aylık kulüp tarihçesi güncellemesi zamanlanıyor"
  (crontab -l 2>/dev/null; echo "$HIST_LINE") | crontab -
  echo "✓ Ayın 1'i 05:00 için cron kaydı eklendi"
else
  echo "✓ Kulüp tarihçesi cron kaydı zaten var"
fi

# Yedekler veritabanıyla aynı diskte duruyor; birim ölürse ikisi de gider.
# TTT_BACKUP_BUCKET ayarlıysa haftalık offsite kopya zamanlanır.
if [ -n "${TTT_BACKUP_BUCKET:-}" ]; then
  BACKUP_LINE="0 3 * * 0 cd $(pwd) && TTT_BACKUP_BUCKET=$TTT_BACKUP_BUCKET ./infra/run_job.sh backup ./infra/backup_offsite.sh"
  if ! crontab -l 2>/dev/null | grep -qF "run_job.sh backup"; then
    echo "▶ Haftalık offsite yedek zamanlanıyor"
    (crontab -l 2>/dev/null; echo "$BACKUP_LINE") | crontab -
    echo "✓ Pazar 03:00 için cron kaydı eklendi"
  else
    echo "✓ Offsite yedek cron kaydı zaten var"
  fi
else
  echo "⚠ TTT_BACKUP_BUCKET ayarlı değil — yedekler yalnızca yerel diskte" >&2
fi

echo "▶ Dışarıdan erişim kontrolü"
curl -fsS https://tikitakatoe.com/ping > /dev/null && echo "✓ https://tikitakatoe.com/ping yanıt veriyor"

echo "▶ Eski istemci uç noktası"
curl -fsS "https://tikitakatoe.com/check_room/0000" > /dev/null && echo "✓ /check_room çalışıyor"

docker compose ps
echo "✓ Dağıtım tamamlandı"
