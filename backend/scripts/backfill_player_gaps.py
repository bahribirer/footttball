"""Ana tablodaki boş uyrukları tarihsel kadro katmanından tamamlar.

`players` tablosunda 13 binden fazla oyuncunun `country_of_citizenship`
alanı boştu. Uyruk olmadan Tiki Taka Toe'nun millet × kulüp kesişimi asla
tutmuyor, oyuncu arama sonuçlarında bayrak çıkmıyor ve uyruk temelli
kategoriler bu isimleri hiç görmüyordu.

`scripts/sync_club_history.py` çalıştıktan sonra çağrılır. Yalnızca BOŞ
alanlar doldurulur; mevcut değerler değiştirilmez.

Kullanım:
    python scripts/sync_club_history.py          # önce katmanı doldur
    python scripts/backfill_player_gaps.py       # sonra boşlukları kapat
    python scripts/backfill_player_gaps.py --dry-run
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from scripts.sync_current_squads import DB_PATH  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    conn = sqlite3.connect(DB_PATH)

    tables = {row[0] for row in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    if "club_history" not in tables:
        print("club_history tablosu yok — önce sync_club_history.py çalıştırın.")
        return 1

    empty_before = conn.execute(
        "SELECT COUNT(*) FROM players "
        "WHERE country_of_citizenship IS NULL OR country_of_citizenship = ''"
    ).fetchone()[0]

    # Bir oyuncunun birden çok kulüp kaydı olabilir; hepsi aynı uyruğu verir,
    # yine de tek bir değere indirgenir.
    rows = conn.execute(
        """SELECT name_normalized, country FROM (
               SELECT name_normalized, country,
                      ROW_NUMBER() OVER (
                          PARTITION BY name_normalized ORDER BY country
                      ) AS rn
               FROM club_history
               WHERE country IS NOT NULL AND country <> ''
           ) WHERE rn = 1"""
    ).fetchall()

    print(f"tarihsel katmanda uyruk bilgisi olan: {len(rows)} oyuncu")
    print(f"ana tabloda uyruğu boş satır       : {empty_before}")

    if args.dry_run:
        would = conn.execute(
            """SELECT COUNT(*) FROM players p
               WHERE (p.country_of_citizenship IS NULL OR p.country_of_citizenship = '')
                 AND EXISTS (SELECT 1 FROM club_history h
                             WHERE h.name_normalized = p.name_normalized
                               AND h.country IS NOT NULL AND h.country <> '')"""
        ).fetchone()[0]
        print(f"doldurulacak satır                 : {would}  (dry-run)")
        return 0

    conn.executemany(
        """UPDATE players
              SET country_of_citizenship = ?
            WHERE name_normalized = ?
              AND (country_of_citizenship IS NULL OR country_of_citizenship = '')""",
        [(country, key) for key, country in rows],
    )
    conn.commit()

    empty_after = conn.execute(
        "SELECT COUNT(*) FROM players "
        "WHERE country_of_citizenship IS NULL OR country_of_citizenship = ''"
    ).fetchone()[0]

    print(f"kalan boş satır                    : {empty_after} "
          f"({empty_before - empty_after} satır dolduruldu)")
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
