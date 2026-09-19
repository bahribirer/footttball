"""Skor tablosu: puanlama kuralları, günlük tekillik, API ve maç sonu kaydı."""

import asyncio

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.realtime.modes.base import BaseMode
from app.realtime.protocol import GameMode
from app.realtime.room import Player, Room
from app.services import daily_service, score_service
from tests.fakes import FakeSocket


def _humans(a="A", b="B"):
    return [{"slot": 0, "player_id": a, "name": "Ayşe"}, {"slot": 1, "player_id": b, "name": "Bora"}]


def test_insana_karsi_galibiyet_beraberlik_ve_maglubiyet_puanlari():
    score_service.record_match("tiki_taka_toe", _humans(), winner_slot=0)
    score_service.record_match("tiki_taka_toe", _humans(), winner_slot=None)
    board = {r["name_key"]: r for r in score_service.leaderboard()}
    assert board["ayşe"]["points"] == score_service.WIN + score_service.DRAW
    assert board["bora"]["points"] == score_service.LOSS + score_service.DRAW
    assert board["ayşe"]["rank"] == 1 and board["ayşe"]["wins"] == 1


def test_bota_karsi_yalniz_kazanan_puan_alir_ve_zorluk_belirler():
    players = [{"slot": 0, "player_id": "A", "name": "Ayşe"},
               {"slot": 1, "player_id": None, "name": "Bot", "is_bot": True}]
    score_service.record_match("player_guess", players, winner_slot=0, vs_bot=True, bot_difficulty="hard")
    score_service.record_match("player_guess", players, winner_slot=1, vs_bot=True, bot_difficulty="hard")
    score_service.record_match("player_guess", players, winner_slot=0, vs_bot=True, bot_difficulty="easy")
    board = score_service.leaderboard()
    assert len(board) == 1  # bot tabloya girmez
    assert board[0]["points"] == score_service.BOT_WIN["hard"] + score_service.BOT_WIN["easy"]


def test_kimliksiz_oyuncu_puan_almaz():
    score_service.record_match("career_path", [{"slot": 0, "player_id": None, "name": "x"},
                                               {"slot": 1, "player_id": None, "name": "y"}], winner_slot=0)
    assert score_service.leaderboard() == []


def test_gunluk_puan_ayni_gun_bir_kez():
    assert score_service.record_daily("A", "Ayşe", "2026-09-19", 6) is True
    assert score_service.record_daily("A", "Ayşe", "2026-09-19", 9) is False
    assert score_service.record_daily("A", "Ayşe", "2026-09-20", 3) is True
    me = score_service.summary("A")
    assert me["per_mode"] == {"daily": 9} and me["total"] == 9 and me["rank"] == 1


def test_mod_filtresi_ve_siralama():
    score_service.record_match("tiki_taka_toe", _humans(), winner_slot=1)
    score_service.record_match("category_race", _humans(), winner_slot=0)
    score_service.record_match("category_race", _humans(), winner_slot=0)
    assert [r["name_key"] for r in score_service.leaderboard("tiki_taka_toe")] == ["bora", "ayşe"]
    assert score_service.leaderboard("category_race")[0]["name_key"] == "ayşe"
    assert score_service.leaderboard()[0]["name_key"] == "ayşe"
    assert score_service.leaderboard("daily") == []


def test_api_leaderboard_ve_gunluk_gonderim():
    client = TestClient(app)
    today = daily_service.today().isoformat()
    r = client.post("/api/v1/leaderboard/daily",
                    json={"player_id": "cihaz-12345", "name": "Ayşe", "date": today, "score": 7})
    assert r.status_code == 200 and r.json()["accepted"] is True and r.json()["total"] == 7
    r = client.post("/api/v1/leaderboard/daily",
                    json={"player_id": "cihaz-12345", "name": "Ayşe", "date": today, "score": 9})
    assert r.json()["accepted"] is False

    r = client.post("/api/v1/leaderboard/daily",
                    json={"player_id": "cihaz-12345", "name": "Ayşe", "date": "2020-01-01", "score": 9})
    assert r.status_code == 400

    r = client.get("/api/v1/leaderboard", params={"mode": "all", "player_id": "cihaz-12345"})
    body = r.json()
    assert body["entries"][0]["name"] == "Ayşe" and body["me"]["rank"] == 1
    assert "career_path" in body["modes"]
    assert client.get("/api/v1/leaderboard", params={"mode": "yok"}).status_code == 400


class _DummyMode(BaseMode):
    mode_id = GameMode.PLAYER_GUESS

    async def start(self):  # pragma: no cover
        pass


def test_mac_bitince_motor_puani_yazar():
    room = Room(code="SKOR", mode=GameMode.PLAYER_GUESS)
    room.players = [
        Player(socket=FakeSocket(), name="Ayşe", slot=0, player_id="A"),
        Player(socket=FakeSocket(), name="Bora", slot=1, player_id="B"),
    ]
    engine = _DummyMode(room)
    asyncio.run(engine.finish(winner_slot=1, reason="test"))
    board = {r["name_key"]: r for r in score_service.leaderboard()}
    assert board["bora"]["points"] == score_service.WIN and board["ayşe"]["points"] == score_service.LOSS


def test_ayni_ad_farkli_cihazlardan_tek_satir():
    """Hesap yok; aynı ad iki cihazdan gelirse tabloda tek görünür."""
    score_service.record_match("tiki_taka_toe",
                               [{"slot": 0, "player_id": "tel", "name": "Bahri"},
                                {"slot": 1, "player_id": "B", "name": "Bora"}], winner_slot=0)
    score_service.record_match("tiki_taka_toe",
                               [{"slot": 0, "player_id": "sim", "name": " bahri"},
                                {"slot": 1, "player_id": "B", "name": "Bora"}], winner_slot=0)
    board = score_service.leaderboard()
    names = [r["name_key"] for r in board]
    assert names.count("bahri") == 1
    assert board[0]["points"] == 2 * score_service.WIN and board[0]["wins"] == 2
    # Özet de birleşik: telefondan bakan simülatördeki puanı da görür.
    assert score_service.summary("tel")["total"] == 2 * score_service.WIN
    assert score_service.summary("sim")["rank"] == 1


def test_eski_scores_db_name_key_ile_gocer(tmp_path, monkeypatch):
    import sqlite3
    path = tmp_path / "old.db"
    con = sqlite3.connect(path)
    con.executescript("""
        CREATE TABLE players_meta (player_id TEXT PRIMARY KEY, name TEXT NOT NULL,
                                   created_at REAL NOT NULL, updated_at REAL NOT NULL);
        CREATE TABLE score_events (id INTEGER PRIMARY KEY AUTOINCREMENT, player_id TEXT NOT NULL,
            mode TEXT NOT NULL, kind TEXT NOT NULL, points INTEGER NOT NULL,
            vs_bot INTEGER NOT NULL DEFAULT 0, opponent_id TEXT, ref TEXT, created_at REAL NOT NULL);
        INSERT INTO players_meta VALUES ('x', 'Ayşe', 1, 1);
        INSERT INTO score_events (player_id, mode, kind, points, created_at) VALUES ('x', 'daily', 'daily', 5, 1);
    """)
    con.commit(); con.close()
    monkeypatch.setattr(score_service, "db_path", lambda: str(path))
    monkeypatch.setattr(score_service, "_initialised", False)
    board = score_service.leaderboard()
    assert board[0]["name_key"] == "ayşe" and board[0]["points"] == 5
