"""Oda kayıt defteri: oluşturma, katılma, ayrılma ve temizlik."""

import asyncio
import logging
import random
import string
import time

from fastapi import WebSocket

from app.core.config import settings
from app.realtime import persistence, store as room_store
from app.realtime.modes.base import BaseMode
from app.realtime.modes.category_race import CategoryRaceMode
from app.realtime.modes.last_letter import LastLetterMode
from app.realtime.modes.player_guess import PlayerGuessMode
from app.realtime.modes.tiki_taka_toe import TikiTakaToeMode
from app.realtime.protocol import GameMode, ServerMessage
from app.realtime.room import Player, Room

logger = logging.getLogger(__name__)

MODE_ENGINES: dict[str, type[BaseMode]] = {
    GameMode.TIKI_TAKA_TOE: TikiTakaToeMode,
    GameMode.PLAYER_GUESS: PlayerGuessMode,
    GameMode.LAST_LETTER: LastLetterMode,
    GameMode.CATEGORY_RACE: CategoryRaceMode,
}


class RoomFull(Exception):
    pass


class RoomNotFound(Exception):
    pass


class UnknownMode(Exception):
    """İstemci sunucunun tanımadığı bir mod istedi.

    Uygulama sunucudan eskiyse ya da ileride kaldırılmış bir mod hâlâ
    istemcide duruyorsa buraya düşer. Sessizce 500 vermek yerine istemciye
    "güncelle" diyebilmek için ayrı bir tip.
    """


class ModeMismatch(Exception):
    def __init__(self, expected: str) -> None:
        super().__init__(expected)
        self.expected = expected


