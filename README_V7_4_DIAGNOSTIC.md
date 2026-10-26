# ClubNage NFC V7.4 — diagnostic du téléchargement Excel kDrive

Base attendue : V7.3 (`0.7.3+11`). Nouvelle version : `0.7.4+12`.

- Affiche l’étape précise de la synchronisation : vérification du dossier, recherche du fichier, téléchargement, contrôle du format, décodage Excel.
- Signale le code HTTP et la route API en cas d’échec réseau (sans afficher le jeton).
- Indique la taille et le type MIME de la réponse et distingue un XLSX direct d’un ZIP contenant des XLSX.
- Vérifie les entrées `[Content_Types].xml` et `xl/workbook.xml` dans l’archive avant de lancer le parseur Excel.
- Valide les deux classeurs avant de mettre à jour l’affichage consultatif ; aucune écriture dans la base NFC/QR ou les présences.
- Les noms des licenciés et le jeton API ne sont jamais inclus dans les messages de diagnostic.
- Ne corrige pas automatiquement les erreurs d’API : il rend leur cause visible.

Après installation en mise à jour, ouvrir l’écran kDrive et appuyer sur « Synchroniser les deux fichiers kDrive ». Copier le message final exact, sans partager le jeton.

Compilation Flutter non exécutée dans l’environnement de préparation : validation GitHub Actions nécessaire.
