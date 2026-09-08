"""Odaların yeniden başlatmayı atlatması.

Oda durumu süreç belleğinde tutuluyor; her dağıtım o an oynanan maçları
öldürüyordu. Otomatik dağıtım kurulunca bu her backend commit'inde
yaşanacak hale geldi.

Çözüm Redis değil: tek süreçte çalışan bir oyun için kapanırken durumu
diske yazıp açılışta geri okumak yetiyor. İstemciler zaten belirteçle
otomatik yeniden bağlanıyor (45 sn tolerans) ve container yeniden başlaması
~10-20 saniye sürüyor — yani oyuncu için görünmez oluyor.

Neyin geri geldiği moda göre değişir:

  * Tiki Taka Toe oyun mantığını istemcide tutuyor (relay); oda ve oyuncular
    dönünce tahta kaldığı yerden sürer.
  * Sunucu yönetimli modlarda tur zamanlayıcıları geri getirilemez; skorlar
    ve tur numarası korunur, içinde bulunulan tur baştan başlar.

Anlık görüntü kısa ömürlüdür: açılışta okunur ve hemen silinir, üzerinden
`RESTORE_MAX_AGE_SECONDS` geçmişse yok sayılır. Amacı yeniden başlatmayı
atlatmak, kalıcı depolama olmak değil.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
import time
from pathlib import Path

from app.core.config import settings

logger = logging.getLogger(__name__)

# Bundan eski anlık görüntüler yok sayılır: sunucu uzun süre kapalı
# kaldıysa oyuncular çoktan ayrılmıştır, eski odaları diriltmek kafa
# karıştırır.
RESTORE_MAX_AGE_SECONDS = 180

SNAPSHOT_VERSION = 1


def snapshot_path() -> Path:
    """Anlık görüntü dosyası.

    Veritabanının yanında durur; o dizin container'a yazılabilir bağlı ve
    yeniden başlatmalar arasında kalıcı.
    """
    override = os.getenv("ROOM_SNAPSHOT_PATH")
    if override:
        return Path(override)
    return Path(settings.DB_PATH).parent / "rooms.snapshot.json"


def save(rooms: list[dict]) -> int:
    """Odaları diske yazar; yazılan oda sayısını döndürür.

    Yazma atomik: yarım kalan bir dosya açılışta çöp odalar üretirdi.
    """
    path = snapshot_path()
    payload = {
        "version": SNAPSHOT_VERSION,
        "saved_at": time.time(),
        "rooms": rooms,
    }
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            "w", dir=path.parent, delete=False, encoding="utf-8"
        ) as handle:
            json.dump(payload, handle, ensure_ascii=False)
            temp_name = handle.name
        os.replace(temp_name, path)
        logger.info("Oda anlik goruntusu yazildi: %d oda", len(rooms))
        return len(rooms)
    except Exception:
        # Kapanış sırasında yazamamak servisi engellememelidir.
        logger.exception("Oda anlik goruntusu yazilamadi")
        return 0


def load() -> list[dict]:
    """Anlık görüntüyü okur ve dosyayı siler.

    Silme kasıtlı: aynı görüntüden iki kez oda diriltmek, çoktan bitmiş
    maçları geri getirirdi.
    """
    path = snapshot_path()
    if not path.exists():
        return []

    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        logger.exception("Oda anlik goruntusu okunamadi")
        _discard(path)
        return []
    finally:
        pass

    _discard(path)

    if payload.get("version") != SNAPSHOT_VERSION:
        logger.warning("Anlik goruntu surumu uyumsuz, yok sayildi")
        return []

    age = time.time() - float(payload.get("saved_at", 0))
    if age > RESTORE_MAX_AGE_SECONDS:
        logger.info("Anlik goruntu cok eski (%.0f sn), yok sayildi", age)
        return []

    rooms = payload.get("rooms") or []
    logger.info("Oda anlik goruntusu okundu: %d oda (%.0f sn once)", len(rooms), age)
    return rooms


def _discard(path: Path) -> None:
    try:
        path.unlink(missing_ok=True)
    except Exception:
        logger.exception("Anlik goruntu silinemedi")
