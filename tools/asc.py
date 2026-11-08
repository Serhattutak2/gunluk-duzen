#!/usr/bin/env python3
# Günlük Düzen — App Store Connect otomasyonu (API anahtarıyla).
# Kullanım: python3 tools/asc.py hazirlik | bilgiler | gonder | durum
#   hazirlik : Paket kimliğini (bundle id) Apple Developer'a kaydeder.
#   bilgiler : Açıklama, anahtar kelimeler, kategori, yaş sınırı, fiyat (ücretsiz),
#              ülkeler, inceleme iletişim bilgisi ve ekran görüntülerini yükler.
#   gonder   : TestFlight'taki son build'i sürüme bağlar ve Apple incelemesine gönderir.
#   durum    : Uygulamanın ve sürümün durumunu yazdırır.
# Ortam: KID, ISS, P8
import os, sys, time, json, hashlib, glob, urllib.request, urllib.error
import jwt

BUNDLE = "com.serhattutak.gunlukduzen"
NAME = "Günlük Düzen"
VER = os.environ.get("VER", "1.0").strip() or "1.0"
KID = "".join(c for c in os.environ.get("KID", "") if c.isalnum())
ISS = "".join(c for c in os.environ.get("ISS", "") if c.isalnum() or c == "-")
P8 = "\n".join(l.strip() for l in os.environ.get("P8", "").replace("\r", "").split("\n") if l.strip()) + "\n"
BASE = "https://api.appstoreconnect.apple.com"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
META = json.load(open(os.path.join(ROOT, "store", "metadata.json"), encoding="utf-8"))
REF_BUNDLE = "com.serhattutak.mirasfc"   # inceleme iletişim bilgisi buradan kopyalanır

def token():
    now = int(time.time())
    return jwt.encode({"iss": ISS, "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"},
                      P8, algorithm="ES256", headers={"kid": KID, "typ": "JWT"})

def api(method, path, body=None):
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            t = r.read().decode()
            return r.status, (json.loads(t) if t.strip() else {})
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try: j = json.loads(t)
        except Exception: j = {"raw": t[:1500]}
        return e.code, j

def err(r):
    try: return "; ".join((e.get("title", "") + ": " + e.get("detail", "")) for e in r.get("errors", [])) or json.dumps(r)[:800]
    except Exception: return json.dumps(r)[:800]

PROBLEMS = []
def step(name, ok, r=None):
    print(("  ✓ " if ok else "  ✗ ") + name + ("" if ok or r is None else "  -> " + err(r)))
    if not ok: PROBLEMS.append(name)

def die(msg, r=None):
    print("HATA:", msg + ("" if r is None else "  -> " + err(r))); sys.exit(1)

def find_app(bundle=BUNDLE):
    st, r = api("GET", f"/v1/apps?filter[bundleId]={bundle}&limit=1")
    return r["data"][0] if st == 200 and r.get("data") else None

def need_app():
    a = find_app()
    if not a:
        die(f"App Store Connect'te {BUNDLE} paket kimlikli uygulama yok. Önce App Store Connect > Uygulamalar > + > Yeni Uygulama ile oluştur.")
    print("Uygulama:", a["attributes"].get("name"), a["id"])
    return a["id"]

def editable_version(app_id):
    st, r = api("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=10")
    for v in r.get("data", []):
        if v["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"):
            if v["attributes"]["versionString"] != VER:
                api("PATCH", f"/v1/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"], "attributes": {"versionString": VER}}})
            return v["id"], v["attributes"]["appStoreState"]
    st, r = api("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": VER},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
    if st not in (200, 201): die("Sürüm oluşturulamadı", r)
    return r["data"]["id"], r["data"]["attributes"]["appStoreState"]

# ---------------------------------------------------------------- hazirlik
def hazirlik():
    st, r = api("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE}&limit=5")
    if st != 200: die("API anahtarı çalışmadı (gizli anahtarları kontrol et)", r)
    if any(b["attributes"]["identifier"] == BUNDLE for b in r.get("data", [])):
        print("Paket kimliği zaten kayıtlı:", BUNDLE)
    else:
        st, r = api("POST", "/v1/bundleIds", {"data": {"type": "bundleIds",
            "attributes": {"identifier": BUNDLE, "name": "Gunluk Duzen", "platform": "IOS"}}})
        step("Paket kimliği kaydedildi: " + BUNDLE, st in (200, 201), r)
    a = find_app()
    print("App Store Connect uygulaması:", "VAR (" + a["attributes"]["name"] + ")" if a else "YOK — App Store Connect'te Yeni Uygulama oluştur ve bu paket kimliğini seç.")

# ---------------------------------------------------------------- bilgiler
def localizations(ver_id):
    st, r = api("GET", f"/v1/appStoreVersions/{ver_id}/appStoreVersionLocalizations?limit=50")
    return r.get("data", [])

