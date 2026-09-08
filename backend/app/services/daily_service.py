"""Günlük meydan okuma.

Oynamak için arkadaşının aynı anda müsait olması gerekiyordu; bu, kaç
kişinin oynadığının üstünde sert bir tavandı. Günlük meydan okuma rakip
istemiyor: herkese aynı 3x3 tahta gelir, tek deneme hakkı vardır ve sonuç
paylaşılabilir bir emoji ızgarası olarak çıkar.

Tahta günün tarihinden türetilir. Aynı gün herkes aynı tahtayı görür,
sunucu hiçbir şey saklamaz: tohum tarihten hesaplandığı için tahta her
istekte aynı üretilir. Bu, kayıt tutmadan "herkes aynı bulmacayı çözüyor"
etkisini verir.
"""

from __future__ import annotations

import hashlib
import random
from datetime import date, datetime, timezone

from app.services import pool_service

# Meydan okumanın günü UTC'ye göre değişir; herkesin aynı anda yeni tahtaya
# geçmesi için yerel saat kullanılmaz.
BOARD_SIZE = 3

# İlk günün tarihi; paylaşım metnindeki sıra numarası bundan sayılır.
EPOCH = date(2026, 9, 1)


def today() -> date:
    return datetime.now(timezone.utc).date()


def puzzle_number(day: date | None = None) -> int:
    """Paylaşım metninde görünen sıra numarası (#1, #2, ...)."""
    day = day or today()
    return (day - EPOCH).days + 1


def _seed(day: date) -> int:
    """Tarihten belirlenimci tohum.

    Basit `hash()` kullanılmaz: Python'da süreçler arası tutarlı değil,
    aynı gün iki farklı süreç farklı tahta üretirdi.
    """
    digest = hashlib.sha256(day.isoformat().encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def board(day: date | None = None) -> dict:
    """Günün tahtası: 3 millet x 3 kulüp.

    Havuz `pool_service` üzerinden geliyor; oradaki eşleşme matrisi her
    kesişimde en az bir futbolcu olmasını garanti ediyor.
    """
    day = day or today()
    rng = random.Random(_seed(day))
    nations, clubs = pool_service.build_duel_board(
        club_count=BOARD_SIZE, nation_count=BOARD_SIZE, rng=rng
    )
    return {
        "date": day.isoformat(),
        "number": puzzle_number(day),
        "nations": nations,
        "clubs": clubs,
    }


def share_text(number: int, results: list[bool]) -> str:
    """Paylaşılabilir emoji ızgarası.

    Doğru cevaplar yeşil, boş bırakılan ya da yanlışlar gri. Futbolcu
    adları YAZILMAZ: paylaşım cevabı ele vermemeli, yoksa arkadaşına
    gönderdiğin an bulmacayı bozarsın.
    """
    filled = (results + [False] * (BOARD_SIZE * BOARD_SIZE))[: BOARD_SIZE * BOARD_SIZE]
    score = sum(1 for value in filled if value)
    rows = []
    for row in range(BOARD_SIZE):
        chunk = filled[row * BOARD_SIZE : (row + 1) * BOARD_SIZE]
        rows.append("".join("🟩" if value else "⬜" for value in chunk))
    return f"Tiki Taka Toe #{number}   {score}/{BOARD_SIZE * BOARD_SIZE}\n" + "\n".join(rows)
