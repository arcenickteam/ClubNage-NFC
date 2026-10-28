# ClubNage NFC V7.11 — Appel manuel et contacts

Base : V7.10 (0.7.10+18), avec correctif de compilation du 28 octobre.
La fonction de clôture V7.10 est conservée.

## Changements
- Présences : recherche, fiche du licencié, choix Présent / Retard / Absent pour chaque membre attendu de la séance ouverte.
- Non pointé est distinct d'Absent déclaré. Aucun absent n'est créé automatiquement.
- Une correction remplace le pointage du même licencié dans la même séance. Son identifiant et l'heure du premier enregistrement sont conservés pour la compatibilité avec les lignes déjà exportées.
- Un badge lu après une absence déclarée transforme ce pointage en Présent ou Retard. Un badge déjà enregistré comme présent/retard reste un doublon refusé.
- Tous les statuts sont sauvegardés localement, même sans Internet.
- Excel : ajout de la colonne Statut, après les 12 colonnes existantes. Les anciens pointages encore disponibles localement sont complétés au prochain envoi. Les anciennes lignes dont le téléphone ne possède plus le pointage gardent un statut vide, non deviné.
- Une ligne déjà exportée est mise à jour si son contenu a changé. La vérification distante contrôle les valeurs, et pas uniquement les identifiants. Les autres feuilles sont recopiées sans modification par le rédacteur XLSX existant.
- Fiche : boutons Appel et SMS par numéro français reconnu; tuteur présenté séparément. Ouverture de l'application du téléphone : l'utilisateur confirme l'appel ou l'envoi. Aucune communication automatique.
- La fiche peut défiler sur les petits écrans.

## Installation sur le Mac
1. Extraire le ZIP dans un dossier séparé (ne pas l'extraire directement dans le projet).
2. Dans le Terminal :
   bash /chemin/vers/le/dossier/installer.sh "$HOME/Desktop/ClubNage-NFC"
3. Le script vérifie la branche v7, les fichiers sources V7.10 et l'absence de modifications suivies. Il conserve une sauvegarde locale avant remplacement. Il n'effectue aucun commit ni push.
4. Dans le projet, contrôler `git diff`, puis exécuter les commandes Git indiquées à la fin du script.
5. GitHub Actions lancera l'analyse Flutter, les tests existants et les quatre nouveaux scénarios, puis la compilation Android.

## Validation effectuée ici et limites
- Syntaxe des fichiers Dart contrôlée avec un analyseur syntaxique; archive et script d'installation contrôlés.
- Flutter/Dart SDK indisponibles dans l'environnement : `flutter analyze`, `flutter test` et compilation APK NON exécutés ici. Une analyse syntaxique ne vérifie pas les types ni les dépendances.
- Aucun appel réel à kDrive, aucune écriture dans les classeurs du club, aucun essai sur téléphone effectué ici.
- Le mécanisme ETag existant est conservé; la prise en charge effective de l'écriture conditionnelle par kDrive n'est pas nouvellement validée. Pour cette version, éviter des synchronisations simultanées depuis plusieurs téléphones.
- Les tests utilisent un kDrive simulé; ils ne remplacent pas les essais Android/kDrive ci-dessous.
- Appel/SMS : url_launcher 6.3.3, documentation https://pub.dev/packages/url_launcher ; boutons pour numéros français 0x, +33, 0033. Un texte sans numéro reconnu reste affiché, sans bouton.

## Recette sur téléphone et sur une copie de test du classeur
1. Anti-doublons : synchroniser les 3 pointages existants puis synchroniser à nouveau sans changement. Attendu : 3 lignes, zéro nouveau pointage au second envoi. Le premier envoi peut annoncer 3 mises à jour pour compléter Statut.
2. Hors connexion : activer le mode avion, ouvrir une séance de test et pointer un membre manuellement. Attendu : statut visible immédiatement; synchronisation échouée mais donnée conservée.
3. Persistance : forcer l'arrêt, rouvrir, vérifier la séance et le statut. Réactiver Internet et synchroniser : une seule ligne pour ce pointage.
4. Corrections : passer Présent → Retard → Absent en synchronisant entre chaque changement. Attendu : même ID et même nombre de lignes, dernière valeur dans Statut. Refaire sans synchronisation entre les changements : seul le dernier état doit être envoyé.
5. Badge après absence : déclarer Absent puis lire son NFC/QR. Attendu : Présent ou Retard, une seule ligne après synchronisation.
6. Contacts : vérifier les numéros affichés; toucher Appel puis revenir; toucher SMS puis revenir sans envoyer. Tester la fiche d'un mineur avec numéro tuteur et celle sans téléphone.
7. Clôture : terminer plusieurs séances, puis relancer l'application. Attendu : aucun écran noir/blanc et historique conservé.

Les boutons collectifs « Tous présents / Tous absents » de la photo ne sont pas inclus : cette version implémente les trois choix individuels demandés.