def set_version_texts(ver_id):
    m = META["tr"]
    locs = localizations(ver_id)
    if not any(l["attributes"]["locale"].startswith("tr") for l in locs):
        st, r = api("POST", "/v1/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations",
            "attributes": {"locale": "tr"}, "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver_id}}}}})
        step("Türkçe sürüm metni oluşturuldu", st in (200, 201), r)
        locs = localizations(ver_id)
    for l in locs:
        loc = l["attributes"]["locale"]
        mm = META["tr"] if loc.startswith("tr") else META.get("en", META["tr"])
        attrs = {"description": mm["description"], "keywords": mm["keywords"], "promotionalText": mm["promotionalText"],
                 "supportUrl": META["supportUrl"], "marketingUrl": META["marketingUrl"]}
        st, r = api("PATCH", f"/v1/appStoreVersionLocalizations/{l['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": l["id"], "attributes": attrs}})
        step(f"Açıklama ve anahtar kelimeler ({loc})", st == 200, r)
    st, r = api("PATCH", f"/v1/appStoreVersions/{ver_id}", {"data": {"type": "appStoreVersions", "id": ver_id,
        "attributes": {"copyright": META["copyright"], "releaseType": "AFTER_APPROVAL"}}})
    step("Telif ve otomatik yayın", st == 200, r)
    return localizations(ver_id)

def set_app_info(app_id):
    st, r = api("GET", f"/v1/apps/{app_id}/appInfos?limit=5")
    infos = r.get("data", [])
    info = next((i for i in infos if i["attributes"].get("appStoreState", i["attributes"].get("state")) not in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION")), infos[0] if infos else None)
    if not info: step("Uygulama bilgisi bulunamadı", False, r); return
    st, r = api("PATCH", f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": META["primaryCategory"]}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": META["secondaryCategory"]}}}}})
    step("Kategori (Verimlilik + Sağlık ve Fitness)", st == 200, r)
    st, r = api("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations?limit=50")
    for l in r.get("data", []):
        loc = l["attributes"]["locale"]
        mm = META["tr"] if loc.startswith("tr") else META.get("en", META["tr"])
        st2, r2 = api("PATCH", f"/v1/appInfoLocalizations/{l['id']}", {"data": {"type": "appInfoLocalizations", "id": l["id"],
            "attributes": {"subtitle": mm["subtitle"], "privacyPolicyUrl": META["privacyUrl"]}}})
        step(f"Alt başlık ve gizlilik politikası ({loc})", st2 == 200, r2)
    # yaş sınırı: her şey "yok"
    st, r = api("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")
    if st == 200 and r.get("data"):
        ad = r["data"]
        BOOL = {"gambling", "unrestrictedWebAccess", "seventeenPlus", "lootBox", "advertising", "ageAssurance",
                "healthOrWellnessTopics", "messagingAndChat", "parentalControls", "userGeneratedContent", "isAdvertising",
                "isAgeAssurance", "isHealthOrWellnessTopics", "isLootBox", "isMessagingAndChat", "isParentalControls",
                "isUserGeneratedContent", "isUnrestrictedWebAccess", "isGambling"}
        SKIP = {"kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride", "developerAgeRatingInfoUrl", "gracRatingClassificationNumber"}
        attrs = {k: (False if k in BOOL or isinstance(v, bool) else "NONE") for k, v in ad["attributes"].items() if k not in SKIP and "korea" not in k.lower() and "grac" not in k.lower()}
        import re
        tried = {}
        for _ in range(15):
            st, r = api("PATCH", f"/v1/ageRatingDeclarations/{ad['id']}", {"data": {"type": "ageRatingDeclarations", "id": ad["id"], "attributes": attrs}})
            if st == 200: break
            changed = False
            for e in r.get("errors", []):
                d = e.get("detail", "")
                names = re.findall(r"'([A-Za-z]+)'", d) + [e.get("source", {}).get("pointer", "").split("/")[-1]]
                names = [n for n in names if n]
                if "required" in d or "missing" in d:
                    for n in names:
                        if n not in attrs: attrs[n] = False; tried[n] = 0; changed = True
                elif "Expected a BOOLEAN" in d or "Expected a STRING" in d:
                    for n in names:
                        v = False if "Expected a BOOLEAN" in d else "NONE"
                        if attrs.get(n, None) != v: attrs[n] = v; changed = True
                elif any(w in d.lower() for w in ("type", "invalid", "not a valid", "enum")):
                    for n in names:
                        if n in attrs and tried.get(n, 0) < 2:
                            tried[n] = tried.get(n, 0) + 1
                            attrs[n] = "NONE" if attrs[n] is False else False; changed = True
                else:
                    for n in names:
                        if n in attrs: attrs.pop(n); changed = True
            print("    yaş formu denemesi:", err(r)[:160])
            if not changed: break
        step("Yaş sınırı (4+)", st == 200, r)
    else:
        step("Yaş sınırı formu bulunamadı", False, r)

