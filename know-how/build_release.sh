#!/usr/bin/env bash
# USB ile taşınacak sürüm paketini üretir.
#
# Her servisin imajını derler/çeker, `docker save` ile tar'lar, sürüm
# dosyalarını yazar ve doğrulama toplamlarını üretir. Çıktı, hedef makineye
# kopyalanmaya hazır tek bir dizin.
#
#   ./know-how/build_release.sh 1.2.0
#   ./know-how/build_release.sh 1.2.0 --with-data     # oyuncu veritabanı dahil
#   ./know-how/build_release.sh 1.2.0 --allow-dirty   # commit edilmemiş değişikliklerle
#
# Servis tanımları docker-compose.yml'dan TÜRETİLİR, elle yazılmaz; böylece
# paketteki tanım kaynakla ayrışamaz.
#
# Üçüncü parti imajlar digest'e sabitlenir: `nginx:1.27-alpine` bugün ve
# gelecek ay farklı imaj demek, iki paket sessizce farklı olurdu.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

VERSION="${1:-}"
WITH_DATA=0
ALLOW_DIRTY=0
shift || true
for arg in "$@"; do
  case "$arg" in
    --with-data)   WITH_DATA=1 ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    *) echo "Bilinmeyen seçenek: $arg" >&2; exit 2 ;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "Kullanım: $0 <versiyon> [--with-data] [--allow-dirty]" >&2
  exit 2
fi
if ! printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "✗ Versiyon x.y.z biçiminde olmalı: $VERSION" >&2
  exit 2
fi

OUT="$ROOT/know-how/releases/$VERSION"
if [ -d "$OUT" ]; then
  echo "✗ $VERSION zaten var: $OUT" >&2
  echo "  Yeniden üretmek için önce silin." >&2
  exit 1
fi

# --- ön koşullar ------------------------------------------------------
command -v docker >/dev/null || { echo "✗ docker bulunamadı" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "✗ docker çalışmıyor" >&2; exit 1; }

# --- python (pyyaml gerekli) -----------------------------------------
# Servis tanımları compose'dan türetiliyor, bu da yaml istiyor. Sistem
# python'unda genelde kurulu değil; sırayla proje sanal ortamı, sistem
# python'u, en son geçici bir sanal ortam denenir. Betiğin çalışması
# kullanıcının makinesine pyyaml kurmuş olmasına bağlı olmamalı.
resolve_python() {
  local candidate
  for candidate in "$ROOT/backend/.venv/bin/python" python3; do
    if command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ]; then
      if "$candidate" -c "import yaml" >/dev/null 2>&1; then
        echo "$candidate"
        return 0
      fi
    fi
  done

  local venv="${TMPDIR:-/tmp}/ttt-release-venv"
  if [ ! -x "$venv/bin/python" ]; then
    echo "  pyyaml bulunamadı, geçici ortam kuruluyor" >&2
    python3 -m venv "$venv" >&2
    "$venv/bin/pip" install --quiet pyyaml >&2
  fi
  echo "$venv/bin/python"
}
PY="$(resolve_python)"

GIT_SHA="$(git rev-parse HEAD)"
GIT_DIRTY="$(git status --porcelain | head -1)"
if [ -n "$GIT_DIRTY" ] && [ "$ALLOW_DIRTY" = "0" ]; then
  echo "✗ Çalışma ağacı temiz değil. Paketin hangi koddan çıktığı belirsiz kalır." >&2
  echo "  Yine de üretmek için: --allow-dirty" >&2
  exit 1
fi

echo "▶ Sürüm $VERSION  (commit ${GIT_SHA:0:8}${GIT_DIRTY:+, KİRLİ})"
mkdir -p "$OUT/images" "$OUT/services"

# --- servis tanımlarını compose'dan türet -----------------------------
echo "▶ Servis tanımları türetiliyor"
"$PY" "$ROOT/know-how/templates/split_compose.py" \
  "$ROOT/docker-compose.yml" "$OUT/services"

SERVICES="$("$PY" -c "
import yaml, sys
d = yaml.safe_load(open('$ROOT/docker-compose.yml'))
print(' '.join(d['services'].keys()))
" 2>/dev/null || echo "backend nginx certbot redis")"
echo "  servisler: $SERVICES"

