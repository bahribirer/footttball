"""Ad biçimi tutmayan oyuncuların uyruğunu Wikipedia araması üzerinden bulur.

`fill_missing_nationalities.py` birebir etiket eşleşmesi arıyor; Wikidata'da
farklı yazılan adlar ("Ui-jo Hwang" → "Hwang Ui-jo", "Tete Morente" →
"Tetè Morente") böyle bulunamıyor. Bu betik önce Wikipedia'da arayıp varlığı
bulur, sonra uyruğunu okur.

Sorgu başına birkaç istek gerektiği için yalnızca oyunda karşılaşılabilecek
oyuncular hedeflenir: güncel sezonlarda ve büyük liglerde olanlar.

Kullanım:
    python scripts/fill_nationalities_by_search.py --since 2024
    python scripts/fill_nationalities_by_search.py --since 2024 --dry-run
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

from scripts.sync_club_history import COUNTRY_ALIASES, SPARQL, UA, _get  # noqa: E402
from scripts.sync_current_squads import DB_PATH, normalize  # noqa: E402

WIKI_API = "https://en.wikipedia.org/w/api.php"
BIG_LEAGUES = ("TR1", "GB1", "IT1", "ES1", "L1", "FR1", "NL1", "PO1")


def find_qid(name: str) -> str | None:
    data = _get(
        f"{WIKI_API}?action=query&list=search&format=json&formatversion=2&srlimit=1"
        f"&srsearch={urllib.parse.quote(name + ' footballer')}"
    )
    hits = data.get("query", {}).get("search", [])
    if not hits:
        return None
    data = _get(
        f"{WIKI_API}?action=query&prop=pageprops&format=json&formatversion=2"
        f"&redirects=1&titles={urllib.parse.quote(hits[0]['title'])}"
    )
    pages = data.get("query", {}).get("pages", [])
    if not pages or pages[0].get("missing"):
        return None
    return pages[0].get("pageprops", {}).get("wikibase_item")


def nationality(qid: str) -> str | None:
    query = f"""
    SELECT ?natLabel WHERE {{
      wd:{qid} wdt:P31 wd:Q5 ; wdt:P27 ?nat .
      SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
    }} LIMIT 1"""
    data = _get(f"{SPARQL}?format=json&query={urllib.parse.quote(query)}")
    rows = data["results"]["bindings"]
    if not rows:
        return None
    raw = rows[0]["natLabel"]["value"]
    return COUNTRY_ALIASES.get(raw, raw)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--since", type=int, default=2024,
                        help="bu sezondan itibaren oynayanlar")
    parser.add_argument("--all-leagues", action="store_true",
                        help="yalnızca büyük liglerle sınırlama")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    conn = sqlite3.connect(DB_PATH)
    league_filter = "" if args.all_leagues else (
        f" AND current_club_domestic_competition_id IN "
        f"({','.join('?' * len(BIG_LEAGUES))})"
    )
    params: tuple = (args.since,) if args.all_leagues else (args.since, *BIG_LEAGUES)

    names = [row[0] for row in conn.execute(
        f"""SELECT DISTINCT name FROM players
            WHERE (country_of_citizenship IS NULL OR country_of_citizenship = '')
              AND last_season >= ?{league_filter}
            ORDER BY name""", params)]

    print(f"{len(names)} oyuncu aranacak\n")
    filled = 0

    for index, name in enumerate(names, 1):
        try:
            qid = find_qid(name)
            country = nationality(qid) if qid else None
        except Exception as exc:
            print(f"  [{index}/{len(names)}] {name}: hata ({exc})")
            continue

        if not country:
            print(f"  [{index}/{len(names)}] {name}: bulunamadı")
            continue

        if not args.dry_run:
            conn.execute(
                """UPDATE players SET country_of_citizenship = ?
                   WHERE name_normalized = ?
                     AND (country_of_citizenship IS NULL
                          OR country_of_citizenship = '')""",
                (country, normalize(name)),
            )
            conn.commit()

        filled += 1
        print(f"  [{index}/{len(names)}] {name}: {country}")
        time.sleep(0.4)

    print(f"\n{filled}/{len(names)} dolduruldu" + (" (dry-run)" if args.dry_run else ""))
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
