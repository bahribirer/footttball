#!/usr/bin/env bash
# Yeni bir sunucuyu sıfırdan kurar ve uygulamayı ayağa kaldırır.
#
# Yerel makinede çalıştırılır:
#   ./infra/provision.sh ubuntu@<IP> ~/Downloads/<anahtar>.pem [dal]
#
# Yaptıkları:
#   1. Docker ve Docker Compose kurar
#   2. Depoyu /srv/tikitakatoe altına klonlar
#   3. Oyuncu veritabanını yerel kopyadan yükler (depoda tutulmuyor)
#   4. Let's Encrypt sertifikasını alır (nginx'i geçici olarak devre dışı bırakarak)
#   5. Servisleri başlatır ve dışarıdan erişimi doğrular
#
# Betik yeniden çalıştırılabilir: kurulu adımları atlar, sertifikayı yeniden almaz.

set -euo pipefail

TARGET="${1:-}"
KEY="${2:-}"
BRANCH="${3:-main}"

REPO="https://github.com/bahribirer/footttball.git"
APP_DIR="/srv/tikitakatoe"
DOMAIN="tikitakatoe.com"
LOCAL_DB="backend/data/tikitakapi.db"

if [ -z "$TARGET" ] || [ -z "$KEY" ]; then
  echo "Kullanım: $0 ubuntu@<IP> <anahtar.pem> [dal]" >&2
  exit 1
fi

if [ ! -f "$LOCAL_DB" ]; then
  echo "✗ $LOCAL_DB bulunamadı. Proje kökünde çalıştırın." >&2
  exit 1
fi

chmod 600 "$KEY"
SSH="ssh -i $KEY -o StrictHostKeyChecking=accept-new $TARGET"

echo "▶ 1/6  Bağlantı denetleniyor"
$SSH "echo '  bağlandı:' \$(hostname) '/' \$(lsb_release -ds 2>/dev/null || uname -sr)"

echo "▶ 2/6  Docker kuruluyor"
$SSH 'bash -s' <<'REMOTE'
set -euo pipefail
if command -v docker >/dev/null 2>&1; then
  echo "  docker zaten kurulu: $(docker --version)"
else
  sudo apt-get update -qq
  sudo apt-get install -y -qq ca-certificates curl git
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
  echo "  docker kuruldu: $(docker --version)"
fi
REMOTE

echo "▶ 3/6  Depo hazırlanıyor"
$SSH "bash -s" <<REMOTE
set -euo pipefail
sudo mkdir -p "$APP_DIR"
sudo chown -R \$USER:\$USER "$APP_DIR"
if [ -d "$APP_DIR/.git" ]; then
  cd "$APP_DIR"
  git fetch origin "$BRANCH"
  git checkout "$BRANCH"
  git pull --ff-only origin "$BRANCH"
  echo "  depo güncellendi: \$(git log --oneline -1)"
else
  git clone --branch "$BRANCH" "$REPO" "$APP_DIR"
  echo "  depo klonlandı"
fi
mkdir -p "$APP_DIR/backend/data" "$APP_DIR/infra/certbot/conf" "$APP_DIR/infra/certbot/www"
REMOTE

echo "▶ 4/6  Oyuncu veritabanı yükleniyor (33 MB)"
if $SSH "test -f $APP_DIR/backend/data/tikitakapi.db"; then
  echo "  veritabanı sunucuda zaten var, atlanıyor"
else
  scp -i "$KEY" -o StrictHostKeyChecking=accept-new "$LOCAL_DB" "$TARGET:$APP_DIR/backend/data/tikitakapi.db"
  echo "  yüklendi"
fi

if [ "${SKIP_TLS:-0}" = "1" ]; then
  echo "▶ 5/6  TLS sertifikası — atlandı (SKIP_TLS=1)"
  echo "  DNS yeni sunucuya yönlendikten sonra betiği tekrar çalıştırın."
  exit 0
fi

echo "▶ 5/6  TLS sertifikası"
$SSH "bash -s" <<REMOTE
set -euo pipefail
cd "$APP_DIR"
if [ -d "infra/certbot/conf/live/$DOMAIN" ]; then
  echo "  sertifika zaten var, atlanıyor"
else
  # nginx 443'te sertifika olmadan başlayamadığı için ilk sertifika
  # standalone modda, 80 portu boşken alınır.
  sudo docker compose down 2>/dev/null || true
  sudo docker run --rm -p 80:80 \
    -v "$APP_DIR/infra/certbot/conf:/etc/letsencrypt" \
    -v "$APP_DIR/infra/certbot/www:/var/www/certbot" \
    certbot/certbot certonly --standalone \
    -d "$DOMAIN" -d "www.$DOMAIN" \
    --non-interactive --agree-tos --register-unsafely-without-email
  echo "  sertifika alındı"
fi
REMOTE

echo "▶ 6/6  Servisler başlatılıyor"
$SSH "cd $APP_DIR && sudo docker compose up -d --build"
sleep 10

echo "▶ Doğrulama"
$SSH "cd $APP_DIR && sudo docker compose ps"
echo -n "  https://$DOMAIN/ping  -> "
curl -fsS --max-time 15 "https://$DOMAIN/ping" || echo "(henüz yanıt yok — DNS yayılmasını bekleyin)"
echo
echo -n "  /check_room (eski istemciler) -> "
curl -fsS --max-time 15 "https://$DOMAIN/check_room/0000" || echo "(yanıt yok)"
echo
echo "✓ Kurulum tamamlandı"
