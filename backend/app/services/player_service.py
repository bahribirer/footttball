"""Oyuncu arama ve tahmin doğrulama."""

import functools
import math
import unicodedata

from app.db.database import fetch_all, fetch_one
from app.services.country_service import flag_url

SEARCH_LIMIT = 40
LEGEND_SLOTS = 3       # öneri listesinde efsanelere ayrılan yer
LEGEND_MIN_YEAR = 1970 # bundan önce bitmiş kariyerler öneride çıkmaz
SUGGESTION_CLUBS = 4   # öneride gösterilecek en fazla kulüp sayısı


# NFKD ayrıştırması bu harfleri çözemediği için elle karşılık verilir;
# aksi halde "Calhanoglu" yazan oyuncu "Çalhanoğlu" kaydını bulamıyor.
_TRANSLIT = str.maketrans({
    "ı": "i", "İ": "i", "ß": "ss", "ø": "o", "Ø": "o", "đ": "d", "Đ": "d",
    "ł": "l", "Ł": "l", "æ": "ae", "Æ": "ae", "œ": "oe", "Œ": "oe",
    "ð": "d", "Ð": "d", "þ": "th", "Þ": "th", "ħ": "h", "ŋ": "n",
})


def normalize(text: str | None) -> str:
    """Aksan ve büyük/küçük harf farklarını yok sayan karşılaştırma anahtarı."""
    if not text:
        return ""
    translated = text.translate(_TRANSLIT)
    decomposed = unicodedata.normalize("NFKD", translated)
    stripped = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return " ".join(stripped.lower().split())


_layer_cache: dict[str, bool] = {}


def _has_table(table: str) -> bool:
    """Ek veri katmanı kurulu mu (bir kez sorgulanır)."""
    if table not in _layer_cache:
        row = fetch_one(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table,)
        )
        _layer_cache[table] = row is not None
    return _layer_cache[table]


def has_squad_layer() -> bool:
    """Güncel kadro katmanı (`scripts/sync_current_squads.py`)."""
    return _has_table("squad_updates")


def has_history_layer() -> bool:
    """Tarihsel kadro katmanı (`scripts/sync_club_history.py`).

    Ana tablo eski dönemleri ve pek çok oyuncunun uyruğunu içermiyor;
    Fatih Tekke'nin Trabzonspor yılları gibi doğru cevaplar bu yüzden
    reddediliyordu.
    """
    return _has_table("club_history")


# --- ad eşleştirme ---------------------------------------------------------
#
# Oyuncular futbolcuyu çoğunlukla soyadıyla yazıyor ("Messi", "Haaland").
# Eşleştirme yalnızca tam ada bakarsa bu cevaplar reddediliyordu. Aşağıdaki
# yardımcılar adın tamamını, soyadını ya da içindeki herhangi bir kelimeyi
# kabul eden bir koşul üretir; birden fazla aday çıkarsa en tanınmış oyuncu
# (piyasa değeri en yüksek) seçilir.


def has_token_index() -> bool:
    return _has_table("name_tokens")


def _name_match(column: str, key: str) -> tuple[str, list]:
    """Tam ad / soyad / ara isim eşleşmesi için SQL koşulu ve parametreleri.

    Önceki sürüm baştan joker içeren `LIKE '% messi'` kullanıyordu. Bu kalıp
    indeks kullanamıyor: SQLite her sorguda tabloyu baştan sona tarıyordu —
    ölçümde players 43 ms, club_history 64 ms, tek doğrulama üç katmanda
    ~110 ms. `name_tokens` isimleri kelimelerine ayırıp indekslediği için
    arama eşitlik sorgusuna dönüşüyor.

    Tablo yoksa (henüz üretilmemişse) eski davranışa düşülür; böylece
    build_name_tokens.py çalıştırılmadan da sistem doğru sonuç verir.
    """
    if has_token_index():
        return (
            f"({column} = ? OR {column} IN "
            "(SELECT name_normalized FROM name_tokens WHERE token = ?))",
            [key, key],
        )
    return (
        f"({column} = ? OR {column} LIKE ? OR {column} LIKE ? OR {column} LIKE ?)",
        [key, f"% {key}", f"{key} %", f"% {key} %"],
    )


def _name_rank(column: str, key: str) -> tuple[str, list]:
    """Tam ad en önce, sonra soyad eşleşmesi, en sonda ara isimler."""
    return (
        f"CASE WHEN {column} = ? THEN 0 WHEN {column} LIKE ? THEN 1 ELSE 2 END",
        [key, f"% {key}"],
    )


