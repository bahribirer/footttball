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
        raise SystemExit(f"{method} {path} -> {response.status_code}: {response.text[:4000]}")
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


def other_localization_ids(version_id: str) -> list[str]:
    """Sürümde tr dışındaki yerelleştirmeler (örn. birincil dil en-US).

    Apple her yerelleştirme için ekran görüntüsü ve açıklama ister; boş
    kalan biri gönderimi engeller. Aynı içerik onlara da yazılır.
    """
    data = call("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    out = []
    for l in data.get("data", []):
        if l["attributes"].get("locale") != LOCALE:
            print(f"  ek yerelleştirme: {l['attributes'].get('locale')}")
            out.append(l["id"])
    return out


def fill_localization(loc_id: str) -> None:
    u = urls()
    attrs = {"description": read("description.txt"), "keywords": read("keywords.txt")[:100],
             "promotionalText": read("promotional_text.txt")[:170], "supportUrl": u["SUPPORT_URL"],
             "marketingUrl": u.get("MARKETING_URL", "")}
    call("PATCH", f"/appStoreVersionLocalizations/{loc_id}", json={"data": {
        "type": "appStoreVersionLocalizations", "id": loc_id, "attributes": attrs}})


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
    def _write(attributes: dict) -> str:
        if loc:
            call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", json={"data": {
                "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": attributes}})
            return loc["id"]
        created = call("POST", "/appStoreVersionLocalizations", json={"data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {"locale": LOCALE, **attributes},
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
        }})
        return created["data"]["id"]

    try:
        lid = _write(attrs)
    except SystemExit as exc:
        # İlk sürümde "Yenilikler" alanı yok; Apple 409 döner. Onsuz yaz.
        if "whatsNew" not in str(exc):
            raise
        attrs.pop("whatsNew", None)
        lid = _write(attrs)
        print("  (ilk sürüm: 'Yenilikler' alanı atlandı)")
    print(f"  {LOCALE} sürüm metinleri yazıldı")
    return lid


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
    attrs = {"name": read("name.txt")[:30], "subtitle": read("subtitle.txt")[:30],
             "privacyPolicyUrl": u["PRIVACY_URL"]}
    seen = False
    for loc in locs.get("data", []):
        # Her yerelleştirmede gizlilik adresi zorunlu; ad/alt başlık boşsa doldur.
        cur = loc["attributes"]
        patch = {"privacyPolicyUrl": u["PRIVACY_URL"]}
        if cur.get("locale") == LOCALE:
            patch.update({"name": attrs["name"], "subtitle": attrs["subtitle"]}); seen = True
        else:
            if not cur.get("name"):
                patch["name"] = attrs["name"]
            if not cur.get("subtitle"):
                patch["subtitle"] = attrs["subtitle"]
        call("PATCH", f"/appInfoLocalizations/{loc['id']}", json={"data": {
            "type": "appInfoLocalizations", "id": loc["id"], "attributes": patch}})
        print(f"  uygulama bilgisi ({cur.get('locale')}) yazıldı")
    if not seen:
        call("POST", "/appInfoLocalizations", json={"data": {
            "type": "appInfoLocalizations", "attributes": {"locale": LOCALE, **attrs},
            "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}}}})
        print(f"  uygulama bilgisi ({LOCALE}) oluşturuldu")

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


def set_content_rights() -> None:
    """Üçüncü taraf içerik beyanı (kulüp armaları, Wikimedia fotoğrafları)."""
    call("PATCH", f"/apps/{APP_ID}", json={"data": {
        "type": "apps", "id": APP_ID,
        "attributes": {"contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT"}}})
    print("  içerik hakları beyanı: üçüncü taraf içerik (hakları var)")


def _current_app_info() -> dict | None:
    infos = call("GET", f"/apps/{APP_ID}/appInfos")
    return next((i for i in infos.get("data", [])
                 if i["attributes"].get("appStoreState") not in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_INFO", "REMOVED_FROM_SALE")), None) or (infos.get("data") or [None])[0]


def set_age_rating(version_id: str) -> None:
    # Yaş derecesi beyanı appInfo'ya bağlı (eski sürüm API'de appStoreVersion'daydı).
    decl = {}
    info = _current_app_info()
    if info:
        decl = call("GET", f"/appInfos/{info['id']}/ageRatingDeclaration", ok_404=True)
    if not decl.get("data"):
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
    attrs["gunsOrOtherWeapons"] = "NONE"
    attrs.update({"gambling": False, "unrestrictedWebAccess": False, "lootBox": False,
                  "advertising": False, "userGeneratedContent": False, "messaging": False,
                  "messagingAndChat": False, "healthOrWellnessTopics": False,
                  "parentalControls": False, "ageAssurance": False})
    try:
        call("PATCH", f"/ageRatingDeclarations/{did}", json={"data": {
            "type": "ageRatingDeclarations", "id": did, "attributes": attrs}})
        print("  yaş derecesi: 4+ (hepsi NONE)")
    except SystemExit as exc:
        # Alan adları sürümden sürüme değişiyor; bilinmeyenleri at, tekrar dene.
        import re as _re
        text = str(exc)
        bad = set()
        for block in text.split('"id"')[1:]:
            if "INVALID" in block or "not a valid" in block or "unknown" in block.lower():
                bad |= set(_re.findall(r"attributes/(\w+)", block))
        attrs2 = {k: v for k, v in attrs.items() if k not in bad}
        try:
            call("PATCH", f"/ageRatingDeclarations/{did}", json={"data": {
                "type": "ageRatingDeclarations", "id": did, "attributes": attrs2}})
            print(f"  yaş derecesi: 4+ ({len(bad)} bilinmeyen alan atlandı: {sorted(bad)})")
        except SystemExit as exc2:
            print(f"  yaş derecesi yazılamadı: {str(exc2)[:3000]}")


def set_data_usages() -> None:
    """App Privacy etiketleri: cihaz kimliği ve oyun içeriği, kişiyle bağlı değil.

    Toplanan: cihaza özel rastgele kimlik (DEVICE_ID), takma ad ve skorlar
    (OTHER_USER_CONTENT). Amaç: uygulama işlevi. Takip yok, reklam yok.
    """
    existing_resp = call("GET", f"/apps/{APP_ID}/dataUsages?limit=200", ok_404=True)
    if not existing_resp:
        print("  App Privacy için açık API yok → App Store Connect › App Privacy'de elle:")
        print("    Toplanan veri: Device ID (Identifiers) ve Other User Content — ikisi de")
        print("    'App Functionality', 'Not linked to the user', takip yok.")
        return
    existing = existing_resp.get("data", [])
    wanted = [("DEVICE_ID", "APP_FUNCTIONALITY", "DATA_NOT_LINKED_TO_YOU"),
              ("OTHER_USER_CONTENT", "APP_FUNCTIONALITY", "DATA_NOT_LINKED_TO_YOU")]
    have = set()
    for du in existing:
        rel = du.get("relationships", {})
        have.add((rel.get("category", {}).get("data", {}).get("id"),
                  rel.get("purpose", {}).get("data", {}).get("id"),
                  rel.get("dataProtection", {}).get("data", {}).get("id")))
    for cat, purpose, prot in wanted:
        if (cat, purpose, prot) in have:
            continue
        call("POST", "/appDataUsages", json={"data": {
            "type": "appDataUsages",
            "relationships": {
                "app": {"data": {"type": "apps", "id": APP_ID}},
                "category": {"data": {"type": "appDataUsageCategories", "id": cat}},
                "purpose": {"data": {"type": "appDataUsagePurposes", "id": purpose}},
                "dataProtection": {"data": {"type": "appDataUsageDataProtections", "id": prot}},
            }}})
        print(f"  veri kullanımı eklendi: {cat} / {purpose} / {prot}")
    state = call("GET", f"/apps/{APP_ID}/dataUsagePublishState", ok_404=True).get("data")
    if state and not state["attributes"].get("published"):
        call("PATCH", f"/appDataUsagesPublishState/{state['id']}", json={"data": {
            "type": "appDataUsagesPublishState", "id": state["id"], "attributes": {"published": True}}})
        print("  gizlilik etiketleri yayımlandı")
    elif state:
        print("  gizlilik etiketleri zaten yayımlı")
    else:
        print("  yayım durumu okunamadı")


def set_review_details(version_id: str) -> None:
    first = os.getenv("REVIEW_FIRST_NAME") or "Bahri"
    last = os.getenv("REVIEW_LAST_NAME") or "Birer"
    email = os.getenv("REVIEW_EMAIL") or "bahribirerr@gmail.com"
    phone = os.getenv("REVIEW_PHONE")
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
    if "contactPhone" not in attrs:
        attrs.update({"contactFirstName": first, "contactLastName": last, "contactEmail": email})
        if phone:
            attrs["contactPhone"] = phone
    if existing.get("data"):
        call("PATCH", f"/appStoreReviewDetails/{existing['data']['id']}", json={"data": {
            "type": "appStoreReviewDetails", "id": existing["data"]["id"], "attributes": attrs}})
        print("  inceleme notu/iletişim güncellendi")
    elif phone:
        call("POST", "/appStoreReviewDetails", json={"data": {
            "type": "appStoreReviewDetails", "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})
        print("  inceleme notu/iletişim oluşturuldu")
    else:
        # Apple telefon olmadan inceleme detayı oluşturmuyor (+90 ... biçiminde).
        print("  ✗ İnceleme iletişim telefonu yok. REVIEW_PHONE gizli değişkenini ekleyin")
        print("    (örn. +90 5xx xxx xx xx) ya da App Store Connect › App Review Information'a girin.")


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
    old = call("GET", f"/appScreenshotSets/{sset['id']}/appScreenshots?limit=50")
    have = [(x["attributes"].get("fileName"), x["attributes"].get("assetDeliveryState", {}).get("state")) for x in old.get("data", [])]
    if [h[0] for h in have] == [p.name for p in files] and all(h[1] == "COMPLETE" for h in have):
        print(f"  {len(have)} ekran görüntüsü zaten yüklü ve işlenmiş")
        return
    print(f"  mevcut: {have}")
    # Eskileri sil, sırayı baştan kur.
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
    # İşlenmesini bekle; hata varsa göster (yanlış boyut burada anlaşılır).
    for _ in range(30):
        states = []
        for i in ids:
            a = call("GET", f"/appScreenshots/{i}")["data"]["attributes"]
            st = a.get("assetDeliveryState", {})
            states.append((a.get("fileName"), st.get("state"), st.get("errors")))
        if all(s[1] == "COMPLETE" for s in states):
            break
        if any(s[1] == "FAILED" for s in states):
            raise SystemExit(f"ekran görüntüsü işlenemedi: {states}")
        time.sleep(5)
    print(f"  {len(ids)} ekran görüntüsü ({SCREENSHOT_DISPLAY}): {[s[1] for s in states]}")


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
    others = other_localization_ids(vid)
    for oid in others:
        fill_localization(oid)
    if not args.skip_screenshots:
        print("▶ Ekran görüntüleri")
        upload_screenshots(loc_id)
        for oid in others:
            upload_screenshots(oid)
    print("▶ İçerik hakları")
    set_content_rights()
    print("▶ Yaş derecesi")
    set_age_rating(vid)
    print("▶ Gizlilik etiketleri")
    set_data_usages()
    print("▶ İnceleme bilgisi")
    set_review_details(vid)
    print("▶ Derleme")
    attach_build(vid, args.build)
    if args.submit:
        print("▶ Gönderim")
        try:
            submit(vid)
        except SystemExit as exc:
            text = str(exc)
            print(text[:3000])
            print("\n✗ Gönderim engellendi. Kalan zorunluluklar App Store Connect'te elle tamamlanmalı,")
            print("  sonra bu iş akışı yeniden çalıştırılır (ya da ASC'de 'Submit for Review').")
            return 1
    else:
        print("▶ Gönderim atlandı (--submit yok)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
