"""Bot rakip.

Oyuncu illa oda kurup arkadaş çağırmak zorunda kalmasın diye. Bot, odaya
önceden oturan sahte bir oyuncu: motorlar onun bot olduğunu bilmez, aynı
`Player` nesnesi, aynı `handle_action` çağrıları. Tek fark soketi —
`BotSocket` sunucunun gönderdiği mesajları alır ve moda göre bir "beyin"e
verir; beyin de bir insan gibi düşünür, gecikir, bazen yanılır.

Bot hile yapmaz: turun çözümünü okumaz, veritabanına insanın da
sorabileceği soruları sorar (bot_service). Zorluk, ne kadar sık bildiğini
ve ne kadar hızlı olduğunu belirler.
"""

from __future__ import annotations

import asyncio
import json
import logging
import random
from typing import TYPE_CHECKING

from app.realtime.protocol import GameMode
from app.services import bot_service

if TYPE_CHECKING:
    from app.realtime.room import Player, Room

logger = logging.getLogger(__name__)


class BotSocket:
    """Sunucudan botun aldığı mesajları beyne iletir."""

    def __init__(self) -> None:
        self.brain: BotBrain | None = None

    async def send_text(self, raw: str) -> None:
        if self.brain is None:
            return
        try:
            message = json.loads(raw)
        except json.JSONDecodeError:
            return
        # Beyin işlerini ayrı görevde yapar; gönderen tarafı bekletmemeli.
        # Hata beyinde kalır: bot düşünürken patlasa da oda ve oyuncu yaşar.
        asyncio.create_task(self._safe(message))

    async def _safe(self, message: dict) -> None:
        try:
            await self.brain.on_message(message)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("Bot beyni mesajı işleyemedi: %s", message.get("type"))

    async def close(self, code: int = 1000) -> None:
        if self.brain is not None:
            self.brain.stop()


class BotBrain:
    """Bir modun bot stratejisi."""

    def __init__(self, room: "Room", me: "Player", difficulty: str) -> None:
        self.room = room
        self.me = me
        self.difficulty = difficulty
        self._tasks: set[asyncio.Task] = set()
        self._stopped = False

    @property
    def engine(self):
        return self.room.engine

    def stop(self) -> None:
        self._stopped = True
        for task in self._tasks:
            task.cancel()
        self._tasks.clear()

    def later(self, delay: float, coro) -> None:
        """Düşünme süresi sonra bir hamle. Bot durdurulduysa hiçbir şey."""
        async def _run():
            try:
                await asyncio.sleep(delay)
                if not self._stopped and self.engine is not None:
                    await coro()
            except asyncio.CancelledError:
                pass
            except Exception:
                logger.exception("Bot hamlesi hata verdi (oda %s)", self.room.code)
        task = asyncio.create_task(_run())
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)

    async def act(self, payload: dict) -> None:
        if self.engine is not None and not self._stopped:
            await self.engine.handle_action(self.me, payload)

    async def relay(self, data: dict) -> None:
        if self.engine is not None and not self._stopped:
            await self.engine.handle_relay(self.me, data)

    async def on_message(self, message: dict) -> None:
        raise NotImplementedError


# =======================================================================
#  Tiki Taka Toe — tahta istemcide; bot kendi kopyasını tutar
# =======================================================================