def verify_player(player_name: str, nationality: str, club: str) -> bool:
    """Oyuncunun verilen millet + kulüp ikilisine uyup uymadığını kontrol eder.

    Eski sürümde isim karşılaştırması büyük/küçük harfe duyarlıydı: SQL `LIKE`
    eşleşse bile Python tarafındaki `==` kontrolü yüzünden doğru tahminler
    reddedilebiliyordu. Artık normalize edilmiş karşılaştırma yapılıyor.

    Ana tabloda bulunamayan eşleşmeler güncel kadro katmanında aranır; böylece
    son transfer döneminde takım değiştiren oyuncular da kabul edilir.
    """
    if not player_name or not nationality or not club:
        return False

    key = normalize(player_name)
    where, params = _name_match("name_normalized", key)

    rows = fetch_all(
        f"""SELECT DISTINCT name FROM players
            WHERE {where}
              AND country_of_citizenship = ?
              AND current_club_name LIKE ?""",
        (*params, nationality, f"%{club}%"),
    )
    if rows:
        return True

    if not has_squad_layer():
        return False

    rows = fetch_all(
        f"""SELECT 1 FROM squad_updates
            WHERE {where}
              AND country = ?
              AND club_name LIKE ?""",
        (*params, nationality, f"%{club}%"),
    )
    if rows:
        return True

    if not has_history_layer():
        return False

    rows = fetch_all(
        f"""SELECT 1 FROM club_history
            WHERE {where}
              AND country = ?
              AND club_name LIKE ?""",
        (*params, nationality, f"%{club}%"),
    )
    return bool(rows)


def club_history(player_name: str) -> list[str]:
    """Oyuncunun oynadığı kulüpler, güncelden eskiye.

    Oyun eski takımları da kabul ettiği için öneri listesinde kulüp geçmişi
    gösterilir; oyuncu "Haaland – Man City, Dortmund" bilgisini görerek
    hamlesini seçebilir. Güncel kadro katmanındaki kulüp en başta gelir.
    """
    key = normalize(player_name)
    clubs: list[str] = []

    if has_squad_layer():
        rows = fetch_all(
            "SELECT club_name FROM squad_updates WHERE name_normalized = ?", (key,)
        )
        clubs.extend(row["club_name"] for row in rows)

    rows = fetch_all(
        """SELECT current_club_name, MAX(last_season) AS season
           FROM players
           WHERE name_normalized = ?
             AND current_club_name IS NOT NULL AND current_club_name != ''
           GROUP BY current_club_name
           ORDER BY season DESC
           LIMIT ?""",
        (key, SUGGESTION_CLUBS),
    )
    clubs.extend(row["current_club_name"] for row in rows)

    # Ana tabloda olmayan eski kulüpler tarihsel katmandan tamamlanır.
    if has_history_layer() and len(clubs) < SUGGESTION_CLUBS:
        rows = fetch_all(
            """SELECT club_name FROM club_history
               WHERE name_normalized = ?
               ORDER BY COALESCE(end_year, start_year, 0) DESC
               LIMIT ?""",
            (key, SUGGESTION_CLUBS),
        )
        clubs.extend(row["club_name"] for row in rows)

    # Sıra korunarak yinelenenler ayıklanır.
    seen: set[str] = set()
    unique = [c for c in clubs if c and not (c in seen or seen.add(c))]
    return unique[:SUGGESTION_CLUBS]


# Ün ölçüsü için "büyük kulüp" anahtarları (küçük harf, aksansız; kulüp
# adında geçmesi yeter). Tarihçede kayıt sayısı ölçü olmuyor: Parma-Torino
# gezmiş adsız bir oyuncu Ronaldinho'nun üstüne çıkıyordu.
ELITE_CLUB_KEYS = (
    "barcelona", "real madrid", "atletico madrid", "atletico de madrid", "sevilla",
    "valencia", "villarreal", "athletic", "real sociedad", "deportivo la coruna",
    "manchester united", "manchester city", "liverpool", "chelsea", "arsenal",
    "tottenham", "everton", "leeds", "newcastle", "aston villa", "west ham",
    "juventus", "milan", "internazionale", "inter milan", "napoli", "roma", "lazio",
    "fiorentina", "bayern", "dortmund", "leverkusen", "schalke", "monchengladbach",
    "hamburg", "werder", "paris saint", "marseille", "lyon", "monaco", "saint-etienne",
    "ajax", "psv", "feyenoord", "benfica", "porto", "sporting", "celtic", "rangers",
    "anderlecht", "club brugge", "galatasaray", "fenerbahce", "besiktas", "trabzonspor",
    "boca juniors", "river plate", "independiente", "san lorenzo", "racing club",
    "flamengo", "santos", "sao paulo", "palmeiras", "corinthians", "gremio",
    "internacional", "cruzeiro", "atletico mineiro", "vasco", "fluminense", "botafogo",
    "penarol", "nacional", "colo-colo", "club america", "chivas", "cruz azul",
    "zenit", "spartak", "cska", "dynamo kyiv", "dynamo kiev", "shakhtar", "red star",
    "crvena zvezda", "partizan", "olympiacos", "panathinaikos", "aek", "steaua",
    "al nassr", "al hilal", "al ittihad", "al ahly", "inter miami", "la galaxy",
    "kashima", "urawa", "jeonbuk",
)


