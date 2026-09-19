"""Bot rakip — dört modda da hamle yapıyor mu.

Bot odaya sahte oyuncu olarak oturur; motorlar farkı bilmez. Testler gerçek
motorları kullanır, yalnızca botun düşünme süresi kısaltılır ve veritabanı
soruları sabit cevaplarla değiştirilir — böylece oyuncu verisi olmadan da
koşarlar.
"""

import asyncio
import json

import pytest

from app.realtime import bot as bot_module
from app.realtime.hub import RoomHub
from app.realtime.protocol import GameMode
from app.realtime.room import Player
from app.services import bot_service


class _HumanSocket:
    def __init__(self) -> None:
        self.sent: list[dict] = []

    async def send_text(self, raw: str) -> None:
        self.sent.append(json.loads(raw))

    def events(self) -> list[str]:
        return [m.get("event") or m.get("type") for m in self.sent]

    def relays(self) -> list[dict]:
        return [m["data"] for m in self.sent if m.get("type") == "relay"]


@pytest.fixture
def fast_bot(monkeypatch):
    """Bot anında düşünsün, hep bilsin, DB'ye gitmesin."""
    monkeypatch.setattr(bot_service, "think_time", lambda d: 0.01)
    monkeypatch.setattr(bot_service, "knows", lambda d: True)
    monkeypatch.setattr(bot_service, "player_for_cell", lambda n, c: "Lionel Messi")
    monkeypatch.setattr(bot_service, "random_wrong_name", lambda: "Yanlış Adam")
    monkeypatch.setattr(bot_service, "guess_from_career", lambda clubs, ex: ["Ronaldinho"])
    monkeypatch.setattr(bot_service, "answer_for_category", lambda cid, used, limit=30: "Erling Haaland")


async def _room_with_bot(hub: RoomHub, mode: GameMode, settings: dict | None = None):
    room = await hub.reserve(mode.value, settings or {})
    bot = await hub.add_bot(room, "medium")
    human_socket = _HumanSocket()
    human = Player(socket=human_socket, name="Bahri", slot=0)  # type: ignore[arg-type]
    room.players.insert(0, human)
    room.had_players = True
    return room, human, human_socket, bot


async def _settle(seconds: float = 0.5) -> None:
    await asyncio.sleep(seconds)


@pytest.mark.asyncio
async def test_bot_odaya_oturur_ve_insan_kurucu_olur():
    hub = RoomHub()
    room = await hub.reserve(GameMode.PLAYER_GUESS.value, {"round_count": 3})
    bot = await hub.add_bot(room, "hard")
    assert bot.is_bot and bot.slot == 1
    assert room.has_bot
    assert room.settings["vs_bot"] is True
    assert "zor" in bot.name


@pytest.mark.asyncio
async def test_bot_tek_basina_odayi_dolu_tutmaz():
    hub = RoomHub()
    room = await hub.reserve(GameMode.PLAYER_GUESS.value, {})
    await hub.add_bot(room, "easy")
    assert room.is_empty, "yalniz bot varken oda bos sayilmali"


@pytest.mark.asyncio
async def test_insan_ayrilinca_botlu_oda_kapanir(fast_bot):
    hub = RoomHub()
    room, human, _, bot = await _room_with_bot(hub, GameMode.PLAYER_GUESS, {"round_count": 3})
    await hub.leave(room, human)
    assert hub.get(room.code) is None, "insan gidince oda dusmeli"
    assert bot.socket.brain._stopped  # type: ignore[attr-defined]


@pytest.mark.asyncio
async def test_botlu_oda_anlik_goruntuye_girmez(fast_bot, tmp_path, monkeypatch):
    monkeypatch.setenv("ROOM_SNAPSHOT_PATH", str(tmp_path / "s.json"))
    hub = RoomHub()
    await _room_with_bot(hub, GameMode.PLAYER_GUESS, {"round_count": 3})
    assert await hub.snapshot() == 0