def set_content_rights(app_id):
    st, r = api("PATCH", f"/v1/apps/{app_id}", {"data": {"type": "apps", "id": app_id,
        "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
    step("İçerik hakları beyanı", st == 200, r)

def set_price_free(app_id):
    st, r = api("GET", f"/v1/apps/{app_id}/appPriceSchedule")
    if st == 200 and r.get("data") and r["data"].get("id"):
        st2, r2 = api("GET", f"/v1/appPriceSchedules/{r['data']['id']}/manualPrices?limit=5")
        if st2 == 200 and r2.get("data"):
            print("  ✓ Fiyat zaten ayarlı"); return
    pp, url = None, f"/v1/apps/{app_id}/appPricePoints?filter[territory]=TUR&limit=200"
    while url and not pp:
        st, r = api("GET", url)
        for p in r.get("data", []):
            if float(p["attributes"].get("customerPrice") or 0) == 0: pp = p["id"]; break
        url = r.get("links", {}).get("next")
    if not pp: step("Ücretsiz fiyat noktası bulunamadı", False, r); return
    st, r = api("POST", "/v1/appPriceSchedules", {"data": {"type": "appPriceSchedules", "relationships": {
        "app": {"data": {"type": "apps", "id": app_id}},
        "baseTerritory": {"data": {"type": "territories", "id": "TUR"}},
        "manualPrices": {"data": [{"type": "appPrices", "id": "${p0}"}]}}},
        "included": [{"type": "appPrices", "id": "${p0}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": pp}}}}]})
    step("Fiyat: Ücretsiz", st in (200, 201), r)

def set_availability(app_id):
    st, r = api("GET", f"/v1/apps/{app_id}/appAvailabilityV2")
    if st == 200 and r.get("data"):
        print("  ✓ Ülkeler zaten ayarlı"); return
    terrs, url = [], "/v1/territories?limit=200"
    while url:
        st, r = api("GET", url); terrs += [t["id"] for t in r.get("data", [])]; url = r.get("links", {}).get("next")
    inc = [{"type": "territoryAvailabilities", "id": f"${{t{i}}}", "attributes": {"available": True},
            "relationships": {"territory": {"data": {"type": "territories", "id": t}}}} for i, t in enumerate(terrs)]
    st, r = api("POST", "/v2/appAvailabilities", {"data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}},
                          "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": i["id"]} for i in inc]}}},
        "included": inc})
    step(f"Satış ülkeleri ({len(terrs)} ülke)", st in (200, 201), r)

def set_review_detail(ver_id):
    contact = {}
    ref = find_app(REF_BUNDLE)
    if ref:
        st, r = api("GET", f"/v1/apps/{ref['id']}/appStoreVersions?filter[platform]=IOS&limit=5")
        for v in r.get("data", []):
            st2, r2 = api("GET", f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail")
            if st2 == 200 and r2.get("data"):
                a = r2["data"]["attributes"]
                contact = {k: a.get(k) for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail") if a.get(k)}
                if contact: break
    if len(contact) < 4:
        step("İnceleme iletişim bilgisi Miras FC'den alınamadı (App Store Connect'te elle gir)", False); return
    attrs = dict(contact, demoAccountRequired=False, notes=META["reviewNotes"])
    st, r = api("GET", f"/v1/appStoreVersions/{ver_id}/appStoreReviewDetail")
    if st == 200 and r.get("data"):
        st, r = api("PATCH", f"/v1/appStoreReviewDetails/{r['data']['id']}", {"data": {"type": "appStoreReviewDetails", "id": r["data"]["id"], "attributes": attrs}})
    else:
        st, r = api("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver_id}}}}})
    step("İnceleme iletişim bilgisi ve notu", st in (200, 201), r)

def upload_screens(locs):
    files = sorted(glob.glob(os.path.join(ROOT, "store", "screenshots", "*.png")))
    if not files: step("Ekran görüntüsü dosyası yok", False); return
    for l in locs:
        loc = l["attributes"]["locale"]
        st, r = api("GET", f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets?limit=50")
        sset = next((s for s in r.get("data", []) if s["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"), None)
        if not sset:
            st, r = api("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
                "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": l["id"]}}}}})
            if st not in (200, 201): step(f"Ekran görüntüsü seti ({loc})", False, r); continue
            sset = r["data"]
        st, r = api("GET", f"/v1/appScreenshotSets/{sset['id']}/appScreenshots?limit=50")
        for old in r.get("data", []): api("DELETE", f"/v1/appScreenshots/{old['id']}")
        okn = 0
        for f in files:
            b = open(f, "rb").read()
            st, r = api("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": os.path.basename(f), "fileSize": len(b)},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sset["id"]}}}}})
            if st not in (200, 201): step("Ekran görüntüsü " + os.path.basename(f), False, r); continue
            sid = r["data"]["id"]
            for op in r["data"]["attributes"]["uploadOperations"]:
                req = urllib.request.Request(op["url"], data=b[op["offset"]:op["offset"] + op["length"]], method=op["method"])
                for h in op.get("requestHeaders", []): req.add_header(h["name"], h["value"])
                urllib.request.urlopen(req, timeout=120).read()
            st, r = api("PATCH", f"/v1/appScreenshots/{sid}", {"data": {"type": "appScreenshots", "id": sid,
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(b).hexdigest()}}})
            okn += st == 200
        step(f"Ekran görüntüleri ({loc}): {okn}/{len(files)}", okn == len(files))

