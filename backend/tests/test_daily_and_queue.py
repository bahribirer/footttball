"""Günlük meydan okuma ve hızlı eşleşme.

İkisi de aynı sorunu hedefliyor: oynamak için arkadaşının aynı anda
müsait olması gerekiyordu.
"""

from datetime import date

import pytest

from app.realtime.matchmaking import Matchmaker
from app.realtime.protocol import GameMode
from app.services import daily_service
from tests.conftest import requires_player_data


# --- günlük meydan okuma ------------------------------------------------

def test_sira_numarasi_gunle_artar():
    first = daily_service.puzzle_number(daily_service.EPOCH)
    assert first == 1
    assert daily_service.puzzle_number(date(2026, 9, 11)) == 11


@requires_player_data
def test_ayni_gun_ayni_tahta():
    """Herkes ayni bulmacayi cozmeli; tahta tarihten turetilir."""
    day = date(2026, 9, 15)
    first = daily_service.board(day)
    second = daily_service.board(day)
    assert first == second


@requires_player_data
def test_farkli_gun_farkli_tahta():
    a = daily_service.board(date(2026, 9, 15))
    b = daily_service.board(date(2026, 9, 16))
    assert (a["nations"], a["clubs"]) != (b["nations"], b["clubs"])


@requires_player_data
def test_tahta_uc_ucluk():
    board = daily_service.board(date(2026, 9, 15))
    assert len(board["nations"]) == daily_service.BOARD_SIZE
    assert len(board["clubs"]) == daily_service.BOARD_SIZE


def test_paylasim_metni_cevap_sizdirmaz():
    text = daily_service.share_text(7, [True, False, True] * 3)
    assert "Tiki Taka Toe #7" in text
    assert "6/9" in text
    assert text.count("🟩") == 6
    assert text.count("⬜") == 3
    # Futbolcu adi gecmemeli: paylasim bulmacayi bozmamali.
    assert not any(ch.isalpha() and ch not in "TikaToe" for ch in text.split("\n", 1)[1])


def test_eksik_sonuc_listesi_tamamlanir():
    """Yarim birakilan oyun da paylasilabilmeli."""
    text = daily_service.share_text(1, [True, True])
    assert "2/9" in text
    assert text.count("⬜") == 7


# --- hızlı eşleşme ------------------------------------------------------

@pytest.mark.asyncio
async def test_ilk_oyuncu_bekler_ikincisi_eslesir(monkeypatch):
    created: dict = {}

    class _FakeRoom:
        code = "4242"

    class _FakeHub:
        async def reserve(self, mode, settings):
            created["mode"] = mode
            created["settings"] = settings
            return _FakeRoom()

    import app.realtime.hub as hub_module
    monkeypatch.setattr(hub_module, "hub", _FakeHub())

    maker = Matchmaker()
    first = await maker.enqueue(object(), "Bahri", GameMode.LAST_LETTER.value)
    assert first.matched_code is None
    assert (await maker.waiting_count())[GameMode.LAST_LETTER.value] == 1

    second = await maker.enqueue(object(), "Rakip", GameMode.LAST_LETTER.value)
    assert second.matched_code == "4242"
    assert first.matched_code == "4242", "bekleyen de uyandirilmali"
    assert first.event.is_set()
    assert created["mode"] == GameMode.LAST_LETTER.value
    # Kuyruk bosalmali.
    assert await maker.waiting_count() == {}


@pytest.mark.asyncio
async def test_farkli_modlar_eslesmez():
    maker = Matchmaker()
    a = await maker.enqueue(object(), "A", GameMode.LAST_LETTER.value)
    b = await maker.enqueue(object(), "B", GameMode.CATEGORY_RACE.value)
    assert a.matched_code is None and b.matched_code is None
    counts = await maker.waiting_count()
    assert counts[GameMode.LAST_LETTER.value] == 1
    assert counts[GameMode.CATEGORY_RACE.value] == 1


@pytest.mark.asyncio
async def test_vazgecen_kuyruktan_duser():
    maker = Matchmaker()
    entry = await maker.enqueue(object(), "A", GameMode.LAST_LETTER.value)
    await maker.cancel(entry)
    assert await maker.waiting_count() == {}


@pytest.mark.asyncio
async def test_cok_bekleyen_dusurulur(monkeypatch):
    maker = Matchmaker()
    entry = await maker.enqueue(object(), "A", GameMode.LAST_LETTER.value)
    entry.joined_at -= 10_000
    assert await maker.sweep() == 1
    assert entry.event.is_set(), "dusen oyuncu uyandirilmali"
    assert await maker.waiting_count() == {}
