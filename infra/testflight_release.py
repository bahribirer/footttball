#!/usr/bin/env python3
"""Yüklenen derlemeyi işlenmesi bitince testçilere dağıtır.

Yükleme otomatikleşmişti ama build'i testçi grubuna atamak ve "What to Test"
notunu yazmak elle kalıyordu. Bu betik ikisini de yapar:

  1. Derleme App Store Connect'te görünene ve işlenmesi bitene kadar bekler
  2. Sürüm notunu yazar (git geçmişinden üretilir ya da --notes ile verilir)
  3. Belirtilen beta grubuna atar

Kullanım:
    python infra/testflight_release.py --build 8 --group "tiki taka"

Kimlik bilgileri ortamdan okunur:
    APPSTORE_KEY_ID, APPSTORE_ISSUER_ID, APPSTORE_PRIVATE_KEY (p8 icerigi)
    ya da APPSTORE_PRIVATE_KEY_PATH (dosya yolu)
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time

try:
    import jwt
    import requests
except ImportError:
    print("Gerekli paketler yok:  pip install 'pyjwt[crypto]' requests", file=sys.stderr)
    raise SystemExit(1)

API = "https://api.appstoreconnect.apple.com/v1"
APP_ID = os.getenv("APPSTORE_APP_ID", "6759257459")


def token() -> str:
    key_id = os.environ["APPSTORE_KEY_ID"]
    issuer = os.environ["APPSTORE_ISSUER_ID"]
    private_key = os.getenv("APPSTORE_PRIVATE_KEY")
    if not private_key:
        with open(os.environ["APPSTORE_PRIVATE_KEY_PATH"]) as handle:
            private_key = handle.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def call(method: str, path: str, **kwargs) -> dict:
    response = requests.request(
        method,
        f"{API}{path}" if path.startswith("/") else path,
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
        timeout=45,
        **kwargs,
    )
    if response.status_code >= 400:
        raise SystemExit(f"{method} {path} -> {response.status_code}: {response.text[:500]}")
    return response.json() if response.content else {}


def release_notes() -> str:
    """Son etiketten bu yana gelen commit başlıklarından not üretir."""
    try:
        last_tag = subprocess.run(
            ["git", "describe", "--tags", "--abbrev=0"],
            capture_output=True, text=True, check=False,
        ).stdout.strip()
        rng = f"{last_tag}..HEAD" if last_tag else "-20"
        raw = subprocess.run(
            ["git", "log", "--no-merges", "--pretty=%s", rng],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return "Bu surumde neler degisti: degisiklik listesi uretilemedi."

    lines = [f"- {line}" for line in raw.split("\n") if line][:15]
    if not lines:
        return "Kucuk duzeltmeler."
    # App Store Connect notu 4000 karakterle sinirli.
    return ("Bu surumde test edilecekler:\n" + "\n".join(lines))[:3999]


def find_build(version: str, attempts: int = 40, delay: int = 30) -> dict:
    """Derleme gorunene ve islenmesi bitene kadar bekler."""
    for attempt in range(1, attempts + 1):
        data = call("GET", f"/builds?filter[app]={APP_ID}&filter[version]={version}&limit=1")
        items = data.get("data", [])
        if items:
            state = items[0]["attributes"].get("processingState")
            print(f"  build {version}: {state}")
            if state == "VALID":
                return items[0]
            if state in ("INVALID", "FAILED"):
                raise SystemExit(f"Derleme islenemedi: {state}")
        else:
            print(f"  build {version}: henuz gorunmedi ({attempt}/{attempts})")
        time.sleep(delay)
    raise SystemExit(f"build {version} zaman asimina ugradi")


def find_group(name: str) -> dict:
    data = call("GET", f"/apps/{APP_ID}/betaGroups?limit=50")
    for group in data.get("data", []):
        if group["attributes"].get("name", "").lower() == name.lower():
            return group
    names = [g["attributes"].get("name") for g in data.get("data", [])]
    raise SystemExit(f"'{name}' grubu yok. Mevcut: {names}")


def set_notes(build_id: str, notes: str) -> None:
    """Yerellestirilmis 'What to Test' metnini yazar."""
    data = call("GET", f"/builds/{build_id}/betaBuildLocalizations")
    for localization in data.get("data", []):
        call("PATCH", f"/betaBuildLocalizations/{localization['id']}", json={
            "data": {
                "type": "betaBuildLocalizations",
                "id": localization["id"],
                "attributes": {"whatsNew": notes},
            }
        })
        print(f"  not yazildi: {localization['attributes'].get('locale')}")
    if not data.get("data"):
        call("POST", "/betaBuildLocalizations", json={
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {"locale": "tr", "whatsNew": notes},
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
            }
        })
        print("  not yazildi: tr (yeni)")


def assign(build_id: str, group: dict) -> None:
    """Derlemeyi gruba atar.

    İç gruplara atama yapılamaz ve gerekmez: App Store Connect iç testçilere
    her derlemeyi kendiliğinden açar. Denemek 422 döndürüyor, bu yüzden
    ayırt ediliyor.
    """
    if group["attributes"].get("isInternalGroup"):
        print("  ic grup — derleme testcilere kendiliginden acik, atama gerekmiyor")
        return
    call("POST", f"/betaGroups/{group['id']}/relationships/builds", json={
        "data": [{"type": "builds", "id": build_id}]
    })
    print("  atandi")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", required=True, help="derleme numarasi, orn. 8")
    parser.add_argument("--group", default="tiki taka", help="beta grubu adi")
    parser.add_argument("--notes", help="What to Test metni (bos birakilirsa git'ten uretilir)")
    parser.add_argument("--wait", type=int, default=40, help="kac kez yoklanacak")
    args = parser.parse_args()

    print(f"▶ build {args.build} bekleniyor")
    build = find_build(args.build, attempts=args.wait)
    build_id = build["id"]

    print("▶ surum notu")
    notes = args.notes or release_notes()
    print("  " + notes.split("\n")[0])
    set_notes(build_id, notes)

    print(f"▶ '{args.group}' grubuna ataniyor")
    group = find_group(args.group)
    assign(build_id, group)

    print(f"✓ build {args.build} testcilere dagitildi")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
