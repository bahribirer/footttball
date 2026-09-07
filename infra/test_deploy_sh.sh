#!/usr/bin/env bash
# deploy.sh'ın erken çıkmadığını doğrular.
#
# `set -euo pipefail` altında sıfırdan farklı dönen bir grep betiği tek satır
# çıktı vermeden öldürüyordu; .env yoksa her dağıtım sessizce düşüyordu.
# Bu kontrol betiği sahte bir dizinde ön koşullara kadar çalıştırır ve en az
# bir satır çıktı verdiğini görür.

set -uo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/backend/data" "$TMP/infra/certbot/conf/live"
cp infra/deploy.sh "$TMP/infra/"
touch "$TMP/docker-compose.yml" "$TMP/backend/data/tikitakapi.db"
# .env BİLEREK oluşturulmuyor: kırılan durum tam olarak buydu.

# macOS'ta `timeout` yok; git fetch aşamasında zaten hata verip duruyor.
OUT="$(cd "$TMP" && bash infra/deploy.sh main 2>&1 || true)"

if [ -z "$OUT" ]; then
  echo "✗ deploy.sh hiç çıktı vermeden çıktı (.env yokken erken ölüm)" >&2
  exit 1
fi
if ! printf '%s' "$OUT" | grep -q "Dal: main"; then
  echo "✗ deploy.sh ilk adıma ulaşamadı:" >&2
  printf '%s\n' "$OUT" | head -5 >&2
  exit 1
fi
echo "✓ deploy.sh .env olmadan da ön koşullara ulaşıyor"
