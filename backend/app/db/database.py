"""SQLite bağlantı yönetimi.

Eski kodda modül seviyesinde tek bir global bağlantı (`check_same_thread=False`)
açılıp bazı fonksiyonlarda ayrıca yeni bağlantılar açılıyordu. Bu hem thread
güvenli değildi hem de bağlantı sızıntısına yol açıyordu. Burada her sorgu için
context manager ile bağlantı alınır ve garanti şekilde kapatılır.
"""

import sqlite3
from contextlib import contextmanager
from typing import Any, Iterator, Sequence

from app.core.config import settings


@contextmanager
def get_connection() -> Iterator[sqlite3.Connection]:
    con = sqlite3.connect(settings.DB_PATH, timeout=10)
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
