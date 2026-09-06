"""Güncel kulüp kadrolarını Wikipedia'dan çekip `squad_updates` tablosuna yazar.

Oyuncu veritabanı sezon anlık görüntülerinden oluşuyor ve en son 2025/26'yı
kapsıyor. Sonrasındaki transferler (örneğin Rafael Leão'nun Galatasaray'a
geçişi) bu yüzden tanınmıyordu. Bu betik, büyük liglerin güncel kadrolarını
ayrı bir katman olarak ekler; ana tabloya dokunmaz, böylece oyuncuların eski
kulüpleri de kabul edilmeye devam eder.

Kullanım:
    python -m scripts.sync_current_squads              # tüm ligler
    python -m scripts.sync_current_squads --league TR1 # tek lig
    python -m scripts.sync_current_squads --dry-run

Kaynak, kulüp sayfalarındaki `{{Fs player}}` kadro şablonlarıdır; Wikipedia
transfer dönemlerinde günler içinde güncellenir.
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import time
import unicodedata
import urllib.parse
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

def _db_path() -> Path:
    """Uygulamayla aynı veritabanını hedefler (Docker'da DB_PATH değişkeni)."""
    try:
        from app.core.config import settings

        return Path(settings.DB_PATH)
    except Exception:
        return Path(__file__).resolve().parent.parent / "data" / "tikitakapi.db"


DB_PATH = _db_path()

API = "https://en.wikipedia.org/w/api.php"
UA = "tikitakatoe-squad-sync/1.0 (https://tikitakatoe.com)"

# Sayfa adları sezon başında değişir; --season ile geçersiz kılınabilir.
LEAGUE_PAGES = {
    "TR1": "Süper Lig",
    "GB1": "Premier League",
    "IT1": "Serie A",
    "ES1": "La Liga",
    "L1": "Bundesliga",
    "FR1": "Ligue 1",
    "NL1": "Eredivisie",
    "PO1": "Primeira Liga",
}

# Kadro şablonundaki FIFA kodları, veritabanındaki ülke adlarına çevrilir.
NATION_CODES = {
    "TUR": "Turkey", "POR": "Portugal", "ESP": "Spain", "FRA": "France",
    "GER": "Germany", "ITA": "Italy", "ENG": "England", "SCO": "Scotland",
    "WAL": "Wales", "NIR": "Northern Ireland", "IRL": "Ireland",
    "NED": "Netherlands", "BEL": "Belgium", "BRA": "Brazil", "ARG": "Argentina",
    "URU": "Uruguay", "COL": "Colombia", "CHI": "Chile", "PER": "Peru",
    "ECU": "Ecuador", "PAR": "Paraguay", "VEN": "Venezuela", "BOL": "Bolivia",
    "MEX": "Mexico", "USA": "United States", "CAN": "Canada", "CRC": "Costa Rica",
    "JAM": "Jamaica", "HON": "Honduras", "PAN": "Panama",
    "CRO": "Croatia", "SRB": "Serbia", "BIH": "Bosnia-Herzegovina",
    "SVN": "Slovenia", "SVK": "Slovakia", "CZE": "Czech Republic",
    "POL": "Poland", "UKR": "Ukraine", "RUS": "Russia", "ROU": "Romania",
    "BUL": "Bulgaria", "HUN": "Hungary", "AUT": "Austria", "SUI": "Switzerland",
    "DEN": "Denmark", "SWE": "Sweden", "NOR": "Norway", "FIN": "Finland",
    "ISL": "Iceland", "GRE": "Greece", "ALB": "Albania", "KVX": "Kosovo",
    "MKD": "North Macedonia", "MNE": "Montenegro", "GEO": "Georgia",
    "ARM": "Armenia", "AZE": "Azerbaijan", "BLR": "Belarus", "LTU": "Lithuania",
    "LVA": "Latvia", "EST": "Estonia", "CYP": "Cyprus", "ISR": "Israel",
    "MAR": "Morocco", "ALG": "Algeria", "TUN": "Tunisia", "EGY": "Egypt",
    "SEN": "Senegal", "CIV": "Cote d'Ivoire", "GHA": "Ghana", "NGA": "Nigeria",
    "CMR": "Cameroon", "MLI": "Mali", "BFA": "Burkina Faso", "GUI": "Guinea",
    "COD": "Congo", "COG": "Congo", "GAB": "Gabon", "TOG": "Togo",
    "BEN": "Benin", "ANG": "Angola", "CPV": "Cape Verde", "ZAM": "Zambia",
    "RSA": "South Africa", "KEN": "Kenya", "GAM": "Gambia", "GNB": "Guinea-Bissau",
    "MTN": "Mauritania", "LBY": "Libya", "SDN": "Sudan",
    "JPN": "Japan", "KOR": "Korea, South", "CHN": "China", "AUS": "Australia",
    "NZL": "New Zealand", "IRN": "Iran", "IRQ": "Iraq", "KSA": "Saudi Arabia",
    "QAT": "Qatar", "UAE": "United Arab Emirates", "UZB": "Uzbekistan",
    "JOR": "Jordan", "SYR": "Syria", "LBN": "Lebanon", "IND": "India",
}


# --- metin yardımcıları ---------------------------------------------------

_TRANSLIT = str.maketrans({
    "ı": "i", "İ": "i", "ß": "ss", "ø": "o", "Ø": "o", "đ": "d", "Đ": "d",
    "ł": "l", "Ł": "l", "æ": "ae", "Æ": "ae", "œ": "oe", "Œ": "oe",
    "ð": "d", "Ð": "d", "þ": "th", "Þ": "th", "ħ": "h", "ŋ": "n",
})


def normalize(text: str) -> str:
    """Aksanları ve büyük/küçük farkını yok sayan arama anahtarı.

    `app.services.player_service.normalize` ile aynı kuralları uygular;
    üretilen anahtarlar iki tarafta da eşleşmeli.
    """
    lowered = (text or "").strip().lower().translate(_TRANSLIT)
    decomposed = unicodedata.normalize("NFKD", lowered)
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch))


