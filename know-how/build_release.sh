#!/usr/bin/env bash
# USB ile taşınacak sürüm paketini üretir.
#
# Her servisin imajını derler/çeker, `docker save` ile tar'lar, sürüm
# dosyalarını yazar ve doğrulama toplamlarını üretir. Çıktı, hedef makineye
# kopyalanmaya hazır tek bir dizin.
#
#   ./know-how/build_release.sh 1.2.1                 # delta: yalnızca değişenler
#   ./know-how/build_release.sh 1.2.1 --full          # tam paket (ilk kurulum)
#   ./know-how/build_release.sh 1.2.1 --with-data     # oyuncu veritabanı dahil
#   ./know-how/build_release.sh 1.2.1 --allow-dirty   # commit edilmemiş değişikliklerle
#
# Servis kaynağı seçmek:
#
#   ./know-how/build_release.sh 2.5.0 --backend 011c19b     # o commit'ten derle
#   ./know-how/build_release.sh 2.5.0 --backend v1.1.0      # o etiketten derle
#
# Kendi servislerimiz her zaman KAYNAKTAN DERLENİR, kayıt defterinden
# çekilmez. --backend bir git referansı alır; o commit geçici bir
# worktree'ye çıkarılıp oradan derlenir. Verilmezse çalışma ağacı kullanılır.
#
# Hangi commit'ten çıktığı manifest.json'da kalır; müşteri yalnızca sürüm
# numarasını görür.
#
# Üçüncü parti imajlar (nginx, redis, certbot) upstream'den gelir; onlar
# derlenemez, derleme makinesinde çekilir. Hedef makinede internet
# gerekmez — paket zaten hepsini taşır.
#
# Delta paketleme: her sürüm yalnızca bir öncekine göre DEĞİŞEN servisleri
# taşır. Dokunulmayan bir servisin imajını yeniden yüklemek onu gereksiz
# yere yeniden başlatır ve USB'de yer yakar.
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
FULL=0
# Servis kaynakları: verilmezse yerelden derlenir / compose'daki etiket alınır.
SRC_BACKEND=""
SRC_NGINX=""
SRC_REDIS=""
SRC_CERTBOT=""
# Paketin çalışacağı makinenin mimarisi — bu makinenin değil.
#
# Apple Silicon'da derlenen imaj arm64 olur ve x86 sunucuda çalışmaz;
# `docker load` sessizce geçer, konteyner "exec format error" ile ölür.
# Varsayılan üretim sunucusunun mimarisi.
PLATFORM="${TTT_PLATFORM:-linux/amd64}"
shift || true
while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-data)   WITH_DATA=1 ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --full)        FULL=1 ;;
    --backend)     SRC_BACKEND="${2:?--backend bir değer ister}"; shift ;;
    --nginx)       SRC_NGINX="${2:?--nginx bir değer ister}"; shift ;;
    --redis)       SRC_REDIS="${2:?--redis bir değer ister}"; shift ;;
    --certbot)     SRC_CERTBOT="${2:?--certbot bir değer ister}"; shift ;;
    --platform)    PLATFORM="${2:?--platform bir değer ister}"; shift ;;
    *) echo "Bilinmeyen seçenek: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$VERSION" ]; then
  echo "Kullanım: $0 <versiyon> [--full] [--with-data] [--allow-dirty]" >&2
  exit 2
fi
if ! printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "✗ Versiyon x.y.z biçiminde olmalı: $VERSION" >&2
  exit 2
fi

OUT="$ROOT/know-how/releases/release_$VERSION"
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
# Yalnızca KAYNAK değişiklikleri sayılır.
#
# know-how/releases/ ve üretilen güncelleme notları paketin çıktısı, girdisi
# değil. Bir sürümü yeniden üretmek ya da eskisini silmek ağacı "kirli"
# gösterip yeni paket üretmeyi engelliyordu — kontrolün amacı bu değil.
GIT_DIRTY="$(git status --porcelain \
  -- ':!know-how/releases' ':!know-how/dokumanlar/guncelleme-notlari' \
  | head -1)"
