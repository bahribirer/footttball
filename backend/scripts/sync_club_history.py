"""Kulüplerin tarihsel kadrolarını Wikidata'dan çekip `club_history`'ye yazar.

Ana veritabanı Transfermarkt sezon anlık görüntülerinden üretilmiş ve iki
büyük boşluğu var:

  * Eski dönemler eksik. Fatih Tekke'nin Trabzonspor yılları hiç yok, bu
    yüzden "Trabzonspor × Türkiye" hücresine yazıldığında reddediliyordu.
  * 13 binden fazla oyuncunun uyruğu boş. Uyruk olmadan Tiki Taka Toe'daki
    millet × kulüp kesişimi hiçbir zaman tutmuyor.

Wikidata'nın "member of sports team" (P54) ifadeleri her iki boşluğu da
kapatıyor: kulüp başına tek sorgu, o kulüpte oynamış herkesi uyruğuyla
birlikte veriyor.

Kullanım:
    python scripts/sync_club_history.py                 # tüm kulüpler
    python scripts/sync_club_history.py --club Trabzonspor
    python scripts/sync_club_history.py --limit 40 --dry-run

Ana tabloya dokunulmaz; doğrulama katmanı bu tabloyu ek kaynak olarak okur.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from scripts.sync_current_squads import DB_PATH, club_key, normalize  # noqa: E402

WIKI_API = "https://en.wikipedia.org/w/api.php"
SPARQL = "https://query.wikidata.org/sparql"
UA = "tikitakatoe-club-history/1.0 (https://tikitakatoe.com)"

# Wikidata etiketleri veritabanının ülke sözlüğüne çevrilir.
COUNTRY_ALIASES = {
    "South Korea": "Korea, South",
    "North Korea": "Korea, North",
    "Ivory Coast": "Cote d'Ivoire",
    "Côte d'Ivoire": "Cote d'Ivoire",
    "Bosnia and Herzegovina": "Bosnia-Herzegovina",
    "Cape Verde": "Cape Verde",
    "Curaçao": "Curacao",
    "Republic of the Congo": "Congo",
    "Democratic Republic of the Congo": "Congo",
    "DR Congo": "Congo",
    "Republic of Ireland": "Ireland",
    "United States of America": "United States",
    "Netherlands": "Netherlands",
    "Czechia": "Czech Republic",
    "Turkey": "Turkey",
    "Türkiye": "Turkey",
    "Kingdom of the Netherlands": "Netherlands",
}

SCHEMA = """
CREATE TABLE IF NOT EXISTS club_history (
    name_normalized TEXT NOT NULL,
    player_name     TEXT NOT NULL,
    club_name       TEXT NOT NULL,
    country         TEXT,
    start_year      INTEGER,
    end_year        INTEGER,
    source          TEXT,
    updated_at      TEXT,
    PRIMARY KEY (name_normalized, club_name)
);
CREATE INDEX IF NOT EXISTS idx_club_history_name ON club_history(name_normalized);
CREATE INDEX IF NOT EXISTS idx_club_history_club ON club_history(club_name);
CREATE INDEX IF NOT EXISTS idx_club_history_country ON club_history(country);
"""


def _get(url: str, timeout: int = 90) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def wikidata_id(club: str) -> str | None:
    """Kulüp adından Wikidata varlık kimliği bulur.

    Önce adın kendisi sayfa başlığı olarak denenir; tutmazsa Wikipedia
    araması kullanılır ("Besiktas JK" → "Beşiktaş J.K.").
    """
    for title in (club, f"{club} (football club)"):
        data = _get(
            f"{WIKI_API}?action=query&prop=pageprops&format=json&formatversion=2"
            f"&redirects=1&titles={urllib.parse.quote(title)}"
        )
        pages = data.get("query", {}).get("pages", [])
        if pages and not pages[0].get("missing"):
            qid = pages[0].get("pageprops", {}).get("wikibase_item")
            if qid:
                return qid

    data = _get(
        f"{WIKI_API}?action=query&list=search&format=json&formatversion=2&srlimit=1"
        f"&srsearch={urllib.parse.quote(club + ' football club')}"
    )
    hits = data.get("query", {}).get("search", [])
    if not hits:
        return None

    data = _get(
        f"{WIKI_API}?action=query&prop=pageprops&format=json&formatversion=2"
        f"&titles={urllib.parse.quote(hits[0]['title'])}"
    )
    pages = data.get("query", {}).get("pages", [])
    if not pages or pages[0].get("missing"):
        return None
    return pages[0].get("pageprops", {}).get("wikibase_item")


def squad_members(qid: str) -> list[dict]:
    """Kulüpte oynamış herkesi uyruk ve yıllarıyla döndürür."""
    query = f"""
    SELECT ?playerLabel ?natLabel ?start ?end WHERE {{
      ?player p:P54 ?statement .
      ?statement ps:P54 wd:{qid} .
      OPTIONAL {{ ?statement pq:P580 ?start }}
      OPTIONAL {{ ?statement pq:P582 ?end }}
      OPTIONAL {{ ?player wdt:P27 ?nat }}
      SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
    }}"""
    data = _get(f"{SPARQL}?format=json&query={urllib.parse.quote(query)}")
    return data["results"]["bindings"]


def _year(value: str | None) -> int | None:
    if not value or len(value) < 4 or not value[:4].isdigit():
        return None
    return int(value[:4])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--club", action="append", help="yalnızca bu kulüp(ler)")
    parser.add_argument("--limit", type=int, help="en fazla bu kadar kulüp işle")
    parser.add_argument("--min-players", type=int, default=1,
                        help="ana tabloda en az bu kadar oyuncusu olan kulüpler")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    conn = sqlite3.connect(DB_PATH)
    conn.executescript(SCHEMA)

    if args.club:
        clubs = args.club
    else:
        clubs = [
            row[0] for row in conn.execute(
                """SELECT current_club_name FROM players
                   WHERE current_club_name IS NOT NULL AND current_club_name <> ''
                   GROUP BY current_club_name
                   HAVING COUNT(DISTINCT name) >= ?
                   ORDER BY COUNT(DISTINCT name) DESC""",
                (args.min_players,),
            )
        ]

    # Zaten işlenmiş kulüpler atlanır; betik yarıda kalırsa kaldığı yerden sürer.
    done = {row[0] for row in conn.execute("SELECT DISTINCT club_name FROM club_history")}
    pending = [club for club in clubs if club not in done]
    if args.limit:
        pending = pending[: args.limit]

    print(f"{len(clubs)} kulüp, {len(done)} tamam, {len(pending)} işlenecek\n")

    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    total_rows = skipped = 0

    for index, club in enumerate(pending, 1):
        try:
            qid = wikidata_id(club)
            if not qid:
                print(f"  [{index}/{len(pending)}] {club}: Wikidata kaydı yok")
                skipped += 1
                continue

            members = squad_members(qid)
        except Exception as exc:
            print(f"  [{index}/{len(pending)}] {club}: hata ({exc})")
            skipped += 1
            continue

        # Doğru kulübe baktığımızın kontrolü: ana tabloda bu kulüple anılan
        # oyuncularla kesişim olmalı. Yanlış eşleşen bir Wikidata kaydı
        # veritabanına alakasız isimler yazardı.
        known = {
            row[0] for row in conn.execute(
                "SELECT DISTINCT name_normalized FROM players WHERE current_club_name = ?",
                (club,),
            )
        }
        found = {normalize(m["playerLabel"]["value"]): m for m in members}
        overlap = len(known & set(found))

        if known and overlap == 0:
            print(f"  [{index}/{len(pending)}] {club}: eşleşme yok ({qid}), atlandı")
            skipped += 1
            continue

        rows = []
        for key, member in found.items():
            name = member["playerLabel"]["value"]
            if name.startswith("Q") and name[1:].isdigit():
                continue  # etiketsiz varlık
            raw_country = member.get("natLabel", {}).get("value", "")
            country = COUNTRY_ALIASES.get(raw_country, raw_country) or None
            rows.append((
                key, name, club, country,
                _year(member.get("start", {}).get("value")),
                _year(member.get("end", {}).get("value")),
                f"wikidata:{qid}", stamp,
            ))

        if not args.dry_run and rows:
            conn.executemany(
                "INSERT OR REPLACE INTO club_history "
                "(name_normalized, player_name, club_name, country, "
                " start_year, end_year, source, updated_at) VALUES (?,?,?,?,?,?,?,?)",
                rows,
            )
            conn.commit()

        total_rows += len(rows)
        print(f"  [{index}/{len(pending)}] {club}: {len(rows)} oyuncu "
              f"(kesişim {overlap})")
        time.sleep(0.4)   # Wikidata'ya nazik davran

    print(f"\ntoplam {total_rows} kayıt, {skipped} kulüp atlandı"
          + (" (dry-run)" if args.dry_run else ""))
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
