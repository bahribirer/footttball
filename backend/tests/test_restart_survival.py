"""Odaların yeniden başlatmayı atlatması ve paylaşılan depo.

Oda durumu süreç belleğindeydi: her dağıtım o an oynanan maçları
öldürüyordu. Otomatik dağıtım kurulunca bu her backend commit'inde
yaşanır hale geldi.
"""

import json

import pytest

from app.realtime import persistence, store as room_store
from app.realtime.hub import RoomHub
from app.realtime.protocol import GameMode
from app.realtime.room import Player, Room


@pytest.fixture
def snapshot_file(tmp_path, monkeypatch):
    path = tmp_path / "rooms.snapshot.json"
    monkeypatch.setenv("ROOM_SNAPSHOT_PATH", str(path))
    return path


def _room_with_players(code: str = "1234") -> Room:
    room = Room(code=code, mode=GameMode.TIKI_TAKA_TOE, settings={"league_id": "GB1"})
    room.had_players = True
    for slot, name in enumerate(("Bahri", "Rakip")):
        player = Player(socket=None, name=name, slot=slot)  # type: ignore[arg-type]
        player.score = slot + 1
        room.players.append(player)
    return room


@pytest.mark.asyncio
async def test_oda_yeniden_baslatmayi_atlatir(snapshot_file):
    hub = RoomHub()
    room = _room_with_players()
    tokens = [p.token for p in room.players]
    hub._rooms[room.code] = room

    assert await hub.snapshot() == 1
    assert snapshot_file.exists()

    # Yeni süreç: bellek boş, disk dolu.
    fresh = RoomHub()
    assert await fresh.restore() == 1

    restored = fresh.get("1234")
    assert restored is not None
    assert restored.mode == GameMode.TIKI_TAKA_TOE
    assert restored.settings == {"league_id": "GB1"}
    assert [p.name for p in restored.players] == ["Bahri", "Rakip"]
    assert [p.score for p in restored.players] == [1, 2]
    # Belirteçler korunmalı: istemci onlarla geri bağlanıyor.
    assert [p.token for p in restored.players] == tokens
    # Oyuncular kopuk gelir; soketleriyle döneceklerdir.
    assert all(not p.connected for p in restored.players)


@pytest.mark.asyncio
async def test_ayni_goruntuden_iki_kez_oda_dirilmez(snapshot_file):
    hub = RoomHub()
    hub._rooms["1234"] = _room_with_players()
    await hub.snapshot()

    first = RoomHub()
    assert await first.restore() == 1
    second = RoomHub()
    assert await second.restore() == 0, "anlik goruntu tuketilmis olmali"


@pytest.mark.asyncio
async def test_eski_goruntu_yok_sayilir(snapshot_file, monkeypatch):
    hub = RoomHub()
    hub._rooms["1234"] = _room_with_players()
    await hub.snapshot()

    payload = json.loads(snapshot_file.read_text())
    payload["saved_at"] -= persistence.RESTORE_MAX_AGE_SECONDS + 60
    snapshot_file.write_text(json.dumps(payload))

    fresh = RoomHub()
    assert await fresh.restore() == 0


@pytest.mark.asyncio
async def test_bos_ve_bitmis_odalar_kaydedilmez(snapshot_file):
    hub = RoomHub()

    # Kimse bağlanmamış rezerve oda.
    reserved = Room(code="1111", mode=GameMode.LAST_LETTER)
    hub._rooms["1111"] = reserved

    # Maçı bitmiş oda.
    finished = _room_with_players("2222")

    class _Done:
        finished = True

        def snapshot(self):
            return None

    finished.engine = _Done()
    hub._rooms["2222"] = finished

    assert await hub.snapshot() == 0


@pytest.mark.asyncio
async def test_bozuk_goruntu_acilisi_engellemez(snapshot_file):
    snapshot_file.write_text("{ bu gecerli json degil")
    hub = RoomHub()
    assert await hub.restore() == 0
    assert not snapshot_file.exists(), "bozuk dosya temizlenmeli"


# --- paylaşılan depo ----------------------------------------------------

@pytest.mark.asyncio
async def test_bellek_deposu_varsayilan(monkeypatch):
    monkeypatch.delenv("REDIS_URL", raising=False)
    store = room_store.build_store()
    assert isinstance(store, room_store.MemoryStore)
    assert store.multi_process is False


@pytest.mark.asyncio
async def test_redis_url_verilince_redis_secilir(monkeypatch):
    monkeypatch.setenv("REDIS_URL", "redis://localhost:6379/0")
    store = room_store.build_store()
    assert isinstance(store, room_store.RedisStore)
    assert store.multi_process is True


@pytest.mark.asyncio
async def test_bellek_deposu_yayini_yerel_aboneye_verir():
    store = room_store.MemoryStore()
    seen: list[dict] = []

    async def handler(message: dict) -> None:
        seen.append(message)

    await store.subscribe("1234", handler)
    await store.publish("1234", {"type": "state", "payload": {"x": 1}})
    assert seen == [{"type": "state", "payload": {"x": 1}}]

    await store.unsubscribe("1234")
    await store.publish("1234", {"type": "state"})
    assert len(seen) == 1, "abonelik kapandiktan sonra mesaj gelmemeli"


@pytest.mark.asyncio
async def test_depo_odayi_saklar_ve_siler():
    store = room_store.MemoryStore()
    await store.save_room("1234", {"code": "1234", "mode": "last_letter"})
    assert (await store.load_room("1234"))["mode"] == "last_letter"
    await store.delete_room("1234")
    assert await store.load_room("1234") is None
