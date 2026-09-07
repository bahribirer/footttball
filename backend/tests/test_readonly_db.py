"""Uygulamanın oyuncu veritabanına yazamadığını doğrular.

Yazma yasağı eskiden container'ın `:ro` bağlamasıyla sağlanıyordu. WAL
moduna geçince o bağlama okumayı da kırdı (SQLite okurken -shm dosyasını
açmak zorunda), yasak bağlantı seviyesine taşındı. Bu test korumanın
gerçekten yerinde olduğunu güvenceye alır — aksi halde sessizce kaybolurdu.
"""

import sqlite3

import pytest

from app.db import database
from tests.conftest import requires_player_data


def test_baglanti_salt_okunur_uri_kullaniyor():
    uri = database._read_only_uri("/tmp/ornek.db")
    assert uri.startswith("file:")
    assert "mode=ro" in uri


@requires_player_data
def test_yazma_denemesi_reddediliyor():
    with database.get_connection() as con:
        with pytest.raises(sqlite3.OperationalError):
            con.execute("CREATE TABLE sizinti_testi (x INTEGER)")


@requires_player_data
def test_okuma_calisiyor():
    row = database.fetch_one("SELECT COUNT(*) AS total FROM players")
    assert row is not None and row["total"] > 0
