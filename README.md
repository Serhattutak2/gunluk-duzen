# Günlük Düzen

Alışkanlık takip uygulaması (iOS). Hedeflerini yaptıkça XP kazanırsın, ağacın büyür, bahçende çiçekler açar.

- `app/` — uygulamanın kendisi (tek dosya HTML + yazı tipleri)
- `mobile/` — iOS sarmalayıcı (Capacitor 8, Swift Package Manager)
- `store/` — App Store metinleri ve ekran görüntüleri
- `tools/asc.py` — App Store Connect otomasyonu
- `.github/workflows/ios.yml` — derleme; commit mesajında `[testflight]` varsa TestFlight'a yükler
- `.github/workflows/appstore.yml` — App Store adımları (hazirlik, bilgiler, gonder, durum)

Gerekli gizli anahtarlar: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `IOS_TEAM_ID`.
Paket kimliği: `com.serhattutak.gunlukduzen`
