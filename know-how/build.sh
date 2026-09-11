#!/usr/bin/env bash
# USB ile taşınacak sürüm paketini üç adımda üretir.
#
#   ./know-how/build.sh 1.3.0 --init       iskelet: containers/ + variables.env
#   [containers/ ve variables.env'i doldur]
#   ./know-how/build.sh 1.3.0 --dry-run    plan: neyin derleneceği, hiçbir şeye dokunmaz
#   ./know-how/build.sh 1.3.0              derle → paketle → tar.gz + .sha256
#
# Akış bilerek üçe bölünmüş: karar (hangi servis, hangi commit, hangi hedef)
# insana ait ve variables.env'de yazılı kalıyor; derleme ve paketleme
# makineye ait. --dry-run ikisinin arasında bir kapı — yanlış hedef, kirli
# ağaç, eksik commit derleme başlamadan yakalanır.
#
# Her servisin kaynağı variables.env'de:
#   build:<dizin>[@<ref>]   kaynaktan derle (bizim servisler)
#   image:<ad:etiket>       hazır imaj (üçüncü parti)
#   skip                    bu sürümde girmez, önceki etiket devralınır
#
# Hedef makine TARGET ile seçilir; mimari ve kurulum dizini
# templates/targets.env'den çözülür. Apple Silicon'da derlenen imaj x86
# sunucuda çalışmaz — "exec format error", sebebi log'da yazmaz. Bu yüzden
# mimari hedeften gelir, bu makineden değil.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
KH="$ROOT/know-how"
TPL="$KH/templates"

VERSION="${1:-}"
MODE="build"
ALLOW_DIRTY=0
shift || true
while [ "$#" -gt 0 ]; do
  case "$1" in
    --init)        MODE="init" ;;
    --dry-run)     MODE="dry-run" ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    *) echo "Bilinmeyen seçenek: $1" >&2; exit 2 ;;
  esac
  shift
done

die() { echo "✗ $*" >&2; exit 1; }

[ -n "$VERSION" ] || die "Kullanım: $0 <versiyon> [--init|--dry-run] [--allow-dirty]"
printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || die "Versiyon x.y.z biçiminde olmalı: $VERSION"

OUT="$KH/releases/release_$VERSION"
VARS="$OUT/variables.env"