class RoomHub:
    def __init__(self) -> None:
        self._rooms: dict[str, Room] = {}
        self._lock = asyncio.Lock()
        # Tek süreçte bellek, REDIS_URL verilince Redis. Süreçler arası
        # paylaşım ve yayın bu katmandan geçer.
        self.store: room_store.RoomStore = room_store.build_store()

    async def start_store(self) -> None:
        try:
            await self.store.start()
        except Exception:
            # Redis gelmediyse oyunu durdurmak yerine tek süreçli çalışılır.
            logger.exception("Paylasilan depo acilamadi, bellege dusuluyor")
            self.store = room_store.MemoryStore()
            await self.store.start()

    async def stop_store(self) -> None:
        try:
            await self.store.stop()
        except Exception:
            logger.exception("Depo kapatilamadi")

    @property
    def multi_process(self) -> bool:
        return getattr(self.store, "multi_process", False)

    async def _publish_room(self, room: Room) -> None:
        """Oda durumunu paylaşılan depoya yazar.

        Yalnızca çok süreçli modda anlamlı; tek süreçte fazladan iş
        yapmamak için atlanır.
        """
        if not self.multi_process:
            return
        try:
            await self.store.save_room(room.code, {
                "code": room.code,
                "mode": str(room.mode),
                "settings": room.settings,
                "owner": room_store.NODE_ID,
                "players": [
                    {"name": p.name, "slot": p.slot, "score": p.score,
                     "connected": p.connected}
                    for p in room.players
                ],
            })
        except Exception:
            logger.exception("Oda durumu paylasilamadi: %s", room.code)

    # --- oda yaşam döngüsü ------------------------------------------------

    def generate_code(self) -> str:
        """Kullanımda olmayan bir oda kodu üretir."""
        for _ in range(50):
            code = "".join(random.choices(string.digits, k=settings.ROOM_CODE_LENGTH))
            if code not in self._rooms:
                return code
        raise RuntimeError("Boş oda kodu bulunamadı")

    async def reserve(self, mode: str, room_settings: dict | None = None) -> Room:
        """İstemci bağlanmadan önce odayı rezerve eder (kod çakışmasını önler)."""
        async with self._lock:
            code = self.generate_code()
            try:
                resolved = GameMode(mode)
            except ValueError as exc:
                raise UnknownMode(mode) from exc
            room = Room(code=code, mode=resolved, settings=room_settings or {})
            room.emptied_at = time.time()
            self._rooms[code] = room
        await self.attach_relay(room)
        await self._publish_room(room)
        return room

    async def join(
        self,
        code: str,
        socket: WebSocket,
        name: str,
        mode: str | None,
        token: str | None = None,
    ) -> tuple[Room, Player, bool]:
        """Odaya katılır ya da kopan oturumu geri alır.

        Üçüncü değer, bunun bir yeniden bağlanma olup olmadığını söyler.
        """
        async with self._lock:
            room = self._rooms.get(code)

            # Oda yalnızca `POST /api/v1/rooms` ile kurulur. Bağlanırken oda
            # yaratmak, katılma ekranına yazılan her kodun yeni bir oda
            # açmasına yol açıyordu.
            if room is None:
                raise RoomNotFound(code)

            if mode and room.mode != mode:
                raise ModeMismatch(room.mode)

            # Elinde geçerli belirteç olan oyuncu eski yerine döner: skoru,
            # slotu ve süren oyun korunur. Aksi halde kısa bir kopma maçı
            # bitiriyordu.
            if token:
                for existing in room.players:
                    if existing.token == token:
                        existing.socket = socket
                        existing.connected = True
                        existing.disconnected_at = None
                        if name:
                            existing.name = name
                        room.emptied_at = None
                        return room, existing, True

            active = [player for player in room.players if player.connected]
            if len(active) >= settings.MAX_PLAYERS_PER_ROOM:
                raise RoomFull(code)

            # Tolerans süresi dolmuş kopuk kayıtlar slotu bırakır.
            room.players = active

            player = Player(socket=socket, name=name or f"Oyuncu {room.next_free_slot() + 1}",
                            slot=room.next_free_slot())
            room.players.append(player)
            room.emptied_at = None
            room.had_players = True
        await self.attach_relay(room)
        await self._publish_room(room)
        return room, player, False

    async def mark_disconnected(self, room: Room, player: Player) -> None:
        """Oyuncuyu kopmuş işaretler ama odadan düşürmez.

        Tolerans süresi içinde belirteciyle dönerse oyun kaldığı yerden
        sürer; dönmezse `cleanup_loop` onu odadan çıkarır.
        """
        async with self._lock:
            player.connected = False
            player.disconnected_at = time.time()
            if not any(p.connected for p in room.players):
                room.emptied_at = time.time()

    async def leave(self, room: Room, player: Player) -> None:
        async with self._lock:
            player.connected = False
            if player in room.players:
                room.players.remove(player)
            if room.is_empty:
                room.emptied_at = time.time()

        if room.engine:
            await room.engine.on_player_left(player)

    async def drop_room(self, code: str) -> None:
        async with self._lock:
            room = self._rooms.pop(code, None)
        if room is not None:
            await self.detach_relay(room)
        if self.multi_process:
            try:
                await self.store.delete_room(code)
            except Exception:
                logger.debug("Paylasilan oda kaydi silinemedi: %s", code)

    # --- yeniden başlatmayı atlatma ---------------------------------------

    async def attach_relay(self, room: Room) -> None:
        """Odayı süreçler arası yayına bağlar.

        Tek süreçte hiçbir şey yapmaz. Çok süreçte oda kanalına abone olunur
        ve `broadcast` çağrıları depoya da yayınlanır; böylece rakibi başka
        bir sürece bağlı olan oyuncu da mesajları görür.
        """
        if not self.multi_process or room.relay_broadcast is not None:
            return

        async def _relay(target: Room, message: dict) -> None:
            try:
                await self.store.publish(target.code, message)
            except Exception:
                logger.exception("Oda yayini iletilemedi: %s", target.code)

        async def _incoming(message: dict) -> None:
            message.pop("_node", None)
            await room.deliver_local(message)

        room.relay_broadcast = _relay
        try:
            await self.store.subscribe(room.code, _incoming)
        except Exception:
            logger.exception("Oda kanalina abone olunamadi: %s", room.code)
            room.relay_broadcast = None

    async def detach_relay(self, room: Room) -> None:
        if not self.multi_process:
            return
        room.relay_broadcast = None
        try:
            await self.store.unsubscribe(room.code)
        except Exception:
            logger.debug("Oda kanali kapatilamadi: %s", room.code)

    async def begin_shutdown(self) -> None:
        """Kapanmadan önce oyunculara yeniden bağlanmalarını söyler.

        Soketi sessizce düşürmek istemciyi normal bir kopma sanıp tolerans
        süresi boyunca beklemeye itiyordu. Açık bir bildirim, yeniden
        bağlanmayı hemen başlatır — sunucu birkaç saniye sonra zaten geri
        gelmiş oluyor.
        """
        rooms = list(self._rooms.values())
        for room in rooms:
            try:
                await room.broadcast({
                    "type": ServerMessage.EVENT,
                    "event": "server_restarting",
                    "reconnect_in_seconds": 5,
                })
            except Exception:
                logger.debug("Yeniden baslatma bildirimi gonderilemedi: %s", room.code)

    async def snapshot(self) -> int:
        """Ayakta olan odaları diske yazar.

        Yalnızca gerçekten oynanan odalar kaydedilir: kimsenin bağlanmadığı
        rezerve odaları ya da biten maçları diriltmenin anlamı yok.
        """
        rooms: list[dict] = []
        async with self._lock:
            for room in self._rooms.values():
                if not room.had_players or not room.players:
                    continue
                engine = room.engine
                if engine is not None and getattr(engine, "finished", False):
                    continue
                rooms.append({
                    "code": room.code,
                    "mode": str(room.mode),
                    "settings": room.settings,
                    "created_at": room.created_at,
                    "players": [
                        {
                            "name": player.name,
                            "slot": player.slot,
                            "score": player.score,
                            "token": player.token,
                        }
                        for player in room.players
                    ],
                    # Modun kendi durumu; geri yüklemede ne kadarının
                    # kullanılabileceğine mod karar verir.
                    "engine": engine.snapshot() if engine is not None else None,
                })
        return persistence.save(rooms)

    async def restore(self) -> int:
        """Diskteki odaları geri yükler.

        Oyuncular kopuk olarak kurulur; istemciler belirteçleriyle geri
        bağlanınca yerlerine otururlar. Tolerans sayacı yeniden başlar,
        yoksa kapalı geçen süre onların hakkından yenirdi.
        """
        restored = 0
        for entry in persistence.load():
            try:
                mode = GameMode(entry["mode"])
            except (KeyError, ValueError):
                logger.warning("Bilinmeyen modlu oda atlandi: %s", entry.get("code"))
                continue

            room = Room(
                code=entry["code"],
                mode=mode,
                settings=entry.get("settings") or {},
                created_at=entry.get("created_at", time.time()),
            )
            room.had_players = True
            now = time.time()
            for raw in entry.get("players") or []:
                player = Player(
                    socket=None,  # type: ignore[arg-type]
                    name=raw.get("name", ""),
                    slot=int(raw.get("slot", 0)),
                )
                player.connected = False
                player.disconnected_at = now
                player.score = int(raw.get("score", 0))
                if raw.get("token"):
                    player.token = raw["token"]
                room.players.append(player)

            room.emptied_at = now
            room.pending_engine_state = entry.get("engine")
            async with self._lock:
                self._rooms[room.code] = room
            restored += 1

        if restored:
            logger.info("%d oda geri yuklendi", restored)
        return restored

    # --- sorgular ---------------------------------------------------------

    def get(self, code: str) -> Room | None:
        return self._rooms.get(code)

    def room_status(self, code: str) -> dict:
        room = self._rooms.get(code)
        if room is None:
            return {"room_exists": False, "is_joinable": False}

        active = len([player for player in room.players if player.connected])
        return {
            "room_exists": True,
            "is_joinable": active < settings.MAX_PLAYERS_PER_ROOM,
            "mode": room.mode,
            "players": active,
            "settings": room.settings,
        }

    # --- motor ------------------------------------------------------------

    def build_engine(self, room: Room) -> BaseMode:
        engine_cls = MODE_ENGINES[room.mode]
        room.engine = engine_cls(room)

        # Yeniden başlatmadan sonra geri yüklenen durum varsa uygulanır ve
        # tüketilir; ikinci kez kurulan motora sızmamalı.
        if room.pending_engine_state:
            try:
                room.engine.restore(room.pending_engine_state)
            except Exception:
                logger.exception("Mod durumu geri yuklenemedi: %s", room.code)
            finally:
                room.pending_engine_state = None
        return room.engine

    # --- bakım ------------------------------------------------------------

    async def expire_disconnected(self) -> None:
        """Tolerans süresi dolan kopuk oyuncuları odadan düşürür.

        Kopma anında oyuncu odada bırakılır ki geri dönebilsin; süre dolduğunda
        rakibe ancak burada "ayrıldı" bildirilir.
        """
        now = time.time()
        expired: list[tuple[Room, Player]] = []

        async with self._lock:
            for room in self._rooms.values():
                for player in list(room.players):
                    if (
                        not player.connected
                        and player.disconnected_at
                        and now - player.disconnected_at > settings.RECONNECT_GRACE_SECONDS
                    ):
                        room.players.remove(player)
                        expired.append((room, player))
                if room.players and not any(p.connected for p in room.players):
                    room.emptied_at = room.emptied_at or now

        for room, player in expired:
            logger.info("Oda %s: %s geri dönmedi, düşürüldü", room.code, player.name)
            await room.broadcast({
                "type": ServerMessage.OPPONENT_LEFT,
                "slot": player.slot,
                "name": player.name,
            })
            await room.send_room_state()
            if room.engine:
                await room.engine.on_player_left(player)

    async def cleanup_loop(self) -> None:
        """Boş kalan odaları belirli bir süre sonra siler."""
        while True:
            await asyncio.sleep(5)
            try:
                await self.expire_disconnected()
                # Kuyrukta unutulan oyuncular da temizlenir; bağlantısı
                # kopanlar zaten düşüyor ama çok uzun bekleyenler kalıyordu.
                from app.realtime.matchmaking import matchmaker
                await matchmaker.sweep()
                now = time.time()
                async with self._lock:
                    stale = [
                        code for code, room in self._rooms.items()
                        if room.is_empty
                        and room.emptied_at
                        and now - room.emptied_at > (
                            settings.EMPTY_ROOM_TTL_SECONDS if room.had_players
                            else settings.RESERVED_ROOM_TTL_SECONDS
                        )
                    ]
                    for code in stale:
                        room = self._rooms.pop(code, None)
                        if room and room.engine:
                            await room.engine.stop()
                if stale:
                    logger.info("Boş oda temizlendi: %s", ", ".join(stale))
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Oda temizliği başarısız")


hub = RoomHub()
