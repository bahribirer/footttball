#!/usr/bin/env python3
"""App Store sürümünü hazırlar ve incelemeye gönderir (App Store Connect API).

TestFlight'a çıkan derlemeyi mağaza sürümüne bağlar, metinleri ve ekran
görüntülerini `store/` klasöründen yükler, yaş derecesini ve inceleme
iletişim bilgisini yazar, istenirse incelemeye gönderir.

    python infra/appstore_release.py --version 1.5.0 --build 14 [--submit]

Kimlik: APPSTORE_KEY_ID, APPSTORE_ISSUER_ID, APPSTORE_PRIVATE_KEY (p8 içeriği)
İnceleme iletişimi (isteğe bağlı, yoksa mevcut değer korunur):
    REVIEW_FIRST_NAME, REVIEW_LAST_NAME, REVIEW_PHONE, REVIEW_EMAIL

Her adım ne yaptığını yazar; eksik bir zorunluluk varsa (App Store
Connect'te elle tamamlanması gereken bir şey) açık bir mesajla durur.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
import time
from pathlib import Path

try:
    import jwt
    import requests
except ImportError:
    print("Gerekli paketler yok:  pip install 'pyjwt[crypto]' requests", file=sys.stderr)
    raise SystemExit(1)

API = "https://api.appstoreconnect.apple.com/v1"
APP_ID = os.getenv("APPSTORE_APP_ID", "6759257459")
ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "store"
LOCALE = "tr"   # App Store Connect Türkçe yerel kodu (tr-TR geçersiz)
SCREENSHOT_DISPLAY = "APP_IPHONE_67"   # 6.7"/6.9" (1290×2796, 1320×2868)

_token_cache: tuple[str, float] | None = None


def token() -> str:
    global _token_cache
    if _token_cache and _token_cache[1] > time.time() + 60:
        return _token_cache[0]
    key_id = os.environ["APPSTORE_KEY_ID"]
    issuer = os.environ["APPSTORE_ISSUER_ID"]
    private_key = os.getenv("APPSTORE_PRIVATE_KEY")
    if not private_key:
        with open(os.environ["APPSTORE_PRIVATE_KEY_PATH"]) as handle:
            private_key = handle.read()
    now = int(time.time())
    tok = jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        private_key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
    )
    _token_cache = (tok, now + 1200)
    return tok


def call(method: str, path: str, ok_404: bool = False, **kwargs) -> dict:
    url = f"{API}{path}" if path.startswith("/") else path
    response = requests.request(
        method, url,
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
        timeout=60, **kwargs,
    )
    if response.status_code == 404 and ok_404:
        return {}
    if response.status_code >= 400:
        raise SystemExit(f"{method} {path} -> {response.status_code}: {response.text[:800]}")
    return response.json() if response.content else {}


def read(name: str) -> str:
    return (STORE / "metadata" / LOCALE / name).read_text(encoding="utf-8").strip()


def urls() -> dict[str, str]:
    out = {}
    for line in (STORE / "metadata" / "urls.env").read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


# --- sürüm ---------------------------------------------------------------

def ensure_version(version: str) -> dict:
    data = call("GET", f"/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&limit=10")
    for v in data.get("data", []):
        if v["attributes"].get("versionString") == version:
            print(f"  sürüm {version} var: {v['attributes'].get('appStoreState')}")
            return v
    # Hazırlanan bir sürüm varsa numarasını güncelle (yeni oluşturmak 409 verir)
    for v in data.get("data", []):
        if v["attributes"].get("appStoreState") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
            call("PATCH", f"/appStoreVersions/{v['id']}", json={"data": {
                "type": "appStoreVersions", "id": v["id"],
                "attributes": {"versionString": version}}})
            print(f"  hazırlanan sürüm {v['attributes'].get('versionString')} → {version}")
            v["attributes"]["versionString"] = version
            return v
    created = call("POST", "/appStoreVersions", json={"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": version, "releaseType": "AFTER_APPROVAL"},
        "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
    }})
    print(f"  sürüm {version} oluşturuldu")
    return created["data"]


def set_version_texts(version_id: str) -> str:
    data = call("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    loc = next((l for l in data.get("data", []) if l["attributes"].get("locale") == LOCALE), None)
    u = urls()
    attrs = {
        "description": read("description.txt"),
        "keywords": read("keywords.txt")[:100],
        "promotionalText": read("promotional_text.txt")[:170],
        "whatsNew": read("release_notes.txt")[:4000],
        "supportUrl": u["SUPPORT_URL"],
        "marketingUrl": u.get("MARKETING_URL", ""),
    }
    if loc:
        call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", json={"data": {
            "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": attrs}})
        print(f"  {LOCALE} sürüm metinleri güncellendi")
        return loc["id"]
    created = call("POST", "/appStoreVersionLocalizations", json={"data": {
        "type": "appStoreVersionLocalizations",
        "attributes": {"locale": LOCALE, **attrs},
        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
    }})
    print(f"  {LOCALE} sürüm metinleri oluşturuldu")
    return created["data"]["id"]


def set_app_info() -> None:
    """Ad, alt başlık, gizlilik adresi, kategori (appInfo düzeyinde)."""
    infos = call("GET", f"/apps/{APP_ID}/appInfos")
    info = next((i for i in infos.get("data", [])
                 if i["attributes"].get("appStoreState") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "WAITING_FOR_REVIEW", "READY_FOR_SALE", "READY_FOR_DISTRIBUTION")), None)
    if not info:
        print("  appInfo bulunamadı, atlandı")
        return
    u = urls()
    locs = call("GET", f"/appInfos/{info['id']}/appInfoLocalizations")
    loc = next((l for l in locs.get("data", []) if l["attributes"].get("locale") == LOCALE), None)
    attrs = {"name": read("name.txt")[:30], "subtitle": read("subtitle.txt")[:30],
             "privacyPolicyUrl": u["PRIVACY_URL"]}
    if loc:
        call("PATCH", f"/appInfoLocalizations/{loc['id']}", json={"data": {
            "type": "appInfoLocalizations", "id": loc["id"], "attributes": attrs}})
    else:
        call("POST", "/appInfoLocalizations", json={"data": {
            "type": "appInfoLocalizations", "attributes": {"locale": LOCALE, **attrs},
            "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}}}})
    print(f"  uygulama adı/alt başlık/gizlilik ({LOCALE}) yazıldı")

    # Kategori: yalnız boşsa yaz (kilitli sürümde PATCH reddedilebilir).
    rel = {}
    if u.get("PRIMARY_CATEGORY"):
        rel["primaryCategory"] = {"data": {"type": "appCategories", "id": u["PRIMARY_CATEGORY"]}}
        subs = [s for s in u.get("GAME_SUBCATEGORIES", "").split(",") if s]
        if subs:
            rel["primarySubcategoryOne"] = {"data": {"type": "appCategories", "id": subs[0]}}
        if len(subs) > 1:
            rel["primarySubcategoryTwo"] = {"data": {"type": "appCategories", "id": subs[1]}}
    if u.get("SECONDARY_CATEGORY"):
        rel["secondaryCategory"] = {"data": {"type": "appCategories", "id": u["SECONDARY_CATEGORY"]}}
    if rel:
        try:
            call("PATCH", f"/appInfos/{info['id']}", json={"data": {
                "type": "appInfos", "id": info["id"], "relationships": rel}})
            print("  kategori yazıldı")
        except SystemExit as exc:
            print(f"  kategori yazılamadı (mevcut korunur): {str(exc)[:160]}")


def set_age_rating(version_id: str) -> None:
    decl = call("GET", f"/appStoreVersions/{version_id}/ageRatingDeclaration", ok_404=True)
    if not decl.get("data"):
        print("  yaş derecesi beyanı bulunamadı, atlandı")
        return
    did = decl["data"]["id"]
    attrs = {k: "NONE" for k in (
        "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "horrorOrFearThemes",
        "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
        "sexualContentGraphicAndNudity", "sexualContentOrNudity", "violenceCartoonOrFantasy",
        "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic")}
    attrs.update({"gambling": False, "unrestrictedWebAccess": False, "seventeenPlus": False})
    try:
        call("PATCH", f"/ageRatingDeclarations/{did}", json={"data": {
            "type": "ageRatingDeclarations", "id": did, "attributes": attrs}})
        print("  yaş derecesi: 4+ (hepsi NONE)")
    except SystemExit as exc:
        # Yeni alan adları gelmişse eskiyi düşür ve tekrar dene.
        print(f"  yaş derecesi yazılamadı: {str(exc)[:200]}")


def set_review_details(version_id: str) -> None:
    first, last = os.getenv("REVIEW_FIRST_NAME"), os.getenv("REVIEW_LAST_NAME")
    phone, email = os.getenv("REVIEW_PHONE"), os.getenv("REVIEW_EMAIL")
    notes = ("Oyun hesap istemez; açılışta bir takma ad girmek yeterlidir. "
             "Rakip için 'BOTA KARŞI OYNA' seçilebilir (oda kurma ekranı) ya da iki cihazla oda kodu paylaşılır. "
             "Günün Tahtası tek başına oynanır.")
    existing = call("GET", f"/appStoreVersions/{version_id}/appStoreReviewDetail", ok_404=True)
    attrs = {"notes": notes, "demoAccountRequired": False}
    if first and last and phone and email:
        attrs.update({"contactFirstName": first, "contactLastName": last,
                      "contactPhone": phone, "contactEmail": email})
    else:
        print("  inceleme iletişim bilgisi ortamda yok (REVIEW_*); mevcut değer korunur")
    if existing.get("data"):
        call("PATCH", f"/appStoreReviewDetails/{existing['data']['id']}", json={"data": {
            "type": "appStoreReviewDetails", "id": existing["data"]["id"], "attributes": attrs}})
    else:
        if "contactPhone" not in attrs:
            print("  inceleme detayı yok ve iletişim bilgisi verilmedi → App Store Connect'te elle girilmeli")
            return
        call("POST", "/appStoreReviewDetails", json={"data": {
            "type": "appStoreReviewDetails", "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})
    print("  inceleme notu/iletişim yazıldı")


# --- ekran görüntüleri ----------------------------------------------------

def upload_screenshots(loc_id: str) -> None:
    folder = STORE / "screenshots" / "ios-6.9"
    files = sorted(p for p in folder.glob("*.png"))
    if not files:
        print("  ekran görüntüsü yok, atlandı")
        return
    sets = call("GET", f"/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    sset = next((s for s in sets.get("data", []) if s["attributes"].get("screenshotDisplayType") == SCREENSHOT_DISPLAY), None)
    if not sset:
        sset = call("POST", "/appScreenshotSets", json={"data": {
            "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": SCREENSHOT_DISPLAY},
            "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})["data"]
    # Eskileri sil, sırayı baştan kur.
    old = call("GET", f"/appScreenshotSets/{sset['id']}/appScreenshots?limit=50")
    for shot in old.get("data", []):
        call("DELETE", f"/appScreenshots/{shot['id']}")
    ids = []
    for path in files:
        data = path.read_bytes()
        created = call("POST", "/appScreenshots", json={"data": {
            "type": "appScreenshots", "attributes": {"fileName": path.name, "fileSize": len(data)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sset["id"]}}}}})["data"]
        for op in created["attributes"]["uploadOperations"]:
            chunk = data[op["offset"]: op["offset"] + op["length"]]
            headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            r = requests.request(op["method"], op["url"], data=chunk, headers=headers, timeout=120)
            if r.status_code >= 400:
                raise SystemExit(f"yükleme başarısız {path.name}: {r.status_code} {r.text[:200]}")
        call("PATCH", f"/appScreenshots/{created['id']}", json={"data": {
            "type": "appScreenshots", "id": created["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        ids.append(created["id"])
        print(f"  yüklendi: {path.name} ({len(data)//1024} KB)")
    call("PATCH", f"/appScreenshotSets/{sset['id']}/relationships/appScreenshots", json={
        "data": [{"type": "appScreenshots", "id": i} for i in ids]})
    print(f"  {len(ids)} ekran görüntüsü ({SCREENSHOT_DISPLAY})")


# --- derleme ve gönderim ---------------------------------------------------

def attach_build(version_id: str, build_number: str) -> None:
    data = call("GET", f"/builds?filter[app]={APP_ID}&filter[version]={build_number}&filter[processingState]=VALID&limit=1")
    items = data.get("data", [])
    if not items:
        raise SystemExit(f"build {build_number} VALID durumda bulunamadı (TestFlight işlemesi bitti mi?)")
    call("PATCH", f"/appStoreVersions/{version_id}/relationships/build", json={
        "data": {"type": "builds", "id": items[0]["id"]}})
    print(f"  build {build_number} sürüme bağlandı")


def submit(version_id: str) -> None:
    # Açık bir gönderim varsa onu kullan.
    subs = call("GET", f"/reviewSubmissions?filter[app]={APP_ID}&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES&limit=5", ok_404=True)
    open_sub = next((s for s in subs.get("data", []) if s["attributes"].get("state") == "READY_FOR_REVIEW"), None)
    if any(s["attributes"].get("state") in ("WAITING_FOR_REVIEW", "IN_REVIEW") for s in subs.get("data", [])):
        print("  zaten incelemede bir gönderim var; yeni gönderim yapılmadı")
        return
    if not open_sub:
        open_sub = call("POST", "/reviewSubmissions", json={"data": {
            "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})["data"]
    items = call("GET", f"/reviewSubmissions/{open_sub['id']}/items")
    if not items.get("data"):
        call("POST", "/reviewSubmissionItems", json={"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": open_sub["id"]}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})
    call("PATCH", f"/reviewSubmissions/{open_sub['id']}", json={"data": {
        "type": "reviewSubmissions", "id": open_sub["id"], "attributes": {"submitted": True}}})
    print("  ✓ incelemeye gönderildi")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--version", required=True)
    ap.add_argument("--build", required=True)
    ap.add_argument("--submit", action="store_true")
    ap.add_argument("--skip-screenshots", action="store_true")
    args = ap.parse_args()

    print("▶ Sürüm")
    version = ensure_version(args.version)
    vid = version["id"]
    print("▶ Uygulama bilgisi")
    set_app_info()
    print("▶ Sürüm metinleri")
    loc_id = set_version_texts(vid)
    if not args.skip_screenshots:
        print("▶ Ekran görüntüleri")
        upload_screenshots(loc_id)
    print("▶ Yaş derecesi")
    set_age_rating(vid)
    print("▶ İnceleme bilgisi")
    set_review_details(vid)
    print("▶ Derleme")
    attach_build(vid, args.build)
    if args.submit:
        print("▶ Gönderim")
        submit(vid)
    else:
        print("▶ Gönderim atlandı (--submit yok)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
