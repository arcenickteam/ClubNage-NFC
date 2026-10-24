# ClubNage NFC V7 — premier lot d'essais, sans risque de migration

## Ce qui fonctionne dans ce lot
- La V6 (NFC/QR, groupes, séances, associations locales) est conservée sans migration de ses données.
- Nouvel écran **V7 · Essais kDrive (lecture seule)**, via l'icône nuage dans la barre supérieure.
- Sélection locale de `ClubNage_Base_licencies_26-27_V4.xlsx` et de `ClubNage_Suivi_activite_26-27_V4.xlsx`, récupérés depuis kDrive.
- Lecture des 379 fiches, catégories, sessions, niveaux, activités et des créneaux, avec recherche.
- Aucune écriture dans kDrive, aucune association de badge changée, aucune présence ajoutée par cet écran.

## Important : limites
- Il s'agit d'un **import manuel de fichiers exportés depuis kDrive**, pas encore d'une synchronisation automatique.
- L'import V4 est consultatif et isolé de la liste de pointage V6. Les 379 licenciés ne sont pas encore activés pour le pointage.
- Aucun jeton API personnel n'est intégré au projet. OAuth2 PKCE et migration des badges nécessitent une étape ultérieure.
- Le projet n'a pas pu être compilé dans l'environnement de préparation : vérifiez `flutter pub get`, `flutter analyze` et la compilation Android.
- Le fichier Excel contient des informations personnelles, dont celles de mineurs : ne pas publier les exports sur GitHub.

## Essais Android
1. Conserver la V6 et ses données avant d'installer une nouvelle version. Une installation de V7 avec le même identifiant de paquet peut mettre à niveau la V6 ; effectuer les premiers tests sur un appareil de test.
2. Placer les deux fichiers V4 dans le dossier Téléchargements du téléphone (par kDrive ou transfert local).
3. Ouvrir l'icône nuage en haut de ClubNage NFC.
4. Importer d'abord la base, puis le suivi. Vérifier les effectifs et les créneaux.
5. Tester les écrans V6 séparément sans enregistrer de nouvelles présences réelles.

## Compilation depuis la racine du projet
```bash
flutter pub get
flutter analyze
flutter build apk --debug
```
Le workflow GitHub Actions prend aussi en charge la branche `v7` et génère un APK de test.