# --- imajlar ----------------------------------------------------------
BACKEND_IMAGE="footttball-backend:$VERSION"

echo "▶ Backend imajı derleniyor"
docker build --quiet -t "$BACKEND_IMAGE" "$ROOT/backend" > /dev/null
echo "  $BACKEND_IMAGE"

# Üçüncü parti imajlar: compose'daki etiketten çekip digest'e sabitle.
declare -a PINNED=()
pin_image() {
  # Yalnızca digest stdout'a yazılır; çağıran onu $(...) ile yakalıyor.
  # İlerleme mesajları stderr'e gider — aksi halde mesaj digest'e karışıp
  # version.env'i bozuyordu ve hedef makinede compose kırılıyordu.
  local service="$1" ref="$2"
  echo "  $service: $ref" >&2
  docker pull --quiet "$ref" > /dev/null 2>&1
  local digest
  digest="$(docker inspect --format '{{index .RepoDigests 0}}' "$ref" 2>/dev/null || true)"
  # Yerelde derlenmiş ya da digest'i olmayan imajlar için etikete düşülür.
  [ -z "$digest" ] && digest="$ref"
  printf '%s' "$digest"
}

echo "▶ Üçüncü parti imajlar digest'e sabitleniyor"
NGINX_REF="$("$PY" -c "
import yaml; print(yaml.safe_load(open('$ROOT/docker-compose.yml'))['services']['nginx']['image'])")"
REDIS_REF="$("$PY" -c "
import yaml; print(yaml.safe_load(open('$ROOT/docker-compose.yml'))['services']['redis']['image'])")"
CERTBOT_REF="$("$PY" -c "
import yaml; print(yaml.safe_load(open('$ROOT/docker-compose.yml'))['services']['certbot']['image'])")"

NGINX_DIGEST="$(pin_image nginx "$NGINX_REF")"
REDIS_DIGEST="$(pin_image redis "$REDIS_REF")"
CERTBOT_DIGEST="$(pin_image certbot "$CERTBOT_REF")"

# Paketteki imajlar sürüme özel etiketle taşınır.
#
# Digest referansı (`nginx@sha256:...`) cazip ama riskli: `docker save`
# ile taşınan bir imajın digest'ini geri kazanmak Docker'ın imaj deposuna
# bağlı. Yeni sürümler (containerd) koruyor, eskiler korumuyor ve o
# durumda compose imajı kayıt defterinden çekmeye kalkıyor — internetsiz
# makinede tam olarak olmaması gereken şey. Sürüme özel etiket her Docker
# sürümünde çalışır; digest köken bilgisi olarak manifest'te durur.
NGINX_IMAGE="ttt-nginx:$VERSION"
REDIS_IMAGE="ttt-redis:$VERSION"
CERTBOT_IMAGE="ttt-certbot:$VERSION"
docker tag "$NGINX_REF"   "$NGINX_IMAGE"
docker tag "$REDIS_REF"   "$REDIS_IMAGE"
docker tag "$CERTBOT_REF" "$CERTBOT_IMAGE"
echo "  sürüm etiketleri: $NGINX_IMAGE, $REDIS_IMAGE, $CERTBOT_IMAGE"

# --- imajları tar'la --------------------------------------------------
save_image() {
  local name="$1" ref="$2"
  printf '  %-10s ' "$name"
  docker save "$ref" | gzip -6 > "$OUT/images/$name.tar.gz"
  du -h "$OUT/images/$name.tar.gz" | cut -f1
}

echo "▶ İmajlar tar'lanıyor"
save_image backend "$BACKEND_IMAGE"
save_image nginx   "$NGINX_IMAGE"
save_image redis   "$REDIS_IMAGE"
save_image certbot "$CERTBOT_IMAGE"

# --- veritabanı -------------------------------------------------------
DB_PATH="$ROOT/backend/data/tikitakapi.db"
if [ "$WITH_DATA" = "1" ]; then
  if [ ! -f "$DB_PATH" ]; then
    echo "✗ --with-data verildi ama $DB_PATH yok" >&2
    exit 1
  fi
  echo "▶ Oyuncu veritabanı ekleniyor"
  mkdir -p "$OUT/data"
  # Canlı dosyayı kopyalamak tutarsız bir görüntü verebilir; SQLite'ın
  # kendi yedekleme API'si yazma sürerken de bütün bir kopya üretir.
  python3 - "$DB_PATH" "$OUT/data/tikitakapi.db" <<'DBPY'