def club_key(name: str) -> str:
    """Kulüp adlarını karşılaştırmak için sadeleştirir.

    "Galatasaray S.K. (football)" ile "Galatasaray" aynı anahtara iner.
    """
    text = normalize(name)
    text = re.sub(r"\(.*?\)", " ", text)
    # Noktalama önce ayıklanır: "Galatasaray S.K." → "galatasaray s k",
    # yoksa aşağıdaki ek listesi "s.k." biçimini yakalayamıyordu.
    text = re.sub(r"[^a-z0-9]+", " ", text)
    text = re.sub(
        r"\b(fc|cf|sk|jk|ac|as|sc|ss|ssc|afc|cfc|bk|if|sv|tsv|vfb|vfl|"
        r"fk|kv|rc|ud|cd|sd|club|calcio|football|futbol|de|the)\b",
        " ", text,
    )
    # Noktalı kısaltmalardan artan tek harfler ("a c milan" → "milan").
    text = re.sub(r"\b[a-z]\b", " ", text)
    return re.sub(r"\s+", "", text)


# --- Wikipedia ------------------------------------------------------------

def _api(params: dict) -> dict:
    params = {**params, "format": "json", "formatversion": "2"}
    url = f"{API}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(request, timeout=45) as response:
        return json.loads(response.read().decode("utf-8"))


def league_links(page: str) -> list[str]:
    """Lig sayfasındaki ana ad alanı bağlantıları (kulüp adayları)."""
    links: list[str] = []
    params = {"action": "query", "prop": "links", "titles": page,
              "plnamespace": "0", "pllimit": "max"}
    while True:
        data = _api(params)
        for item in data.get("query", {}).get("pages", []):
            links.extend(link["title"] for link in item.get("links", []))
        cont = data.get("continue")
        if not cont:
            return links
        params.update(cont)


def fetch_wikitext(titles: list[str]) -> dict[str, str]:
    """Sayfaları 50'şerlik gruplar hâlinde çeker (tek istekte 50 sayfa)."""
    result: dict[str, str] = {}
    for start in range(0, len(titles), 50):
        batch = titles[start:start + 50]
        data = _api({
            "action": "query", "prop": "revisions", "rvprop": "content",
            "rvslots": "main", "titles": "|".join(batch), "redirects": "1",
        })
        for page in data.get("query", {}).get("pages", []):
            revisions = page.get("revisions")
            if not revisions:
                continue
            content = revisions[0].get("slots", {}).get("main", {}).get("content")
            if content:
                result[page["title"]] = content
        time.sleep(0.3)  # Wikipedia'ya nazik davran
    return result


_FS_PLAYER = re.compile(r"\{\{\s*[Ff]s player\s*\|(.+?)\}\}", re.S)


def parse_squad(wikitext: str) -> list[tuple[str, str]]:
    """Kadro şablonlarından (isim, ülke) çiftlerini çıkarır."""
    squad: list[tuple[str, str]] = []

    for body in _FS_PLAYER.findall(wikitext):
        fields = dict(
            (m.group(1).strip().lower(), m.group(2).strip())
            for m in re.finditer(r"([a-zA-Z]+)\s*=\s*([^|]*)", body)
        )
        raw_name = fields.get("name", "")
        if not raw_name:
            continue

        # [[Can Armando Güner|Armando Güner]] → görünen ad tercih edilir
        link = re.search(r"\[\[([^\]]+)\]\]", raw_name)
        name = link.group(1) if link else raw_name
        name = name.split("|")[-1].strip()
        name = re.sub(r"\{\{.*?\|?([^|{}]*)\}\}", r"\1", name).strip()
        name = re.sub(r"<.*?>", "", name).strip()

        if not name or len(name) < 3:
            continue

        country = NATION_CODES.get(fields.get("nat", "").upper(), "")
        squad.append((name, country))

    return squad


