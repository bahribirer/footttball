"""Oyuncu Tahmin'de tur atlama teklifi.

Test uçuşunda kimsenin bilemediği turlarda sayacın dolmasını beklemek
oyunun ritmini bozuyordu. Bir oyuncu pas teklif eder, rakip kabul ya da
ret verir — Tiki Taka Toe'daki rövanş isteğiyle aynı akış.

Çalıştırmak için (backend kökünden):
    python -m pytest tests/test_pass_round.py -q
"""

import json

import pytest

from app.realtime.modes.player_guess import PlayerGuessMode


class _FakeSocket:
    def __init__(self) -> None:
        self.sent: list[dict] = []

    async def send_text(self, raw: str) -> None:
        self.sent.append(json.loads(raw))

    def events(self) -> list[str]:
        return [m.get("event") for m in self.sent if m.get("event")]


class _FakePlayer:
    def __init__(self, slot: int) -> None:
        self.slot = slot
        self.score = 0
        self.socket = _FakeSocket()
        self.connected = True

    async def send(self, message: dict) -> None:
        await self.socket.send_text(json.dumps(message))


class _FakeRoom:
    def __init__(self) -> None:
        self.code = "TEST"
        self.settings: dict = {"round_count": 3}
        self.players = [_FakePlayer(0), _FakePlayer(1)]

    def opponent_of(self, player):
        return next((p for p in self.players if p.slot != player.slot), None)

    async def broadcast(self, message: dict) -> None:
        for player in self.players:
            await player.send(message)


def _mode_in_answering() -> tuple[PlayerGuessMode, _FakeRoom]:
    room = _FakeRoom()
    mode = PlayerGuessMode(room)
    mode.phase = "answering"
    mode.selected_nation = "Turkey"
    mode.selected_club = "Trabzonspor"
    mode.attempts = {0: 3, 1: 3}
    mode.wrong_guesses = {0: [], 1: []}
    return mode, room


@pytest.mark.asyncio
async def test_kabul_edilen_pas_turu_puansiz_kapatir():
    mode, room = _mode_in_answering()
    asker, decider = room.players

    await mode.handle_action(asker, {"action": "pass_request"})
    assert mode.pass_request_by == 0
    assert "pass_requested" in decider.socket.events()

    await mode.handle_action(decider, {"action": "pass_response", "accept": True})

    assert "pass_accepted" in asker.socket.events()
    # Cevap aşaması erken biter, kimse puan almaz.
    assert mode._answer_event.is_set()
    assert mode.round_winner is None
    assert all(player.score == 0 for player in room.players)


@pytest.mark.asyncio
async def test_reddedilen_pas_turu_surdurur_ve_tekrar_sorulamaz():
    mode, room = _mode_in_answering()
    asker, decider = room.players

    await mode.handle_action(asker, {"action": "pass_request"})
    await mode.handle_action(decider, {"action": "pass_response", "accept": False})

    assert "pass_declined" in asker.socket.events()
    assert not mode._answer_event.is_set()
    assert mode.pass_request_by is None
    assert 0 in mode.pass_blocked

    # Aynı turda ikinci teklif kabul edilmez.
    await mode.handle_action(asker, {"action": "pass_request"})
    assert mode.pass_request_by is None
    assert mode.state()["pass_request_by"] is None


@pytest.mark.asyncio
async def test_teklifi_veren_kendi_teklifini_onaylayamaz():
    mode, room = _mode_in_answering()
    asker, _ = room.players

    await mode.handle_action(asker, {"action": "pass_request"})
    await mode.handle_action(asker, {"action": "pass_response", "accept": True})

    assert mode.pass_request_by == 0
    assert not mode._answer_event.is_set()


@pytest.mark.asyncio
async def test_cevap_asamasi_disinda_pas_verilemez():
    mode, room = _mode_in_answering()
    mode.phase = "picking"
    asker, _ = room.players

    await mode.handle_action(asker, {"action": "pass_request"})

    assert mode.pass_request_by is None
    errors = [m.get("code") for m in asker.socket.sent if m.get("type") == "error"]
    assert "game_not_running" in errors


@pytest.mark.asyncio
async def test_durum_bekleyen_teklifi_tasir():
    """Yeniden bağlanan oyuncu da açık teklifi görmeli."""
    mode, room = _mode_in_answering()
    asker, _ = room.players

    await mode.handle_action(asker, {"action": "pass_request"})

    state = mode.state()
    assert state["pass_request_by"] == 0
    assert state["pass_blocked"] == []