# --- python (pyyaml gerekli) -----------------------------------------
resolve_python() {
  local c
  for c in "$ROOT/backend/.venv/bin/python" python3; do
    if { command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; } \
       && "$c" -c "import yaml" >/dev/null 2>&1; then
      echo "$c"; return 0
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

compose_services() {
  "$PY" -c "import yaml; print(' '.join(yaml.safe_load(open('$ROOT/docker-compose.yml'))['services']))"
}
compose_image() {
  "$PY" -c "import yaml; print(yaml.safe_load(open('$ROOT/docker-compose.yml'))['services']['$1']['image'])" \
    | sed -E 's/^\$\{[A-Z_]+:-(.*)\}$/\1/'
}

# --- önceki sürüm ------------------------------------------------------
# Yalnızca adı tam release_X.Y.Z olan ve version.env taşıyan dizinler.
previous_release() {
  find "$KH/releases" -mindepth 1 -maxdepth 1 -type d -name 'release_[0-9]*' 2>/dev/null \
    | grep -E '/release_[0-9]+\.[0-9]+\.[0-9]+$' \
    | grep -v "/release_$VERSION\$" \
    | while read -r d; do [ -f "$d/version.env" ] && echo "$d"; done \
    | sort -V | tail -1
}
PREV="$(previous_release || true)"
PREV_VERSION=""
[ -n "$PREV" ] && PREV_VERSION="$(grep '^RELEASE_VERSION=' "$PREV/version.env" | cut -d= -f2)"

# --- kaynak parmak izi ------------------------------------------------
# "Değişti mi" sorusu imaj kimliğine sorulamaz: buildx her derlemeye zaman
# damgalı kanıt ekliyor, kimlik her seferinde farklı çıkıyor. İçeriğe
# bakılır: derlenen servis için kaynak dizinin git ağaç özeti, hazır imaj
# için upstream digest.
fingerprint_build() {
  local dir="$1" ref="${2:-}"
  if [ -n "$ref" ]; then
    git rev-parse "$ref:$dir"
  else
    ( cd "$ROOT/$dir" && find . -type f ! -path '*/__pycache__/*' ! -name '*.pyc' \
        -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d' ' -f1 )
  fi
}
fingerprint_image() {
  # Digest için imajın çekilmiş olması gerekir; çekilmemişse etiketle idare.
  docker image inspect --format '{{index .RepoDigests 0}}' "$1" 2>/dev/null || printf '%s' "$1"
}

# =======================================================================
#  --init : iskelet
# =======================================================================
if [ "$MODE" = "init" ]; then
  [ -d "$OUT" ] && die "$OUT zaten var. Yeniden başlamak için önce silin."
  echo "▶ $VERSION iskeleti"
  mkdir -p "$OUT/containers" "$OUT/images"

  # Servis tanımları compose'dan türer; elle yazılmaz.
  "$PY" "$TPL/split_compose.py" "$ROOT/docker-compose.yml" "$OUT/containers" | sed 's/^/  /'

  # variables.env: değişmeyen servisler "skip" ile önceden doldurulur.
  {
    sed -n '1,/^TARGET=/p' "$TPL/variables.env.example" | sed '$d'
    echo "TARGET=production"
    echo
    sed -n '/^# Servis kaynakları/,/^# --init/p' "$TPL/variables.env.example"
    for svc in $(compose_services); do
      var="$(echo "$svc" | tr '[:lower:]' '[:upper:]')_SOURCE"
      if [ "$svc" = "backend" ]; then
        default="build:backend"
        cur="$(fingerprint_build backend)"
      else
        default="image:$(compose_image "$svc")"
        cur="$(fingerprint_image "$(compose_image "$svc")")"
      fi
      # Önceki sürümle aynıysa skip öner.
      prev_fp=""
      [ -n "$PREV" ] && prev_fp="$(grep "^#SRC_${var%_SOURCE}_IMAGE=" "$PREV/version.env" 2>/dev/null | cut -d= -f2- || true)"
      if [ -n "$prev_fp" ] && [ "$prev_fp" = "$cur" ]; then
        echo "$var=skip"
      else
        echo "$var=$default"
      fi
    done
    echo
    sed -n '/^# Oyuncu veritabanı/,$p' "$TPL/variables.env.example"
  } > "$VARS"

  echo
  echo "✓ İskelet hazır: know-how/releases/release_$VERSION"
  echo
  echo "  Şimdi doldur:"
  echo "    $VARS"
  grep -E '^[A-Z_]+=' "$VARS" | sed 's/^/      /'
  echo
  [ -n "$PREV" ] && echo "  (skip önerileri $PREV_VERSION ile karşılaştırılarak yapıldı)"
  echo "  Sonra:  ./know-how/build.sh $VERSION --dry-run"
  exit 0
fi

# =======================================================================
#  --dry-run ve build : ortak çözümleme
# =======================================================================
[ -d "$OUT" ]  || die "İskelet yok. Önce:  ./know-how/build.sh $VERSION --init"
[ -f "$VARS" ] || die "$VARS yok. Önce --init."

# variables.env'i güvenli oku (source etmek yerine; içine komut yazılamasın).
readvar() { grep -E "^$1=" "$VARS" | tail -1 | cut -d= -f2- | tr -d '\r'; }
TARGET="$(readvar TARGET)"
WITH_DATA="$(readvar WITH_DATA)"; WITH_DATA="${WITH_DATA:-0}"
[ -n "$TARGET" ] || die "variables.env'de TARGET boş"

# Hedef kataloğu
tgt() { grep -E "^${TARGET}_$1=" "$TPL/targets.env" | cut -d= -f2-; }
PLATFORM="$(tgt PLATFORM)"
DEPLOY_DIR="$(tgt DEPLOY_DIR)"
[ -n "$PLATFORM" ] || die "Bilinmeyen hedef: '$TARGET'. Tanımlılar: $(grep -oE '^[a-z]+_PLATFORM' "$TPL/targets.env" | sed 's/_PLATFORM//' | tr '\n' ' ')"

GIT_SHA="$(git rev-parse HEAD)"
echo "▶ Sürüm $VERSION  →  hedef: $TARGET ($PLATFORM, $DEPLOY_DIR)"
[ -n "$PREV" ] && echo "▶ Önceki sürüm: $PREV_VERSION" || echo "▶ Önceki sürüm yok (ilk paket)"

# Her servisi çöz: ne yapılacak, nereden, parmak izi ne.
declare -a PLAN_SVC PLAN_ACTION PLAN_SRC PLAN_FP PLAN_IMG
DIRTY_DIRS=""
for svc in $(compose_services); do
  var="$(echo "$svc" | tr '[:lower:]' '[:upper:]')_SOURCE"
  src="$(readvar "$var")"
  [ -n "$src" ] || die "variables.env'de $var yok"
  img_var="${var%_SOURCE}_IMAGE"
  case "$svc" in
    backend) img="footttball-backend:$VERSION" ;;
    *)       img="ttt-$svc:$VERSION" ;;
  esac

  case "$src" in
    skip)
      # Önceki etiketi devral; yoksa skip edilemez.
      prev_img="$(grep "^$img_var=" "${PREV:-/dev/null}/version.env" 2>/dev/null | cut -d= -f2- || true)"
      [ -n "$prev_img" ] || die "$svc için skip denmiş ama önceki sürümde etiketi yok — ilk pakette skip olamaz"
      PLAN_ACTION+=("skip"); PLAN_SRC+=("$prev_img"); PLAN_FP+=("")
      PLAN_IMG+=("$prev_img") ;;
    build:*)
      spec="${src#build:}"; dir="${spec%%@*}"; ref=""
      case "$spec" in *@*) ref="${spec#*@}" ;; esac
      [ -d "$ROOT/$dir" ] || die "$svc: '$dir' dizini yok"
      if [ -n "$ref" ]; then
        git rev-parse --verify --quiet "$ref^{commit}" >/dev/null || die "$svc: '$ref' diye bir commit yok"
        ref="$(git rev-parse "$ref")"
      else
        # Çalışma ağacından derleniyorsa o dizin temiz olmalı; yoksa paketin
        # hangi koddan çıktığı belirsiz. Çare mesajda.
        if [ -n "$(git status --porcelain -- "$dir")" ] && [ "$ALLOW_DIRTY" = "0" ]; then
          DIRTY_DIRS="$DIRTY_DIRS $dir"
        fi
      fi
      PLAN_ACTION+=("build"); PLAN_SRC+=("$dir${ref:+@${ref:0:12}}")
      PLAN_FP+=("$(fingerprint_build "$dir" "$ref")"); PLAN_IMG+=("$img") ;;
    image:*)
      up="${src#image:}"
      PLAN_ACTION+=("image"); PLAN_SRC+=("$up"); PLAN_FP+=("")   # digest çekince belli olur
      PLAN_IMG+=("$img") ;;
    *) die "$svc: anlaşılmayan kaynak '$src' (build:…, image:…, skip)" ;;
  esac
  PLAN_SVC+=("$svc")
