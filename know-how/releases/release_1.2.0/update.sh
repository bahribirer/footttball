#!/usr/bin/env bash
# Sürüm paketini hedef makineye uygular.
#
# USB'den kopyalanan sürüm dizininin içinden çalıştırılır:
#
#   cd 1.2.0 && sudo ./update.sh /srv/tikitakatoe
#
# Seçenekler:
#   --with-redis    redis servisini de başlatır (çok süreçli çalışma)
#   --skip-verify   doğrulama toplamlarını atlar (önerilmez)
#   --dry-run       ne yapacağını yazar, hiçbir şeye dokunmaz
#
# Sıra: doğrula → yedekle → imajları yükle → .env yaz → başlat → sağlık
# kontrolü. Sağlık kontrolü düşerse önceki sürüme dönülür.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-/srv/tikitakatoe}"
shift || true

WITH_REDIS=0
SKIP_VERIFY=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --with-redis)  WITH_REDIS=1 ;;
    --skip-verify) SKIP_VERIFY=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    *) echo "Bilinmeyen seçenek: $arg" >&2; exit 2 ;;
  esac
done

VERSION="$(grep '^RELEASE_VERSION=' "$HERE/version.env" | cut -d= -f2)"
echo "▶ Sürüm $VERSION -> $TARGET"

[ -d "$TARGET" ] || { echo "✗ Hedef dizin yok: $TARGET" >&2; exit 1; }
command -v docker >/dev/null || { echo "✗ docker bulunamadı" >&2; exit 1; }

# --- doğrulama --------------------------------------------------------
# USB'den kopyalama sessizce bozulabilir; bozuk bir imajı yükleyip servisi
# kırmaktansa hiç başlamamak yeğdir.
if [ "$SKIP_VERIFY" = "0" ]; then
  echo "▶ Doğrulama toplamları"
  if ! ( cd "$HERE" && shasum -a 256 -c checksums.sha256 --quiet 2>/dev/null ); then
    echo "✗ Paket bozuk — hiçbir değişiklik yapılmadı." >&2
    echo "  USB'den yeniden kopyalayın." >&2
    exit 1
  fi
  echo "  ✓ bütün"
fi

if [ "$DRY_RUN" = "1" ]; then
  echo
  echo "— dry-run: yapılacaklar —"
  echo "  imajlar yüklenecek: $(ls "$HERE/images" | tr '\n' ' ')"
  echo "  .env yazılacak:"
  sed 's/^/    /' "$HERE/version.env" | grep -v '^\s*#' | grep -v '^\s*$'
  [ -f "$HERE/data/tikitakapi.db.gz" ] && echo "  veritabanı değiştirilecek"
  exit 0
fi

# --- yedek ------------------------------------------------------------
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$TARGET/know-how-backups/$STAMP"
mkdir -p "$BACKUP"
echo "▶ Yedek: $BACKUP"
[ -f "$TARGET/.env" ] && cp "$TARGET/.env" "$BACKUP/.env"
if [ -f "$TARGET/backend/data/tikitakapi.db" ]; then
  cp "$TARGET/backend/data/tikitakapi.db" "$BACKUP/tikitakapi.db"
  echo "  veritabanı yedeklendi"
fi

# Geri dönüş için önceki sürümün imaj kilidi.
PREVIOUS_ENV=""
[ -f "$BACKUP/.env" ] && PREVIOUS_ENV="$BACKUP/.env"

# --- imajlar ----------------------------------------------------------
# Mimari denetimi.
#
# Yanlış mimarili bir paket sessiz bir tuzak: `docker load` sorunsuz geçer,
# konteyner "exec format error" ile ölür ve sebebi log'da açık yazmaz.
# Apple Silicon'da derlenip x86 sunucuya götürülen paket tam olarak böyle
# davranır. Yüklemeden önce durulur.
EXPECTED_PLATFORM="$(grep '^RELEASE_PLATFORM=' "$HERE/version.env" 2>/dev/null | cut -d= -f2 || true)"
HOST_INFO="$(docker info --format '{{.OSType}}/{{.Architecture}}' 2>/dev/null || echo '?')"
case "$HOST_INFO" in
  *aarch64*|*arm64*) HOST_PLATFORM="linux/arm64" ;;
  *x86_64*|*amd64*)  HOST_PLATFORM="linux/amd64" ;;
  *)                 HOST_PLATFORM="$HOST_INFO" ;;
esac

