"""İsim token indeksinin doğru ve hızlı olduğunu doğrular.

Soyadla arama baştan joker LIKE kullanıyordu; indeks kullanılamadığı için
her sorgu tam tarama yapıyordu. Token tablosu aramayı eşitliğe çevirir.
Buradaki testler iki şeyi güvenceye alır: sonuçlar değişmedi ve sorgu planı
gerçekten indekse düştü.
"""

import pytest

from app.db.database import fetch_all
from app.services import player_service as ps
from tests.conftest import requires_player_data


def test_token_indeksi_yoksa_eski_yola_dusulur(monkeypatch):
    """build_name_tokens.py calistirilmadan da dogru sonuc alinmali."""
    monkeypatch.setattr(ps, "has_token_index", lambda: False)
    where, params = ps._name_match("name_normalized", "messi")
    assert "LIKE" in where
    assert params == ["messi", "% messi", "messi %", "% messi %"]


def test_token_indeksi_varsa_esitlik_sorgusu_kurulur(monkeypatch):
    monkeypatch.setattr(ps, "has_token_index", lambda: True)
    where, params = ps._name_match("name_normalized", "messi")
    assert "name_tokens" in where
    assert "LIKE" not in where
    assert params == ["messi", "messi"]


@requires_player_data
@pytest.mark.skipif(not ps.has_token_index(), reason="name_tokens tablosu yok")
def test_sorgu_plani_tam_tarama_yapmiyor():
    where, params = ps._name_match("name_normalized", "messi")
    plan = [row[3] for row in fetch_all(
        f"EXPLAIN QUERY PLAN SELECT 1 FROM players WHERE {where}", params)]
    birlesik = " ".join(plan)
    assert "SEARCH" in birlesik, plan
    # SCAN players kalirsa indeks devreye girmemis demektir.
    assert "SCAN players" not in birlesik, plan


@requires_player_data
@pytest.mark.parametrize("typed, expected", [
    ("Messi", "Lionel Messi"),
    ("Haaland", "Erling Haaland"),
    ("Mbappe", "Kylian Mbappé"),
    ("Gundogan", "İlkay Gündoğan"),
    ("Lionel Messi", "Lionel Messi"),
])
def test_token_indeksiyle_sonuclar_degismedi(typed, expected):
    found = ps.find_player(typed)
    assert found is not None and found["name"] == expected


@requires_player_data
def test_olmayan_isim_hala_reddediliyor():
    assert ps.find_player("Zzzq Yokoyuncu") is None
