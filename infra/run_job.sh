#!/usr/bin/env bash
# Zamanlanmış işleri sarmalar: loglar, süre tutar ve başarısızlığı duyurur.
#
# Cron işleri sessizce koşuyordu; başarısız olduklarında kimse fark etmiyor,
# kimse log dosyasına bakmıyordu. Bu sarmalayıcı sonucu tek satırlık bir
# durum dosyasına yazar ve /ping gibi dışarıdan okunabilir hale getirir.
#
# Kullanım:
#   ./infra/run_job.sh <ad> <komut...>
#
# Bildirim (isteğe bağlı): JOB_WEBHOOK ayarlıysa başarısızlıkta oraya POST
# atılır. Ayarlı değilse yalnızca log ve durum dosyası yazılır.

set -uo pipefail

if [ "$#" -lt 2 ]; then
  echo "kullanim: run_job.sh <ad> <komut...>" >&2
  exit 2
fi

JOB="$1"; shift
LOG_DIR="${JOB_LOG_DIR:-$HOME/tikitakatoe-jobs}"
STATUS_DIR="${JOB_STATUS_DIR:-$(pwd)/backend/data/jobs}"
mkdir -p "$LOG_DIR" "$STATUS_DIR"

LOG="$LOG_DIR/$JOB.log"
STATUS="$STATUS_DIR/$JOB.json"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
START_EPOCH="$(date +%s)"

# Not: `{ ...; exit $RC; } >> log` kalibi tum betigi sonlandirir ve durum
# dosyasi hic yazilmaz. Komut dogrudan calistirilip cikis kodu okunuyor.
echo "=== $JOB basladi: $STARTED_AT" >> "$LOG"
"$@" >> "$LOG" 2>&1
RC=$?
echo "=== $JOB bitti rc=$RC" >> "$LOG"

DURATION=$(( $(date +%s) - START_EPOCH ))

cat > "$STATUS" <<JSON
{
  "job": "$JOB",
  "started_at": "$STARTED_AT",
  "finished_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "duration_seconds": $DURATION,
  "exit_code": $RC,
  "ok": $([ "$RC" -eq 0 ] && echo true || echo false)
}
JSON

# Log dosyası sınırsız büyümesin.
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 5242880 ]; then
  tail -c 1048576 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

if [ "$RC" -ne 0 ]; then
  echo "✗ $JOB basarisiz (rc=$RC), son satirlar:" >&2
  tail -20 "$LOG" >&2
  if [ -n "${JOB_WEBHOOK:-}" ]; then
    curl -fsS -m 10 -X POST "$JOB_WEBHOOK" \
      -H 'Content-Type: application/json' \
      -d "{\"text\":\"tikitakatoe: $JOB isi basarisiz (rc=$RC)\"}" >/dev/null || true
  fi
fi

exit "$RC"
