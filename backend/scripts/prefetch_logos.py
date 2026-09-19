"""Tüm kulüp logolarını önbelleğe indirir ve eksikleri raporlar.

Kaynak sırası (logo_service ile aynı): önbellek → clubs.logo_url (Wikimedia)
→ TheSportsDB → burada ek olarak Wikidata (P154 logo / P41 bayrak).
Bulunanların adresi `clubs` tablosuna yazılır ki sunucu da aynı yolu izlesin.

Kullanım (backend kökünden):
    python scripts/prefetch_logos.py            # players (son 3 sezon) + club_history
    python scripts/prefetch_logos.py --all      # players'taki tüm kulüpler de
    python scripts/prefetch_logos.py --report   # yalnız eksikleri yaz
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.config import settings  # noqa: E402
from app.services import logo_service  # noqa: E402

WIKIDATA_SPARQL = "https://query.wikidata.org/sparql"
UA = "TikiTakaToe/1.0 (contact: bahribirerr@gmail.com)"


# Veri setindeki ad Wikidata'da tutmayanlar için arama adı.
ALIASES = {
    "AC Venezia 1907": "Venezia FC",
    "Deportivo de La Coruna": "Deportivo de La Coruña",
    "Brescia Calcio": "Brescia Calcio",
    "Treviso FBC 1993": "Treviso F.B.C. 1993",
    "AEL Kalloni": "AEL Kalloni F.C.",
    "AOK Kerkyra": "A.O. Kerkyra",
    "AS Nancy-Lorraine": "AS Nancy",
    "Akhisarspor": "Akhisar Belediyespor",
    "Anzhi Makhachkala": "FC Anzhi Makhachkala",
    "Ascoli Calcio 1898": "Ascoli Calcio 1898 FC",
    "Buyuksehir Belediyesi Ankaraspor": "Osmanlıspor",
    "Carpi FC 1909": "Carpi F.C. 1909",
    "Colo-Colo": "Colo-Colo",
    "Dordrecht'90": "FC Dordrecht",
    "Elazigspor": "Elazığspor",
    "Energiya-Tekstilshchik Kamyshin": "FC Tekstilshchik Kamyshin",
    "Fakel-Voronezh Voronezh": "FC Fakel Voronezh",
    "Hacettepe Spor": "Hacettepe S.K.",
    "Iraklis Thessaloniki": "Iraklis F.C.",
    "Istanbul Buyuksehir Belediyespor": "İstanbul Başakşehir F.K.",
    "Kardemir DC Karabukspor": "Kardemir Karabükspor",
    "Le Mans Union Club 72": "Le Mans FC",
    "Naval 1 de Maio": "Naval 1º de Maio",
    "Novara Calcio 1908": "Novara Calcio",
    "Panthrakikos Komotini": "Panthrakikos F.C.",
    "Peterborough United": "Peterborough United F.C.",
    "SC Beira-Mar": "S.C. Beira-Mar",
    "SC Campomaiorense": "S.C. Campomaiorense",
    "Saturn REN-TV Ramenskoe": "FC Saturn Ramenskoye",
    "Sibir Novosibirsk": "FC Sibir Novosibirsk",
    "Torpedo-Luzhniki Moskva": "FC Torpedo Moscow",
    "Treviso FBC 1993": "Treviso F.B.C. 1993",
    "VfB Leipzig": "1. FC Lokomotive Leipzig",
}


# Elle doğrulanmış adresler (otomatik kaynaklar yanlış armayı seçiyordu).
MANUAL_URLS = {
    "Deportivo de La Coruna": "https://thumb.wikimedia.org/wikipedia/en/thumb/5/56/RC_Deportivo_A_Coru%C3%B1a_logo_2026.svg/330px-RC_Deportivo_A_Coru%C3%B1a_logo_2026.svg.png",
    "Brescia Calcio (- 2025)": "https://thumb.wikimedia.org/wikipedia/en/thumb/1/17/Brescia_calcio_badge.svg/330px-Brescia_calcio_badge.svg.png",
    "Treviso FBC 1993": "https://upload.wikimedia.org/wikipedia/en/3/3c/Treviso_FBC_1993_logo.png",
    "AEL Kalloni": "https://upload.wikimedia.org/wikipedia/en/0/00/AEL_Kalloni_logo.png",
}


def _clean(club: str) -> str:
    """"Brescia Calcio (- 2025)" → "Brescia Calcio"."""
    import re
    base = re.sub(r"\s*\(\s*-?\s*\d{4}\s*\)\s*$", "", club).strip()
    return ALIASES.get(base, base)


def _wikidata_search_logo(club: str) -> str | None:
    """Etiket birebir tutmayınca: arama API'si → adaylar → kulüp + logo."""
    try:
        r = requests.get("https://www.wikidata.org/w/api.php",
                         params={"action": "wbsearchentities", "search": _clean(club), "language": "en",
                                 "type": "item", "limit": 8, "format": "json"},
                         headers={"User-Agent": UA}, timeout=30)
        ids = [x["id"] for x in r.json().get("search", [])]
    except (requests.RequestException, ValueError, KeyError):
        return None
    if not ids:
        return None
    values = " ".join(f"wd:{i}" for i in ids)
    query = f"""
    SELECT ?club ?logo WHERE {{
      VALUES ?club {{ {values} }}
      ?club wdt:P31/wdt:P279* wd:Q476028 .
      {{ ?club wdt:P154 ?logo }} UNION {{ ?club wdt:P41 ?logo }}
    }}"""
    try:
        r = requests.get(WIKIDATA_SPARQL, params={"query": query, "format": "json"},
                         headers={"User-Agent": UA}, timeout=30)
        rows = r.json()["results"]["bindings"]
    except (requests.RequestException, ValueError, KeyError):
        return None
    # arama sırasını koru: ilk aday öncelikli
    by_id = {b["club"]["value"].rsplit("/", 1)[-1]: b["logo"]["value"] for b in rows}
    for i in ids:
        if i in by_id:
            url = by_id[i]
            return url + "?width=256" if "Special:FilePath" in url else url
    return None


