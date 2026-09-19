"""Kariyer Yolu modu.

Son Harf'in yerine geldi. Kurallar: yol kısmen açık, zamanla herkese bir
kulüp daha; her oyuncunun maç boyunca 3 ipucu hakkı, ipucu yalnız kullanana
açar; ilk doğru bilen turu alır.
"""

import pytest

from app.realtime.modes.career_path import CLUES_PER_MATCH, CareerPathMode
from app.services import career_service
from tests.conftest import requires_player_data
from tests.fakes import FakeRoom

SAMPLE = {
    "key": "lionel messi", "name": "Lionel Messi", "nationality": "Argentina",
    "position": "Attack", "image_url": None,
    "path": [
        {"club": "FC Barcelona", "start": 2004, "end": 2021},
        {"club": "Paris Saint-Germain", "start": 2021, "end": 2023},
        {"club": "Inter Miami CF", "start": 2023, "end": None},
    ],
}


def _mode_in_round(monkeypatch) -> tuple[CareerPathMode, FakeRoom]:
    room = FakeRoom(settings={"round_count": 3})
    mode = CareerPathMode(room)
    mode.clues_left = {0: CLUES_PER_MATCH, 1: CLUES_PER_MATCH}
    mode.player = SAMPLE
    mode.path = SAMPLE["path"]
    mode.revealed = 1
    mode.private_reveal = {0: 0, 1: 0}
    mode.attempts = {0: 5, 1: 5}
    mode.wrong_guesses = {0: [], 1: []}
    mode.phase = "answering"
    monkeypatch.setattr(career_service, "matches",
                        lambda guess, key: guess.strip().lower() in ("messi", "lionel messi"))
    return mode, room


def test_baslangicta_yalniz_ilk_kulup_acik(monkeypatch):
    mode, room = _mode_in_round(monkeypatch)
    view = mode.state()["paths"][0]
    assert view[0]["club"] == "FC Barcelona"
    assert view[1] is None and view[2] is None


def test_gizli_kulup_adi_istemciye_hic_gitmez(monkeypatch):
    """Maskelenmiş kulüp payload'da null olmalı; istemci okuyamamalı."""
    mode, room = _mode_in_round(monkeypatch)
    import json
    raw = json.dumps(mode.state(), ensure_ascii=False)
    assert "Paris Saint-Germain" not in raw
    assert "Inter Miami" not in raw


@pytest.mark.asyncio
async def test_ipucu_yalniz_kullanana_acar(monkeypatch):
    mode, room = _mode_in_round(monkeypatch)
    a, b = room.players
    await mode.handle_action(a, {"action": "clue"})

    paths = mode.state()["paths"]
    assert paths[0][1] is not None, "ipucu kullanan ikinci kulubu gormeli"
    assert paths[1][1] is None, "rakip gormemeli"
    assert mode.clues_left[0] == CLUES_PER_MATCH - 1
    assert mode.clues_left[1] == CLUES_PER_MATCH
    # Rakibe içerik değil, yalnız "ipucu kullandı" bildirimi gider.
    assert "opponent_clue" in b.socket.events()
    assert "clue_used" in a.socket.events()


@pytest.mark.asyncio
async def test_ipucu_hakki_mac_boyunca_ucle_sinirli(monkeypatch):
    mode, room = _mode_in_round(monkeypatch)
    a, _ = room.players
    for _ in range(CLUES_PER_MATCH):
        await mode.handle_action(a, {"action": "clue"})
        # Yol 3 kulüp; ikinci ipucundan sonra tamamı açılır, üçüncüsü reddedilir
        # ama hak sayısı yine de o ana kadar düşmüş olmalı.
    assert mode.clues_left[0] <= 1
    await mode.handle_action(a, {"action": "clue"})
    assert "invalid_message" in a.socket.errors()


@pytest.mark.asyncio
async def test_dogru_tahmin_turu_alir(monkeypatch):
    mode, room = _mode_in_round(monkeypatch)
    a, b = room.players
    await mode.handle_action(b, {"action": "guess", "value": "Messi"})
    assert mode.round_winner == 1
    assert b.score == 1 and a.score == 0
    assert mode._answer_event.is_set()
    assert "correct_answer" in a.socket.events()


@pytest.mark.asyncio
async def test_yanlis_tahmin_deneme_hakki_dusurur(monkeypatch):
    mode, room = _mode_in_round(monkeypatch)
    a, _ = room.players
    await mode.handle_action(a, {"action": "guess", "value": "Haaland"})
    assert mode.attempts[0] == 4
    assert mode.round_winner is None
    assert "wrong_answer" in a.socket.events()


@pytest.mark.asyncio
async def test_tur_bitince_tum_yol_acilir(monkeypatch):
    mode, room = _mode_in_round(monkeypatch)
    await mode._round_result()
    st = mode.state()
    assert all(c is not None for c in st["paths"][0])
    assert st["solution"] == "Lionel Messi"


def test_yeniden_baslatmada_ipucu_haklari_korunur(monkeypatch):
    mode, room = _mode_in_round(monkeypatch)
    mode.clues_left = {0: 1, 1: 2}
    snap = mode.snapshot()
    fresh = CareerPathMode(FakeRoom(settings={"round_count": 3}))
    fresh.restore(snap)
    assert fresh.clues_left == {0: 1, 1: 2}


# --- veri katmanı -------------------------------------------------------

@requires_player_data
def test_secilen_futbolcunun_yolu_kronolojik_ve_tekil():
    for _ in range(5):
        picked = career_service.pick_player()
        assert picked is not None
        starts = [c["start"] for c in picked["path"]]
        assert starts == sorted(starts), picked["name"]
        assert 3 <= len(picked["path"]) <= 8


@requires_player_data
def test_kulup_adi_ikilemeleri_tek_satira_iner():
    """'AC Milan' ile 'Milan AC' aynı dönemse bir kez görünmeli."""
    path = career_service.career_path("ronaldinho")
    milans = [c for c in path if "milan" in c["club"].lower()]
    assert len(milans) == 1, path


@requires_player_data
@pytest.mark.parametrize("guess, key, expected", [
    ("Messi", "lionel messi", True),
    ("De Bruyne", "kevin de bruyne", True),
    ("Haaland", "lionel messi", False),
    ("", "lionel messi", False),
])
def test_tahmin_eslestirme(guess, key, expected):
    assert career_service.matches(guess, key) is expected
