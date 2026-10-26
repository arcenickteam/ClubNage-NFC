# V7 — Conservation locale des présences (étape préparatoire)

- Sauvegarde JSON versionnée des séances et pointages dans `shared_preferences`, sur chaque téléphone.
- Restauration après redémarrage de l'application, y compris de la séance ouverte.
- Écritures sérialisées pour éviter qu'une sauvegarde antérieure remplace une plus récente.
- Les associations NFC et QR restent sur leurs clés `uid_*` et `qr_*` existantes, sans migration destructive.
- Aucun token Infomaniak dans les sources, aucun appel d'écriture kDrive ajouté.

## Limites et sécurité

Ce stockage est local et **n'est pas une synchronisation multi-téléphones**. Les préférences
ne constituent pas une base transactionnelle : une fermeture brutale pendant une écriture
peut encore perdre le dernier pointage. Ne pas désinstaller l'application ni effacer ses
données. Avant utilisation réelle, tester sauvegarde/restauration sur un appareil de test.

La synchronisation kDrive nécessitera une méthode d'autorisation mobile sécurisée, un
journal par appareil, une déduplication globale et des essais d'écriture dans un dossier
de test. Le jeton API personnel ne doit jamais être inclus dans le code ou l'APK.

Le projet contient par ailleurs des données personnelles de démonstration codées en dur
(`lib/main.dart`) : les retirer ou les anonymiser avant toute diffusion publique du dépôt.
