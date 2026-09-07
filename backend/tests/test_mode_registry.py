"""Mod kayıtlarının eksiksiz olduğunu doğrular.

Yeni bir mod eklerken 11 ayrı yere dokunmak gerekiyor. Dart tarafında
exhaustive switch derleme hatası veriyor ama Python'da böyle bir koruma yok:
`MODE_ENGINES`'e satır eklemeyi unutmak, ancak iki oyuncu odaya girdiğinde
KeyError olarak ortaya çıkıyordu. Bu testler o sınıfı kapatıyor.
"""

import json
import pathlib
import re

import pytest

from app.realtime.hub import MODE_ENGINES
from app.realtime.modes.base import BaseMode
from app.realtime.protocol import GameMode
from app.services import mode_service

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


@pytest.mark.parametrize("mode", list(GameMode))
def test_her_modun_motoru_var(mode):
    assert mode in MODE_ENGINES, (
        f"{mode.value} icin hub.MODE_ENGINES kaydi yok; oda acilinca KeyError verir"
    )
    assert issubclass(MODE_ENGINES[mode], BaseMode)


@pytest.mark.parametrize("mode", list(GameMode))
def test_motor_kendi_kimligini_bildiriyor(mode):
    """`mode_id` yanlış olursa istemci gelen mesajı yanlış modda işler."""
    assert MODE_ENGINES[mode].mode_id == mode


@pytest.mark.parametrize("mode", list(GameMode))
def test_her_mod_katalogda_var(mode):
    ids = {info.id for info in mode_service.catalog()}
    assert mode.value in ids, f"{mode.value} mod katalogunda gorunmuyor"


@pytest.mark.parametrize("mode", list(GameMode))
def test_her_modun_etiketi_ve_surum_esigi_var(mode):
    assert mode_service.MODE_LABELS.get(mode), f"{mode.value} icin etiket yok"
    assert mode_service.MIN_CLIENT_VERSIONS.get(mode), f"{mode.value} icin surum esigi yok"


def test_katalog_kapatilan_modu_isaretler(monkeypatch):
    monkeypatch.setenv("MODES_DISABLED", GameMode.LAST_LETTER.value)
    by_id = {info.id: info for info in mode_service.catalog()}
    assert by_id[GameMode.LAST_LETTER.value].enabled is False
    assert by_id[GameMode.TIKI_TAKA_TOE.value].enabled is True
    assert mode_service.is_enabled(GameMode.LAST_LETTER.value) is False


# --- istemci sözleşmesi ------------------------------------------------

def _dart_mode_ids() -> set[str]:
    """game_mode.dart icindeki `id: '...'` degerleri."""
    source = (REPO_ROOT / "lib" / "data" / "models" / "game_mode.dart").read_text()
    return set(re.findall(r"id:\s*'([a-z_]+)'", source))


def test_protokol_ve_istemci_ayni_mod_kimliklerini_kullaniyor():
    """Sunucu ile uygulama arasindaki id'ler birebir ayni olmali.

    game_mode.dart'ta "backend protokolüyle birebir aynıdır" yaziyor ama
    bunu kontrol eden bir sey yoktu; bir harflik kayma odayi sessizce
    bozardi.
    """
    dart_ids = _dart_mode_ids()
    if not dart_ids:
        pytest.skip("game_mode.dart okunamadi")
    python_ids = {mode.value for mode in GameMode}
    assert python_ids == dart_ids, (
        f"sadece sunucuda: {python_ids - dart_ids}, sadece istemcide: {dart_ids - python_ids}"
    )


def test_katalog_json_serilestirilebilir():
    """Uc nokta yanitinin sekli bozulmasin."""
    payload = [vars(info) for info in mode_service.catalog()]
    decoded = json.loads(json.dumps(payload))
    for item in decoded:
        assert {"id", "label", "enabled", "min_client_version"} <= set(item)