done

echo
printf '  %-9s %-6s %-44s %s\n' SERVİS İŞLEM KAYNAK ETİKET
for i in "${!PLAN_SVC[@]}"; do
  printf '  %-9s %-6s %-44s %s\n' "${PLAN_SVC[$i]}" "${PLAN_ACTION[$i]}" "${PLAN_SRC[$i]}" "${PLAN_IMG[$i]}"
done
echo

if [ -n "$DIRTY_DIRS" ]; then
  echo "✗ Çalışma ağacında commitlenmemiş değişiklik var:$DIRTY_DIRS" >&2
  echo "  Paketin hangi koddan çıktığı belirsiz kalır. Çare, ikisinden biri:" >&2
  echo "    git add -A && git commit           (sonra tekrar çalıştır)" >&2
  for d in $DIRTY_DIRS; do
    echo "    variables.env:  $(echo "$d" | tr '[:lower:]' '[:upper:]')_SOURCE=build:$d@$(git rev-parse --short HEAD)   (o commit'i sabitle)" >&2
  done
  echo "  Ya da --allow-dirty (önerilmez)." >&2
  exit 1
fi

INCLUDED=""; for i in "${!PLAN_SVC[@]}"; do [ "${PLAN_ACTION[$i]}" != skip ] && INCLUDED="$INCLUDED ${PLAN_SVC[$i]}"; done
INCLUDED="$(echo $INCLUDED)"
[ -n "$INCLUDED" ] || die "Tüm servisler skip — paketlenecek bir şey yok. En az bir servis build: ya da image: olmalı."

