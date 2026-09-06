"""Kopan bağlantının oyunu bitirmemesi.

Test uçuşunda bir oyuncunun interneti kısa süre gitti; hem kendisi geri
bağlanamadı hem de rakibi "ayrıldı" görüp maçtan düştü. Sunucu artık
oyuncunun yerini bir süre koruyor ve belirteçle dönmesine izin veriyor.

Çalıştırmak için (backend kökünden, sunucu ayakta değilken):
    python -m pytest tests/test_reconnect.py -q
"""

import asyncio
import json

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import settings
from app.main import app
from app.realtime.hub import hub


async def _room(mode: str = "last_letter") -> str:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/api/v1/rooms", json={"mode": mode})
    return response.json()["code"]


class _FakeSocket:
    """`Player.send` için yeterli olan asgari soket taklidi."""

    def __init__(self) -> None:
        self.sent: list[dict] = []

    async def send_text(self, raw: str) -> None:
        self.sent.append(json.loads(raw))

    def events(self) -> list[str]:
        return [m.get("event") or m.get("type") for m in self.sent]


@pytest.mark.asyncio
async def test_kopan_oyuncu_belirtecle_ayni_yere_doner():
    code = await _room()
    socket_a, socket_b = _FakeSocket(), _FakeSocket()

    room, player_a, resumed = await hub.join(code, socket_a, "Bahri", "last_letter")
    assert resumed is False
    token = player_a.token
    slot = player_a.slot

    await hub.join(code, socket_b, "Rakip", "last_letter")

    # Ağ koptu: oyuncu odadan DÜŞMEZ, yeri korunur.
    await hub.mark_disconnected(room, player_a)
    assert player_a in room.players
    assert player_a.connected is False

    # Belirteçle dönünce aynı slot ve skor geri gelir.
    _, resumed_player, resumed_flag = await hub.join(
        code, _FakeSocket(), "Bahri", "last_letter", token
    )
    assert resumed_flag is True
    assert resumed_player is player_a
    assert resumed_player.slot == slot
    assert resumed_player.connected is True

    await hub.drop_room(code)


@pytest.mark.asyncio
async def test_yanlis_belirtec_yeni_oyuncu_sayilir():
    code = await _room()
    room, _, _ = await hub.join(code, _FakeSocket(), "Bahri", "last_letter")

    _, player, resumed = await hub.join(
        code, _FakeSocket(), "Yabanci", "last_letter", "gecersiz-belirtec"
    )
    assert resumed is False, "geçersiz belirteçle başkasının yerine geçilememeli"
    assert player.slot == 1

    await hub.drop_room(code)


@pytest.mark.asyncio
async def test_tolerans_dolunca_oyuncu_dusurulur(monkeypatch):
    monkeypatch.setattr(settings, "RECONNECT_GRACE_SECONDS", 0)

    code = await _room()
    socket_b = _FakeSocket()
    room, player_a, _ = await hub.join(code, _FakeSocket(), "Bahri", "last_letter")
    await hub.join(code, socket_b, "Rakip", "last_letter")

    await hub.mark_disconnected(room, player_a)
    await asyncio.sleep(0.05)
    await hub.expire_disconnected()

    assert player_a not in room.players, "tolerans dolunca oyuncu düşmeli"
    assert "opponent_left" in socket_b.events(), "rakibe ancak o zaman bildirilmeli"

    await hub.drop_room(code)
