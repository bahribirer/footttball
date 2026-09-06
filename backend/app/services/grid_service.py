"""Tiki Taka Toe 3x3 tahtası için kulüp ve millet üretimi.

Eski `functions.py` mantığı korundu; iki hata düzeltildi:
  * `finalGrid` başarısızlıkta kendini çağırıyordu (özyineleme -> RecursionError
    riski). Artık sınırlı sayıda denemeyle döngü kullanılıyor.
  * Sorgular her çağrıda yeni bağlantı açıp kapatmıyor, ortak yardımcıyı kullanıyor.
"""

import random

from app.db.database import fetch_column
from app.db.reference_data import BANNED_KEYWORDS, BIG_TEAMS

MAX_GRID_ATTEMPTS = 25

LOCAL_NATION_BY_LEAGUE = {
    "TR1": "Turkey",
    "GB1": "England",
    "ES1": "Spain",
    "IT1": "Italy",
    "L1": "Germany",
    "FR1": "France",
}

_SEASON_FALLBACKS = (2025, 2024, 2023)


def _is_football_club(name: str) -> bool:
    lowered = name.lower()
    return not any(keyword.lower() in lowered for keyword in BANNED_KEYWORDS)


def clubs_for_league(league_id: str) -> list[str]:
    """Ligdeki kulüpleri döndürür. RANDOM tüm ligleri kapsar."""
    if not league_id:
        league_id = "RANDOM"

    if league_id == "RANDOM":
        db_id, operator = "%", "LIKE"
    else:
        db_id, operator = league_id, "="

    teams: list[str] = []
    for season in _SEASON_FALLBACKS:
        teams = fetch_column(
            "SELECT DISTINCT current_club_name FROM players "
            f"WHERE last_season = ? AND current_club_domestic_competition_id {operator} ?",
            (season, db_id),
        )
        teams = [team for team in teams if team and _is_football_club(team)]
        if len(teams) >= 3:
            break

    return teams


def pick_grid_clubs(league_id: str) -> list[str]:
    """Ligden 3 kulüp seçer; mümkünse en az 2'si büyük takımlardan olur."""
    teams = clubs_for_league(league_id)
    big_teams = [team for team in BIG_TEAMS.get(league_id, []) if team in teams]

    selected: list[str] = []
    if len(big_teams) >= 2:
        selected.extend(random.sample(big_teams, 2))
    elif big_teams:
        selected.append(big_teams[0])

    remaining = [team for team in teams if team not in selected]
    needed = 3 - len(selected)
    if len(remaining) >= needed:
        selected.extend(random.sample(remaining, needed))

    if len(selected) < 3:
        selected = random.sample(teams, 3) if len(teams) >= 3 else list(teams)

    random.shuffle(selected)
    return selected


def _nations_for_club(club: str) -> set[str]:
    rows = fetch_column(
        """SELECT DISTINCT country_of_citizenship FROM players
           WHERE current_club_name = ?
             AND last_season >= 2024
             AND country_of_citizenship IS NOT NULL
             AND country_of_citizenship != ''""",
        (club,),
    )
    return set(rows)


def build_grid(league_id: str) -> tuple[list[str], list[str]]:
    """(nations, clubs) üretir; her millet 3 kulübün hepsinde temsil edilir."""
    for _ in range(MAX_GRID_ATTEMPTS):
        clubs = pick_grid_clubs(league_id)
        if len(clubs) < 3:
            continue

        nation_sets = [_nations_for_club(club) for club in clubs]
        common = set.intersection(*nation_sets)
        if len(common) < 3:
            continue

        available = list(common)
        nations: list[str] = []

        local = LOCAL_NATION_BY_LEAGUE.get(league_id)
        if local and local in available:
            nations.append(local)
            available.remove(local)

        nations.extend(random.sample(available, 3 - len(nations)))
        random.shuffle(nations)
        return nations, clubs

    raise ValueError(f"'{league_id}' ligi için uygun tahta üretilemedi")