@functools.lru_cache(maxsize=1)
def _club_weights() -> dict[str, float]:
    """Kulüp → büyük kulüp mü (1.0) değil mi (0.0)."""
    try:
        rows = fetch_all("SELECT DISTINCT club_name FROM club_history")
    except Exception:
        return {}
    out = {}
    for r in rows:
        name = normalize(r["club_name"])
        out[r["club_name"]] = 1.0 if any(k in name for k in ELITE_CLUB_KEYS) else 0.0
    return out


def photo_for(name_normalized: str | None, current: str | None = None) -> str | None:
    """Fotoğraf: ana tablodaki geçerliyse o, yoksa Wikidata katmanı.

    `player_photos` (scripts/fetch_player_photos.py) efsaneler ve ana
    tabloda fotoğrafı olmayan güncel oyuncular için Commons adresi tutar.
    """
    if current and "default" not in current:
        return current
    if not name_normalized or not _has_table("player_photos"):
        return current or None
    row = fetch_one("SELECT image_url FROM player_photos WHERE name_normalized = ?", (name_normalized,))
    return (row["image_url"] if row and row["image_url"] else None) or current or None


def search_legends(key: str, limit: int = LEGEND_SLOTS) -> list[dict]:
    """`players`'ta olmayan ama tarihçede bulunan (efsane) oyuncular.

    Ana tablo yalnız güncel dönemi kapsıyor; Ronaldinho, Zidane gibi isimler
    ancak Wikidata tarihçesinde var. Öneri listesinde onlar da görünmeli ki
    "bu oyuncu yok" izlenimi oluşmasın.
    """
    if not key or len(key) < 3 or not has_history_layer() or not _has_table("name_tokens"):
        return []
    rows = fetch_all(
        """SELECT ch.name_normalized, ch.player_name, ch.country, ch.club_name, ch.start_year
           FROM (SELECT DISTINCT name_normalized FROM name_tokens WHERE token LIKE ? LIMIT 400) t
           JOIN club_history ch ON ch.name_normalized = t.name_normalized
           WHERE NOT EXISTS (SELECT 1 FROM players p WHERE p.name_normalized = ch.name_normalized)""",
        (f"{key}%",),
    )
    weights = _club_weights()
    grouped: dict[str, dict] = {}
    for r in rows:
        g = grouped.setdefault(r["name_normalized"], {
            "name": r["player_name"], "country": r["country"], "clubs": {},
            "last_year": 0, "last_club": None,
        })
        g["clubs"][r["club_name"]] = weights.get(r["club_name"], 0.0)
        year = r["start_year"] or 0
        if year >= g["last_year"]:
            g["last_year"], g["last_club"] = year, r["club_name"]
        if r["country"] and not g["country"]:
            g["country"] = r["country"]

    ranked = []
    for norm, g in grouped.items():
        if g["last_year"] < LEGEND_MIN_YEAR:
            continue
        # Büyük kulüp sayısı; aynı kulübün iki adı (Milan AC / AC Milan)
        # ayrı sayılmasın diye normalize edilerek tekilleştirilir.
        big = {normalize(c) for c, w in g["clubs"].items() if w > 0}
        fame = len({" ".join(sorted(x.split())) for x in big})
        if fame == 0 and norm != key:
            continue
        g["fame"] = fame
        ranked.append((0 if norm == key else 1, -fame, -g["last_year"], norm, g))
    ranked.sort(key=lambda t: t[:4])
    return [
        {"name": g["name"], "country": g["country"], "club": g["last_club"],
         "image_url": photo_for(norm), "position": None, "legend": True, "fame": g["fame"]}
        for _, _, _, norm, g in ranked[:limit]
    ]


