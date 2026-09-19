"""Sunucu çökmesin: bozuk, dev, yanlış tipli istemci mesajları.

Bir oyuncunun yolladığı tek bir kötü mesaj ne süreci ne odayı ne de kendi
bağlantısını öldürmeli. Buradaki testler gerçek WebSocket uçları üzerinden
(TestClient) koşar.
"""

import json

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.realtime.hub import hub


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def _room(client, mode="player_guess", **extra) -> str:
    return client.post("/api/v1/rooms", json={"mode": mode, **extra}).json()["code"]


def _drain(ws, want: str, limit: int = 40) -> dict:
    """`want` tipli/olaylı ilk mesajı döndürür; hiçbiri gelmezse hata."""
    for _ in range(limit):
        msg = ws.receive_json()
        if msg.get("type") == want or msg.get("event") == want:
            return msg
    raise AssertionError(f"{want} gelmedi")


def _ping_ok(ws) -> None:
    ws.send_json({"type": "ping"})
    _drain(ws, "pong")


def test_bozuk_json_ve_dev_mesaj_baglantiyi_dusurmez(client):
    code = _room(client)
    with client.websocket_connect(f"/ws/v2/{code}?name=A&mode=player_guess") as ws:
        _drain(ws, "joined")
        ws.send_text("{bu json degil")
        err = _drain(ws, "error")
        assert err["code"] == "invalid_message"

        ws.send_text("[1,2,3]")
        assert _drain(ws, "error")["code"] == "invalid_message"

        ws.send_text(json.dumps({"type": "action", "pad": "x" * (20 * 1024)}))
        assert _drain(ws, "error")["message"] == "Mesaj çok büyük."

        ws.send_json({"type": "nope"})
        assert _drain(ws, "error")["code"] == "invalid_message"

        ws.send_json({"type": "relay", "data": "string degil dict"})
        _ping_ok(ws)


def test_motor_yokken_action_hata_dondurur_baglanti_surer(client):
    code = _room(client)
    with client.websocket_connect(f"/ws/v2/{code}?name=A&mode=player_guess") as ws:
        _drain(ws, "joined")
        ws.send_json({"type": "action", "action": "guess", "name": "Messi"})
        assert _drain(ws, "error")["code"] == "game_not_running"
        _ping_ok(ws)


@pytest.mark.parametrize("mode,payloads", [
    ("player_guess", [
        {"type": "action", "action": "guess"},                  # alan eksik
        {"type": "action", "action": "guess", "name": 12345},   # yanlış tip
        {"type": "action", "action": "pick", "nation": ["x"]},
        {"type": "action", "action": None},
        {"type": "action"},
    ]),
    ("career_path", [
        {"type": "action", "action": "guess", "name": {"a": 1}},
        {"type": "action", "action": "clue", "extra": 1e308},
        {"type": "action", "action": "guess", "name": "x" * 5000},
    ]),
    ("category_race", [
        {"type": "action", "action": "answer", "name": None},
        {"type": "action", "action": "answer"},
        {"type": "action", "action": "answer", "name": 3.5},
    ]),
    ("tiki_taka_toe", [
        {"type": "relay", "data": {"index": "abc", "symbol": 7}},
        {"type": "relay", "data": {"type": "next_round", "round": "x"}},
        {"type": "relay", "data": {}},
    ]),
])
def test_motor_calisirken_kotu_payload_oyunu_oldurmez(client, mode, payloads):
    """İki oyuncu bağlanır (motor başlar), biri kötü mesajlar yollar.

    Beklenen: bağlantı ping'e cevap vermeye devam eder, rakip de yaşar.
    """
    code = _room(client, mode=mode)
    with client.websocket_connect(f"/ws/v2/{code}?name=A&mode={mode}") as a, \
         client.websocket_connect(f"/ws/v2/{code}?name=B&mode={mode}") as b:
        _drain(a, "joined"); _drain(b, "joined")
        for p in payloads:
            a.send_json(p)
        _ping_ok(a)
        _ping_ok(b)
        room = hub.get(code)
        assert room is not None and room.engine is not None
        assert all(pl.connected for pl in room.players)


def test_bot_odasinda_kotu_mesaj(client):
    code = _room(client, mode="career_path", vs_bot=True)
    client.post(f"/api/v1/rooms/{code}/bot", json={"difficulty": "easy"})
    with client.websocket_connect(f"/ws/v2/{code}?name=A&mode=career_path") as ws:
        _drain(ws, "joined")
        ws.send_json({"type": "action", "action": "guess", "name": ["liste"]})
        ws.send_json({"type": "action", "action": "clue", "slot": 99})
        _ping_ok(ws)


def test_cok_oda_ayni_anda(client):
    """Yüz oda açılıp kapanınca hub sızdırmıyor ve API cevap veriyor."""
    codes = [_room(client, mode="player_guess") for _ in range(100)]
    assert len(set(codes)) == 100
    for code in codes[:10]:
        with client.websocket_connect(f"/ws/v2/{code}?name=A&mode=player_guess") as ws:
            _drain(ws, "joined")
            ws.send_json({"type": "leave"})
    assert client.get("/ping").status_code == 200
    assert client.get("/api/v1/leaderboard").status_code == 200


def test_api_kotu_girdiler(client):
    assert client.post("/api/v1/rooms", json={"mode": "yok"}).status_code in (400, 422)
    assert client.post("/api/v1/rooms", content=b"{{{", headers={"Content-Type": "application/json"}).status_code == 422
    assert client.get("/api/v1/rooms/ABCDEFGHIJKLMNOP").status_code in (200, 404)
    assert client.get("/api/v1/get_player_names", params={"name": "x" * 500}).status_code == 200
    assert client.post("/api/v1/leaderboard/daily", json={"player_id": "a", "name": "x", "date": "bugün", "score": 99}).status_code == 422
    r = client.post("/api/v1/guess_player/detail", json={"player_name": None, "nationality": 1, "club": []})
    assert r.status_code == 422