if [ "$MODE" = "dry-run" ]; then
  command -v docker >/dev/null && docker info >/dev/null 2>&1 \
    && echo "✓ docker hazır" || echo "⚠ docker çalışmıyor — build başarısız olur"
  HOST="$(docker info --format '{{.OSType}}/{{.Architecture}}' 2>/dev/null || echo ?)"
  case "$HOST" in *aarch64*|*arm64*) HOST=linux/arm64 ;; *x86_64*|*amd64*) HOST=linux/amd64 ;; esac
  [ "$HOST" != "$PLATFORM" ] && echo "  (bu makine $HOST, hedef $PLATFORM — çapraz derleme)"
  [ "$WITH_DATA" = "1" ] && echo "  veritabanı pakete girecek ($(du -h "$ROOT/backend/data/tikitakapi.db" 2>/dev/null | cut -f1))"
  echo "✓ Plan geçerli. Üretmek için:  ./know-how/build.sh $VERSION"
  exit 0
fi

# =======================================================================
#  build
# =======================================================================
command -v docker >/dev/null || die "docker bulunamadı"
docker info >/dev/null 2>&1 || die "docker çalışmıyor"
[ -f "$OUT/version.env" ] && die "$VERSION daha önce üretilmiş. Yeniden üretmek için release_$VERSION içindeki version.env, images/*, *.tar.gz dosyalarını silin."

# Yarım kalan worktree'ler temizlensin.
cleanup() { git worktree prune >/dev/null 2>&1 || true; }
trap cleanup EXIT

# macOS'un bash'i 3.2: ilişkisel dizi yok, PLAN_* ile paralel indeksli dizi.
declare -a PLAN_DIGEST
for i in "${!PLAN_SVC[@]}"; do PLAN_DIGEST[$i]=""; done
for i in "${!PLAN_SVC[@]}"; do
  svc="${PLAN_SVC[$i]}"; act="${PLAN_ACTION[$i]}"; img="${PLAN_IMG[$i]}"
  case "$act" in
    skip) continue ;;
    build)
      spec="${PLAN_SRC[$i]}"; dir="${spec%%@*}"; ref=""
      case "$spec" in *@*) ref="$(git rev-parse "${spec#*@}")" ;; esac
      if [ -n "$ref" ]; then
        wt="${TMPDIR:-/tmp}/ttt-build-${ref:0:12}"
        rm -rf "$wt"; git worktree add --detach --quiet "$wt" "$ref"
        echo "▶ $svc: commit ${ref:0:12} derleniyor"
        docker build --quiet --platform "$PLATFORM" -t "$img" "$wt/$dir" >/dev/null
        git worktree remove --force "$wt" >/dev/null 2>&1 || true
      else
        echo "▶ $svc: çalışma ağacından derleniyor"
        docker build --quiet --platform "$PLATFORM" -t "$img" "$ROOT/$dir" >/dev/null
      fi
      PLAN_DIGEST[$i]="derleme ${ref:-$GIT_SHA}" ;;
    image)
      up="${PLAN_SRC[$i]}"
      echo "▶ $svc: $up"
      # Yereldeki kopya başka mimaridense pull işlem yapmaz; önce silinir.
      la="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$up" 2>/dev/null || true)"
      [ -n "$la" ] && [ "$la" != "$PLATFORM" ] && docker rmi -f "$up" >/dev/null 2>&1
      docker pull --quiet --platform "$PLATFORM" "$up" >/dev/null 2>&1 || die "$up çekilemedi"
      PLAN_DIGEST[$i]="$(fingerprint_image "$up")"
      PLAN_FP[$i]="${PLAN_DIGEST[$i]}"
      # docker tag yetmez: containerd deposu bir etiketin birden çok
      # platformunu saklar, tag hangisini aldığını söylemez. buildx'ten
      # tek platformlu imaj istenir.
      printf 'FROM %s\n' "$up" | docker buildx build --platform "$PLATFORM" -t "$img" --load - >/dev/null 2>&1 ;;
  esac
  arch="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$img")"
  [ "$arch" = "$PLATFORM" ] || die "$svc imajı $arch, hedef $PLATFORM"
