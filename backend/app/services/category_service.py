"""Kategori Yarışı modunun kategori havuzu.

Her kategori bir SQL koşuluna karşılık gelir; böylece oyuncunun yazdığı isim
veritabanına sorularak kesin biçimde doğrulanabilir. Sabit listelerle yazılmış
kategoriler doğrulanamayacağı için tercih edilmedi.
"""

import random
from dataclasses import dataclass, field
from functools import lru_cache

from app.db.database import fetch_all, fetch_column
from app.services.player_service import _name_match, has_squad_layer, normalize

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

    # Kulüp/lig temelli kategorilerin `squad_updates` tablosundaki karşılığı.
    # Ana tablo son transfer dönemini kapsamadığı için, yeni takımına göre
    # doğru olan cevaplar yalnızca bu koşulla kabul edilebiliyor.
    squad_where: str | None = None
    squad_params: tuple = field(default_factory=tuple)

    # "easy" | "medium" | "hard" — dar kesişimler (lig × uyruk) oyuncuları
    # zorluyordu; seçenekler artık ağırlıklı olarak kolaylardan geliyor.
    difficulty: str = "medium"

    def to_dict(self) -> dict:
        return {"id": self.id, "label": self.label, "difficulty": self.difficulty}


def _c(cid: str, label: str, where: str, *params,
       squad_where: str | None = None, squad_params: tuple = (),
       difficulty: str = "medium") -> Category:
    return Category(id=cid, label=label, where=where, params=tuple(params),
                    squad_where=squad_where, squad_params=tuple(squad_params),
                    difficulty=difficulty)


@lru_cache(maxsize=1)
def _build_candidates() -> list[Category]:
    """Veritabanındaki gerçek değerlerden kategori adayları üretir."""
    candidates: list[Category] = []

    nations = [n for n in NATION_TR if n in set(fetch_column(
        "SELECT DISTINCT country_of_citizenship FROM players "
        "WHERE country_of_citizenship IS NOT NULL"
    ))]

    # Kulüp kategorileri güncel kadrosu bilinen takımlardan seçilir. Yalnızca
    # ana tablodaki kayıt sayısına bakıldığında liste, oyuncuların tanımadığı
    # kulüplerle doluyor ve Galatasaray gibi takımlar hiç çıkmıyordu.
    clubs: list[str] = []
    if has_squad_layer():
        clubs = fetch_column(
            """SELECT club_name FROM squad_updates
               GROUP BY club_name
               HAVING COUNT(*) >= 14
               ORDER BY COUNT(*) DESC
               LIMIT 80"""
        )

    if not clubs:
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
                difficulty="medium",
            ))

    # 2) Kulüp forması giymiş oyuncular
    for club in clubs:
        candidates.append(_c(
            f"club:{club}",
            f"{club} forması giymiş futbolcular",
            "current_club_name = ?",
            club,
            squad_where="club_name = ?", squad_params=(club,),
            difficulty="easy",
        ))

    # 3) Kulüp + ülke
    for club in clubs[:30]:
        for nation in random.sample(nations, min(8, len(nations))):
            candidates.append(_c(
                f"club_nat:{club}:{nation}",
                f"{club}'ta oynamış {NATION_TR[nation]} futbolcular",
                "current_club_name = ? AND country_of_citizenship = ?",
                club, nation,
                squad_where="club_name = ? AND country = ?",
                squad_params=(club, nation),
                difficulty="hard",
            ))

    # 4) Lig + ülke
    for league, league_tr in LEAGUE_TR.items():
        for nation in nations:
            candidates.append(_c(
                f"league_nat:{league}:{nation}",
                f"{league_tr}'de oynamış {NATION_TR[nation]} futbolcular",
                "current_club_domestic_competition_id = ? AND country_of_citizenship = ?",
                league, nation,
                squad_where="competition_id = ? AND country = ?",
                squad_params=(league, nation),
                difficulty="hard",
            ))

    # 5) Kolay kategoriler — tek geniş süzgeç.
    #
    # Kategoriler yalnızca kesişimlerden üretilince ("Eredivisie'de oynamış
    # Avusturyalı futbolcular") oyuncular tek isim bile bulmakta zorlanıyordu.
    # Aşağıdakiler havuzu geniş tutar.
    for nation in nations:
        candidates.append(_c(
            f"nat:{nation}", f"{NATION_TR[nation]} futbolcular",
            "country_of_citizenship = ?", nation,
            difficulty="easy",
        ))

    for league, league_tr in LEAGUE_TR.items():
        candidates.append(_c(
            f"league:{league}", f"{league_tr}'de oynamış futbolcular",
            "current_club_domestic_competition_id = ?", league,
            squad_where="competition_id = ?", squad_params=(league,),
            difficulty="easy",
        ))

    for position, tr in POSITION_TR.items():
        candidates.append(_c(
            f"pos:{position}", f"Herhangi bir {tr}",
            "position = ?", position,
            difficulty="easy",
        ))

    # Büyük futbol ülkeleri + mevki: geniş havuz, tanıdık isimler.
    for nation in ("Brazil", "Argentina", "France", "Spain", "Germany",
                   "Italy", "England", "Portugal", "Netherlands", "Turkey"):
        if nation not in nations:
            continue
        candidates.append(_c(
            f"nat_easy_att:{nation}",
            f"{NATION_TR[nation]} forvetler",
            "country_of_citizenship = ? AND position = 'Attack'", nation,
            difficulty="easy",
        ))
        candidates.append(_c(
            f"nat_easy_gk:{nation}",
            f"{NATION_TR[nation]} kaleciler",
            "country_of_citizenship = ? AND position = 'Goalkeeper'", nation,
            difficulty="medium",
        ))

    # 6) Özel nitelikler
    candidates += [
        _c("value:50m", "Piyasa değeri 50 milyon € üzeri futbolcular",
           "CAST(market_value_in_eur AS INTEGER) >= 50000000", difficulty="easy"),
        _c("value:80m", "Piyasa değeri 80 milyon € üzeri futbolcular",
           "CAST(market_value_in_eur AS INTEGER) >= 80000000", difficulty="medium"),
        _c("tall:195", "Boyu 195 cm ve üzeri futbolcular",
           "CAST(height_in_cm AS INTEGER) >= 195", difficulty="medium"),
        _c("tall:190gk", "Boyu 190 cm üzeri kaleciler",
           "CAST(height_in_cm AS INTEGER) >= 190 AND position = 'Goalkeeper'",
           difficulty="medium"),
    ]

    for league, league_tr in LEAGUE_TR.items():
        candidates.append(_c(
            f"left:{league}", f"{league_tr}'de oynamış solak futbolcular",
            "current_club_domestic_competition_id = ? AND foot = 'left'", league,
            difficulty="medium",
        ))
        candidates.append(_c(
            f"young:{league}", f"{league_tr}'de oynamış 2003 ve sonrası doğumlular",
            "current_club_domestic_competition_id = ? AND date_of_birth >= '2003-01-01'",
            league,
            difficulty="medium",
        ))

    for nation in nations:
        candidates.append(_c(
            f"nat_left:{nation}", f"Solak {NATION_TR[nation]} futbolcular",
            "country_of_citizenship = ? AND foot = 'left'", nation,
            difficulty="hard",
        ))

    return candidates


