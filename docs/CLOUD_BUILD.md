# ClubNage NFC V3 — compilation Android dans le cloud

Cette version est préparée pour générer automatiquement un APK Android avec GitHub Actions.

## Ce qu'il faut

- un compte GitHub gratuit ;
- créer un dépôt GitHub pour le projet ;
- envoyer le contenu de ce dossier dans le dépôt ;
- lancer l'action **ClubNage NFC - Android APK** depuis l'onglet **Actions**.

Aucun Flutter, Android Studio ou SDK Android n'est nécessaire sur le Mac ou le PC utilisé pour déposer le projet.

## Résultat

L'action génère :

`build/app/outputs/flutter-apk/app-release.apk`

L'APK est ensuite disponible dans **Actions > workflow > Artifacts > ClubNage-NFC-V3-Android**.

## Important

Cet APK est destiné au test sur le Samsung A33 5G. Il n'est pas encore une version production multi-téléphones/OneDrive. Le premier objectif est de valider le flux réel :

**NTAG213 → lecture UID → application → présence.**

La clé de signature de production ne doit jamais être placée dans le dépôt. Pour une publication Google Play, une signature dédiée devra être configurée.