done

# --- skip edilenlerin tanımı pakete girmez ---------------------------
for i in "${!PLAN_SVC[@]}"; do
  [ "${PLAN_ACTION[$i]}" = skip ] && rm -f "$OUT/containers/${PLAN_SVC[$i]}.yml"
done

# --- imajları tar'la + SHA256SUMS ------------------------------------
echo "▶ İmajlar tar'lanıyor"
: > "$OUT/images/SHA256SUMS"
for i in "${!PLAN_SVC[@]}"; do
  [ "${PLAN_ACTION[$i]}" = skip ] && continue
  svc="${PLAN_SVC[$i]}"; img="${PLAN_IMG[$i]}"
  printf '  %-9s ' "$svc"
  docker save --platform "$PLATFORM" "$img" | gzip -6 > "$OUT/images/$svc.tar.gz"
  # Tar'ın içindeki etiket version.env ile birebir aynı olmalı; uyuşmazsa
  # ancak sahada compose up sırasında fark edilir.
  tag_in_tar="$(gunzip -c "$OUT/images/$svc.tar.gz" | tar -xOf - manifest.json 2>/dev/null \
    | "$PY" -c "import json,sys; print(json.load(sys.stdin)[0]['RepoTags'][0])" 2>/dev/null || echo ?)"
  [ "$tag_in_tar" = "$img" ] || die "$svc tar'ındaki etiket '$tag_in_tar', beklenen '$img'"
  ( cd "$OUT/images" && shasum -a 256 "$svc.tar.gz" >> SHA256SUMS )
  du -h "$OUT/images/$svc.tar.gz" | cut -f1
done

# --- veritabanı -------------------------------------------------------
if [ "$WITH_DATA" = "1" ]; then
  echo "▶ Oyuncu veritabanı"
  mkdir -p "$OUT/data"
  "$PY" - "$ROOT/backend/data/tikitakapi.db" "$OUT/data/tikitakapi.db" <<'DBPY'
import sqlite3, sys
src = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True, timeout=60)
dst = sqlite3.connect(sys.argv[2])
with dst: src.backup(dst)
src.close(); dst.close()
DBPY
  gzip -6 "$OUT/data/tikitakapi.db"
  echo "  $(du -h "$OUT/data/tikitakapi.db.gz" | cut -f1)"
fi

# --- version.env ------------------------------------------------------
echo "▶ version.env"
{
  echo "# $VERSION imaj kilidi. update.sh bunu hedefteki .env'e yazar."
  echo "# Üretim: $(date -u +%Y-%m-%dT%H:%M:%SZ)  commit ${GIT_SHA:0:12}  hedef: $TARGET"
  echo
  echo "RELEASE_VERSION=$VERSION"
  echo "RELEASE_PLATFORM=$PLATFORM"
  echo "RELEASE_TARGET=$TARGET"
  for i in "${!PLAN_SVC[@]}"; do
    echo "$(echo "${PLAN_SVC[$i]}" | tr '[:lower:]' '[:upper:]')_IMAGE=${PLAN_IMG[$i]}"
  done
  echo "INCLUDED_SERVICES=$INCLUDED"
  echo
  echo "# Sonraki sürümün delta karşılaştırması için kaynak parmak izleri."
  for i in "${!PLAN_SVC[@]}"; do
    svc="${PLAN_SVC[$i]}"; var="$(echo "$svc" | tr '[:lower:]' '[:upper:]')_IMAGE"
    if [ "${PLAN_ACTION[$i]}" = skip ]; then
      # Skip edilenin parmak izi öncekinden taşınır; yoksa zincir kopar.
      grep "^#SRC_$var=" "$PREV/version.env" 2>/dev/null || true
    else
      echo "#SRC_$var=${PLAN_FP[$i]}"
    fi
  done
} > "$OUT/version.env"

