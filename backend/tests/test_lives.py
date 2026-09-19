"""Can sistemi: saatte 10 maç, cihaz kimliğine bağlı."""

import time

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import lives_service


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def _drain(ws, want, limit=40):
    for _ in range(limit):
        m = ws.receive_json()
        if m.get("type") == want or m.get("event") == want:
            return m
    raise AssertionError(f"{want} gelmedi")


def test_yeni_cihaz_tam_canla_baslar():
    s = lives_service.status("cihaz-aaaa")
    assert s["lives"] == 10 and s["max"] == 10 and 0 < s["resets_in"] <= 3600


def test_can_duser_ve_sifirda_reddedilir():
    for _ in range(10):
        lives_service.consume("cihaz-bbbb")
    assert lives_service.status("cihaz-bbbb")["lives"] == 0
    with pytest.raises(lives_service.NoLives):
        lives_service.check("cihaz-bbbb")
    # 0'ın altına inmez
    assert lives_service.consume("cihaz-bbbb")["lives"] == 0


def test_pencere_dolunca_yenilenir(monkeypatch):
    for _ in range(10):
        lives_service.consume("cihaz-cccc")
    real = time.time
    monkeypatch.setattr(lives_service.time, "time", lambda: real() + 3601)
    assert lives_service.status("cihaz-cccc")["lives"] == 10
    lives_service.check("cihaz-cccc")  # fırlatmaz


def test_kimliksiz_istemci_serbest():
    lives_service.check(None)
    assert lives_service.consume(None) is None


def test_mac_baslayinca_iki_oyuncudan_da_can_duser(client):
    code = client.post("/api/v1/rooms", json={"mode": "player_guess"}).json()["code"]
    with client.websocket_connect(f"/ws/v2/{code}?name=A&mode=player_guess&pid=cihaz-dddd") as a, \
         client.websocket_connect(f"/ws/v2/{code}?name=B&mode=player_guess&pid=cihaz-eeee") as b:
        _drain(a, "joined"); _drain(b, "joined")
        _drain(a, "start")
    assert lives_service.status("cihaz-dddd")["lives"] == 9
    assert lives_service.status("cihaz-eeee")["lives"] == 9
    # Bekleyen kurucu (rakip gelmedi) can yakmaz.
    code2 = client.post("/api/v1/rooms", json={"mode": "player_guess"}).json()["code"]
    with client.websocket_connect(f"/ws/v2/{code2}?name=A&mode=player_guess&pid=cihaz-dddd") as a:
        _drain(a, "joined")
    assert lives_service.status("cihaz-dddd")["lives"] == 9


def test_bota_karsi_da_can_duser(client):
    code = client.post("/api/v1/rooms", json={"mode": "career_path", "vs_bot": True}).json()["code"]
    client.post(f"/api/v1/rooms/{code}/bot", json={"difficulty": "easy"})
    with client.websocket_connect(f"/ws/v2/{code}?name=A&mode=career_path&pid=cihaz-ffff") as a:
        _drain(a, "joined")
        _drain(a, "start")
    assert lives_service.status("cihaz-ffff")["lives"] == 9


def test_cani_biten_odaya_giremez(client):
    for _ in range(10):
        lives_service.consume("cihaz-gggg")
    code = client.post("/api/v1/rooms", json={"mode": "player_guess"}).json()["code"]
    with client.websocket_connect(f"/ws/v2/{code}?name=A&mode=player_guess&pid=cihaz-gggg") as ws:
        err = ws.receive_json()
        assert err["type"] == "error" and err["code"] == "no_lives"
        assert err["resets_in"] > 0 and "dk sonra" in err["message"]
    # Oda boş kaldı, kimse oturmadı.
    assert client.get(f"/api/v1/rooms/{code}").json()["players"] == 0


def test_lives_api(client):
    r = client.get("/api/v1/lives", params={"player_id": "cihaz-hhhh"})
    assert r.status_code == 200 and r.json()["lives"] == 10
    assert client.get("/api/v1/lives", params={"player_id": "kisa"}).status_code == 422


def test_yonetici_can_verir():
    for _ in range(10):
        lives_service.consume("cihaz-iiii")
    assert lives_service.grant("cihaz-iiii")["lives"] == 10
    assert lives_service.grant("cihaz-iiii", 3)["lives"] == 3