# Backend'in kaynağı açıkça verildiyse çalışma ağacının hâli önemsiz:
# paket o ağaçtan değil, söylenen yapıdan çıkıyor.
[ -n "$SRC_BACKEND" ] && ALLOW_DIRTY=1
if [ -n "$GIT_DIRTY" ] && [ "$ALLOW_DIRTY" = "0" ]; then
  echo "✗ Çalışma ağacı temiz değil. Paketin hangi koddan çıktığı belirsiz kalır." >&2
  echo "  Yine de üretmek için: --allow-dirty" >&2
  exit 1
fi

echo "▶ Sürüm $VERSION  (commit ${GIT_SHA:0:8}${GIT_DIRTY:+, KİRLİ})"
echo "▶ Hedef mimari: $PLATFORM"
HOST_ARCH="$(docker info --format '{{.OSType}}/{{.Architecture}}' 2>/dev/null || echo bilinmiyor)"
case "$HOST_ARCH" in
  *aarch64*|*arm64*) HOST_NORM="linux/arm64" ;;
  *x86_64*|*amd64*)  HOST_NORM="linux/amd64" ;;
  *)                 HOST_NORM="$HOST_ARCH" ;;
esac
if [ "$HOST_NORM" != "$PLATFORM" ]; then
  echo "  (bu makine $HOST_NORM — çapraz derleme, biraz yavaş olabilir)"
fi
mkdir -p "$OUT/images" "$OUT/containers"

# --- servis tanımlarını compose'dan türet -----------------------------
echo "▶ Servis tanımları türetiliyor"
"$PY" "$ROOT/know-how/templates/split_compose.py" \
  "$ROOT/docker-compose.yml" "$OUT/containers"

SERVICES="$("$PY" -c "
import yaml, sys
d = yaml.safe_load(open('$ROOT/docker-compose.yml'))
print(' '.join(d['services'].keys()))
" 2>/dev/null || echo "backend nginx certbot redis")"
echo "  servisler: $SERVICES"

# --- delta: hangi servisler pakete girecek ---------------------------
# Her paket yalnızca DEĞİŞEN servisleri taşır. Sekiz servisli bir yığında
# tek satır değişince gigabaytlarca imajı USB'ye kopyalamak hem zaman
# kaybı hem de gereksiz risk: dokunulmayan bir servisin imajını yeniden
# yüklemek onu yeniden başlatır.
#
# Karşılaştırma en son üretilmiş pakete göre yapılır. --full ile hepsi
# alınır; ilk kurulum paketi böyle üretilir.
PREVIOUS_RELEASE=""
if [ "$FULL" = "0" ]; then
  PREVIOUS_RELEASE="$(ls -1d "$ROOT"/know-how/releases/release_* 2>/dev/null \
    | grep -v "release_$VERSION\$" | sort -V | tail -1)"
fi

CHANGED=""
if [ -n "$PREVIOUS_RELEASE" ] && [ -f "$PREVIOUS_RELEASE/version.env" ]; then
  echo "▶ Delta tabanı: $(basename "$PREVIOUS_RELEASE")"
else
  echo "▶ Tam paket (karşılaştırılacak önceki sürüm yok)"
fi

# --- imajlar ----------------------------------------------------------
BACKEND_IMAGE="footttball-backend:$VERSION"

# Backend her zaman KAYNAKTAN derlenir; kayıt defterinden çekilmez.
#
# --backend ile bir git referansı (commit sha, etiket, dal) verilirse o
# commit'in kodu geçici bir worktree'ye çıkarılıp oradan derlenir. Böylece
# paket, çalışma ağacının o anki hâlinden bağımsız olarak istenen sürümün
# kodunu taşır — ve internet gerekmez.
BACKEND_SOURCE=""
if [ -n "$SRC_BACKEND" ]; then
  if ! git rev-parse --verify --quiet "$SRC_BACKEND^{commit}" >/dev/null; then
    echo "✗ Böyle bir commit yok: $SRC_BACKEND" >&2
    exit 1
  fi
  RESOLVED_SHA="$(git rev-parse "$SRC_BACKEND")"
  WORKTREE="${TMPDIR:-/tmp}/ttt-build-${RESOLVED_SHA:0:12}"
  echo "▶ Backend kaynağı: commit ${RESOLVED_SHA:0:12}"
  rm -rf "$WORKTREE"
  git worktree add --detach --quiet "$WORKTREE" "$RESOLVED_SHA"
  # Worktree geçici; derleme bitince kaldırılır, yarım kalsa bile
  # `git worktree prune` toparlar.
  trap 'git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true' EXIT
  docker build --quiet --platform "$PLATFORM" -t "$BACKEND_IMAGE" "$WORKTREE/backend" > /dev/null
  BACKEND_SOURCE="commit $RESOLVED_SHA"
  echo "  -> $BACKEND_IMAGE"
