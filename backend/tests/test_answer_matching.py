"""Cevap eşleştirme kuralları.

Test uçuşundan gelen geri bildirimler:
  * "Messi" kabul edilmiyordu — tam ad şartı vardı.
  * "Fatih Tekke / Trabzonspor / Türkiye" reddediliyordu — ana tabloda o
    dönem ve uyruk yok; tarihsel kadro katmanı bunu kapatır.

Çalıştırmak için (backend kökünden):  python -m pytest tests -q
"""

import pytest

from app.realtime.modes.last_letter import _openings, first_letter, last_letter
from app.services import player_service as ps


@pytest.mark.parametrize("typed, expected", [
    ("Messi", "Lionel Messi"),
    ("messi", "Lionel Messi"),
    ("MESSI", "Lionel Messi"),
    ("Haaland", "Erling Haaland"),
    ("Mbappe", "Kylian Mbappé"),        # aksansız yazım
    ("Gundogan", "İlkay Gündoğan"),     # Türkçe harfler
    ("Lionel Messi", "Lionel Messi"),   # tam ad hâlâ çalışır
])
def test_soyadla_yazilan_futbolcu_bulunur(typed, expected):
    found = ps.find_player(typed)
    assert found is not None, f"{typed} bulunamadı"
    assert found["name"] == expected


def test_olmayan_isim_reddedilir():
    assert ps.find_player("Zzzq Yokoyuncu") is None


@pytest.mark.parametrize("name, nation, club", [
    ("Messi", "Argentina", "Paris Saint-Germain"),
    ("Haaland", "Norway", "Manchester City"),
])
def test_hucre_dogrulamasi_soyadi_kabul_eder(name, nation, club):
    assert ps.verify_player(name, nation, club) is True


def test_yanlis_hucre_reddedilir():
    assert ps.verify_player("Messi", "Argentina", "Galatasaray") is False


@pytest.mark.skipif(not ps.has_history_layer(), reason="tarihsel katman kurulu değil")
def test_eski_donem_oyuncusu_kabul_edilir():
    # Ana tabloda Fatih Tekke'nin yalnızca Zenit ve Rubin kayıtları var,
    # uyruğu da boş. Doğru cevap yine de kabul edilmeli.
    assert ps.verify_player("Fatih Tekke", "Turkey", "Trabzonspor") is True


def test_son_harf_zinciri_soyadi_kabul_eder():
    # "Messi" yazıldığında kanonik ad "Lionel Messi"; zincir hem 'm' hem 'l'
    # ile devam edebilmeli, sonraki harf kanonik adın sonundan gelir.
    openings = _openings("Messi", "Lionel Messi")
    assert "m" in openings and "l" in openings
    assert last_letter("Lionel Messi") == "i"


def test_ilk_ve_son_harf_aksandan_etkilenmez():
    assert first_letter("Çalhanoğlu") == "c"
    assert last_letter("Mbappé") == "e"