# --- Tiki Taka Toe ------------------------------------------------------

@pytest.mark.asyncio
async def test_ttt_bot_adini_duyurur_ve_sirasi_gelince_oynar(fast_bot, monkeypatch):
    from app.realtime.modes import tiki_taka_toe as ttt
    monkeypatch.setattr(ttt.grid_service, "build_grid",
                        lambda league: (["Argentina", "Brazil", "France"],
                                        ["PSG", "Barcelona", "Real Madrid"]))
    hub = RoomHub()
    room, human, hs, bot = await _room_with_bot(hub, GameMode.TIKI_TAKA_TOE, {"league_id": "RANDOM"})
    engine = hub.build_engine(room)
    await engine.start()
    await _settle()

    relays = hs.relays()
    assert any(r.get("type") == "announceName" and r.get("playerType") == "O" for r in relays)

    # İnsan (X) bir hamle yapar; bot (O) cevap vermeli.
    await engine.handle_relay(human, {"index": 5, "symbol": "X", "playerName": "Messi"})
    await _settle(1.5)   # selectCell + 0.8 sn bekleme + hamle
    bot_moves = [r for r in hs.relays() if r.get("symbol") == "O" and "index" in r]
    assert bot_moves, "bot hamle yapmadi"
    assert bot_moves[-1]["index"] in ttt_playable() and bot_moves[-1]["index"] != 5
    assert bot_moves[-1].get("playerName") == "Lionel Messi"


def ttt_playable():
    return {5, 6, 7, 9, 10, 11, 13, 14, 15}


@pytest.mark.asyncio
async def test_ttt_bot_kazanmayi_engeller(fast_bot, monkeypatch):
    """İnsan iki taş dizmişse bot üçüncüyü kapatmalı (zor/orta)."""
    from app.realtime.modes import tiki_taka_toe as ttt
    monkeypatch.setattr(ttt.grid_service, "build_grid",
                        lambda league: (["A", "B", "C"], ["X1", "X2", "X3"]))
    hub = RoomHub()
    room, human, hs, bot = await _room_with_bot(hub, GameMode.TIKI_TAKA_TOE, {})
    brain = bot.socket.brain  # type: ignore[attr-defined]
    brain.difficulty = "hard"
    engine = hub.build_engine(room)
    await engine.start()
    await _settle(0.2)
    # Tahta: X 5 ve 6'da; bot 7'yi kapatmalı.
    brain.squares[5] = "X"; brain.squares[6] = "X"; brain.squares[10] = "O"
    assert brain._choose_cell() == 7


# --- Oyuncu Tahmin ------------------------------------------------------

@pytest.mark.asyncio
async def test_player_guess_bot_secer_ve_cevaplar(fast_bot, monkeypatch):
    from app.realtime.modes import player_guess as pg
    monkeypatch.setattr(pg.pool_service, "build_duel_board",
                        lambda: (["Argentina", "Brazil", "France", "Spain", "Italy"],
                                 ["PSG", "Barcelona", "Real Madrid", "Juventus", "Bayern"]))
    monkeypatch.setattr(pg.settings, "PG_PICK_COUNTDOWN", 0)
    monkeypatch.setattr(pg.settings, "PG_ANSWER_COUNTDOWN", 0)
    monkeypatch.setattr(pg, "PICK_SECONDS", 2)
    monkeypatch.setattr(pg.player_service, "verify_player", lambda n, c, k: n == "Lionel Messi")
    monkeypatch.setattr(pg.player_service, "find_player", lambda n: {"name": n, "image_url": None})

    hub = RoomHub()
    room, human, hs, bot = await _room_with_bot(hub, GameMode.PLAYER_GUESS, {"round_count": 1})
    engine = hub.build_engine(room)
    await engine.start()
    await _settle(4.0)

    # Bot 1. slot: tek turda kulüp seçer. Seçim olayı yayınlanmış olmalı.
    assert "picked" in hs.events() or engine.selected_club is not None
    # Cevap aşamasında bot doğru bilir ve turu alır.
    assert bot.score >= 1 or "correct_answer" in hs.events()