def _wikipedia_pageimage(club: str) -> str | None:
    """Son çare: İngilizce Wikipedia sayfasının ana görseli (arma).

    Armaların çoğu telifli olduğu için Commons/Wikidata'da yok; Wikipedia
    'fair use' ile tutuyor. pilicense=any bunları da döndürür.
    """
    name = _clean(club)
    try:
        r = requests.get("https://en.wikipedia.org/w/api.php",
                         params={"action": "query", "prop": "pageimages", "piprop": "thumbnail",
                                 "pithumbsize": 256, "pilicense": "any", "redirects": 1,
                                 "format": "json", "titles": name},
                         headers={"User-Agent": UA}, timeout=30)
        pages = r.json().get("query", {}).get("pages", {})
        for page in pages.values():
            thumb = page.get("thumbnail", {}).get("source")
            if thumb:
                return thumb.split("?", 1)[0]
        # Sayfa yoksa arama ile ilk sonucu dene.
        r = requests.get("https://en.wikipedia.org/w/api.php",
                         params={"action": "query", "list": "search", "srsearch": f"{name} football club",
                                 "srlimit": 1, "format": "json"},
                         headers={"User-Agent": UA}, timeout=30)
        hits = r.json().get("query", {}).get("search", [])
        if not hits:
            return None
        r = requests.get("https://en.wikipedia.org/w/api.php",
                         params={"action": "query", "prop": "pageimages", "piprop": "thumbnail",
                                 "pithumbsize": 256, "pilicense": "any", "format": "json",
                                 "titles": hits[0]["title"]},
                         headers={"User-Agent": UA}, timeout=30)
        for page in r.json().get("query", {}).get("pages", {}).values():
            thumb = page.get("thumbnail", {}).get("source")
            if thumb:
                return thumb.split("?", 1)[0]
    except (requests.RequestException, ValueError, KeyError):
        return None
    return None


def _wikidata_logo(club: str) -> str | None:
    """Ad araması (rdfs:label / altLabel) → futbol kulübü → P154 logo."""
    club = _clean(club)
    query = f"""
    SELECT ?logo WHERE {{
      ?club wdt:P31/wdt:P279* wd:Q476028 .
      {{ ?club rdfs:label "{club}"@en }} UNION {{ ?club skos:altLabel "{club}"@en }}
      {{ ?club wdt:P154 ?logo }} UNION {{ ?club wdt:P41 ?logo }}
    }} LIMIT 1"""
    try:
        r = requests.get(WIKIDATA_SPARQL, params={"query": query, "format": "json"},
                         headers={"User-Agent": UA}, timeout=30)
        if r.status_code != 200:
            return None
        rows = r.json()["results"]["bindings"]
        if not rows:
            return None
        url = rows[0]["logo"]["value"]
        # Special:FilePath → indirilebilir küçük resim
        if "Special:FilePath" in url:
            url = url + "?width=256"
        return url
    except (requests.RequestException, ValueError, KeyError):
        return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()

    con = sqlite3.connect(settings.DB_PATH)
    clubs: set[str] = set()
    season_filter = "" if args.all else "WHERE last_season >= 2022"
    clubs |= {r[0] for r in con.execute(
        f"SELECT DISTINCT current_club_name FROM players {season_filter}") if r[0]}
    clubs |= {r[0] for r in con.execute("SELECT DISTINCT club_name FROM club_history") if r[0]}
    clubs = {c for c in clubs if c and not c.startswith("Retired") and "Without Club" not in c}
    print(f"{len(clubs)} kulüp")

    missing: list[str] = []
    found_new: list[tuple[str, str]] = []
    for i, club in enumerate(sorted(clubs), 1):
        if logo_service.cached_logo_path(club):
            continue
        if args.report:
            missing.append(club)
            continue
        path = None
        if club in MANUAL_URLS:
            path = logo_service._download(MANUAL_URLS[club], club)
            if path:
                found_new.append((club, MANUAL_URLS[club]))
        if not path:
            path = logo_service.resolve_logo(club)
        if not path:
            url = _wikidata_logo(club) or _wikidata_search_logo(club) or _wikipedia_pageimage(club)
            if url:
                path = logo_service._download(url, club)
                if path:
                    found_new.append((club, url))
            time.sleep(0.3)
        if not path:
            missing.append(club)
        if i % 50 == 0:
            print(f"  [{i}/{len(clubs)}] eksik: {len(missing)}")

    if found_new:
        with sqlite3.connect(settings.DB_PATH) as w:
            w.executemany(
                "INSERT INTO clubs (name, logo_url) VALUES (?, ?) "
                "ON CONFLICT(name) DO UPDATE SET logo_url = excluded.logo_url",
                found_new)
        print(f"{len(found_new)} kulüp adresi Wikidata'dan clubs tablosuna yazıldı")

    print(f"\nlogosu olmayan: {len(missing)}")
    for club in missing:
        print("  -", club)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