class TikiTakaToeBrain(BotBrain):
    PLAYABLE = (5, 6, 7, 9, 10, 11, 13, 14, 15)
    LINES = (
        (5, 6, 7), (9, 10, 11), (13, 14, 15),
        (5, 9, 13), (6, 10, 14), (7, 11, 15),
        (5, 10, 15), (7, 10, 13),
    )

    def __init__(self, room, me, difficulty) -> None:
        super().__init__(room, me, difficulty)
        self.squares: list[str] = [""] * 16
        self.nations: list[str] = []
        self.clubs: list[str] = []
        self.my_symbol = "X" if me.slot == 0 else "O"
        self.turn = "X"           # kurucu (X) başlar
        self.round = 1
        self.round_over = False

    async def on_message(self, message: dict) -> None:
        mtype = message.get("type")
        if mtype == "start":
            payload = message.get("payload") or {}
            self._new_board(payload.get("nations") or [], payload.get("clubs") or [])
            await self.relay({"type": "announceName", "name": self.me.name,
                              "playerType": self.my_symbol})
            self._maybe_move()
        elif mtype == "relay":
            await self._on_relay(message.get("from"), message.get("data") or {})
        elif mtype == "event":
            ev = message.get("event")
            if ev in ("next_round", "rematch_data"):
                if ev == "next_round":
                    self.round = int(message.get("round") or self.round + 1)
                self._new_board(message.get("nations") or [], message.get("clubs") or [])
                self._maybe_move()

    def _new_board(self, nations, clubs) -> None:
        self.squares = [""] * 16
        self.nations, self.clubs = list(nations), list(clubs)
        self.turn = "X"
        self.round_over = False

    async def _on_relay(self, from_slot, data: dict) -> None:
        if from_slot == self.me.slot:
            return
        if "index" in data and data.get("symbol") in ("X", "O"):
            index = int(data["index"])
            symbol = data["symbol"]
            if index >= 0 and 0 <= index < 16:
                self.squares[index] = symbol
            self._after_move(symbol)
            return
        if data.get("type") == "replayRequest":
            # Rövanşı hep kabul eder.
            self.later(1.0, lambda: self.act({"action": "rematch_data"}))
            self.round = 1

    def _after_move(self, moved_symbol: str) -> None:
        if self._winner():
            self.round_over = True
            # İnsan diyaloğu kapatınca next_round ister; bot da ister — sunucu
            # aynı tur numarasını bir kez işler.
            self.later(3.0, lambda: self.act({"action": "next_round", "round": self.round + 1}))
            return
        if all(self.squares[i] for i in self.PLAYABLE):
            self.round_over = True
            self.later(3.0, lambda: self.act({"action": "next_round", "round": self.round}))
            return
        self.turn = "O" if moved_symbol == "X" else "X"
        self._maybe_move()

    def _winner(self) -> str | None:
        for a, b, c in self.LINES:
            if self.squares[a] and self.squares[a] == self.squares[b] == self.squares[c]:
                return self.squares[a]
        return None

    def _maybe_move(self) -> None:
        if self.turn != self.my_symbol or self.round_over:
            return
        self.later(bot_service.think_time(self.difficulty), self._move)

    async def _move(self) -> None:
        if self.turn != self.my_symbol or self.round_over:
            return
        index = self._choose_cell()
        if index is None:
            return
        nation = self.nations[(index // 4) - 1] if self.nations else ""
        club = self.clubs[(index % 4) - 1] if self.clubs else ""
        await self.relay({"type": "selectCell", "index": index})
        await asyncio.sleep(0.8)

        name = None
        if bot_service.knows(self.difficulty):
            name = await asyncio.to_thread(bot_service.player_for_cell, nation, club)
        if name:
            self.squares[index] = self.my_symbol
            await self.relay({"index": index, "symbol": self.my_symbol, "playerName": name})
            self._after_move(self.my_symbol)
        else:
            # Bilemedi: sıra devreder.
            await self.relay({"index": -1, "symbol": self.my_symbol})
            self._after_move(self.my_symbol)

    def _choose_cell(self) -> int | None:
        empty = [i for i in self.PLAYABLE if not self.squares[i]]
        if not empty:
            return None
        rival = "O" if self.my_symbol == "X" else "X"
        # Zorda tam strateji, kolayda rastgele.
        if self.difficulty == "easy" and random.random() < 0.6:
            return random.choice(empty)
        for symbol in (self.my_symbol, rival):        # önce kazan, sonra engelle
            for a, b, c in self.LINES:
                cells = (self.squares[a], self.squares[b], self.squares[c])
                if cells.count(symbol) == 2 and "" in cells:
                    for i in (a, b, c):
                        if not self.squares[i]:
                            return i
        if not self.squares[10]:
            return 10
        corners = [i for i in (5, 7, 13, 15) if not self.squares[i]]
        return random.choice(corners) if corners else random.choice(empty)


# =======================================================================
#  Oyuncu Tahmin
# =======================================================================

class PlayerGuessBrain(BotBrain):
    def __init__(self, room, me, difficulty) -> None:
        super().__init__(room, me, difficulty)
        self.answered_round = -1
        self.picked_round = -1

    async def on_message(self, message: dict) -> None:
        if message.get("type") not in ("start", "state"):
            return
        st = message.get("payload") or {}
        phase, rnd = st.get("phase"), int(st.get("round") or 0)

        if phase == "picking" and self.picked_round != rnd:
            self.picked_round = rnd
            pool = st.get("nations") if st.get("nation_picker") == self.me.slot else st.get("clubs")
            if pool:
                choice = random.choice(pool)
                self.later(random.uniform(1.0, 3.0), lambda: self.act({"action": "pick", "value": choice}))

        elif phase == "answering" and self.answered_round != rnd and st.get("round_winner") is None:
            self.answered_round = rnd
            nation, club = st.get("selected_nation"), st.get("selected_club")
            self.later(bot_service.think_time(self.difficulty), lambda: self._answer(nation, club))

    async def _answer(self, nation, club) -> None:
        name = None
        if nation and club and bot_service.knows(self.difficulty):
            name = await asyncio.to_thread(bot_service.player_for_cell, nation, club)
        if not name:
            name = await asyncio.to_thread(bot_service.random_wrong_name)
        await self.act({"action": "guess", "value": name})


# =======================================================================
#  Kariyer Yolu — açılan kulüplerden çıkarım yapar, ipucu kullanır
# =======================================================================

class CareerPathBrain(BotBrain):
    def __init__(self, room, me, difficulty) -> None:
        super().__init__(room, me, difficulty)
        self.seen_round = -1
        self.tried: set[str] = set()
        self.thinking = False

    async def on_message(self, message: dict) -> None:
        if message.get("type") not in ("start", "state"):
            return
        st = message.get("payload") or {}
        if st.get("phase") != "answering" or st.get("round_winner") is not None:
            return
        rnd = int(st.get("round") or 0)
        if rnd != self.seen_round:
            self.seen_round = rnd
            self.tried = set()
        if self.thinking:
            return
        paths = st.get("paths") or {}
        mine = paths.get(str(self.me.slot)) or paths.get(self.me.slot) or []
        visible = [c["club"] for c in mine if c]
        if not visible:
            return
        self.thinking = True
        self.later(bot_service.think_time(self.difficulty), lambda: self._reason(visible, st))

    async def _reason(self, visible: list[str], st: dict) -> None:
        try:
            candidates = await asyncio.to_thread(bot_service.guess_from_career, visible, self.tried)
            # Aday azsa emin olur; çoksa ipucu ister (hakkı varsa), yoksa bekler.
            confident = len(candidates) <= {"easy": 1, "medium": 3, "hard": 6}[self.difficulty]
            if candidates and confident and bot_service.knows(self.difficulty):
                guess = candidates[0]
                self.tried.add(bot_service.normalize(guess))
                await self.act({"action": "guess", "value": guess})
            elif (st.get("clues_left") or {}).get(str(self.me.slot), 0) > 0 and random.random() < 0.5:
                await self.act({"action": "clue"})
            # aksi halde bir sonraki state'te (yeni kulüp açılınca) tekrar düşünür
        finally:
            self.thinking = False


# =======================================================================
#  Kategori Yarışı — sıra gelince kategoriye uyan bir isim
# =======================================================================

class CategoryRaceBrain(BotBrain):
    def __init__(self, room, me, difficulty) -> None:
        super().__init__(room, me, difficulty)
        self.pending = False

    async def on_message(self, message: dict) -> None:
        if message.get("type") not in ("start", "state"):
            return
        st = message.get("payload") or {}
        if st.get("phase") != "playing" or st.get("current_turn") != self.me.slot or self.pending:
            return
        self.pending = True
        self.later(bot_service.think_time(self.difficulty), lambda: self._answer(st))

    async def _answer(self, st: dict) -> None:
        try:
            category = (st.get("category") or {}).get("id")
            used = {bot_service.normalize(h.get("answer", "")) for h in (st.get("history") or [])}
            name = None
            if category and bot_service.knows(self.difficulty):
                name = await asyncio.to_thread(bot_service.answer_for_category, category, used)
            if not name:
                name = await asyncio.to_thread(bot_service.random_wrong_name)
            await self.act({"action": "answer", "value": name})
        finally:
            self.pending = False


BRAINS = {
    GameMode.TIKI_TAKA_TOE: TikiTakaToeBrain,
    GameMode.PLAYER_GUESS: PlayerGuessBrain,
    GameMode.CAREER_PATH: CareerPathBrain,
    GameMode.CATEGORY_RACE: CategoryRaceBrain,
}


def attach_brain(room: "Room", player: "Player", difficulty: str) -> BotBrain:
    brain_cls = BRAINS.get(room.mode)
    if brain_cls is None:
        raise ValueError(f"{room.mode} için bot yok")
    brain = brain_cls(room, player, difficulty)
    player.socket.brain = brain   # type: ignore[attr-defined]
    return brain
