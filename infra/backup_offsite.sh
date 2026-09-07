#!/usr/bin/env bash
# Veritabanını sunucu dışına yedekler.
#
# Yedekler şu an veritabanıyla aynı EBS biriminde duruyor; birim ölürse
# ikisi de gider. Bu betik sıkıştırılmış bir kopyayı S3'e yollar.
#
# Kurulum (sunucuda, bir kez):
#   sudo apt-get install -y awscli
#   aws configure          # ya da EC2 instance role
#   export TTT_BACKUP_BUCKET=s3://benim-kovam/tikitakatoe
#
# Cron (haftalık, pazar 03:00):
#   0 3 * * 0 cd /srv/tikitakatoe && ./infra/run_job.sh backup ./infra/backup_offsite.sh

set -euo pipefail

DB_PATH="${DB_PATH:-backend/data/tikitakapi.db}"
BUCKET="${TTT_BACKUP_BUCKET:-}"
KEEP_REMOTE_DAYS="${KEEP_REMOTE_DAYS:-90}"

if [ -z "$BUCKET" ]; then
  echo "✗ TTT_BACKUP_BUCKET ayarlanmamış" >&2
  exit 1
fi
if [ ! -f "$DB_PATH" ]; then
  echo "✗ $DB_PATH yok" >&2
  exit 1
fi

STAMP="$(date -u +%Y%m%d-%H%M%S)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Canlı veritabanını kopyalarken yazma araya girebilir; SQLite'ın kendi
# yedekleme API'si tutarlı bir kopya üretir.
echo "▶ Tutarlı kopya alınıyor"
python3 - "$DB_PATH" "$TMP/tikitakapi.db" <<'PY'
import sqlite3, sys
src = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True, timeout=60)
dst = sqlite3.connect(sys.argv[2])
with dst:
    src.backup(dst)
src.close(); dst.close()
PY

echo "▶ Sıkıştırılıyor"
gzip -6 "$TMP/tikitakapi.db"
SIZE="$(du -h "$TMP/tikitakapi.db.gz" | cut -f1)"

echo "▶ Yükleniyor ($SIZE)"
aws s3 cp "$TMP/tikitakapi.db.gz" "$BUCKET/tikitakapi.$STAMP.db.gz" --only-show-errors

# Uzaktaki eski yedekleri temizle.
CUTOFF="$(date -u -d "$KEEP_REMOTE_DAYS days ago" +%Y-%m-%d 2>/dev/null || date -u -v-"${KEEP_REMOTE_DAYS}"d +%Y-%m-%d)"
aws s3 ls "$BUCKET/" | while read -r day _ _ name; do
  if [[ "$day" < "$CUTOFF" ]] && [[ "$name" == tikitakapi.*.db.gz ]]; then
    echo "  eski uzak yedek siliniyor: $name"
    aws s3 rm "$BUCKET/$name" --only-show-errors
  fi
done

echo "✓ $BUCKET/tikitakapi.$STAMP.db.gz"
