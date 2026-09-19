"""Puanlar ve genel sıralama.

Hesap sistemi yok; her cihaz kendine bir kimlik (UUID) üretir, adıyla
birlikte gönderir. Aynı kişi iki telefondan iki ayrı kayıt olur — bu
aşamada kabul edilebilir, hesap gelince birleştirilir.

Skorlar ayrı bir veritabanında (scores.db). Oyuncu veritabanı bilerek salt
okunur; uygulama oraya hiç yazmıyor ve bu koruma test ediliyor. Skor
yazmak için o korumayı delmek yerine ikinci bir dosya açılıyor.

Puanlama:
  * insana karşı maç: kazanan 10, berabere 4, kaybeden 1
  * bota karşı:       kolay 1 / orta 2 / zor 3 (yalnız kazanınca) —
                      aksi halde kolay bot puan çiftliği olurdu
  * günün tahtası:    doğru kutu sayısı (0-9), günde bir kez
"""

from __future__ import annotations

import logging
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from app.core.config import settings

logger = logging.getLogger(__name__)

WIN, DRAW, LOSS = 10, 4, 1
BOT_WIN = {"easy": 1, "medium": 2, "hard": 3}

SCHEMA = """
CREATE TABLE IF NOT EXISTS players_meta (
    player_id  TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    name_key   TEXT NOT NULL DEFAULT '',   -- küçük harf, kırpılmış ad
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS score_events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    player_id   TEXT NOT NULL,
    mode        TEXT NOT NULL,           -- oyun modu ya da 'daily'
    kind        TEXT NOT NULL,           -- win / draw / loss / daily
    points      INTEGER NOT NULL,
    vs_bot      INTEGER NOT NULL DEFAULT 0,
    opponent_id TEXT,
    ref         TEXT,                    -- günün tahtası: tarih (tekillik için)
    created_at  REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_score_player ON score_events(player_id);
CREATE INDEX IF NOT EXISTS idx_score_mode   ON score_events(mode);
CREATE UNIQUE INDEX IF NOT EXISTS uq_daily ON score_events(player_id, mode, ref)
    WHERE mode = 'daily';
"""


def db_path() -> str:
    return str(Path(settings.DB_PATH).parent / "scores.db")


_initialised = False


@contextmanager
def connection() -> Iterator[sqlite3.Connection]:
    global _initialised
    con = sqlite3.connect(db_path(), timeout=10, isolation_level=None)
    con.row_factory = sqlite3.Row
    try:
        if not _initialised:
            con.execute("PRAGMA journal_mode=WAL")
            con.executescript(SCHEMA)
            _migrate(con)
            _initialised = True
        yield con
    finally:
        con.close()


def name_key(name: str) -> str:
    """Aynı ad farklı cihazlardan gelse de tabloda tek satır olsun.

    Hesap yok; kimlik cihaza bağlı. Kullanıcı telefonunu değiştirince ya da
    simülatörden girince aynı ad üç dört kez alt alta görünüyordu. Tablo
    ada göre toplar: "Bahri", "bahri " ve "BAHRİ" aynı kişi sayılır.
    """
    return " ".join((name or "Oyuncu").casefold().split())[:32]


def _migrate(con: sqlite3.Connection) -> None:
    cols = {r["name"] for r in con.execute("PRAGMA table_info(players_meta)")}
    if "name_key" not in cols:
        con.execute("ALTER TABLE players_meta ADD COLUMN name_key TEXT NOT NULL DEFAULT ''")
    con.execute("CREATE INDEX IF NOT EXISTS idx_meta_name_key ON players_meta(name_key)")
    rows = con.execute("SELECT player_id, name FROM players_meta WHERE name_key = ''").fetchall()
    for r in rows:
        con.execute("UPDATE players_meta SET name_key = ? WHERE player_id = ?",
                    (name_key(r["name"]), r["player_id"]))


def _upsert_player(con: sqlite3.Connection, player_id: str, name: str) -> None:
    now = time.time()
    shown = (name or "Oyuncu").strip()[:32] or "Oyuncu"
    con.execute(
        """INSERT INTO players_meta (player_id, name, name_key, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?)
           ON CONFLICT(player_id) DO UPDATE SET name = excluded.name, name_key = excluded.name_key,
                                              updated_at = excluded.updated_at""",
        (player_id, shown, name_key(shown), now, now),
    )


