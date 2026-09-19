"""Kariyer Yolu modu için futbolcu ve kariyer verisi.

Mod, bir futbolcunun kulüp yolunu (ilk → güncel) kısmen gösterir ve iki
oyuncu kimin olduğunu bilmeye çalışır. Buradaki iş: iyi bir futbolcu seçmek
ve yolunu temiz bir listeye çevirmek.

"İyi futbolcu" iki havuzdan gelir:
  * Güncel yıldızlar — `players` tablosunda piyasa değeri yüksek olanlar.
  * Efsaneler — `players`'ta olmayan ama tarihçe katmanında çok kulüpte
    görünenler (Ronaldinho, Zidane). Piyasa değeri yok; kulüp sayısı ve
    büyük kulüplerde oynamış olması ölçüt.

Kulüp adları Wikidata'dan farklı biçimlerde geliyor ("AC Milan" / "Milan
AC"); yol kurulurken normalize edilip tekilleştirilir, yoksa aynı kulüp iki
kez görünürdü ve ipucu hakkı boşa giderdi.
"""

from __future__ import annotations

import random
import re

from app.services import player_service
from app.db.database import fetch_all, fetch_one
from app.services.player_service import normalize

# Bir yol en az bu kadar kulüp içermeli; ikisi tahmin için çok az.
MIN_CLUBS = 3
MAX_CLUBS = 8

# Güncel yıldız havuzu için alt sınır (EUR).
STAR_MIN_VALUE = 5_000_000

# Efsane havuzu: tarihçede en az bu kadar farklı kulüp.
LEGEND_MIN_CLUBS = 4

_STRIP = re.compile(r"\b(fc|cf|sc|ac|as|ss|us|club|calcio|de|fútbol|futbol|1893|1909|1913|1936)\b")


def _club_key(name: str) -> str:
    """Kulüp adının kaba anahtarı: 'AC Milan' ile 'Milan AC' aynı olsun."""
    key = normalize(name)
    key = _STRIP.sub(" ", key)
    key = re.sub(r"\(.*?\)", " ", key)          # "(- 2025)" gibi ekler
    key = re.sub(r"[^a-z0-9 ]", " ", key)
    return " ".join(sorted(key.split()))


def career_path(name_normalized: str) -> list[dict]:
    """Futbolcunun kulüpleri, kronolojik ve tekilleştirilmiş.

    Aynı kulübe iki ayrı dönemde dönmüşse (Pogba: Juventus 2012, Juventus
    2022) ikisi de kalır — bu gerçek bir kariyer olayı. Ama aynı dönemin iki
    farklı adla yazılmış hâli (AC Milan 2008 / Milan AC 2008) tek satıra iner.
    """
    rows = fetch_all(
        """SELECT club_name, start_year, end_year FROM club_history
           WHERE name_normalized = ? AND start_year IS NOT NULL
           ORDER BY start_year, end_year""",
        (name_normalized,),
    )
    path: list[dict] = []
    seen: set[tuple[str, int]] = set()
    for row in rows:
        key = (_club_key(row["club_name"]), int(row["start_year"]))
        if key in seen:
            continue
        # Aynı kulübün bitişik dönemleri (2008-2010 ve 2008-2010 farklı ad)
        if path and _club_key(path[-1]["club"]) == key[0] and abs(path[-1]["start"] - key[1]) <= 1:
            continue
        seen.add(key)
        path.append({
            "club": row["club_name"],
            "start": int(row["start_year"]),
            "end": int(row["end_year"]) if row["end_year"] else None,
        })
    return path


def _candidates_stars(limit: int) -> list[dict]:
    return [dict(r) for r in fetch_all(
        """SELECT p.name_normalized AS key, p.name, p.country_of_citizenship AS nationality,
                  p.image_url, p.position,
                  MAX(CAST(COALESCE(p.highest_market_value_in_eur,'0') AS INTEGER)) AS value
           FROM players p
           JOIN club_history ch ON ch.name_normalized = p.name_normalized
                                AND ch.start_year IS NOT NULL
           GROUP BY p.name_normalized
           HAVING COUNT(DISTINCT ch.club_name) >= ? AND value >= ?
           ORDER BY RANDOM() LIMIT ?""",
        (MIN_CLUBS, STAR_MIN_VALUE, limit),
    )]


def _candidates_legends(limit: int) -> list[dict]:
    """`players`'ta olmayan ama tarihçede çok kulüpte görünenler."""
    return [dict(r) for r in fetch_all(
        """SELECT ch.name_normalized AS key, MAX(ch.player_name) AS name,
                  MAX(ch.country) AS nationality, NULL AS image_url, NULL AS position,
                  0 AS value
           FROM club_history ch
           LEFT JOIN players p ON p.name_normalized = ch.name_normalized
           WHERE p.name_normalized IS NULL AND ch.start_year IS NOT NULL
             AND ch.start_year >= 1985
           GROUP BY ch.name_normalized
           HAVING COUNT(DISTINCT ch.club_name) >= ?
           ORDER BY RANDOM() LIMIT ?""",
        (LEGEND_MIN_CLUBS, limit),
    )]


def pick_player(exclude: set[str] | None = None) -> dict | None:
    """Bir tur için futbolcu ve yolunu seçer.

    Yıldızlar ağırlıklı (4'te 3), arada bir efsane. Yol çok kısa ya da çok
    uzun çıkarsa (veri hatası) atlanıp başkası denenir.
    """
    exclude = exclude or set()
    pool = _candidates_stars(40)
    if random.random() < 0.25:
        pool = _candidates_legends(20) + pool
    random.shuffle(pool)

    for cand in pool:
        if cand["key"] in exclude:
            continue
        path = career_path(cand["key"])
        if not MIN_CLUBS <= len(path) <= MAX_CLUBS:
            continue
        return {
            "key": cand["key"],
            "name": cand["name"],
            "nationality": cand["nationality"],
            "position": cand.get("position"),
            "image_url": player_service.photo_for(cand["key"], cand.get("image_url")),
            "path": path,
        }
    return None


def matches(guess: str, solution_key: str) -> bool:
    """Tahmin çözümle aynı futbolcu mu.

    Kullanıcı soyadla yazabilir; player_service'in eşleştirmesi kullanılır.
    """
    from app.services.player_service import find_player
    found = find_player(guess)
    if found and normalize(found["name"]) == solution_key:
        return True
    # find_player başka birini bulmuş olabilir (aynı soyadlı iki oyuncu);
    # yazılanın çözümün son kelimesiyle ya da tamamıyla eşleşmesi de kabul.
    g = normalize(guess)
    if not g:
        return False
    if g == solution_key:
        return True
    words = solution_key.split()
    return len(g) >= 4 and (g == words[-1] or g == " ".join(words[-2:]))
