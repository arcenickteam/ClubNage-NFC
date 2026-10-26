# V7 — Sauvegarde locale des présences (sur base APK #56)

- Source : commit `a6f2820`, restauré via commit de revert `78dfbdd`.
- Ajout d'un snapshot local versionné des séances, des pointages et de la séance active via `shared_preferences`.
- Chargement du snapshot avant d'autoriser un nouveau pointage.
- Sauvegarde après ouverture, fermeture, expiration de séance et nouveau pointage NFC/QR.
- Les clés `uid_<licencié>` et `qr_<licencié>` déjà utilisées pour les associations sont inchangées.
- En cas de sauvegarde illisible, l'application affiche une erreur et ne remplace pas la sauvegarde.
- Ne contient ni token kDrive ni noms des licenciés dans le nouveau snapshot.

## Version et tests

- Version Flutter `0.7.1+9`.
- Test de sérialisation/restauration et de non-modification des clés NFC/QR dans `test/local_attendance_store_test.dart`.
- Workflow existant : `flutter analyze` et compilation ; le test doit être lancé séparément avec `flutter test test/local_attendance_store_test.dart`.

## Limites / validation requise

- Pas de synchronisation kDrive, ni de partage multi-téléphone dans ce lot.
- `shared_preferences` n'est pas une base transactionnelle ; pour une exploitation intensive et une file d'attente multi-appareils, prévoir SQLite et un journal d'événements.
- Une interruption brutale entre un scan et l'écriture asynchrone peut encore perdre le dernier événement : vérifier la durabilité avant déploiement.
- Compilation Flutter et test sur Android non réalisés ici : vérifier via GitHub Actions, sans désinstaller l'application existante.
- Attention : le projet contient des données de démonstration nominatives dans `main.dart`, héritées de la base #56 ; audit confidentialité nécessaire avant diffusion.