# --- veritabanı -----------------------------------------------------------

SCHEMA = """
CREATE TABLE IF NOT EXISTS squad_updates (
    name_normalized TEXT NOT NULL,
    player_name     TEXT NOT NULL,
    club_name       TEXT NOT NULL,
    country         TEXT,
    competition_id  TEXT,
    season          INTEGER,
    image_url       TEXT,
    source          TEXT,
    updated_at      TEXT,
    PRIMARY KEY (name_normalized, club_name)
);
CREATE INDEX IF NOT EXISTS idx_squad_updates_name ON squad_updates(name_normalized);
CREATE INDEX IF NOT EXISTS idx_squad_updates_club ON squad_updates(club_name);
"""


def known_clubs(conn: sqlite3.Connection) -> dict[str, str]:
    """Sadeleştirilmiş kulüp anahtarı → veritabanındaki kulüp adı."""
    mapping: dict[str, str] = {}
    rows = conn.execute(
        "SELECT DISTINCT current_club_name FROM players "
        "WHERE current_club_name IS NOT NULL AND current_club_name <> ''"
    )
    for (name,) in rows:
        key = club_key(name)
        # Aynı anahtara düşen adlarda en kısa (en sade) hâli tercih edilir.
        if key and (key not in mapping or len(name) < len(mapping[key])):
            mapping[key] = name
    return mapping


def existing_players(conn: sqlite3.Connection) -> dict[str, tuple[str, str, str]]:
    """name_normalized → (ad, ülke, görsel) — en güncel sezon kaydından."""
    rows = conn.execute(
        "SELECT name_normalized, name, country_of_citizenship, image_url "
        "FROM players WHERE name_normalized IS NOT NULL "
        "ORDER BY last_season ASC"
    )
    # ORDER BY artan: sonraki (daha yeni) kayıt öncekini ezer.
    return {key: (name, country or "", image or "") for key, name, country, image in rows}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--league", action="append", choices=sorted(LEAGUE_PAGES),
                        help="yalnızca bu lig(ler); varsayılan hepsi")
    parser.add_argument("--season", help="sezon etiketi, örn. 2026–27")
    parser.add_argument("--dry-run", action="store_true",
                        help="veritabanına yazmadan neyin ekleneceğini göster")
    args = parser.parse_args()

    # Sezon Temmuz'da döner: Eylül 2026 → "2026–27".
    today = date.today()
    start_year = today.year if today.month >= 7 else today.year - 1
    season_label = args.season or f"{start_year}–{str(start_year + 1)[-2:]}"

    leagues = args.league or list(LEAGUE_PAGES)
    conn = sqlite3.connect(DB_PATH)
    conn.executescript(SCHEMA)

    clubs = known_clubs(conn)
    players = existing_players(conn)
    print(f"veritabanı: {len(clubs)} kulüp, {len(players)} benzersiz oyuncu")
    print(f"sezon     : {season_label}\n")

    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    total_rows = 0

    for code in leagues:
        page = f"{season_label} {LEAGUE_PAGES[code]}"
        print(f"── {code}: {page}")

        try:
            links = league_links(page)
        except Exception as exc:  # ağ hatası bir ligi atlatır, betiği durdurmaz
            print(f"   ! sayfa okunamadı: {exc}")
            continue

        if not links:
            print("   ! bağlantı bulunamadı (sayfa adı değişmiş olabilir)")
            continue

        # Yalnızca veritabanında karşılığı olan kulüpler ilgilendiriyor.
        candidates = [t for t in links if club_key(t) in clubs]
        pages = fetch_wikitext(candidates)

        league_rows = 0
        for title, wikitext in pages.items():
            if "fs player" not in wikitext.lower():
                continue

            club = clubs.get(club_key(title))
            if not club:
                continue

            for name, country in parse_squad(wikitext):
                key = normalize(name)
                known = players.get(key)
                # Ülke ve görsel için ana tablodaki kayıt önceliklidir.
                row = (
                    key, known[0] if known else name, club,
                    (known[1] if known and known[1] else country) or None,
                    code, start_year, known[2] if known else None,
                    f"wikipedia:{title}", stamp,
                )
                if not args.dry_run:
                    conn.execute(
                        "INSERT OR REPLACE INTO squad_updates "
                        "(name_normalized, player_name, club_name, country, "
                        " competition_id, season, image_url, source, updated_at) "
                        "VALUES (?,?,?,?,?,?,?,?,?)", row,
                    )
                league_rows += 1

        conn.commit()
        total_rows += league_rows
        print(f"   {len(pages)} kulüp sayfası, {league_rows} kadro kaydı")

    print(f"\ntoplam {total_rows} kayıt" + (" (dry-run, yazılmadı)" if args.dry_run else ""))
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
