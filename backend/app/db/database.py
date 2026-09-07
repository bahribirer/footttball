"""SQLite bağlantı yönetimi.

Eski kodda modül seviyesinde tek bir global bağlantı (`check_same_thread=False`)
açılıp bazı fonksiyonlarda ayrıca yeni bağlantılar açılıyordu. Bu hem thread
güvenli değildi hem de bağlantı sızıntısına yol açıyordu. Burada her sorgu için
context manager ile bağlantı alınır ve garanti şekilde kapatılır.
"""

import logging
import sqlite3
from contextlib import contextmanager
from typing import Any, Iterator, Sequence

from app.core.config import settings

logger = logging.getLogger(__name__)

_wal_checked = False


def _ensure_wal(con: sqlite3.Connection) -> None:
    """Veritabanını bir kez WAL moduna alır.

    Varsayılan `delete` günlüğünde yazma süren boyunca okumalar bloke olur;
    aylık kulüp tarihçesi tazelemesi çalışırken oyuncular cevap doğrulaması
    yapamıyordu. WAL okuyucuyu yazıcıdan ayırır. Kalıcı bir ayardır, ilk
    başarılı denemeden sonra tekrar denenmez.

    Veritabanı salt okunur bağlanmışsa (üretimde container böyle bağlıyor)
    değişiklik yapılamaz; bu durumda sessizce geçilir ve host tarafında
    ayarlanmış olması beklenir.
    """
    global _wal_checked
    if _wal_checked:
        return
    _wal_checked = True
    try:
        mode = con.execute("PRAGMA journal_mode").fetchone()[0]
        if str(mode).lower() != "wal":
            new_mode = con.execute("PRAGMA journal_mode=WAL").fetchone()[0]
            logger.info("SQLite gunluk modu: %s -> %s", mode, new_mode)
    except sqlite3.Error as exc:
        logger.warning("WAL moduna gecilemedi: %s", exc)


@contextmanager
def get_connection() -> Iterator[sqlite3.Connection]:
    con = sqlite3.connect(settings.DB_PATH, timeout=10)
    con.row_factory = sqlite3.Row
    _ensure_wal(con)
    try:
        yield con
    finally:
        con.close()


def fetch_all(query: str, params: Sequence[Any] = ()) -> list[sqlite3.Row]:
    with get_connection() as con:
        return con.execute(query, params).fetchall()


def fetch_one(query: str, params: Sequence[Any] = ()) -> sqlite3.Row | None:
    with get_connection() as con:
        return con.execute(query, params).fetchone()


def fetch_column(query: str, params: Sequence[Any] = ()) -> list[Any]:
    """Tek kolonluk sorgular için düz liste döndürür."""
    return [row[0] for row in fetch_all(query, params)]
