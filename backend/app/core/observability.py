"""Hata raporlama.

Testçiler bir sorun yaşadığında elimizde yalnızca sözlü anlatım kalıyordu;
"bir yerde internetim koptu gibi oldu" cümlesinden gerçek nedeni bulmak
saatler aldı. Sentry bağlıyken aynı olay stack trace'iyle geliyor.

Bağlanma isteğe bağlıdır: `SENTRY_DSN` verilmezse hiçbir şey yapılmaz ve
paket kurulu olmasa bile uygulama normal çalışır. Böylece geliştirme ve CI
ortamları hesap gerektirmez.
"""

import logging
import os

logger = logging.getLogger(__name__)


def setup_error_reporting(environment: str, release: str | None = None) -> bool:
    """Sentry'yi kurar. Bağlandıysa True döner."""
    dsn = os.getenv("SENTRY_DSN", "").strip()
    if not dsn:
        logger.info("SENTRY_DSN yok, hata raporlama kapali")
        return False

    try:
        import sentry_sdk
    except ImportError:
        logger.warning("SENTRY_DSN verildi ama sentry-sdk kurulu degil")
        return False

    sentry_sdk.init(
        dsn=dsn,
        environment=environment,
        release=release,
        # Oyun trafiği yoğun; her isteği izlemek hem maliyetli hem gereksiz.
        traces_sample_rate=float(os.getenv("SENTRY_TRACES_SAMPLE_RATE", "0.05")),
        # Oyuncu adları kişisel veri sayılabilir; varsayılan olarak gönderilmez.
        send_default_pii=False,
    )
    logger.info("Hata raporlama acik (%s)", environment)
    return True
