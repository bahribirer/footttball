"""Efsane oyuncular (yalnız tarihçede olanlar) öneride ve doğrulamada çıkar."""

import pytest

from app.services import player_service as ps
from tests.conftest import requires_player_data

needs_history = pytest.mark.skipif(
    not ps.has_history_layer(), reason="club_history katmanı yok")


@requires_player_data
@needs_history
def test_ronaldinho_oneride_ilk_sirada():
    names = [r["name"] for r in ps.search_players("ronaldinho", "http://x")]
    assert names and names[0] == "Ronaldinho"


@requires_player_data
@needs_history
def test_efsane_guncel_yildizlari_ilk_ucten_itmez():
    """"ronaldo" yazan Cristiano'yu ilk üçte görmeli; adsız efsaneler sonra gelir."""
    results = ps.search_players("ronaldo", "http://x")
    top3 = [r["name"] for r in results[:3]]
    assert "Cristiano Ronaldo" in top3
    assert not any(r.get("legend") and r["fame"] < 5 for r in results[:3])


@requires_player_data
@needs_history
def test_efsane_find_player_ile_bulunur():
    found = ps.find_player("Ronaldinho")
    assert found and found["name"] == "Ronaldinho" and found["country"] == "Brazil"


def test_elite_kulup_anahtarlari_aksansiz():
    assert all(k == ps.normalize(k) for k in ps.ELITE_CLUB_KEYS)
