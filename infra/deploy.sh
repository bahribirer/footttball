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

echo "▶ Dışarıdan erişim kontrolü"
curl -fsS https://tikitakatoe.com/ping > /dev/null && echo "✓ https://tikitakatoe.com/ping yanıt veriyor"

echo "▶ Eski istemci uç noktası"
curl -fsS "https://tikitakatoe.com/check_room/0000" > /dev/null && echo "✓ /check_room çalışıyor"

docker compose ps
echo "✓ Dağıtım tamamlandı"