def record_match(mode: str, players: list[dict], winner_slot: int | None,
                 vs_bot: bool = False, bot_difficulty: str = "medium") -> None:
    """Maç sonucunu yazar.

    `players`: [{"slot", "player_id", "name", "is_bot"}]. Botların kaydı
    tutulmaz; puan yalnız insanlara yazılır.
    """
    humans = [p for p in players if p.get("player_id") and not p.get("is_bot")]
    if not humans:
        return
    now = time.time()
    with connection() as con:
        for p in humans:
            _upsert_player(con, p["player_id"], p.get("name", ""))
            if vs_bot:
                if winner_slot == p["slot"]:
                    kind, points = "win", BOT_WIN.get(bot_difficulty, 2)
                else:
                    kind, points = ("draw", 0) if winner_slot is None else ("loss", 0)
            else:
                if winner_slot is None:
                    kind, points = "draw", DRAW
                elif winner_slot == p["slot"]:
                    kind, points = "win", WIN
                else:
                    kind, points = "loss", LOSS
            opponent = next((q.get("player_id") for q in players if q["slot"] != p["slot"]), None)
            con.execute(
                """INSERT INTO score_events (player_id, mode, kind, points, vs_bot, opponent_id, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (p["player_id"], mode, kind, points, 1 if vs_bot else 0, opponent, now),
            )


def record_daily(player_id: str, name: str, date: str, score: int) -> bool:
    """Günün tahtası sonucu. Aynı gün ikinci gönderim yok sayılır (False)."""
    score = max(0, min(9, int(score)))
    with connection() as con:
        _upsert_player(con, player_id, name)
        try:
            con.execute(
                """INSERT INTO score_events (player_id, mode, kind, points, vs_bot, ref, created_at)
                   VALUES (?, 'daily', 'daily', ?, 0, ?, ?)""",
                (player_id, score, date, time.time()),
            )
            return True
        except sqlite3.IntegrityError:
            return False


def leaderboard(mode: str | None = None, limit: int = 50) -> list[dict]:
    """Toplam puana göre sıralı liste; `mode` verilirse yalnız o mod.

    Satırlar ada göre toplanır (bkz. `name_key`); gösterilen ad en son
    kullanılan yazım.
    """
    where, params = "", []
    if mode and mode != "all":
        where, params = "WHERE e.mode = ?", [mode]
    with connection() as con:
        rows = con.execute(
            f"""SELECT m.name_key,
                       (SELECT name FROM players_meta m2 WHERE m2.name_key = m.name_key
                        ORDER BY updated_at DESC LIMIT 1) AS name,
                       SUM(e.points) AS points,
                       SUM(CASE WHEN e.kind = 'win' THEN 1 ELSE 0 END) AS wins,
                       COUNT(CASE WHEN e.kind IN ('win','draw','loss') THEN 1 END) AS matches,
                       MAX(CASE WHEN e.mode = 'daily' THEN e.points ELSE 0 END) AS best_daily,
                       MIN(m.created_at) AS first_seen
                FROM score_events e JOIN players_meta m ON m.player_id = e.player_id
                {where}
                GROUP BY m.name_key
                HAVING points > 0
                ORDER BY points DESC, wins DESC, first_seen ASC
                LIMIT ?""",
            (*params, limit),
        ).fetchall()
    return [
        {"rank": i + 1, "name_key": r["name_key"], "name": r["name"],
         "points": int(r["points"]), "wins": int(r["wins"]), "matches": int(r["matches"]),
         "best_daily": int(r["best_daily"])}
        for i, r in enumerate(rows)
    ]


def summary(player_id: str) -> dict:
    """Bir oyuncunun (adıyla toplanmış) genel sırası ve mod başına puanları."""
    with connection() as con:
        me = con.execute("SELECT name, name_key FROM players_meta WHERE player_id = ?",
                         (player_id,)).fetchone()
        if not me:
            return {"player_id": player_id, "name": None, "name_key": None,
                    "total": 0, "rank": None, "per_mode": {}}
        key = me["name_key"]
        per_mode = {
            r["mode"]: int(r["points"])
            for r in con.execute(
                """SELECT e.mode, SUM(e.points) AS points
                   FROM score_events e JOIN players_meta m ON m.player_id = e.player_id
                   WHERE m.name_key = ? GROUP BY e.mode""",
                (key,),
            )
        }
        total = sum(per_mode.values())
        rank_row = con.execute(
            """SELECT COUNT(*) + 1 AS rank FROM (
                   SELECT m.name_key, SUM(e.points) AS p
                   FROM score_events e JOIN players_meta m ON m.player_id = e.player_id
                   GROUP BY m.name_key
               ) WHERE p > ?""",
            (total,),
        ).fetchone()
    return {
        "player_id": player_id,
        "name": me["name"],
        "name_key": key,
        "total": total,
        "rank": int(rank_row["rank"]) if total > 0 else None,
        "per_mode": per_mode,
    }


def admin_stats() -> dict:
    """Panel için özet sayılar."""
    day_ago = time.time() - 86400
    with connection() as con:
        players = con.execute("SELECT COUNT(DISTINCT name_key) AS n FROM players_meta").fetchone()["n"]
        devices = con.execute("SELECT COUNT(*) AS n FROM players_meta").fetchone()["n"]
        matches = con.execute(
            "SELECT COUNT(*) AS n FROM score_events WHERE kind IN ('win','draw','loss')").fetchone()["n"]
        matches_24h = con.execute(
            "SELECT COUNT(*) AS n FROM score_events WHERE kind IN ('win','draw','loss') AND created_at > ?",
            (day_ago,)).fetchone()["n"]
        vs_bot_24h = con.execute(
            "SELECT COUNT(*) AS n FROM score_events WHERE vs_bot = 1 AND created_at > ?",
            (day_ago,)).fetchone()["n"]
        daily_24h = con.execute(
            "SELECT COUNT(*) AS n FROM score_events WHERE mode = 'daily' AND created_at > ?",
            (day_ago,)).fetchone()["n"]
        by_mode = {r["mode"]: int(r["n"]) for r in con.execute(
            "SELECT mode, COUNT(*) AS n FROM score_events GROUP BY mode")}
        recent = [dict(r) for r in con.execute(
            """SELECT m.name, e.mode, e.kind, e.points, e.vs_bot, e.created_at
               FROM score_events e JOIN players_meta m ON m.player_id = e.player_id
               ORDER BY e.id DESC LIMIT 25""")]
        players_recent = [dict(r) for r in con.execute(
            """SELECT m.name, m.name_key, m.player_id, m.updated_at, m.created_at,
                      COALESCE((SELECT SUM(points) FROM score_events e WHERE e.player_id = m.player_id), 0) AS points
               FROM players_meta m ORDER BY m.updated_at DESC LIMIT 100""")]
    return {
        "players": int(players), "devices": int(devices),
        "match_events": int(matches), "match_events_24h": int(matches_24h),
        "vs_bot_24h": int(vs_bot_24h), "daily_24h": int(daily_24h),
        "events_by_mode": by_mode, "recent_events": recent,
        "players_recent": players_recent,
    }
