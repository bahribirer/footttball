"""Can sistemi: cihaz başına saatte 10 oyun.

Puan toplamak çok kolaydı; sınırsız maç sınırsız puan demekti. Her cihaz
(player_id) bir saatlik pencerede en çok MAX_LIVES maça girer; pencere
dolunca canlar tam olarak yenilenir. Ad değiştirmek işe yaramaz: kimlik
cihaza bağlı, ad yalnız görünüm.

Kural:
  * odaya girişte can kontrol edilir (0 ise reddedilir)
  * maç başlarken (motor kurulurken) her insan oyuncudan 1 can düşer;
    rövanş yeni maç sayılır. Bekleme odasında beklemek can yakmaz.
  * kopup geri dönmek (resume) can yakmaz
Veri scores.db'de (yazılabilir dosya).
"""

from __future__ import annotations

import logging
import time

from app.services.score_service import connection

logger = logging.getLogger(__name__)

MAX_LIVES = 10
WINDOW_SECONDS = 3600

SCHEMA = """
CREATE TABLE IF NOT EXISTS lives (
    player_id    TEXT PRIMARY KEY,
    lives        INTEGER NOT NULL,
    window_start REAL NOT NULL,
    updated_at   REAL NOT NULL
);
"""


class NoLives(Exception):
    def __init__(self, resets_in: int) -> None:
        super().__init__(f"can yok, {resets_in} sn sonra yenilenir")
        self.resets_in = resets_in


def _ensure(con) -> None:
    con.executescript(SCHEMA)


def _row(con, player_id: str, now: float) -> tuple[int, float]:
    """Pencere dolmuşsa tazeler; (lives, window_start) döner."""
    r = con.execute("SELECT lives, window_start FROM lives WHERE player_id = ?", (player_id,)).fetchone()
    if r is None:
        con.execute("INSERT INTO lives (player_id, lives, window_start, updated_at) VALUES (?, ?, ?, ?)",
                    (player_id, MAX_LIVES, now, now))
        return MAX_LIVES, now
    lives, start = int(r["lives"]), float(r["window_start"])
    if now - start >= WINDOW_SECONDS:
        lives, start = MAX_LIVES, now
        con.execute("UPDATE lives SET lives = ?, window_start = ?, updated_at = ? WHERE player_id = ?",
                    (lives, start, now, player_id))
    return lives, start


def _public(lives: int, start: float, now: float) -> dict:
    resets_at = start + WINDOW_SECONDS
    return {
        "lives": lives,
        "max": MAX_LIVES,
        "resets_at": resets_at,
        "resets_in": max(0, int(resets_at - now)),
        "window_seconds": WINDOW_SECONDS,
    }


def status(player_id: str) -> dict:
    now = time.time()
    with connection() as con:
        _ensure(con)
        lives, start = _row(con, player_id, now)
    return _public(lives, start, now)


def check(player_id: str | None) -> None:
    """Odaya giriş öncesi: can yoksa NoLives fırlatır. Kimliksiz istemci
    (eski sürüm) serbest bırakılır; yeni istemciler hep kimlik gönderir."""
    if not player_id:
        return
    now = time.time()
    with connection() as con:
        _ensure(con)
        lives, start = _row(con, player_id, now)
    if lives <= 0:
        raise NoLives(int(start + WINDOW_SECONDS - now))


def consume(player_id: str | None) -> dict | None:
    """Maç başlarken 1 can düşer (0'ın altına inmez)."""
    if not player_id:
        return None
    now = time.time()
    with connection() as con:
        _ensure(con)
        lives, start = _row(con, player_id, now)
        lives = max(0, lives - 1)
        con.execute("UPDATE lives SET lives = ?, updated_at = ? WHERE player_id = ?", (lives, now, player_id))
    return _public(lives, start, now)


def consume_for_room(players) -> None:
    """Odadaki insan oyuncuların hepsinden 1 can düşer."""
    for p in players:
        if getattr(p, "is_bot", False):
            continue
        try:
            consume(p.player_id)
        except Exception:  # noqa: BLE001
            logger.exception("Can düşülemedi: %s", p.player_id)


def grant(player_id: str, lives: int | None = None) -> dict:
    """Yönetici: canları yeniler (varsayılan tam)."""
    now = time.time()
    with connection() as con:
        _ensure(con)
        _row(con, player_id, now)
        value = MAX_LIVES if lives is None else max(0, min(MAX_LIVES, lives))
        con.execute("UPDATE lives SET lives = ?, window_start = ?, updated_at = ? WHERE player_id = ?",
                    (value, now, now, player_id))
    return _public(value, now, now)