# --- update.sh, revert, not, manifest --------------------------------
cp "$TPL/update.sh" "$OUT/update.sh"; chmod +x "$OUT/update.sh"
if [ -n "$PREV" ]; then
  echo "▶ revert_$PREV_VERSION.sh"
  sed -e "s|@@PREV_VERSION@@|$PREV_VERSION|g" -e "s|@@THIS_VERSION@@|$VERSION|g" \
      "$TPL/revert.sh" > "$OUT/revert_$PREV_VERSION.sh"
  chmod +x "$OUT/revert_$PREV_VERSION.sh"
  cp "$PREV/version.env" "$OUT/version_$PREV_VERSION.env"
fi

SKIPPED=""; for i in "${!PLAN_SVC[@]}"; do [ "${PLAN_ACTION[$i]}" = skip ] && SKIPPED="$SKIPPED ${PLAN_SVC[$i]}"; done
mkdir -p "$KH/dokumanlar/guncelleme-notlari/md"
"$PY" "$TPL/render_note.py" --version "$VERSION" --included "$INCLUDED" \
  --skipped "$(echo $SKIPPED)" --previous "$PREV_VERSION" --with-data "$WITH_DATA" \
  --output "$KH/dokumanlar/guncelleme-notlari/md/$VERSION.md"
echo "▶ Güncelleme notu: dokumanlar/guncelleme-notlari/md/$VERSION.md"

{
  echo "version: $VERSION"; echo "target: $TARGET ($PLATFORM)"; echo "git: $GIT_SHA"
  echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "included: $INCLUDED"; echo "skipped:$SKIPPED"
  echo; echo "sources:"
  for i in "${!PLAN_SVC[@]}"; do
    svc="${PLAN_SVC[$i]}"
    printf '  %-9s %-6s %s\n' "$svc" "${PLAN_ACTION[$i]}" "${PLAN_DIGEST[$i]:-${PLAN_SRC[$i]}}"
  done
} > "$OUT/MANIFEST.txt"

# --- checksum, tar.gz + .sha256 (release klasörünün İÇİNDE) ------------
echo "▶ Paketleniyor"
( cd "$OUT" && find . -type f ! -name checksums.sha256 ! -name '*.tar.gz' ! -name '*.tar.gz.sha256' \
    -print0 | sort -z | xargs -0 shasum -a 256 > checksums.sha256 )
TARBALL="release_$VERSION.tar.gz"
# Önce geçici ada yazılır, sonra taşınır: tar kendi çıktısını okumasın.
( cd "$KH/releases" && tar czf ".$TARBALL.tmp" \
    --exclude="release_$VERSION/$TARBALL" --exclude="release_$VERSION/$TARBALL.sha256" \
    "release_$VERSION/" && mv ".$TARBALL.tmp" "release_$VERSION/$TARBALL" )
( cd "$OUT" && shasum -a 256 "$TARBALL" > "$TARBALL.sha256" )

echo
echo "✓ Paket hazır"
echo "  $OUT/$TARBALL  ($(du -h "$OUT/$TARBALL" | cut -f1))"
echo "  $OUT/$TARBALL.sha256"
echo
echo "  USB'ye:   cp release_$VERSION/$TARBALL release_$VERSION/$TARBALL.sha256 /Volumes/<USB>/"
echo "  Sahada:   sha256sum -c $TARBALL.sha256 && tar xzf $TARBALL && cd release_$VERSION && sudo ./update.sh $DEPLOY_DIR"
