# ClubNage NFC V7.3 — recherche des fichiers Excel kDrive

- Base : V7.2 (commit 997a0e5), version 0.7.3+11.
- Recherche d’abord les deux noms officiels `..._V4.xlsx`.
- Si l’API kDrive renvoie HTTP 404, essaie `..._V4(1).xlsx` puis `..._V4 (1).xlsx`.
- Un 401/403 reste une erreur d’autorisation et ne provoque pas de substitution.
- Aucun changement à la base locale, aux associations NFC/QR, ni aux présences.
- L’import reste consultatif : il ne remplace pas la base de l’application.
- Le suffixe (1) d’un téléchargement sur Mac n’implique pas qu’il existe sur kDrive.
- Compilation Flutter/Android et téléchargement API à valider sur l’appareil.