if [ -n "$EXPECTED_PLATFORM" ] && [ "$EXPECTED_PLATFORM" != "$HOST_PLATFORM" ]; then
  echo "✗ Mimari uyuşmuyor — hiçbir şeye dokunulmadı." >&2
  echo "  Paket : $EXPECTED_PLATFORM" >&2
  echo "  Makine: $HOST_PLATFORM" >&2
  echo >&2
  echo "  Paketi doğru mimariyle yeniden üretin:" >&2
  echo "    ./know-how/build_release.sh <sürüm> --platform $HOST_PLATFORM" >&2
  exit 1
fi
[ -n "$EXPECTED_PLATFORM" ] && echo "▶ Mimari: $EXPECTED_PLATFORM ✓"

echo "▶ İmajlar yükleniyor"
for archive in "$HERE"/images/*.tar.gz; do
  printf '  %-14s ' "$(basename "$archive" .tar.gz)"
  gunzip -c "$archive" | docker load | tail -1
done

# --- servis tanımları -------------------------------------------------
echo "▶ Servis tanımları"
mkdir -p "$TARGET/know-how-services"
# Delta paketinde yalnızca değişen servislerin tanımı var;
# hedefteki diğerleri olduğu gibi kalır.
cp "$HERE"/containers/*.yml "$TARGET/know-how-services/"

# --project-directory ve --env-file ŞART.
#
# docker compose proje dizinini ilk `-f` dosyasının bulunduğu yerden
# belirliyor; burası know-how-services/ olduğu için $TARGET/.env hiç
# okunmuyordu. BACKEND_IMAGE boş kalınca compose varsayılan GHCR adresine
# düşüp imajı ÇEKMEYE kalkıyordu — internetsiz makinede tam olarak
# olmaması gereken şey.
COMPOSE_ARGS="--project-directory $TARGET --env-file $TARGET/.env"
COMPOSE_ARGS="$COMPOSE_ARGS -f $TARGET/know-how-services/_base.yml"
for service in backend nginx certbot; do
  COMPOSE_ARGS="$COMPOSE_ARGS -f $TARGET/know-how-services/$service.yml"
done
if [ "$WITH_REDIS" = "1" ]; then
  COMPOSE_ARGS="$COMPOSE_ARGS -f $TARGET/know-how-services/redis.yml"
fi

# --- veritabanı -------------------------------------------------------
if [ -f "$HERE/data/tikitakapi.db.gz" ]; then
  echo "▶ Oyuncu veritabanı yazılıyor"
  mkdir -p "$TARGET/backend/data"
  gunzip -c "$HERE/data/tikitakapi.db.gz" > "$TARGET/backend/data/tikitakapi.db.new"
  mv "$TARGET/backend/data/tikitakapi.db.new" "$TARGET/backend/data/tikitakapi.db"
  # Container uygulama kullanıcısı bu dizine yazabilmeli: WAL modunda
  # SQLite okurken bile -shm dosyasını açmak zorunda.
  chown -R 1000:1000 "$TARGET/backend/data" 2>/dev/null || true
  echo "  ✓ yazıldı"
fi

# --- .env -------------------------------------------------------------
echo "▶ İmaj kilidi uygulanıyor"
# Hedefteki .env'de bu paketle ilgisi olmayan ayarlar olabilir (SENTRY_DSN,
# MODES_DISABLED gibi); yalnızca imaj satırları değiştirilir.
touch "$TARGET/.env"
grep -vE '^(RELEASE_VERSION|BACKEND_IMAGE|NGINX_IMAGE|REDIS_IMAGE|CERTBOT_IMAGE)=' \
  "$TARGET/.env" > "$TARGET/.env.tmp" || true
grep -vE '^\s*(#|$)' "$HERE/version.env" >> "$TARGET/.env.tmp"
mv "$TARGET/.env.tmp" "$TARGET/.env"

# --- bind yolları ve portlar -----------------------------------------
# Servis tanımlarındaki bind kaynakları ve host portları değişkene çevrildi.
# Burada .env'e YALNIZCA eksik olanlar yazılır: operatör bir dizini başka
# yere taşımışsa (örneğin veritabanını büyük diske) sonraki güncelleme onu
# geri almamalı.
echo "▶ Bind yolları ve portlar"
ADDED=0
while IFS='=' read -r key default; do
  case "$key" in ''|\#*) continue ;; esac
  if grep -qE "^${key}=" "$TARGET/.env"; then
    echo "  = $key (mevcut değer korundu)"
    continue
  fi
  # Göreli varsayılanlar hedefe göre mutlaklaştırılır; operatör .env'e
  # bakınca dizinin nerede olduğunu görebilmeli.
  value="$default"
  case "$default" in
    ./*) value="$TARGET/${default#./}" ;;
  esac
  printf '%s=%s\n' "$key" "$value" >> "$TARGET/.env"
  echo "  + $key=$value"
  ADDED=$((ADDED + 1))
done < "$HERE/containers/bind_defaults.env"
[ "$ADDED" = "0" ] && echo "  (hepsi zaten tanımlı)"

# --- başlat -----------------------------------------------------------
echo "▶ Servisler başlatılıyor"
# --pull never: paket kendi kendine yetmeli. Compose bir imajı çekmeye
# kalkıyorsa bu bir yapılandırma hatasıdır ve sessizce internete gitmek
# yerine yüksek sesle düşmesi gerekir.
( cd "$TARGET" && docker compose $COMPOSE_ARGS up -d --pull never )

# --- sağlık kontrolü --------------------------------------------------
echo "▶ Sağlık kontrolü"
HEALTHY=0
for i in $(seq 1 30); do
  if ( cd "$TARGET" && docker compose $COMPOSE_ARGS exec -T backend python -c \
      "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/ping', timeout=3).status==200 else 1)" ) 2>/dev/null; then
    HEALTHY=1
    break
  fi
  sleep 2
done

if [ "$HEALTHY" = "0" ]; then
  echo "✗ Backend sağlık kontrolünden geçmedi" >&2
  ( cd "$TARGET" && docker compose $COMPOSE_ARGS logs --tail=40 backend ) || true
  if [ -n "$PREVIOUS_ENV" ]; then
    echo "↩ Önceki imaj kilidine dönülüyor" >&2
    cp "$PREVIOUS_ENV" "$TARGET/.env"
    ( cd "$TARGET" && docker compose $COMPOSE_ARGS up -d ) || true
  fi
  exit 1
fi

echo "  ✓ Backend ayakta"

# Backend sağlıklı olsa bile başka bir servis çöküp duruyor olabilir.
# Testte nginx sertifika bulamayıp yeniden başlama döngüsüne girdi ve
# update.sh yine de "başarılı" dedi — sessiz kalmamalı.
# Servislerin oturması beklenir. Kontrol hemen koşarsa çökmek üzere olan
# bir servis hâlâ "Up" görünür ve elden kaçar: denemede nginx sertifika
# bulamayıp döngüye giriyordu ama kontrol onu "Up" yakalayıp başarılı
# demişti.
echo "▶ Diğer servisler (oturması bekleniyor)"
sleep 8
UNSTABLE=""
while read -r line; do
  name="${line%%|*}"
  state="${line#*|}"
  case "$state" in
    *Restarting*|*Exited*|*unhealthy*)
      UNSTABLE="$UNSTABLE $name"
      echo "  ✗ $name: $state" ;;
    *) echo "  ✓ $name: $state" ;;
  esac
done < <( cd "$TARGET" && docker compose $COMPOSE_ARGS ps --format '{{.Service}}|{{.Status}}' 2>/dev/null )

# İkinci örnekleme: ilk turda "Up" görünüp hemen sonra çöken servisler
# yakalansın.
if [ -z "$UNSTABLE" ]; then
  sleep 6
  while read -r line; do
    name="${line%%|*}"
    state="${line#*|}"
    case "$state" in
      *Restarting*|*Exited*|*unhealthy*)
        UNSTABLE="$UNSTABLE $name"
        echo "  ✗ $name: $state (ilk kontrolden sonra çöktü)" ;;
    esac
  done < <( cd "$TARGET" && docker compose $COMPOSE_ARGS ps --format '{{.Service}}|{{.Status}}' 2>/dev/null )
fi

if [ -n "$UNSTABLE" ]; then
  echo >&2
  echo "⚠ Kararsız servis(ler):$UNSTABLE" >&2
  echo "  Backend ayakta ama yığın eksik. Sık karşılaşılan sebep: nginx için" >&2
  echo "  TLS sertifikası yok (infra/certbot/conf/live). Bkz. README." >&2
  ( cd "$TARGET" && docker compose $COMPOSE_ARGS logs --tail=15 $UNSTABLE ) 2>/dev/null || true
  exit 1
fi

echo
echo "✓ $VERSION uygulandı"
echo "  Yedek: $BACKUP"
echo "  Geri dönmek için:  cp $BACKUP/.env $TARGET/.env && cd $TARGET && docker compose $COMPOSE_ARGS up -d"