def search_players(name: str, base_url: str) -> list[dict]:
    """Otomatik tamamlama için oyuncu arar; her oyuncu bir kez döner."""
    if not name or len(name) < 2:
        return []

    # Arama aksansız kolon üzerinden yapılır: "guler" yazan oyuncu
    # "Arda Güler" kaydını da bulur.
    #
    # Sıralama: önce adın başıyla eşleşenler, sonra soyadın (herhangi bir
    # kelimenin) başıyla eşleşenler, en sonda ortada geçenler. Oyuncular
    # çoğunlukla soyadıyla arandığı için "sane" araması Leroy Sané'yi
    # Alassane Ndao'nun üstünde göstermelidir. Aynı öncelikte güncel
    # sezondakiler öne alınır.
    key = normalize(name)
    rows = fetch_all(
        """SELECT name, country_of_citizenship, current_club_name,
                  current_club_domestic_competition_id, image_url, position,
                  last_season, highest_market_value_in_eur
           FROM players
           WHERE name_normalized LIKE ?
           ORDER BY CASE
                      WHEN name_normalized LIKE ? OR name_normalized LIKE ? THEN 0
                      ELSE 1
                    END,
                    CAST(COALESCE(highest_market_value_in_eur, 0) AS INTEGER) DESC,
                    last_season DESC,
                    name ASC
           LIMIT ?""",
        (f"%{key}%", f"{key}%", f"% {key}%", SEARCH_LIMIT),
    )

    results: list[dict] = []
    seen: set[tuple[str, str]] = set()

    for row in rows:
        ident = (row["name"], row["country_of_citizenship"])
        if ident in seen:
            continue
        seen.add(ident)

        club = row["current_club_name"]
        results.append({
            "name": row["name"],
            "country": row["country_of_citizenship"],
            "club": club,
            "clubs": club_history(row["name"]),
            "flag_url": flag_url(row["country_of_citizenship"]),
            "logo_url": f"{base_url}/api/v1/logo_image/{club}" if club else None,
            "image_url": photo_for(normalize(row["name"]), row["image_url"]),
            "position": row["position"],
        })

    # Efsaneler: ana tabloda olmayan tarihçe oyuncuları. İstemci ilk altıyı
    # gösterdiği için listeye üçüncü sıradan girerler; adı birebir aranan
    # ("ronaldinho") ya da çok büyük kulüp gezmiş efsane en üste çıkar.
    legends = search_legends(key)
    if legends:
        results = results[: max(0, SEARCH_LIMIT - len(legends))]
        top, rest = [], []
        for item in legends:
            club = item["club"]
            entry = {
                **item,
                "clubs": club_history(item["name"]),
                "flag_url": flag_url(item["country"]),
                "logo_url": f"{base_url}/api/v1/logo_image/{club}" if club else None,
            }
            famous = normalize(item["name"]) == key or item["fame"] >= 5
            (top if famous else rest).append(entry)
        cut = min(len(results), 3)
        results = top + results[:cut] + rest + results[cut:]

    return results


def player_exists(player_name: str) -> str | None:
    """Oyuncu veritabanında varsa kanonik adını döndürür."""
    found = find_player(player_name)
    return found["name"] if found else None


def find_player(player_name: str) -> dict | None:
    """Oyuncunun kanonik adı, görseli, kulübü ve ülkesi.

    Arayüz kabul edilen cevapları oyuncu fotoğrafıyla gösterdiği için
    doğrulama sonucuyla birlikte bu alanlar da döndürülür.
    """
    if not player_name or not player_name.strip():
        return None

    key = normalize(player_name)
    where, where_params = _name_match("name_normalized", key)
    rank, rank_params = _name_rank("name_normalized", key)

    # Aynı ada birden çok oyuncu uyabilir ("Silva"); en tanınmışı seçilir.
    row = fetch_one(
        f"""SELECT name, image_url, current_club_name, country_of_citizenship
            FROM players
            WHERE {where}
            ORDER BY {rank},
                     CAST(COALESCE(highest_market_value_in_eur, 0) AS INTEGER) DESC,
                     last_season DESC
            LIMIT 1""",
        (*where_params, *rank_params),
    )
    if row:
        return {
            "name": row["name"],
            "image_url": photo_for(normalize(row["name"]), row["image_url"]),
            "club": row["current_club_name"],
            "country": row["country_of_citizenship"],
        }

    # Efsane: yalnız tarihçede var (fotoğraf yok).
    if not has_history_layer():
        return None
    where, where_params = _name_match("name_normalized", key)
    hist = fetch_one(
        f"""SELECT player_name, country, club_name
            FROM club_history WHERE {where}
            ORDER BY start_year DESC LIMIT 1""",
        where_params,
    )
    if not hist:
        return None
    return {
        "name": hist["player_name"],
        "image_url": photo_for(normalize(hist["player_name"])),
        "club": hist["club_name"],
        "country": hist["country"],
    }
