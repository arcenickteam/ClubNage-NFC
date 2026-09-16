# ClubNage NFC V3 — Cloud Build

Version préparée pour produire l'APK Android sans installer Flutter/Android Studio sur la machine locale.

### Compilation
GitHub Actions installe Flutter et génère la plateforme Android avant de lancer :

`flutter build apk --release`

### Artifact attendu
`Club-MN-NFC-V5-Android` → `app-release.apk`

### Appareil cible de test
Samsung Galaxy A33 5G.

### Fonction prioritaire
Lecture réelle des badges NTAG213 via NFC.
