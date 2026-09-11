#!/usr/bin/env bash
# build.sh'ın hatalı girdide SESSİZCE ölmediğini doğrular.
#
# set -e + pipefail altında grep eşleşme bulamayınca betik tek satır çıktı
# vermeden çıkıyor ve die satırlarına ulaşamıyor. Bu üç kez yaşandı
# (deploy.sh .env, tgt, readvar). Her hatalı girdi için beklenen şey: sıfır
# dışı çıkış VE anlaşılır bir mesaj. Docker gerektirmez; --dry-run'ın
# çözümleme aşamasında durur.

set -uo pipefail
cd "$(dirname "$0")/.."

V=0.0.1
OUT="know-how/releases/release_$V"
trap 'rm -rf "$OUT"' EXIT
rm -rf "$OUT"

# init docker istemez ama pyyaml ister; yoksa geçici venv kurar.
./know-how/build.sh $V --init >/dev/null 2>&1 || { echo "✗ init başarısız"; exit 1; }
VARS="$OUT/variables.env"
cp "$VARS" "$VARS.orig"

# Bu "önceki sürüm yok" senaryosu değil; skip'in çalışması için bir önceki
# sürüm olmalı. Yoksa init hepsini build yapar — sorun değil.

expect_fail() {
  local label="$1" needle="$2"
  local out rc
  out="$(./know-how/build.sh $V --dry-run 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "✗ $label: başarılı çıktı, hata bekleniyordu"; return 1
  fi
  if [ -z "$out" ]; then
    echo "✗ $label: sessizce öldü (rc=$rc), mesaj yok"; return 1
  fi
  if ! printf '%s' "$out" | grep -q -- "$needle"; then
    echo "✗ $label: mesaj beklenen metni içermiyor ('$needle'):"
    printf '%s\n' "$out" | tail -2 | sed 's/^/    /'; return 1
  fi
  echo "✓ $label"
}

FAIL=0
sed -i.bak 's|^TARGET=.*|TARGET=mars|' "$VARS"
expect_fail "bilinmeyen hedef" "Bilinmeyen hedef" || FAIL=1

cp "$VARS.orig" "$VARS"; sed -i.bak '/^TARGET=/d' "$VARS"
expect_fail "TARGET eksik" "TARGET boş" || FAIL=1

cp "$VARS.orig" "$VARS"; sed -i.bak '/^BACKEND_SOURCE=/d' "$VARS"
expect_fail "kaynak satırı eksik" "BACKEND_SOURCE yok" || FAIL=1

cp "$VARS.orig" "$VARS"; sed -i.bak 's|^BACKEND_SOURCE=.*|BACKEND_SOURCE=build:backend@deadbeef|' "$VARS"
expect_fail "olmayan commit" "commit yok" || FAIL=1

cp "$VARS.orig" "$VARS"; sed -i.bak 's|^BACKEND_SOURCE=.*|BACKEND_SOURCE=pull:x|' "$VARS"
expect_fail "anlaşılmayan kaynak" "anlaşılmayan kaynak" || FAIL=1

cp "$VARS.orig" "$VARS"; sed -i.bak 's|^BACKEND_SOURCE=.*|BACKEND_SOURCE=build:yok_boyle_dizin|' "$VARS"
expect_fail "olmayan dizin" "dizini yok" || FAIL=1

cp "$VARS.orig" "$VARS"
for v in BACKEND NGINX REDIS CERTBOT; do sed -i.bak "s|^${v}_SOURCE=.*|${v}_SOURCE=skip|" "$VARS"; done
expect_fail "hepsi skip" "paketlenecek bir şey yok" || FAIL=1

# Geçerli planın geçmesi de kontrol.
cp "$VARS.orig" "$VARS"; sed -i.bak 's|^BACKEND_SOURCE=.*|BACKEND_SOURCE=build:backend|' "$VARS"
if out="$(./know-how/build.sh $V --dry-run 2>&1)" && printf '%s' "$out" | grep -q "Plan geçerli"; then
  echo "✓ geçerli plan kabul ediliyor"
else
  echo "✗ geçerli plan reddedildi:"; printf '%s\n' "$out" | tail -3 | sed 's/^/    /'; FAIL=1
fi

[ "$FAIL" = 0 ] && echo "✓ build.sh hatalı girdide konuşarak ölüyor" || exit 1
