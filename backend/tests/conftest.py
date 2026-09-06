"""Testlerin ortak koşulları.

Oyuncu veritabanı depoya dahil değil (birkaç yüz MB, sezon anlık
görüntülerinden üretiliyor). Geliştirici makinesinde varken CI'da yok; veri
gerektiren testler bu durumda atlanır, mantık testleri her yerde koşar.
"""

import pytest

from app.db.database import fetch_one


def _player_table_has_rows() -> bool:
    try:
        row = fetch_one("SELECT 1 AS ok FROM players LIMIT 1")
    except Exception:
        return False
    return row is not None


HAS_PLAYER_DATA = _player_table_has_rows()

requires_player_data = pytest.mark.skipif(
    not HAS_PLAYER_DATA,
    reason="Oyuncu veritabanı yok; veriye dayalı testler atlandı.",
)
