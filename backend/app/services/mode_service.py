"""Oyun modu kataloğu ve özellik bayrakları.

Modun kodu uygulamayla birlikte gider ama **açılması** sunucudan kontrol
edilir. Böylece yeni bir mod kapalı olarak yayınlanıp hazır olduğunda
açılabilir, bozulursa App Review beklemeden anında kapatılabilir.

Bayraklar ortam değişkeninden okunur; `MODES_DISABLED` virgülle ayrılmış mod
kimlikleri alır. Kapatmak için container'a değişkeni verip yeniden başlatmak
yeterli — kod değişikliği ya da yeni sürüm gerekmez.
"""

import os
from dataclasses import dataclass, field

from app.realtime.protocol import GameMode

# İstemcinin bu modu oynayabilmesi için gereken en düşük uygulama sürümü.
# Eski bir yapı listeyi aldığında tanımadığı modu göstermez; sunucu da
# katılmaya çalışırsa net bir hata döndürür.
MIN_CLIENT_VERSIONS: dict[str, str] = {
    GameMode.TIKI_TAKA_TOE: "1.0.0",
    GameMode.PLAYER_GUESS: "1.0.0",
    GameMode.LAST_LETTER: "1.0.0",
    GameMode.CATEGORY_RACE: "1.0.0",
}

# Katalogda gösterilecek insan okunur bilgiler. İstemcideki metinlerin
# kaynağı hâlâ uygulama; buradakiler yeni modların eski istemcilere de
# anlamlı görünmesi ve yönetim arayüzleri için.
MODE_LABELS: dict[str, str] = {
    GameMode.TIKI_TAKA_TOE: "Tiki Taka Toe",
    GameMode.PLAYER_GUESS: "Oyuncu Tahmin",
    GameMode.LAST_LETTER: "Son Harf",
    GameMode.CATEGORY_RACE: "Kategori Yarışı",
}


@dataclass(frozen=True)
class ModeInfo:
    id: str
    label: str
    enabled: bool
    min_client_version: str
    settings: dict = field(default_factory=dict)


def _disabled_ids() -> set[str]:
    raw = os.getenv("MODES_DISABLED", "")
    return {part.strip() for part in raw.split(",") if part.strip()}


def is_enabled(mode_id: str) -> bool:
    return mode_id not in _disabled_ids()


def catalog() -> list[ModeInfo]:
    """Tüm modlar, açık/kapalı durumlarıyla."""
    disabled = _disabled_ids()
    return [
        ModeInfo(
            id=mode.value,
            label=MODE_LABELS.get(mode, mode.value),
            enabled=mode.value not in disabled,
            min_client_version=MIN_CLIENT_VERSIONS.get(mode, "1.0.0"),
        )
        for mode in GameMode
    ]
