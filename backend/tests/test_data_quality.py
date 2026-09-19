"""Veri bütünlüğü: bayrak, logo, fotoğraf kapsamı (gerçek veritabanı ile).

Eşikler scripts/audit_data.py çıktısına göre konuldu; düşerse veri
katmanı bozulmuş ya da yeni bir kaynak eklenmiş demektir.
"""

import importlib.util
import sys
from pathlib import Path

import pytest

from tests.conftest import requires_player_data

_spec = importlib.util.spec_from_file_location(
    "audit_data", Path(__file__).resolve().parent.parent / "scripts" / "audit_data.py")
audit = importlib.util.module_from_spec(_spec)
sys.modules["audit_data"] = audit
_spec.loader.exec_module(audit)


@requires_player_data
def test_her_ulkenin_bayrak_kodu_var_ve_istemci_katalogunda():
    c = audit.countries()
    assert c["without_flag_code"] == [], "get_iso_code çözemeyen ülke adları"
    assert c["missing_in_client"] == [], "country_catalog.dart _isoByName eksik (scripts ile üret)"


@requires_player_data
def test_her_kulubun_logo_kaynagi_var():
    k = audit.clubs()
    assert k["without_logo_source"] == [], "scripts/prefetch_logos.py çalıştır"


@requires_player_data
def test_fotograf_kapsami():
    p = audit.photos()
    cur = p["players_2024"]
    assert cur["with_photo"] >= 0.99 * cur["total"], "son sezon oyuncularının fotoğrafı eksik"
    rec = p["players_2022"]
    assert rec["with_photo"] >= 0.90 * rec["total"]
    leg = p["legends_fame3"]
    assert leg["with_photo"] >= 0.50 * leg["total"], "efsane fotoğrafları (scripts/fetch_player_photos.py)"


def test_bayrak_kodlari_flagcdn_bicimine_uyar():
    from app.services.country_service import _SPECIAL, _UK_NATIONS
    import re
    for code in list(_SPECIAL.values()) + list(_UK_NATIONS.values()):
        assert re.fullmatch(r"[A-Z]{2}(-[A-Z]{3})?", code), code
