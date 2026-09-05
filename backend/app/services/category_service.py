"""Kategori Yarışı modunun kategori havuzu.

Her kategori bir SQL koşuluna karşılık gelir; böylece oyuncunun yazdığı isim
veritabanına sorularak kesin biçimde doğrulanabilir. Sabit listelerle yazılmış
kategoriler doğrulanamayacağı için tercih edilmedi.
"""

import random
from dataclasses import dataclass, field
from functools import lru_cache

from app.db.database import fetch_all, fetch_column
from app.services.player_service import normalize

# Görünen adlar
POSITION_TR = {
    "Goalkeeper": "kaleci",
    "Defender": "defans oyuncusu",
    "Midfield": "orta saha oyuncusu",
    "Attack": "forvet",
}

SUB_POSITION_TR = {
    "Centre-Back": "stoper",
    "Left-Back": "sol bek",
    "Right-Back": "sağ bek",
    "Defensive Midfield": "ön libero",
    "Central Midfield": "merkez orta saha",
    "Attacking Midfield": "ofansif orta saha",
    "Left Winger": "sol kanat",
    "Right Winger": "sağ kanat",
    "Centre-Forward": "santrfor",
}

NATION_TR = {
    "Brazil": "Brezilyalı", "Argentina": "Arjantinli", "France": "Fransız",
    "Spain": "İspanyol", "Germany": "Alman", "Italy": "İtalyan",
    "England": "İngiliz", "Portugal": "Portekizli", "Netherlands": "Hollandalı",
    "Belgium": "Belçikalı", "Croatia": "Hırvat", "Turkey": "Türk",
    "Uruguay": "Uruguaylı", "Colombia": "Kolombiyalı", "Serbia": "Sırp",
    "Denmark": "Danimarkalı", "Sweden": "İsveçli", "Norway": "Norveçli",
    "Poland": "Polonyalı", "Switzerland": "İsviçreli", "Nigeria": "Nijeryalı",
    "Ghana": "Ganalı", "Senegal": "Senegalli", "Morocco": "Faslı",
    "Ivory Coast": "Fildişili", "Cameroon": "Kamerunlu", "Algeria": "Cezayirli",
    "Japan": "Japon", "Korea, South": "Güney Koreli", "United States": "Amerikalı",
    "Mexico": "Meksikalı", "Chile": "Şilili", "Austria": "Avusturyalı",
    "Czech Republic": "Çek", "Greece": "Yunan", "Ukraine": "Ukraynalı",
    "Russia": "Rus", "Scotland": "İskoç", "Wales": "Galli", "Ireland": "İrlandalı",
    "Slovakia": "Slovak", "Slovenia": "Sloven", "Hungary": "Macar",
    "Romania": "Rumen", "Egypt": "Mısırlı",
}

LEAGUE_TR = {
    "GB1": "Premier Lig", "ES1": "La Liga", "IT1": "Serie A",
    "L1": "Bundesliga", "FR1": "Ligue 1", "TR1": "Süper Lig",
    "PO1": "Portekiz Ligi", "NL1": "Eredivisie",
}

MIN_POOL_SIZE = 12   # kategori en az bu kadar oyuncu içermeli
CATEGORY_CHOICES = 40


@dataclass(frozen=True)
class Category:
    id: str
    label: str
    where: str
    params: tuple = field(default_factory=tuple)

    def to_dict(self) -> dict:
        return {"id": self.id, "label": self.label}


def _c(cid: str, label: str, where: str, *params) -> Category:
    return Category(id=cid, label=label, where=where, params=tuple(params))


