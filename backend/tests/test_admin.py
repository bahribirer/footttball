"""Yönetim paneli: anahtar zorunlu, oda listesi, duyuru, oda kapatma."""

import pytest
from fastapi.testclient import TestClient

from app.core.config import settings
from app.main import app
from app.services import admin_service


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(settings, "ADMIN_TOKEN", "gizli")
    admin_service.clear_notice()
    with TestClient(app) as c:
        yield c


H = {"X-Admin-Token": "gizli"}


def _drain(ws, want, limit=40):
    for _ in range(limit):
        m = ws.receive_json()
        if m.get("type") == want or m.get("event") == want:
            return m
    raise AssertionError(f"{want} gelmedi")


def test_anahtarsiz_ve_yanlis_anahtar_reddedilir(client):
    assert client.get("/api/v1/admin/overview").status_code == 401
    assert client.get("/api/v1/admin/overview", headers={"X-Admin-Token": "yok"}).status_code == 401
    assert client.get("/api/v1/admin/overview", headers=H).status_code == 200


def test_anahtar_tanimli_degilse_panel_kapali(client, monkeypatch):
    monkeypatch.setattr(settings, "ADMIN_TOKEN", "")
    assert client.get("/api/v1/admin/overview", headers=H).status_code == 503
    # Sayfa yine servis edilir ama veri çekemez.
    assert client.get("/admin").status_code == 200


def test_panel_sayfasi_ve_genel_bakis(client):
    html = client.get("/admin")
    assert html.status_code == 200 and "YÖNETİM" in html.text
    o = client.get("/api/v1/admin/overview", headers=H).json()
    assert {"server", "counts", "scores", "notice"} <= set(o)
    assert o["counts"]["rooms"] >= 0 and "players" in o["scores"]


def test_odalar_listelenir_ve_kapatilir(client):
    code = client.post("/api/v1/rooms", json={"mode": "player_guess"}).json()["code"]
    with client.websocket_connect(f"/ws/v2/{code}?name=Ayşe&mode=player_guess&pid=cihaz1") as ws:
        _drain(ws, "joined")
        rooms = client.get("/api/v1/admin/rooms", headers=H).json()["rooms"]
        mine = next(r for r in rooms if r["code"] == code)
        assert mine["mode"] == "player_guess"
        assert mine["players"][0]["name"] == "Ayşe" and mine["players"][0]["player_id"] == "cihaz1"
        assert mine["engine"] is None  # tek oyuncu, motor yok

        r = client.post(f"/api/v1/admin/rooms/{code}/close", headers=H, json={"reason": "bakım"})
        assert r.status_code == 200
        notice = _drain(ws, "admin_notice")
        assert notice["message"] == "bakım"
    assert client.get(f"/api/v1/rooms/{code}").json()["room_exists"] is False
    assert client.post("/api/v1/admin/rooms/XXXX/close", headers=H).status_code == 404


def test_duyuru_odadakilere_gider_ve_panoya_yazilir(client):
    code = client.post("/api/v1/rooms", json={"mode": "career_path"}).json()["code"]
    assert client.get("/api/v1/notice").json()["notice"] is None
    with client.websocket_connect(f"/ws/v2/{code}?name=A&mode=career_path") as ws:
        _drain(ws, "joined")
        r = client.post("/api/v1/admin/notify", headers=H,
                        json={"title": "Bakım", "message": "10 dk sonra bakım", "ttl_seconds": 600})
        assert r.status_code == 200 and r.json()["delivered"] == 1
        n = _drain(ws, "admin_notice")
        assert n["title"] == "Bakım"
    public = client.get("/api/v1/notice").json()["notice"]
    assert public and public["message"] == "10 dk sonra bakım"

    # Tek odaya hedefli duyuru panoyu değiştirmez.
    r = client.post("/api/v1/admin/notify", headers=H,
                    json={"message": "sadece oda", "target": "YOK1"})
    assert r.status_code == 404
    client.post("/api/v1/admin/notice/clear", headers=H)
    assert client.get("/api/v1/notice").json()["notice"] is None


def test_duyuru_dogrulama(client):
    assert client.post("/api/v1/admin/notify", headers=H, json={"message": ""}).status_code == 422
    assert client.post("/api/v1/admin/notify", headers=H,
                       json={"message": "x", "ttl_seconds": 1}).status_code == 422


def test_panel_dosyasi_imaja_giriyor():
    """Dockerfile static/admin'i kopyalamalı; yoksa üretimde /admin 500 verir."""
    from pathlib import Path
    dockerfile = (Path(__file__).resolve().parent.parent / "Dockerfile").read_text()
    assert "COPY static/admin" in dockerfile
    ignore = (Path(__file__).resolve().parent.parent / ".dockerignore").read_text()
    assert "static/admin" not in ignore
