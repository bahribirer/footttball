"""Botun futbol bilgisi.

Bot hile yapmaz: sunucuda yaşıyor olsa da bir turun çözümüne bakmaz.
Buradaki fonksiyonlar, bir insanın da yapabileceği şeyi yapar — "bu kulüp
ve bu ülkeye uyan bir futbolcu kim?", "şu kulüplerde sırayla oynamış kim
var?" diye veritabanına sorar. Zorluk, botun bunu ne kadar sık ve ne kadar
hızlı yapabildiğini belirler.
"""

from __future__ import annotations

import random

from app.db.database import fetch_all
from app.services import category_service
from app.services.player_service import normalize

# Zorluk → (doğru bilme olasılığı, düşünme süresi aralığı sn)
DIFFICULTY = {
    "easy":   {"accuracy": 0.45, "think": (4.0, 9.0)},
    "medium": {"accuracy": 0.70, "think": (2.5, 6.0)},
    "hard":   {"accuracy": 0.92, "think": (1.5, 3.5)},
}


def think_time(difficulty: str) -> float:
    lo, hi = DIFFICULTY.get(difficulty, DIFFICULTY["medium"])["think"]
    return random.uniform(lo, hi)


def knows(difficulty: str) -> bool:
    """Bu hamlede bot doğru cevabı 'biliyor' mu (zar)."""
    return random.random() < DIFFICULTY.get(difficulty, DIFFICULTY["medium"])["accuracy"]


def player_for_cell(nation: str, club: str) -> str | None:
    """Ülke × kulüp kesişimine uyan bir futbolcu."""
    rows = fetch_all(
        """SELECT DISTINCT name FROM players
           WHERE country_of_citizenship = ? AND current_club_name LIKE ?
           ORDER BY CAST(COALESCE(highest_market_value_in_eur,'0') AS INTEGER) DESC
           LIMIT 8""",
        (nation, f"%{club}%"),
    )
    if not rows:
        rows = fetch_all(
            """SELECT DISTINCT player_name AS name FROM club_history
               WHERE country = ? AND club_name LIKE ? LIMIT 8""",
            (nation, f"%{club}%"),
        )
    if not rows:
        return None
    # En tanınmışlardan rastgele; hep aynı ismi söylemesin.
    return random.choice(rows[: max(1, len(rows) // 2 + 1)])["name"]


def random_wrong_name() -> str:
    """Yanlış tahmin için gerçek ama alakasız bir futbolcu adı."""
    rows = fetch_all(
        "SELECT name FROM players WHERE last_season >= 2015 ORDER BY RANDOM() LIMIT 1"
    )
    return rows[0]["name"] if rows else "Bilinmeyen Oyuncu"


def guess_from_career(clubs: list[str], exclude: set[str]) -> list[str]:
    """Şu kulüplerde bu sırayla oynamış futbolcular.

    İnsan da kariyer yolunu görünce böyle düşünür: "Grêmio'dan PSG'ye,
    sonra Barcelona... Ronaldinho!" Aday sayısı azaldıkça bot emin olur.
    """
    if not clubs:
        return []
    # İlk kulübe uyanlarla başla, her sonraki kulüple daralt.
    keys = f"%{clubs[0]}%"
    candidates = {
        r["name_normalized"]: r["player_name"]
        for r in fetch_all(
            "SELECT DISTINCT name_normalized, player_name FROM club_history WHERE club_name LIKE ?",
            (keys,),
        )
    }
    for club in clubs[1:]:
        if not candidates:
            break
        keep = {
            r["name_normalized"]
            for r in fetch_all(
                "SELECT DISTINCT name_normalized FROM club_history WHERE club_name LIKE ?",
                (f"%{club}%",),
            )
        }
        candidates = {k: v for k, v in candidates.items() if k in keep}
    return [v for k, v in candidates.items() if k not in exclude][:20]


def answer_for_category(category_id: str, used: set[str], limit: int = 30) -> str | None:
    category = category_service.get_category(category_id)
    if category is None:
        return None
    names = category_service.sample_answers(category, limit=limit)
    fresh = [n for n in names if normalize(n) not in used]
    return random.choice(fresh) if fresh else None


BOT_NAMES = ["Robo Kaleci", "Otomatik Orta Saha", "Silikon Forvet", "Bot Pirlo", "AI Xavi"]


def pick_name(difficulty: str) -> str:
    suffix = {"easy": " (kolay)", "medium": "", "hard": " (zor)"}.get(difficulty, "")
    return random.choice(BOT_NAMES) + suffix
