"""Oyuncu arama ve tahmin doğrulama."""

import unicodedata

from app.db.database import fetch_all, fetch_one
from app.services.country_service import flag_url

SEARCH_LIMIT = 40
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


def _name_match(column: str, key: str) -> tuple[str, list]:
    """Tam ad / soyad / ara isim eşleşmesi için SQL koşulu ve parametreleri."""
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
        key = (row["name"], row["country_of_citizenship"])
        if key in seen:
            continue
        seen.add(key)

        club = row["current_club_name"]
        results.append({
            "name": row["name"],
            "country": row["country_of_citizenship"],
            "club": club,
            "clubs": club_history(row["name"]),
            "flag_url": flag_url(row["country_of_citizenship"]),
            "logo_url": f"{base_url}/api/v1/logo_image/{club}" if club else None,
            "image_url": row["image_url"],
            "position": row["position"],
        })

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
    if not row:
        return None

    return {
        "name": row["name"],
        "image_url": row["image_url"],
        "club": row["current_club_name"],
        "country": row["country_of_citizenship"],
    }