def _pool_size(category: Category) -> int:
    row = fetch_all(
        f"SELECT COUNT(DISTINCT name) AS total FROM players WHERE {category.where}",
        category.params,
    )
    return row[0]["total"] if row else 0


# Sunulan seçeneklerin zorluk dağılımı: çoğunluk kolay, en fazla bir zor.
# Tümü kesişimlerden seçilince oyuncular tek isim bile bulamıyordu.
DIFFICULTY_MIX = ("easy", "easy", "medium", "easy", "medium", "hard",
                  "easy", "medium", "easy", "medium")


def random_categories(count: int = 3) -> list[Category]:
    """Havuzu yeterli, zorluğu dengeli rastgele kategoriler döndürür."""
    candidates = _build_candidates()
    by_difficulty: dict[str, list[Category]] = {}
    for category in candidates:
        by_difficulty.setdefault(category.difficulty, []).append(category)
    for bucket in by_difficulty.values():
        random.shuffle(bucket)

    cursors = {level: 0 for level in by_difficulty}
    chosen: list[Category] = []
    seen: set[str] = set()

    def take(level: str) -> Category | None:
        """İstenen zorluktan, havuzu yeterli ilk kategoriyi verir."""
        bucket = by_difficulty.get(level, [])
        while cursors.get(level, 0) < len(bucket):
            category = bucket[cursors[level]]
            cursors[level] += 1
            if category.id in seen:
                continue
            if _pool_size(category) >= MIN_POOL_SIZE:
                return category
        return None

    for level in DIFFICULTY_MIX:
        if len(chosen) == count:
            break
        category = take(level)
        if category:
            chosen.append(category)
            seen.add(category.id)

    # Karışım yetmezse kalan yerler herhangi bir zorluktan tamamlanır.
    for level in ("easy", "medium", "hard"):
        while len(chosen) < count:
            category = take(level)
            if not category:
                break
            chosen.append(category)
            seen.add(category.id)

    if not chosen:  # her ihtimale karşı güvenli varsayılan
        chosen = [_c("fallback", "Brezilyalı futbolcular",
                     "country_of_citizenship = ?", "Brazil", difficulty="easy")]
    return chosen


def get_category(category_id: str) -> Category | None:
    for category in _build_candidates():
        if category.id == category_id:
            return category
    return None


def verify_answer(category: Category, player_name: str) -> str | None:
    """İsim kategoriye uyuyorsa oyuncunun kanonik adını, uymuyorsa None döner.

    Kulüp ve lig temelli kategorilerde ana tablo yetmeyebilir: son transfer
    döneminde takım değiştiren oyuncular ancak güncel kadro katmanında
    görünür. O katman da sorgulanmazsa doğru cevaplar reddediliyordu.
    """
    if not player_name.strip():
        return None

    key = normalize(player_name)
    where, params = _name_match("name_normalized", key)

    # Oyuncular futbolcuyu çoğunlukla soyadıyla yazıyor; tam ad şartı
    # doğru cevapları reddediyordu.
    rows = fetch_all(
        f"""SELECT DISTINCT name FROM players
            WHERE {where} AND ({category.where})
            ORDER BY CAST(COALESCE(highest_market_value_in_eur, 0) AS INTEGER) DESC""",
        (*params, *category.params),
    )
    if rows:
        return rows[0]["name"]

    if not category.squad_where or not has_squad_layer():
        return None

    rows = fetch_all(
        f"""SELECT DISTINCT player_name AS name FROM squad_updates
            WHERE {where} AND ({category.squad_where})""",
        (*params, *category.squad_params),
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