else
  echo "▶ Backend imajı çalışma ağacından derleniyor"
  docker build --quiet --platform "$PLATFORM" -t "$BACKEND_IMAGE" "$ROOT/backend" > /dev/null
  BACKEND_SOURCE="calisma agaci (${GIT_SHA:0:12})"
  echo "  $BACKEND_IMAGE"
fi

# Üçüncü parti imajlar: compose'daki etiketten çekip digest'e sabitle.
declare -a PINNED=()
pin_image() {
  # Yalnızca digest stdout'a yazılır; çağıran onu $(...) ile yakalıyor.
  # İlerleme mesajları stderr'e gider — aksi halde mesaj digest'e karışıp
  # version.env'i bozuyordu ve hedef makinede compose kırılıyordu.
  local service="$1" ref="$2"
  echo "  $service: $ref" >&2

  # Yereldeki kopya başka mimaridense `pull` işlem yapmaz ve yanlış imaj
  # pakete girer. Uyuşmuyorsa önce silinir.
  local local_arch
  local_arch="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$ref" 2>/dev/null || true)"
  if [ -n "$local_arch" ] && [ "$local_arch" != "$PLATFORM" ]; then
    echo "    yereldeki kopya $local_arch, siliniyor" >&2
    docker rmi -f "$ref" > /dev/null 2>&1 || true
  fi
  docker pull --quiet --platform "$PLATFORM" "$ref" > /dev/null 2>&1
  local digest
  digest="$(docker inspect --format '{{index .RepoDigests 0}}' "$ref" 2>/dev/null || true)"
  # Yerelde derlenmiş ya da digest'i olmayan imajlar için etikete düşülür.
  [ -z "$digest" ] && digest="$ref"
  printf '%s' "$digest"
}

echo "▶ Üçüncü parti imajlar digest'e sabitleniyor"
compose_image() {
  "$PY" -c "
import yaml; print(yaml.safe_load(open('$ROOT/docker-compose.yml'))['services']['$1']['image'])"
}
# Kaynak açıkça verilmişse o, verilmemişse compose'daki etiket.
NGINX_REF="${SRC_NGINX:-$(compose_image nginx)}"
REDIS_REF="${SRC_REDIS:-$(compose_image redis)}"
CERTBOT_REF="${SRC_CERTBOT:-$(compose_image certbot)}"

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

# `docker tag` burada yetmiyor. containerd imaj deposu bir etiketin birden
# fazla platformunu birlikte saklıyor ve `tag` hangisini aldığını
# söylemiyor; sonuç, hedef mimari amd64 iken pakete arm64 imaj girmesi
# oluyordu. buildx'ten tek platformlu imaj istemek bunu kesinleştiriyor:
# çıkan imajın mimarisi tek ve `inspect` doğru söylüyor.
retag_platform() {
  local source_ref="$1" target_tag="$2"
  printf 'FROM %s\n' "$source_ref" \
    | docker buildx build --platform "$PLATFORM" -t "$target_tag" --load - >/dev/null 2>&1
}
retag_platform "$NGINX_REF"   "$NGINX_IMAGE"
retag_platform "$REDIS_REF"   "$REDIS_IMAGE"
retag_platform "$CERTBOT_REF" "$CERTBOT_IMAGE"
echo "  sürüm etiketleri: $NGINX_IMAGE, $REDIS_IMAGE, $CERTBOT_IMAGE ($PLATFORM)"

