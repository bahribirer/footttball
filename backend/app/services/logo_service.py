"""Kulüp logolarının bulunması, indirilmesi ve yerel önbelleğe alınması.

Sıra: yerel önbellek -> veritabanındaki logo_url -> TheSportsDB araması.
"""

import os
import re
import threading

import requests

from app.core.config import settings
from app.db.database import fetch_one
from app.db.reference_data import TSDB_SEARCH

os.makedirs(settings.LOGO_DIR, exist_ok=True)

# Aynı kulüp için eş zamanlı indirmeleri engeller (aynı dosyaya iki yazma).
_download_locks: dict[str, threading.Lock] = {}
_locks_guard = threading.Lock()

_BANNED_TEAM_KEYWORDS = (
    "basketbol", "basketball", "voleybol", "volleyball", "handball", "hentbol",
)


def _lock_for(club_name: str) -> threading.Lock:
    with _locks_guard:
        return _download_locks.setdefault(club_name, threading.Lock())


def sanitize_filename(name: str) -> str:
    safe = re.sub(r"[^a-zA-Z0-9\s\-\.]", "", name)
    return safe.strip().replace(" ", "_")


def cached_logo_path(club_name: str) -> str | None:
    safe = sanitize_filename(club_name)
    for ext in (".png", ".jpg", ".gif"):
        path = os.path.join(settings.LOGO_DIR, f"{safe}{ext}")
        if os.path.exists(path) and os.path.getsize(path) > 100:
            return path
    return None


def _write_atomic(filepath: str, content: bytes) -> str:
    """Yarım kalmış indirmelerin bozuk dosya bırakmaması için önce .tmp yazılır."""
    tmp = f"{filepath}.tmp"
    with open(tmp, "wb") as fh:
        fh.write(content)
    os.replace(tmp, filepath)
    return filepath


_WIKI_THUMB = re.compile(
    r"^https?://upload\.wikimedia\.org/wikipedia/(?P<repo>commons|en)/thumb/[0-9a-f]/[0-9a-f]{2}/(?P<file>[^/]+)/\d+px-"
)


def _wikimedia_thumb(url: str, width: int = 256) -> str | None:
    """Eski biçim küçük resim adresini geçerli olana çevirir.

    Wikimedia 2025 sonunda küçük resimleri thumb.wikimedia.org'a taşıdı ve
    standart dışı genişlikleri (256px) 400 ile reddetmeye başladı; DB'deki
    adresler o eski biçimdeydi. Dosya adı adresten çıkarılır, imageinfo API
    güncel adresi verir.
    """
    m = _WIKI_THUMB.match(url)
    if not m:
        return None
    repo, file = m.group("repo"), m.group("file")
    api = "https://commons.wikimedia.org/w/api.php" if repo == "commons" else "https://en.wikipedia.org/w/api.php"
    try:
        response = requests.get(
            api,
            params={"action": "query", "titles": f"File:{file}", "prop": "imageinfo",
                    "iiprop": "url", "iiurlwidth": width, "format": "json"},
            headers={"User-Agent": settings.BROWSER_UA},
            timeout=settings.HTTP_TIMEOUT,
        )
        pages = response.json().get("query", {}).get("pages", {})
        for page in pages.values():
            info = (page.get("imageinfo") or [{}])[0]
            return info.get("thumburl") or info.get("url")
    except (requests.RequestException, ValueError):
        return None
    return None


def _download(url: str, club_name: str) -> str | None:
    if not url:
        return None
    filepath = os.path.join(settings.LOGO_DIR, f"{sanitize_filename(club_name)}.png")
    if "upload.wikimedia.org" in url:
        url = _wikimedia_thumb(url) or url
    try:
        response = requests.get(
            url,
            headers={"User-Agent": settings.BROWSER_UA},
            timeout=settings.HTTP_TIMEOUT,
            allow_redirects=True,
        )
        if response.status_code == 200 and len(response.content) > 100:
            return _write_atomic(filepath, response.content)
    except requests.RequestException:
        pass
    return None


def _db_logo_url(club_name: str) -> str | None:
    row = fetch_one("SELECT logo_url FROM clubs WHERE name = ?", (club_name,))
    return row["logo_url"] if row and row["logo_url"] else None


def _download_from_tsdb(club_name: str) -> str | None:
    search = TSDB_SEARCH.get(club_name, club_name)
    try:
        response = requests.get(
            settings.TSDB_API,
            params={"t": search},
            headers={"User-Agent": settings.BROWSER_UA},
            timeout=settings.HTTP_TIMEOUT,
        )
        if response.status_code != 200:
            return None
        teams = response.json().get("teams") or []
    except (requests.RequestException, ValueError):
        return None

    if not teams:
        return None

    # Aramalar bazen aynı şehrin basketbol/voleybol kulübünü döndürüyor
    # (ör. "Gaziantep" -> Gaziantep Basketbol). Önce spor dalına, sonra ada bakılır.
    football_teams = [
        team for team in teams
        if (team.get("strSport") or "").lower() == "soccer"
        and not any(k in (team.get("strTeam") or "").lower() for k in _BANNED_TEAM_KEYWORDS)
    ]
    if not football_teams:
        return None

    selected = football_teams[0]
    for team in football_teams:
        if (team.get("strTeam") or "").lower() == search.lower():
            selected = team
            break

    badge = selected.get("strBadge") or selected.get("strTeamBadge")
    return _download(badge, club_name) if badge else None


def resolve_logo(club_name: str) -> str | None:
    """Kulüp logosunun yerel dosya yolunu döndürür; bulunamazsa None."""
    cached = cached_logo_path(club_name)
    if cached:
        return cached

    with _lock_for(club_name):
        # Kilidi beklerken başka bir istek indirmiş olabilir.
        cached = cached_logo_path(club_name)
        if cached:
            return cached

        db_url = _db_logo_url(club_name)
        if db_url:
            path = _download(db_url, club_name)
            if path:
                return path

        return _download_from_tsdb(club_name)
