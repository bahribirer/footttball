#!/usr/bin/env python3
"""'United Kingdom' uyruklarını İngiltere/İskoçya/Galler/K.İrlanda'ya ayırır.

Wikidata futbolcuların uyruğunu (P27) çoğu zaman "United Kingdom" olarak
veriyor. Oyunun sözlüğünde böyle bir değer yok — bu satırlar hiçbir kutuyla
eşleşmiyor. Ölçümde `club_history`'de 52.541 satır, 15.444 farklı futbolcu
bu durumda.

İki aşamada çözülür:

  1. Ana `players` tablosu: aynı futbolcu orada zaten England/Scotland/Wales/
     Northern Ireland olarak duruyorsa o değer kullanılır. Bedava ve oyunun
     kendi sözlüğüyle birebir tutarlı.
  2. Wikidata P1532 ("country for sport"): futbolcunun hangi milli takımı
     temsil ettiğini söyler. Futbol için doğru alan budur — P27 pasaportu,
     P1532 milli takımı anlatır. Bulunamayanlar dokunulmadan bırakılır;
     yanlış ülke atamak, eksik bırakmaktan kötüdür.

Kullanım:
    python scripts/resolve_uk_nationality.py --dry-run
    python scripts/resolve_uk_nationality.py
    python scripts/resolve_uk_nationality.py --skip-wikidata   # sadece 1. asama
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

from scripts.sync_current_squads import DB_PATH  # noqa: E402

SPARQL = "https://query.wikidata.org/sparql"
UA = "tikitakatoe-uk-nationality/1.0 (https://tikitakatoe.com)"
BATCH = 50

UK_VALUES = ("United Kingdom", "Kingdom of Great Britain", "Great Britain")

# Wikidata etiketi -> oyunun sozlugu.
HOME_NATIONS = {
    "England": "England",
    "Scotland": "Scotland",
    "Wales": "Wales",
    "Northern Ireland": "Northern Ireland",
    "Ireland": "Republic of Ireland",
}


def _escape(name: str) -> str:
    return name.replace("\\", "\\\\").replace('"', '\\"')


def lookup_sport_country(names: list[str]) -> dict[str, str]:
    """{ad: ulke} — P1532 (country for sport) uzerinden."""
    values = " ".join(f'"{_escape(n)}"@en' for n in names)
    query = f"""
    SELECT ?label ?natLabel WHERE {{
      VALUES ?label {{ {values} }}
      ?player rdfs:label ?label ;
              wdt:P31 wd:Q5 ;
              wdt:P1532 ?nat .
      SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
    }}"""
    url = f"{SPARQL}?format=json&query={urllib.parse.quote(query)}"
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(request, timeout=180) as response:
        data = json.loads(response.read().decode("utf-8"))

    found: dict[str, str] = {}
    for row in data["results"]["bindings"]:
        label = row["label"]["value"]
        country = row["natLabel"]["value"]
        mapped = HOME_NATIONS.get(country)
        if not mapped:
            continue
        # Bir futbolcu birden fazla milli takim gorunuyorsa (yas kategorileri,
        # ulke degistirenler) ilk gelen alinir; celiskiliyse atlanir.
        if label in found and found[label] != mapped:
            found[label] = ""
        else:
            found.setdefault(label, mapped)
    return {k: v for k, v in found.items() if v}


def stage_one(con: sqlite3.Connection, dry_run: bool) -> int:
    """Ana tablodaki bilinen uyruklari uygular."""
    rows = con.execute(
        f"""SELECT DISTINCT ch.name_normalized, p.country_of_citizenship
            FROM club_history ch
            JOIN players p ON p.name_normalized = ch.name_normalized
            WHERE ch.country IN ({','.join('?' * len(UK_VALUES))})
              AND p.country_of_citizenship IN ('England','Scotland','Wales','Northern Ireland')""",
        UK_VALUES,
    ).fetchall()

    print(f"  1. asama: {len(rows)} futbolcu ana tablodan cozuldu")
    if dry_run or not rows:
        return len(rows)

    con.executemany(
        f"""UPDATE club_history SET country = ?
            WHERE name_normalized = ?
              AND country IN ({','.join('?' * len(UK_VALUES))})""",
        [(country, name, *UK_VALUES) for name, country in rows],
    )
    con.commit()
    return len(rows)


def stage_two(con: sqlite3.Connection, dry_run: bool, limit: int | None) -> int:
    """Kalanlari Wikidata'nin spor milliyeti alanindan cozer."""
    names = [
        r[0] for r in con.execute(
            f"""SELECT DISTINCT player_name FROM club_history
                WHERE country IN ({','.join('?' * len(UK_VALUES))})
                ORDER BY player_name""",
            UK_VALUES,
        )
    ]
    if limit:
        names = names[:limit]
    print(f"  2. asama: {len(names)} futbolcu Wikidata'ya soruluyor")

    resolved = 0
    for index in range(0, len(names), BATCH):
        chunk = names[index:index + BATCH]
        try:
            found = lookup_sport_country(chunk)
        except Exception as exc:
            print(f"    ! sorgu basarisiz ({index}): {exc}")
            time.sleep(5)
            continue

        if found and not dry_run:
            con.executemany(
                f"""UPDATE club_history SET country = ?
                    WHERE player_name = ?
                      AND country IN ({','.join('?' * len(UK_VALUES))})""",
                [(country, name, *UK_VALUES) for name, country in found.items()],
            )
            con.commit()
        resolved += len(found)
        done = min(index + BATCH, len(names))
        print(f"    {done}/{len(names)} — toplam cozulen {resolved}", flush=True)
        time.sleep(1.0)
    return resolved


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-wikidata", action="store_true")
    parser.add_argument("--limit", type=int)
    args = parser.parse_args()

    con = sqlite3.connect(DB_PATH, timeout=60)
    placeholders = ",".join("?" * len(UK_VALUES))
    before = con.execute(
        f"SELECT COUNT(*) FROM club_history WHERE country IN ({placeholders})", UK_VALUES
    ).fetchone()[0]
    print(f"▶ baslangic: {before} satir cozulmemis")

    stage_one(con, args.dry_run)
    if not args.skip_wikidata:
        stage_two(con, args.dry_run, args.limit)

    after = con.execute(
        f"SELECT COUNT(*) FROM club_history WHERE country IN ({placeholders})", UK_VALUES
    ).fetchone()[0]
    print(f"✓ {before} -> {after} satir ({before - after} cozuldu)")

    for country, count in con.execute(
        """SELECT country, COUNT(*) FROM club_history
           WHERE country IN ('England','Scotland','Wales','Northern Ireland')
           GROUP BY country ORDER BY 2 DESC"""
    ):
        print(f"    {country:20} {count}")
    con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
