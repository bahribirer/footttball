"""Kategori Yarışı — verilen kategoriye uyan futbolcular sırayla yazılır."""

import asyncio

from app.realtime.modes.turn_clock import AnswerResult, TurnClockMode
from app.realtime.protocol import GameMode
from app.services import category_service, player_service


class CategoryRaceMode(TurnClockMode):
    mode_id = GameMode.CATEGORY_RACE

    def __init__(self, room) -> None:
        super().__init__(room)
        self.category: category_service.Category | None = None
        self.examples: list[str] = []

    async def prepare(self) -> None:
        requested = self.room.settings.get("category_id")
        category = None
        if requested:
            category = await asyncio.to_thread(category_service.get_category, requested)
        if category is None:
            categories = await asyncio.to_thread(category_service.random_categories, 1)
            category = categories[0]
        self.category = category

    async def validate_answer(self, answer: str) -> AnswerResult:
        if self.category is None:
            return AnswerResult(False, reason="not_ready")

        canonical = await asyncio.to_thread(
            category_service.verify_answer, self.category, answer
        )
        if not canonical:
            return AnswerResult(False, reason="off_category")

        found = await asyncio.to_thread(player_service.find_player, canonical)
        return AnswerResult(True, canonical=canonical, player=found)

    async def _timeout(self, slot: int) -> None:
        # Oyun biterken örnek doğru cevapları göster.
        if self.category and not self.examples:
            self.examples = await asyncio.to_thread(
                category_service.sample_answers, self.category, 5
            )
            await self.emit("examples", answers=self.examples)
        await super()._timeout(slot)

    def round_payload(self) -> dict:
        return {
            "category": self.category.to_dict() if self.category else None,
            "examples": self.examples,
        }