import sqlite3, sys
src = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True, timeout=60)
dst = sqlite3.connect(sys.argv[2])
with dst:
    src.backup(dst)
src.close(); dst.close()
DBPY
  gzip -6 "$OUT/data/tikitakapi.db"
  echo "  $(du -h "$OUT/data/tikitakapi.db.gz" | cut -f1)"
fi

# --- version.env ------------------------------------------------------
echo "▶ version.env"
cat > "$OUT/version.env" <<ENVEOF
# $VERSION sürümünün imaj kilidi.
#
# update.sh bu dosyayı hedef makinedeki .env'e yazar; docker compose
# imajları buradan okur. Etiketler sürüme özel: paketten yüklenen imaj
# her Docker sürümünde bu adla bulunur, kayıt defterine gidilmez.
# Hangi kaynaktan geldikleri (digest dahil) manifest.json'da.
#
# Üretim: $(date -u +%Y-%m-%dT%H:%M:%SZ)  commit ${GIT_SHA:0:12}

RELEASE_VERSION=$VERSION
BACKEND_IMAGE=$BACKEND_IMAGE
NGINX_IMAGE=$NGINX_IMAGE
REDIS_IMAGE=$REDIS_IMAGE
CERTBOT_IMAGE=$CERTBOT_IMAGE
ENVEOF

# --- update.sh --------------------------------------------------------
cp "$ROOT/know-how/templates/update.sh" "$OUT/update.sh"
chmod +x "$OUT/update.sh"

# --- manifest ---------------------------------------------------------
echo "▶ manifest.json"
cat > "$OUT/.sources.tmp" <<SRCEOF
nginx|$NGINX_REF|$NGINX_DIGEST
redis|$REDIS_REF|$REDIS_DIGEST
certbot|$CERTBOT_REF|$CERTBOT_DIGEST
SRCEOF
python3 - "$OUT" "$VERSION" "$GIT_SHA" "$WITH_DATA" <<'MANPY'
import hashlib, json, os, subprocess, sys
from datetime import datetime, timezone

out, version, sha, with_data = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"

images = {}
for name in sorted(os.listdir(os.path.join(out, "images"))):
    path = os.path.join(out, "images", name)
    images[name] = {"bytes": os.path.getsize(path)}

sources = {}
src_path = os.path.join(out, ".sources.tmp")
if os.path.exists(src_path):
    for line in open(src_path):
        parts = line.strip().split("|")
        if len(parts) == 3:
            sources[parts[0]] = {"pulled_from": parts[1], "digest": parts[2]}
    os.remove(src_path)

env = {}
for line in open(os.path.join(out, "version.env")):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        key, value = line.split("=", 1)
        env[key] = value

manifest = {
    "version": version,
    "git_sha": sha,
    "built_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "includes_database": with_data,
    "images": env,
    "sources": sources,
    "artifacts": images,
    "total_bytes": sum(
        os.path.getsize(os.path.join(root, f))
        for root, _, files in os.walk(out) for f in files
    ),
}
with open(os.path.join(out, "manifest.json"), "w") as fh:
    json.dump(manifest, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
MANPY

# --- doğrulama toplamları --------------------------------------------
echo "▶ checksums.sha256"
( cd "$OUT" && find . -type f ! -name checksums.sha256 -print0 \
    | sort -z | xargs -0 shasum -a 256 > checksums.sha256 )

# --- özet -------------------------------------------------------------
TOTAL="$(du -sh "$OUT" | cut -f1)"
echo
echo "✓ Paket hazır: know-how/releases/$VERSION  ($TOTAL)"
echo
echo "  USB'ye kopyala:"
echo "    cp -R know-how/releases/$VERSION /Volumes/<USB>/"
echo
echo "  Hedef makinede:"
echo "    cd $VERSION && sudo ./update.sh /srv/tikitakatoe"