@lru_cache(maxsize=1)
def _build_candidates() -> list[Category]:
    """Veritabanındaki gerçek değerlerden kategori adayları üretir."""
    candidates: list[Category] = []

    nations = [n for n in NATION_TR if n in set(fetch_column(
        "SELECT DISTINCT country_of_citizenship FROM players "
        "WHERE country_of_citizenship IS NOT NULL"
    ))]

    clubs = fetch_column(
        """SELECT current_club_name FROM players
           WHERE current_club_name IS NOT NULL AND current_club_name != ''
           GROUP BY current_club_name
           HAVING COUNT(DISTINCT name) >= 40
           ORDER BY COUNT(DISTINCT name) DESC
           LIMIT 60"""
    )

    # 1) Ülke + mevki
    for nation in nations:
        for position, tr in POSITION_TR.items():
            candidates.append(_c(
                f"nat_pos:{nation}:{position}",
                f"{NATION_TR[nation]} {tr}",
                "country_of_citizenship = ? AND position = ?",
                nation, position,
            ))

    # 2) Kulüp forması giymiş oyuncular
    for club in clubs:
        candidates.append(_c(
            f"club:{club}",
            f"{club} forması giymiş futbolcular",
            "current_club_name = ?",
            club,
        ))

    # 3) Kulüp + ülke
    for club in clubs[:30]:
        for nation in random.sample(nations, min(8, len(nations))):
            candidates.append(_c(
                f"club_nat:{club}:{nation}",
                f"{club}'ta oynamış {NATION_TR[nation]} futbolcular",
                "current_club_name = ? AND country_of_citizenship = ?",
                club, nation,
            ))

    # 4) Lig + ülke
    for league, league_tr in LEAGUE_TR.items():
        for nation in nations:
            candidates.append(_c(
                f"league_nat:{league}:{nation}",
                f"{league_tr}'de oynamış {NATION_TR[nation]} futbolcular",
                "current_club_domestic_competition_id = ? AND country_of_citizenship = ?",
                league, nation,
            ))

    # 5) Özel nitelikler
    candidates += [
        _c("value:50m", "Piyasa değeri 50 milyon € üzeri futbolcular",
           "CAST(market_value_in_eur AS INTEGER) >= 50000000"),
        _c("value:80m", "Piyasa değeri 80 milyon € üzeri futbolcular",
           "CAST(market_value_in_eur AS INTEGER) >= 80000000"),
        _c("tall:195", "Boyu 195 cm ve üzeri futbolcular",
           "CAST(height_in_cm AS INTEGER) >= 195"),
        _c("tall:190gk", "Boyu 190 cm üzeri kaleciler",
           "CAST(height_in_cm AS INTEGER) >= 190 AND position = 'Goalkeeper'"),
    ]

    for league, league_tr in LEAGUE_TR.items():
        candidates.append(_c(
            f"left:{league}", f"{league_tr}'de oynamış solak futbolcular",
            "current_club_domestic_competition_id = ? AND foot = 'left'", league,
        ))
        candidates.append(_c(
            f"young:{league}", f"{league_tr}'de oynamış 2003 ve sonrası doğumlular",
            "current_club_domestic_competition_id = ? AND date_of_birth >= '2003-01-01'",
            league,
        ))

    for nation in nations:
        candidates.append(_c(
            f"nat_left:{nation}", f"Solak {NATION_TR[nation]} futbolcular",
            "country_of_citizenship = ? AND foot = 'left'", nation,
        ))

    return candidates


def _pool_size(category: Category) -> int:
    row = fetch_all(
        f"SELECT COUNT(DISTINCT name) AS total FROM players WHERE {category.where}",
        category.params,
    )
    return row[0]["total"] if row else 0


def random_categories(count: int = 3) -> list[Category]:
    """Yeterli sayıda oyuncu barındıran rastgele kategoriler döndürür."""
    candidates = _build_candidates()
    chosen: list[Category] = []
    seen: set[str] = set()

    for category in random.sample(candidates, min(CATEGORY_CHOICES, len(candidates))):
        if category.id in seen:
            continue
        if _pool_size(category) >= MIN_POOL_SIZE:
            chosen.append(category)
            seen.add(category.id)
        if len(chosen) == count:
            break

    if not chosen:  # her ihtimale karşı güvenli varsayılan
        chosen = [_c("fallback", "Brezilyalı futbolcular",
                     "country_of_citizenship = ?", "Brazil")]
    return chosen


def get_category(category_id: str) -> Category | None:
    for category in _build_candidates():
        if category.id == category_id:
            return category
    return None


def verify_answer(category: Category, player_name: str) -> str | None:
    """İsim kategoriye uyuyorsa oyuncunun kanonik adını, uymuyorsa None döner."""
    if not player_name.strip():
        return None

    rows = fetch_all(
        f"""SELECT DISTINCT name FROM players
            WHERE name_normalized = ? AND ({category.where})""",
        (normalize(player_name), *category.params),
    )
    return rows[0]["name"] if rows else None


def sample_answers(category: Category, limit: int = 5) -> list[str]:
    """Süre dolduğunda gösterilecek örnek doğru cevaplar."""
    rows = fetch_all(
        f"""SELECT DISTINCT name FROM players
            WHERE {category.where}
            ORDER BY CAST(COALESCE(market_value_in_eur, '0') AS INTEGER) DESC
            LIMIT ?""",
        (*category.params, limit),
    )
    return [row["name"] for row in rows]
