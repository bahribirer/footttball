"""Kalan boş uyrukları Wikidata'dan oyuncu adıyla doldurur.

`sync_club_history.py` uyrukların büyük kısmını kulüp kadrolarından getirir,
ama kulübü eşleşmeyen ya da Wikidata'da kulüp kaydı olmayan futbolcular
boşta kalıyor. Bu betik onları doğrudan adlarıyla arar.

Ad benzerliği yanlış kişiyi getirebileceği için iki koruma var:
  * Varlık insan (P31 = Q5) ve futbolcu (P106) olmalı.
  * Normalize edilmiş ad birebir eşleşmeli.

Kullanım:
    python scripts/fill_missing_nationalities.py
    python scripts/fill_missing_nationalities.py --limit 200 --dry-run
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from scripts.sync_club_history import COUNTRY_ALIASES  # noqa: E402
from scripts.sync_current_squads import DB_PATH, normalize  # noqa: E402

SPARQL = "https://query.wikidata.org/sparql"
UA = "tikitakatoe-nationality/1.0 (https://tikitakatoe.com)"
BATCH = 60


def _escape(name: str) -> str:
    return name.replace("\\", "\\\\").replace('"', '\\"')


def lookup(names: list[str]) -> dict[str, str]:
    """Verilen adlar için {normalize edilmiş ad: ülke} döndürür."""
    values = " ".join(f'"{_escape(n)}"@en' for n in names)
    query = f"""
    SELECT ?label ?natLabel WHERE {{
      VALUES ?label {{ {values} }}
      ?player rdfs:label ?label ;
              wdt:P31 wd:Q5 ;
              wdt:P106 ?occupation ;
              wdt:P27 ?nat .
      VALUES ?occupation {{ wd:Q937857 wd:Q628099 }}
      SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
    }}"""
    url = f"{SPARQL}?format=json&query={urllib.parse.quote(query)}"
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = json.loads(response.read().decode("utf-8"))

    found: dict[str, str] = {}
    for row in data["results"]["bindings"]:
        key = normalize(row["label"]["value"])
        raw = row["natLabel"]["value"]
        # Aynı ada birden çok kişi düşerse ilk sonuç korunur.
        found.setdefault(key, COUNTRY_ALIASES.get(raw, raw))
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute(
        """SELECT DISTINCT name FROM players
           WHERE (country_of_citizenship IS NULL OR country_of_citizenship = '')
             AND name IS NOT NULL AND name <> ''
           ORDER BY CAST(COALESCE(highest_market_value_in_eur, 0) AS INTEGER) DESC"""
    ).fetchall()

    names = [row[0] for row in rows]
    if args.limit:
        names = names[: args.limit]

    print(f"uyruğu boş {len(names)} oyuncu aranacak\n")

    filled = 0
    for start in range(0, len(names), BATCH):
        chunk = names[start : start + BATCH]
        try:
            found = lookup(chunk)
        except Exception as exc:
            print(f"  [{start}/{len(names)}] sorgu hatası: {exc}")
            time.sleep(3)
            continue

        if found and not args.dry_run:
            conn.executemany(
                """UPDATE players SET country_of_citizenship = ?
                   WHERE name_normalized = ?
                     AND (country_of_citizenship IS NULL
                          OR country_of_citizenship = '')""",
                [(country, key) for key, country in found.items()],
            )
            conn.commit()

        filled += len(found)
        print(f"  [{start + len(chunk)}/{len(names)}] {len(found)} uyruk bulundu")
        time.sleep(0.5)

    remaining = conn.execute(
        "SELECT COUNT(DISTINCT name) FROM players "
        "WHERE country_of_citizenship IS NULL OR country_of_citizenship = ''"
    ).fetchone()[0]
    print(f"\n{filled} oyuncu eşleşti, kalan boş: {remaining}"
          + (" (dry-run)" if args.dry_run else ""))
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
