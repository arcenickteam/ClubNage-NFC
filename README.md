# ClubNage NFC — V3

V3 is the first source milestone with **real NFC and QR scanning code**, not a visual mockup.

## Included
- Montchanin Natation logo
- iPhone + Android Flutter architecture
- NTAG213/ISO14443 NFC UID reading through `nfc_manager`
- QR fallback through `mobile_scanner`
- multiple groups per member
- duplicate detection
- wrong-group rejection
- local badge association persisted with SharedPreferences
- attendance and statistics UI

## Important
This archive is **Flutter source code**, not a signed iOS IPA or Android APK. The actual iOS build for an iPhone running iOS 26 requires Xcode 26 on macOS Sequoia 15.6+ according to Apple. Your current Ventura Mac cannot do that build.

The production phase still needs a secure central backend for multi-phone synchronization and the OneDrive/Excel connector.

## Packages
- nfc_manager 4.2.1 — iOS + Android NFC
- mobile_scanner 7.4.0 — QR/barcode scanner
- shared_preferences 2.5.3 — local settings

## Platform configuration required after `flutter create`
See `docs/PLATFORM_SETUP.md`.
