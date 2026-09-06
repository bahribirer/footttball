"""Oyun modlarının ortak kullandığı kulüp / millet havuzları.

Oyunun tanınmış takım ve ülkelerle oynanması için elle seçilmiş bir havuz
kullanılır; havuz veritabanıyla kesiştirilerek yalnızca kaydı olan isimler kalır.
"""

import random
from functools import lru_cache

from app.db.database import fetch_all
from app.db.reference_data import BIG_TEAMS

# Oyuncuların tanıyacağı kulüpler. Veritabanındaki kanonik adlarla birebir aynı.
POPULAR_CLUBS = [
    # İngiltere
    "Manchester City", "Arsenal FC", "Liverpool FC", "Manchester United",
    "Chelsea FC", "Tottenham Hotspur", "Newcastle United", "Aston Villa",
    "Everton FC", "West Ham United", "Leicester City",
    # İspanya
    "Real Madrid", "FC Barcelona", "Atletico de Madrid", "Sevilla FC",
    "Valencia CF", "Villarreal CF", "Athletic Bilbao", "Real Betis Balompie",
    "Real Sociedad",
    # İtalya
    "Juventus FC", "AC Milan", "Inter Milan", "AS Roma", "SSC Napoli",
    "SS Lazio", "ACF Fiorentina", "Atalanta BC", "Torino FC",
    # Almanya
    "Bayern Munich", "Borussia Dortmund", "Bayer 04 Leverkusen", "RB Leipzig",
    "Eintracht Frankfurt", "VfB Stuttgart", "SV Werder Bremen", "FC Schalke 04",
    "Borussia Monchengladbach", "VfL Wolfsburg", "Hamburger SV",
    # Fransa
    "Paris Saint-Germain", "Olympique Marseille", "Olympique Lyon", "AS Monaco",
    "LOSC Lille", "Stade Rennais FC", "OGC Nice", "AS Saint-Etienne",
    "FC Girondins Bordeaux",
    # Türkiye
    "Galatasaray", "Fenerbahce", "Besiktas JK", "Trabzonspor",
    # Portekiz / Hollanda / diğer
    "SL Benfica", "FC Porto", "Sporting CP", "Ajax Amsterdam", "PSV Eindhoven",
    "Feyenoord Rotterdam", "Celtic FC", "Rangers FC", "Zenit St. Petersburg",
    "Shakhtar Donetsk", "Olympiacos Piraeus", "Club Brugge KV", "RSC Anderlecht",
    "SC Braga", "Sevilla FC",
]

# Futbolcu ihracatı yüksek, oyuncuların bileceği ülkeler.
POPULAR_NATIONS = [
    "Brazil", "Argentina", "France", "Spain", "Germany", "Italy", "England",
    "Portugal", "Netherlands", "Belgium", "Croatia", "Turkey", "Uruguay",
    "Colombia", "Serbia", "Denmark", "Sweden", "Norway", "Poland", "Switzerland",
    "Nigeria", "Ghana", "Senegal", "Morocco", "Ivory Coast", "Cameroon",
    "Algeria", "Japan", "Korea, South", "United States", "Mexico", "Chile",
    "Austria", "Czech Republic", "Greece", "Ukraine", "Russia", "Scotland",
    "Wales", "Ireland", "Slovakia", "Slovenia", "Hungary", "Romania", "Egypt",
]

# 5x5 tahtada her hücrede en az bu kadar oyuncu bulunmalı.
MIN_PLAYERS_PER_CELL = 2
MAX_BOARD_ATTEMPTS = 400


@lru_cache(maxsize=1)
def _club_nation_matrix() -> dict[str, dict[str, int]]:
    """{kulüp: {millet: oyuncu sayısı}} — süreç boyunca bir kez hesaplanır."""
    rows = fetch_all(
        """SELECT current_club_name AS club,
                  country_of_citizenship AS nation,
                  COUNT(DISTINCT name) AS total
           FROM players
           WHERE current_club_name IS NOT NULL AND current_club_name != ''
             AND country_of_citizenship IS NOT NULL AND country_of_citizenship != ''
           GROUP BY club, nation"""
    )
    matrix: dict[str, dict[str, int]] = {}
    for row in rows:
        matrix.setdefault(row["club"], {})[row["nation"]] = row["total"]
    return matrix


@lru_cache(maxsize=1)
def available_clubs() -> list[str]:
    matrix = _club_nation_matrix()
    clubs = [club for club in POPULAR_CLUBS if club in matrix]
    for league_clubs in BIG_TEAMS.values():
        clubs.extend(club for club in league_clubs if club in matrix)
    return sorted(set(clubs))


def build_duel_board(
    club_count: int = 5,
    nation_count: int = 5,
    min_players: int = MIN_PLAYERS_PER_CELL,
) -> tuple[list[str], list[str]]:
    """Her (millet, kulüp) çiftinde en az `min_players` oyuncu olan tahta üretir.

    Döndürülen (nations, clubs) ikilisinde tüm kombinasyonlar çözülebilirdir;
    böylece oyuncular hangi ikiliyi seçerse seçsin cevabı olan bir soru çıkar.
    """
    matrix = _club_nation_matrix()
    clubs_pool = available_clubs()

    for _ in range(MAX_BOARD_ATTEMPTS):
        clubs = random.sample(clubs_pool, club_count)

        common = None
        for club in clubs:
            nations_here = {
                nation for nation, total in matrix[club].items()
                if total >= min_players and nation in POPULAR_NATIONS
            }
            common = nations_here if common is None else common & nations_here
            if len(common) < nation_count:
                break

        if common and len(common) >= nation_count:
            nations = random.sample(sorted(common), nation_count)
            random.shuffle(clubs)
            return nations, clubs

    # Havuz daralırsa tanınırlık şartını gevşetip tekrar dene.
    for _ in range(MAX_BOARD_ATTEMPTS):
        clubs = random.sample(clubs_pool, club_count)
        sets = [
            {n for n, total in matrix[club].items() if total >= 1}
            for club in clubs
        ]
        common = set.intersection(*sets)
        if len(common) >= nation_count:
            return random.sample(sorted(common), nation_count), clubs

    raise ValueError("Oyuncu Tahmin tahtası üretilemedi")
