#!/usr/bin/env bash
# @@THIS_VERSION@@ sürümünden @@PREV_VERSION@@ sürümüne döner.
#
#   sudo ./revert_@@PREV_VERSION@@.sh /srv/tikitakatoe
#
# Geri dönüş imaj yüklemez: @@PREV_VERSION@@ imajları hedef makinede zaten
# duruyor (bu paket uygulanmadan önce çalışan sürümdü). Yapılan iş, imaj
# kilidini geri yazıp servisleri yeniden başlatmak — saniyeler sürer.
#
# Eğer o imajlar makineden silinmişse (docker image prune) betik uyarır ve
# durur; sessizce kayıt defterine gitmeye çalışmaz.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-/srv/tikitakatoe}"
PREV_ENV="$HERE/version_@@PREV_VERSION@@.env"

echo "▶ @@THIS_VERSION@@ -> @@PREV_VERSION@@"
[ -d "$TARGET" ] || { echo "✗ Hedef dizin yok: $TARGET" >&2; exit 1; }
[ -f "$PREV_ENV" ] || { echo "✗ $PREV_ENV yok" >&2; exit 1; }

# --- imajlar yerinde mi -----------------------------------------------
echo "▶ Önceki sürümün imajları kontrol ediliyor"
MISSING=""
while IFS='=' read -r key value; do
  case "$key" in *_IMAGE) ;; *) continue ;; esac
  if ! docker image inspect "$value" >/dev/null 2>&1; then
    MISSING="$MISSING $value"
    echo "  ✗ $value yok"
  else
    echo "  ✓ $value"
  fi
done < <(grep -E '^[A-Z_]+_IMAGE=' "$PREV_ENV")

if [ -n "$MISSING" ]; then
  echo >&2
  echo "✗ Geri dönülemiyor: şu imajlar makinede yok:$MISSING" >&2
  echo "  @@PREV_VERSION@@ paketini USB'den tekrar uygulayın." >&2
  exit 1
fi

# --- kilidi geri yaz --------------------------------------------------
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$TARGET/know-how-backups/revert-$STAMP"
mkdir -p "$BACKUP"
cp "$TARGET/.env" "$BACKUP/.env"
echo "▶ Mevcut kilit yedeklendi: $BACKUP/.env"

grep -vE '^(RELEASE_VERSION|BACKEND_IMAGE|NGINX_IMAGE|REDIS_IMAGE|CERTBOT_IMAGE|INCLUDED_SERVICES)=' \
  "$TARGET/.env" > "$TARGET/.env.tmp" || true
grep -vE '^\s*(#|$)' "$PREV_ENV" >> "$TARGET/.env.tmp"
mv "$TARGET/.env.tmp" "$TARGET/.env"

# --- yeniden başlat ---------------------------------------------------
COMPOSE_ARGS="--project-directory $TARGET --env-file $TARGET/.env"
for yml in "$TARGET"/know-how-services/*.yml; do
  COMPOSE_ARGS="$COMPOSE_ARGS -f $yml"
done

echo "▶ Servisler yeniden başlatılıyor"
( cd "$TARGET" && docker compose $COMPOSE_ARGS up -d --pull never )

echo "▶ Sağlık kontrolü"
for i in $(seq 1 30); do
  if ( cd "$TARGET" && docker compose $COMPOSE_ARGS exec -T backend python -c \
      "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/ping', timeout=3).status==200 else 1)" ) 2>/dev/null; then
    echo "  ✓ Backend ayakta"
    echo
    echo "✓ @@PREV_VERSION@@ sürümüne dönüldü"
    exit 0
  fi
  sleep 2
done

echo "✗ Geri dönülen sürüm de sağlık kontrolünden geçmedi" >&2
( cd "$TARGET" && docker compose $COMPOSE_ARGS logs --tail=40 backend ) || true
exit 1