# --- imajları tar'la --------------------------------------------------
save_image() {
  local name="$1" ref="$2"
  # Yanlış mimarili bir imajı pakete koymak sessiz bir tuzak: docker load
  # geçer, konteyner çalışmaz. Burada durulur.
  local arch
  arch="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$ref" 2>/dev/null || echo '?')"
  if [ "$arch" != "$PLATFORM" ]; then
    echo "✗ $name imajı $arch, hedef $PLATFORM — paket üretilmedi" >&2
    exit 1
  fi
  printf '  %-10s ' "$name"
  docker save --platform "$PLATFORM" "$ref" | gzip -6 > "$OUT/images/$name.tar.gz"
  du -h "$OUT/images/$name.tar.gz" | cut -f1
}

# Bir servisin imajı önceki pakettekiyle aynıysa tar'lanmaz.
should_include() {
  local service="$1" new_ref="$2" var="$3"
  [ "$FULL" = "1" ] && return 0
  [ -z "$PREVIOUS_RELEASE" ] && return 0
  local old_ref
  old_ref="$(grep "^${var}=" "$PREVIOUS_RELEASE/version.env" 2>/dev/null | cut -d= -f2- || true)"
  [ -z "$old_ref" ] && return 0

  # Etiket sürümü taşıdığı için ("ttt-nginx:1.2.0") isim her sürümde
  # değişir; asıl soru İÇERİĞİN değişip değişmediği. Imaj kimliği
  # karşılaştırılır.
  local new_id old_id
  new_id="$(docker image inspect --format '{{.Id}}' "$new_ref" 2>/dev/null || echo new)"
  old_id="$(grep "^#ID_${var}=" "$PREVIOUS_RELEASE/version.env" 2>/dev/null | cut -d= -f2- || echo old)"
  [ "$new_id" != "$old_id" ]
}

echo "▶ İmajlar tar'lanıyor"
INCLUDED=""
SKIPPED=""
tar_if_changed() {
  local service="$1" ref="$2" var="$3"
  if should_include "$service" "$ref" "$var"; then
    save_image "$service" "$ref"
    INCLUDED="$INCLUDED $service"
  else
    printf '  %-10s değişmedi, atlandı\n' "$service"
    SKIPPED="$SKIPPED $service"
    # Değişmeyen servisin tanımı da pakete girmez: delta paketi yalnızca
    # dokunulan servisleri anlatmalı.
    rm -f "$OUT/containers/$service.yml"
  fi
}

tar_if_changed backend "$BACKEND_IMAGE" BACKEND_IMAGE
tar_if_changed nginx   "$NGINX_IMAGE"   NGINX_IMAGE
tar_if_changed redis   "$REDIS_IMAGE"   REDIS_IMAGE
tar_if_changed certbot "$CERTBOT_IMAGE" CERTBOT_IMAGE

# Atlanan servisler ÖNCEKİ sürümün etiketinde kalmalı.
#
# Aksi halde version.env pakette olmayan bir imajı işaret eder: bu makinede
# etiket var (derleme sırasında konuldu) ama hedefte yok ve `--pull never`
# ile dağıtım patlar. Ayrıca etiket değiştiği için compose dokunulmayan
# servisleri de yeniden başlatır — deltanın amacı tam olarak bunu önlemek.
carry_forward() {
  local service="$1" var="$2"
  case " $SKIPPED " in *" $service "*) ;; *) return 0 ;; esac
  local old_ref
  old_ref="$(grep "^${var}=" "$PREVIOUS_RELEASE/version.env" 2>/dev/null | cut -d= -f2- || true)"
  [ -z "$old_ref" ] && return 0
  printf -v "$var" '%s' "$old_ref"
  echo "  $service: $old_ref (önceki sürümden devralındı)"
}

if [ -n "$SKIPPED" ]; then
  echo "▶ Atlanan servislerin etiketleri"
  carry_forward nginx   NGINX_IMAGE
  carry_forward redis   REDIS_IMAGE
  carry_forward certbot CERTBOT_IMAGE
fi

