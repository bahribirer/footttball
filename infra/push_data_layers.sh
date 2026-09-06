#!/usr/bin/env bash
# Veri katmanlarını (club_history, squad_updates) sunucuya taşır.
#
# Bu tablolar Wikipedia/Wikidata'dan üretiliyor ve üretimi saatler sürüyor.
# Sunucuda yeniden üretmek yerine yerelde hazırlanıp buradan aktarılır;
# ana `players` tablosu dokunulmadan kalır, boş uyruklar sunucuda
# `backfill_player_gaps.py` ile doldurulur.
#
# Kullanım (proje kökünden):
#   ./infra/push_data_layers.sh

set -euo pipefail

HOST="${TTT_HOST:-ubuntu@63.187.180.209}"
KEY="${TTT_KEY:-$HOME/.ssh/tikitakatoe.pem}"
LOCAL_DB="backend/data/tikitakapi.db"
DUMP="/tmp/ttt_layers.sql"

[ -f "$LOCAL_DB" ] || { echo "✗ $LOCAL_DB yok" >&2; exit 1; }

echo "▶ Katmanlar dışa aktarılıyor"
rm -f "$DUMP" "$DUMP.gz"
python3 - "$LOCAL_DB" "$DUMP" <<'PY'
import sqlite3, sys
db, out = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
with open(out, "w", encoding="utf-8") as fh:
    for line in con.iterdump():
        # Yalnızca katman tabloları; ana `players` tablosu aktarılmaz.
        # Düz alt dize araması indeks tanımlarını da yakalar
        # ("CREATE INDEX idx_club_history_name ON club_history(...)").
        if "club_history" in line or "squad_updates" in line:
            fh.write(line + "\n")
print(f"  club_history : {con.execute('SELECT COUNT(*) FROM club_history').fetchone()[0]} kayıt")
print(f"  squad_updates: {con.execute('SELECT COUNT(*) FROM squad_updates').fetchone()[0]} kayıt")
PY
echo "  $(wc -l < "$DUMP" | tr -d ' ') satır"

echo "▶ Sunucuya kopyalanıyor"
gzip -f "$DUMP"
scp -q -i "$KEY" "$DUMP.gz" "$HOST:/tmp/ttt_layers.sql.gz"

echo "▶ Sunucuda uygulanıyor"
ssh -i "$KEY" "$HOST" bash -s <<'REMOTE'
set -euo pipefail
cd /srv/tikitakatoe
DB="backend/data/tikitakapi.db"

BACKUP="backend/data/tikitakapi.$(date +%Y%m%d-%H%M%S).pre-layers.db"
cp "$DB" "$BACKUP"
echo "  yedek: $BACKUP"

gunzip -f /tmp/ttt_layers.sql.gz
python3 - "$DB" /tmp/ttt_layers.sql <<'PY'
import sqlite3, sys
db, dump = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
con.executescript("DROP TABLE IF EXISTS club_history; DROP TABLE IF EXISTS squad_updates;")
with open(dump, encoding="utf-8") as fh:
    con.executescript(fh.read())
con.commit()
for table in ("club_history", "squad_updates"):
    print(f"  {table}: {con.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0]} kayıt")
PY
rm -f /tmp/ttt_layers.sql

echo "▶ Boş uyruklar dolduruluyor"
/usr/bin/python3 backend/scripts/backfill_player_gaps.py

echo "▶ Backend yeniden başlatılıyor (katman önbelleği tazelensin)"
docker compose restart backend >/dev/null
REMOTE

echo "✓ Veri katmanları sunucuda"