def bilgiler():
    app_id = need_app()
    ver_id, state = editable_version(app_id)
    print("Sürüm:", VER, state)
    locs = set_version_texts(ver_id)
    set_app_info(app_id)
    set_content_rights(app_id)
    set_price_free(app_id)
    set_availability(app_id)
    set_review_detail(ver_id)
    upload_screens(locs)
    print()
    print("ELLE YAPILACAK TEK ŞEY: App Store Connect > Günlük Düzen > Uygulama Gizliliği >")
    print("  'Veri toplamıyoruz' seç ve Yayınla. (Apple bunu API ile açmıyor.)")
    if PROBLEMS: print("\nSorunlu adımlar:", ", ".join(PROBLEMS)); sys.exit(1)

# ---------------------------------------------------------------- gonder
def gonder():
    app_id = need_app()
    ver_id, state = editable_version(app_id)
    print("Sürüm:", VER, state)
    st, r = api("GET", f"/v1/builds?filter[app]={app_id}&filter[preReleaseVersion.version]={VER}&sort=-uploadedDate&limit=10")
    builds = [b for b in r.get("data", []) if b["attributes"].get("processingState") == "VALID"]
    if not builds: die("Hazır build yok. Önce iOS iş akışıyla TestFlight'a yükle, Apple'ın işlemesini bekle (10-30 dk).", r)
    bid = builds[0]["id"]
    st, r = api("PATCH", f"/v1/appStoreVersions/{ver_id}/relationships/build", {"data": {"type": "builds", "id": bid}})
    if st not in (200, 204): die("Build sürüme bağlanamadı", r)
    print("Build bağlandı:", builds[0]["attributes"].get("version"))
    st, r = api("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&limit=20")
    sub = next((s["id"] for s in r.get("data", []) if s["attributes"].get("state") in ("READY_FOR_REVIEW", "UNRESOLVED_ISSUES")), None)
    if not sub:
        st, r = api("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        if st not in (200, 201): die("Gönderim oluşturulamadı", r)
        sub = r["data"]["id"]
    st, r = api("GET", f"/v1/reviewSubmissions/{sub}/items?limit=50")
    if not any(i.get("relationships", {}).get("appStoreVersion", {}).get("data", {}).get("id") == ver_id for i in r.get("data", [])):
        st, r = api("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver_id}}}}})
        if st not in (200, 201): die("Sürüm gönderime eklenemedi (eksik bilgi olabilir; Uygulama Gizliliği yayınlandı mı?)", r)
    st, r = api("PATCH", f"/v1/reviewSubmissions/{sub}", {"data": {"type": "reviewSubmissions", "id": sub, "attributes": {"submitted": True}}})
    if st != 200: die("Gönderim onaylanamadı", r)
    print("APPLE İNCELEMESİNE GÖNDERİLDİ ✓  Durum:", r["data"]["attributes"].get("state"))

def durum():
    a = find_app()
    if not a: print("Uygulama App Store Connect'te yok."); return
    st, r = api("GET", f"/v1/apps/{a['id']}/appStoreVersions?limit=5")
    for v in r.get("data", []): print("Sürüm", v["attributes"]["versionString"], v["attributes"]["appStoreState"])
    st, r = api("GET", f"/v1/builds?filter[app]={a['id']}&sort=-uploadedDate&limit=5")
    for b in r.get("data", []): print("Build", b["attributes"].get("version"), b["attributes"].get("processingState"))

if __name__ == "__main__":
    if not KID or not ISS or "PRIVATE KEY" not in P8:
        print("HATA: Gizli anahtarlar eksik. Depo > Settings > Secrets and variables > Actions altına")
        print("      ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 ve IOS_TEAM_ID ekle (Miras FC'deki değerlerin aynısı).")
        sys.exit(1)
    cmd = sys.argv[1] if len(sys.argv) > 1 else "durum"
    {"hazirlik": hazirlik, "bilgiler": bilgiler, "gonder": gonder, "durum": durum}[cmd]()