# --- Kariyer Yolu -------------------------------------------------------

@pytest.mark.asyncio
async def test_career_bot_acilan_kulupten_cikarim_yapar(fast_bot, monkeypatch):
    from app.realtime.modes import career_path as cp
    from app.services import career_service
    sample = {"key": "ronaldinho", "name": "Ronaldinho", "nationality": "Brazil",
              "position": None, "image_url": None,
              "path": [{"club": "Grêmio", "start": 1998, "end": 2001},
                       {"club": "Paris Saint-Germain", "start": 2001, "end": 2003},
                       {"club": "FC Barcelona", "start": 2003, "end": 2008}]}
    monkeypatch.setattr(career_service, "pick_player", lambda ex: sample)
    monkeypatch.setattr(career_service, "matches", lambda g, k: g == "Ronaldinho")
    monkeypatch.setattr(cp, "OPEN_COUNTDOWN", 0)

    hub = RoomHub()
    room, human, hs, bot = await _room_with_bot(hub, GameMode.CAREER_PATH, {"round_count": 1})
    engine = hub.build_engine(room)
    await engine.start()
    await _settle(1.5)

    assert "correct_answer" in hs.events(), hs.events()
    assert bot.score == 1


@pytest.mark.asyncio
async def test_career_bot_cozumu_okumaz(fast_bot, monkeypatch):
    """Botun beyni state'ten yalnız kendi görebildiği kulüpleri alır."""
    from app.realtime.modes import career_path as cp
    from app.services import career_service
    captured = {}
    def spy(clubs, ex):
        captured["clubs"] = list(clubs); return []
    monkeypatch.setattr(bot_service, "guess_from_career", spy)
    sample = {"key": "x y", "name": "X Y", "nationality": "Z", "position": None, "image_url": None,
              "path": [{"club": "Gizli1", "start": 1, "end": 2}, {"club": "Gizli2", "start": 2, "end": 3},
                       {"club": "Gizli3", "start": 3, "end": None}]}
    monkeypatch.setattr(career_service, "pick_player", lambda ex: sample)
    monkeypatch.setattr(cp, "OPEN_COUNTDOWN", 0)
    hub = RoomHub()
    room, human, hs, bot = await _room_with_bot(hub, GameMode.CAREER_PATH, {"round_count": 1})
    engine = hub.build_engine(room)
    await engine.start()
    await _settle(1.0)
    assert captured.get("clubs") == ["Gizli1"], "bot yalniz acik olan ilk kulubu gormeli"


# --- Kategori Yarışı ----------------------------------------------------

@pytest.mark.asyncio
async def test_category_bot_sirasi_gelince_cevaplar(fast_bot, monkeypatch):
    from app.realtime.modes import category_race as cr
    from app.services import category_service
    cat = category_service.Category("nat:Norway", "Norveçli", "1=1", (), difficulty="easy")
    monkeypatch.setattr(category_service, "get_category", lambda cid: cat)
    monkeypatch.setattr(category_service, "random_categories", lambda count=3: [cat])
    monkeypatch.setattr(category_service, "verify_answer", lambda c, n: "Erling Haaland" if "Haaland" in n else None)
    monkeypatch.setattr(cr.player_service, "find_player", lambda n: {"name": n, "image_url": None, "club": None, "country": None}, raising=False)

    hub = RoomHub()
    room, human, hs, bot = await _room_with_bot(hub, GameMode.CATEGORY_RACE, {"clock_seconds": 30, "penalty": 3})
    engine = hub.build_engine(room)
    await engine.start()
    # Sırayı bota ver.
    engine.current_turn = 1
    await engine.push_state()
    await _settle(1.0)

    assert "accepted" in hs.events(), hs.events()
    assert bot.score == 1
    assert engine.current_turn == 0, "cevaptan sonra sira insana gecmeli"
