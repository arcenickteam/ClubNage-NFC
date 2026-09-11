# Platform setup

After creating the Flutter platform folders with `flutter create .`, apply these settings.

## Android
In `android/app/src/main/AndroidManifest.xml`, inside `<manifest>` add:

`<uses-permission android:name="android.permission.NFC" />`

The QR scanner needs camera permission; mobile_scanner documents the corresponding camera configuration.

## iOS
In `ios/Runner/Info.plist`, add:

`<key>NFCReaderUsageDescription</key>`
`<string>ClubNage utilise le NFC pour enregistrer les présences des nageurs.</string>`

Add the Near Field Communication Tag Reader Session Formats capability in Xcode. The nfc_manager package documents the required iOS NFC entitlement/configuration.

For QR scanning, add:

`<key>NSCameraUsageDescription</key>`
`<string>ClubNage utilise la caméra pour scanner les QR codes de secours.</string>`

No child personal data should be written to an NFC tag. The app maps the tag UID to a member record locally/server-side.
