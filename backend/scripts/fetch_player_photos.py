"""Wikidata'dan oyuncu fotoğrafı (P18) toplar → `player_photos` tablosu.

Hedefler:
  * yalnız tarihçede olan (efsane) oyuncular — büyük kulüp geçmişi olanlar
  * `players`'ta fotoğrafı olmayan güncel oyuncular (son sezon ≥ 2022)

Adla eşleşme (rdfs:label@en) + futbolcu mesleği (P106 = Q937857). Aynı
ada birden çok kayıt gelirse uyruk tutan tercih edilir; tutmuyorsa ilk.
Fotoğraf adresi Commons Special:FilePath?width=300 (yönlendirmeli, tarayıcı
ve Flutter Image.network takip eder).

Kullanım (backend kökünden):
    python scripts/fetch_player_photos.py            # eksikler
    python scripts/fetch_player_photos.py --limit 500
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
import time
import urllib.parse
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.config import settings  # noqa: E402
from app.services import player_service as ps  # noqa: E402

SPARQL = "https://query.wikidata.org/sparql"
UA = "TikiTakaToe/1.0 (contact: bahribirerr@gmail.com)"
BATCH = 40

SCHEMA = """
CREATE TABLE IF NOT EXISTS player_photos (
    name_normalized TEXT PRIMARY KEY,
    player_name     TEXT NOT NULL,
    image_url       TEXT,
    source          TEXT,
    updated_at      TEXT
);
"""


def _targets(con: sqlite3.Connection) -> list[tuple[str, str, str | None]]:
    """(name_normalized, ad, uyruk) — fotoğrafı olmayanlar."""
    done = {r[0] for r in con.execute("SELECT name_normalized FROM player_photos")}
    out: list[tuple[str, str, str | None]] = []

    weights = ps._club_weights()
    rows = con.execute(
        """SELECT ch.name_normalized, MAX(ch.player_name), MAX(ch.country), MAX(ch.start_year),
                  GROUP_CONCAT(DISTINCT ch.club_name)
           FROM club_history ch LEFT JOIN players p ON p.name_normalized = ch.name_normalized
           WHERE p.name_normalized IS NULL
           GROUP BY ch.name_normalized""").fetchall()
    for norm, name, country, last_year, clubs in rows:
        if norm in done or (last_year or 0) < 1970:
            continue
        big = {ps.normalize(c) for c in (clubs or "").split(",") if weights.get(c, 0) > 0}
        if len({" ".join(sorted(x.split())) for x in big}) >= 1:
            out.append((norm, name, country))

    rows = con.execute(
        """SELECT name_normalized, name, country_of_citizenship FROM players
           WHERE last_season >= 2022
             AND (image_url IS NULL OR image_url = '' OR image_url LIKE '%default%')""").fetchall()
    for norm, name, country in rows:
        if norm not in done:
            out.append((norm, name, country))
    # aynı ad iki listede olabilir
    seen: set[str] = set()
    uniq = []
    for t in out:
        if t[0] not in seen:
            seen.add(t[0]); uniq.append(t)
    return uniq


def _query(names: list[str]) -> list[dict]:
    values = " ".join('"%s"@en' % n.replace('"', '\\"') for n in names)
    q = f"""SELECT ?name ?img ?country WHERE {{
      VALUES ?name {{ {values} }}
      {{ ?p rdfs:label ?name }} UNION {{ ?p skos:altLabel ?name }}
      ?p wdt:P106 wd:Q937857 ; wdt:P18 ?img .
      OPTIONAL {{ ?p wdt:P27 ?c . ?c rdfs:label ?country FILTER(LANG(?country)="en") }}
    }}"""
    for attempt in range(3):
        try:
            r = requests.get(SPARQL, params={"query": q, "format": "json"},
                             headers={"User-Agent": UA}, timeout=90)
            if r.status_code == 429:
                time.sleep(10 * (attempt + 1)); continue
            if r.status_code != 200:
                return []
            return r.json()["results"]["bindings"]
        except (requests.RequestException, ValueError):
            time.sleep(3)
    return []


def _thumb(url: str) -> str:
    # http://commons.wikimedia.org/wiki/Special:FilePath/X → https + width
    path = url.split("Special:FilePath/", 1)[-1]
    return f"https://commons.wikimedia.org/wiki/Special:FilePath/{path}?width=300"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    con = sqlite3.connect(settings.DB_PATH)
    con.executescript(SCHEMA)
    targets = _targets(con)
    if args.limit:
        targets = targets[: args.limit]
    print(f"{len(targets)} oyuncu için fotoğraf aranacak")

    found = missing = 0
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    for i in range(0, len(targets), BATCH):
        batch = targets[i : i + BATCH]
        by_name: dict[str, list[dict]] = {}
        for b in _query([t[1] for t in batch]):
            by_name.setdefault(b["name"]["value"], []).append(b)
        rows = []
        for norm, name, country in batch:
            cands = by_name.get(name, [])
            pick = None
            if cands:
                pick = next((c for c in cands
                             if country and c.get("country", {}).get("value", "") == country), cands[0])
            if pick:
                rows.append((norm, name, _thumb(pick["img"]["value"]), "wikidata:P18", now)); found += 1
            else:
                rows.append((norm, name, None, "wikidata:none", now)); missing += 1
        con.executemany(
            "INSERT OR REPLACE INTO player_photos VALUES (?, ?, ?, ?, ?)", rows)
        con.commit()
        if (i // BATCH) % 10 == 0:
            print(f"  [{i + len(batch)}/{len(targets)}] bulundu {found}, yok {missing}")
        time.sleep(1.0)
    print(f"bitti: bulundu {found}, bulunamadı {missing}")
    return 0


if __name__ == "__main__" and "--search-pass" not in sys.argv:
    raise SystemExit(main())


# --- ikinci geçiş: etiket tutmayanlar için arama API'si -------------------

def search_pass(min_fame: int = 3) -> None:
    """Etiketle bulunamayan ünlü efsaneler: wbsearchentities → aday → P18."""
    con = sqlite3.connect(settings.DB_PATH)
    con.executescript(SCHEMA)
    weights = ps._club_weights()
    rows = con.execute(
        """SELECT ch.name_normalized, MAX(ch.player_name), MAX(ch.country), MAX(ch.start_year),
                  GROUP_CONCAT(DISTINCT ch.club_name)
           FROM club_history ch LEFT JOIN players p ON p.name_normalized = ch.name_normalized
           LEFT JOIN player_photos pp ON pp.name_normalized = ch.name_normalized
           WHERE p.name_normalized IS NULL AND (pp.image_url IS NULL)
           GROUP BY ch.name_normalized""").fetchall()
    targets = []
    for norm, name, country, ly, clubs in rows:
        if (ly or 0) < 1970:
            continue
        big = {ps.normalize(c) for c in (clubs or "").split(",") if weights.get(c, 0) > 0}
        if len({" ".join(sorted(x.split())) for x in big}) >= min_fame:
            targets.append((norm, name, country))
    print(f"arama geçişi: {len(targets)} efsane")
    found = 0
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    for i, (norm, name, country) in enumerate(targets, 1):
        try:
            r = requests.get("https://www.wikidata.org/w/api.php",
                             params={"action": "wbsearchentities", "search": name, "language": "en",
                                     "type": "item", "limit": 6, "format": "json"},
                             headers={"User-Agent": UA}, timeout=30)
            ids = [x["id"] for x in r.json().get("search", [])]
        except (requests.RequestException, ValueError, KeyError):
            ids = []
        if not ids:
            continue
        values = " ".join(f"wd:{x}" for x in ids)
        q = f"""SELECT ?p ?img ?country WHERE {{
          VALUES ?p {{ {values} }}
          ?p wdt:P106 wd:Q937857 ; wdt:P18 ?img .
          OPTIONAL {{ ?p wdt:P27 ?c . ?c rdfs:label ?country FILTER(LANG(?country)="en") }} }}"""
        binds = []
        for attempt in range(2):
            try:
                rr = requests.get(SPARQL, params={"query": q, "format": "json"},
                                  headers={"User-Agent": UA}, timeout=60)
                if rr.status_code == 429:
                    time.sleep(8); continue
                binds = rr.json()["results"]["bindings"] if rr.status_code == 200 else []
                break
            except (requests.RequestException, ValueError):
                time.sleep(2)
        if not binds:
            continue
        # arama sırasını koru; uyruk tutan öncelikli
        order = {f"http://www.wikidata.org/entity/{x}": k for k, x in enumerate(ids)}
        binds.sort(key=lambda b: (0 if country and b.get("country", {}).get("value") == country else 1,
                                  order.get(b["p"]["value"], 99)))
        con.execute("INSERT OR REPLACE INTO player_photos VALUES (?, ?, ?, ?, ?)",
                    (norm, name, _thumb(binds[0]["img"]["value"]), "wikidata:search", now))
        con.commit(); found += 1
        if i % 50 == 0:
            print(f"  [{i}/{len(targets)}] bulundu {found}")
        time.sleep(0.6)
    print(f"arama geçişi bitti: {found} fotoğraf")


if __name__ == "__main__" and "--search-pass" in sys.argv:
    search_pass()
