"""Oyuncu arama ve tahmin doğrulama."""

import unicodedata

from app.db.database import fetch_all, fetch_one
from app.services.country_service import flag_url

SEARCH_LIMIT = 50


def normalize(text: str | None) -> str:
    """Aksan ve büyük/küçük harf farklarını yok sayan karşılaştırma anahtarı."""
    if not text:
        return ""
    decomposed = unicodedata.normalize("NFKD", text)
    stripped = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return " ".join(stripped.lower().split())


def verify_player(player_name: str, nationality: str, club: str) -> bool:
    """Oyuncunun verilen millet + kulüp ikilisine uyup uymadığını kontrol eder.

    Eski sürümde isim karşılaştırması büyük/küçük harfe duyarlıydı: SQL `LIKE`
    eşleşse bile Python tarafındaki `==` kontrolü yüzünden doğru tahminler
    reddedilebiliyordu. Artık normalize edilmiş karşılaştırma yapılıyor.
    """
    if not player_name or not nationality or not club:
        return False

    rows = fetch_all(
        """SELECT DISTINCT name FROM players
           WHERE name LIKE ?
             AND country_of_citizenship = ?
             AND current_club_name LIKE ?""",
        (player_name, nationality, f"%{club}%"),
    )
    target = normalize(player_name)
    return any(normalize(row["name"]) == target for row in rows)


def search_players(name: str, base_url: str) -> list[dict]:
    """Otomatik tamamlama için oyuncu arar; her oyuncu bir kez döner."""
    if not name or len(name) < 2:
        return []

    rows = fetch_all(
        """SELECT name, country_of_citizenship, current_club_name,
                  current_club_domestic_competition_id, image_url, position, last_season
           FROM players
           WHERE name LIKE ?
           ORDER BY CASE WHEN name LIKE ? THEN 0 ELSE 1 END,
                    last_season DESC,
                    name ASC
           LIMIT ?""",
        (f"%{name}%", f"{name}%", SEARCH_LIMIT),
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

    row = fetch_one(
        """SELECT name, image_url, current_club_name, country_of_citizenship
           FROM players
           WHERE name LIKE ?
           ORDER BY last_season DESC
           LIMIT 1""",
        (player_name.strip(),),
    )
    if not row or normalize(row["name"]) != normalize(player_name):
        return None

    return {
        "name": row["name"],
        "image_url": row["image_url"],
        "club": row["current_club_name"],
        "country": row["country_of_citizenship"],
    }
