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

def _read_only_uri(path: str) -> str:
    """Dosya yolunu salt okunur SQLite URI'sine çevirir."""
    from urllib.parse import quote

    return f"file:{quote(path)}?mode=ro"


@contextmanager
def get_connection() -> Iterator[sqlite3.Connection]:
    """Salt okunur bağlantı.

    Uygulama oyuncu veritabanına hiç yazmıyor; veriyi host'taki betikler
    üretiyor. Yazma yasağı eskiden container'ın `:ro` bağlamasıyla
    sağlanıyordu ama WAL modunda bu çalışmıyor: SQLite okurken bile `-shm`
    dosyasını açabilmek zorunda, salt okunur dizinde "attempt to write a
    readonly database" veriyor. Bu yüzden yasak bağlantı seviyesine taşındı —
    dizin yazılabilir, bağlantı `mode=ro`. Koruma aynı, WAL çalışıyor.
    """
    con = sqlite3.connect(_read_only_uri(settings.DB_PATH), uri=True, timeout=10)
    con.row_factory = sqlite3.Row
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
