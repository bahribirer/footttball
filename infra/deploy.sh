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

# --- Derle ve başlat --------------------------------------------------
echo "▶ İmaj derleniyor"
docker compose build backend

echo "▶ Servisler yeniden başlatılıyor"
docker compose up -d

# --- Doğrulama --------------------------------------------------------
echo "▶ Sağlık kontrolü"
for i in $(seq 1 30); do
  if docker compose exec -T backend python -c \
      "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/ping', timeout=3).status==200 else 1)" 2>/dev/null; then
    echo "✓ Backend ayakta"
    break
  fi
  [ "$i" = "30" ] && { echo "✗ Backend sağlık kontrolünden geçmedi"; docker compose logs --tail=50 backend; exit 1; }
  sleep 2
done

# --- Güncel kadrolar --------------------------------------------------
# Oyuncu veritabanı sezon anlık görüntülerinden oluşuyor ve son transfer
# dönemini kapsamıyor. Kadro katmanı Wikipedia'dan haftalık tazelenir;
# container veritabanını salt okunur bağladığı için betik host'ta çalışır.
CRON_LINE="0 4 * * 1 cd $(pwd) && /usr/bin/python3 backend/scripts/sync_current_squads.py >> \$HOME/tikitakatoe-squads.log 2>&1"
if ! crontab -l 2>/dev/null | grep -qF "sync_current_squads.py"; then
  echo "▶ Haftalık kadro güncellemesi zamanlanıyor"
  (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
  echo "✓ Pazartesi 04:00 için cron kaydı eklendi"
else
  echo "✓ Kadro güncelleme cron kaydı zaten var"
fi

# Kulüp tarihçesi ayda bir tazelenir: eski kadrolar ve uyruklar yavaş
# değişir, ama yeni oyuncular geldikçe katman büyür.
HIST_LINE="0 5 1 * * cd $(pwd) && /usr/bin/python3 backend/scripts/sync_club_history.py >> \$HOME/tikitakatoe-history.log 2>&1 && /usr/bin/python3 backend/scripts/backfill_player_gaps.py >> \$HOME/tikitakatoe-history.log 2>&1"
if ! crontab -l 2>/dev/null | grep -qF "sync_club_history.py"; then
  echo "▶ Aylık kulüp tarihçesi güncellemesi zamanlanıyor"
  (crontab -l 2>/dev/null; echo "$HIST_LINE") | crontab -
  echo "✓ Ayın 1'i 05:00 için cron kaydı eklendi"
else
  echo "✓ Kulüp tarihçesi cron kaydı zaten var"
fi

echo "▶ Dışarıdan erişim kontrolü"
curl -fsS https://tikitakatoe.com/ping > /dev/null && echo "✓ https://tikitakatoe.com/ping yanıt veriyor"

echo "▶ Eski istemci uç noktası"
curl -fsS "https://tikitakatoe.com/check_room/0000" > /dev/null && echo "✓ /check_room çalışıyor"

docker compose ps
echo "✓ Dağıtım tamamlandı"