[ -z "$INCLUDED" ] && { echo "✗ Hiçbir servis değişmemiş; paketlenecek bir şey yok." >&2; rm -rf "$OUT"; exit 1; }

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
RELEASE_PLATFORM=$PLATFORM
BACKEND_IMAGE=$BACKEND_IMAGE
NGINX_IMAGE=$NGINX_IMAGE
REDIS_IMAGE=$REDIS_IMAGE
CERTBOT_IMAGE=$CERTBOT_IMAGE

# Bu pakette taşınan servisler. update.sh yalnızca bunları yükler;
# geri kalanlar hedef makinede zaten çalışıyor.
INCLUDED_SERVICES=$(echo $INCLUDED | xargs)

# Sonraki paketin delta karşılaştırması için imaj kimlikleri.
# Yorum satırı: docker compose bunları okumaz.
#ID_BACKEND_IMAGE=$(docker image inspect --format '{{.Id}}' "$BACKEND_IMAGE" 2>/dev/null || true)
#ID_NGINX_IMAGE=$(docker image inspect --format '{{.Id}}' "$NGINX_IMAGE" 2>/dev/null || true)
#ID_REDIS_IMAGE=$(docker image inspect --format '{{.Id}}' "$REDIS_IMAGE" 2>/dev/null || true)
#ID_CERTBOT_IMAGE=$(docker image inspect --format '{{.Id}}' "$CERTBOT_IMAGE" 2>/dev/null || true)
ENVEOF

# --- update.sh --------------------------------------------------------
cp "$ROOT/know-how/templates/update.sh" "$OUT/update.sh"
chmod +x "$OUT/update.sh"

# --- revert betiği ----------------------------------------------------
# Geri dönüş, önceki sürümün imaj kilidini geri yazmaktan ibaret: imajlar
# hedef makinede duruyor, yeniden yükleme gerekmiyor. Betik elle
# yazılmıyor çünkü elle yazıldığında hangi sürüme döndüğü kolayca
# yanlış kalıyor.
if [ -n "$PREVIOUS_RELEASE" ] && [ -f "$PREVIOUS_RELEASE/version.env" ]; then
  PREV_VERSION="$(grep '^RELEASE_VERSION=' "$PREVIOUS_RELEASE/version.env" | cut -d= -f2)"
  echo "▶ revert_$PREV_VERSION.sh"
  sed -e "s|@@PREV_VERSION@@|$PREV_VERSION|g" \
      -e "s|@@THIS_VERSION@@|$VERSION|g" \
      "$ROOT/know-how/templates/revert.sh" > "$OUT/revert_$PREV_VERSION.sh"
  chmod +x "$OUT/revert_$PREV_VERSION.sh"
  # Dönülecek sürümün kilidi pakette taşınır; hedefte bulunmayabilir.
  cp "$PREVIOUS_RELEASE/version.env" "$OUT/version_$PREV_VERSION.env"
fi

# --- müşteri talimatı -------------------------------------------------
echo "▶ Güncelleme notu"
mkdir -p "$ROOT/know-how/dokumanlar/guncelleme-notlari/md"
NOTE="$ROOT/know-how/dokumanlar/guncelleme-notlari/md/$VERSION.md"
"$PY" "$ROOT/know-how/templates/render_note.py" \
  --version "$VERSION" \
  --included "$(echo $INCLUDED | xargs)" \
  --skipped "$(echo $SKIPPED | xargs)" \
  --previous "${PREV_VERSION:-}" \
  --with-data "$WITH_DATA" \
  --output "$NOTE"
echo "  know-how/dokumanlar/guncelleme-notlari/md/$VERSION.md"

# --- manifest ---------------------------------------------------------
echo "▶ manifest.json"
cat > "$OUT/.sources.tmp" <<SRCEOF
backend|$BACKEND_SOURCE|$(docker image inspect --format '{{.Id}}' "$BACKEND_IMAGE" 2>/dev/null || true)
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
echo "✓ Paket hazır: know-how/releases/release_$VERSION  ($TOTAL)"
echo
echo "  USB'ye kopyala:"
echo "    cp -R know-how/releases/release_$VERSION /Volumes/<USB>/"
echo
echo "  Hedef makinede:"
echo "    cd release_$VERSION && sudo ./update.sh /srv/tikitakatoe"
