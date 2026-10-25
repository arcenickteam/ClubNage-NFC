# V7 – intégration expérimentale OAuth2 kDrive

## Modifications
- Bouton « Se connecter à Infomaniak » via AppAuth OAuth2/PKCE, scope `drive`, Client ID public, sans Client secret.
- Vérification explicite de l’ID de dossier 215 (issu de l’URL web) et de son nom avant tout téléchargement.
- Recherche des deux fichiers V4 par nom exact via API v3.
- Tentative de téléchargement binaire via API v2, décodage Excel, mise à jour **uniquement de l’écran de consultation**.
- En cas d’échec, conservation des anciennes données affichées et affichage de l’erreur ; import manuel toujours disponible.
- Pas de stockage de token persistant : nouvelle connexion après redémarrage.
- Aucune écriture dans kDrive, aucun changement des badges NFC/QR ni des pointages V6.

## À valider sur Samsung
1. Compiler via GitHub Actions, installer sur appareil de test.
2. Ouvrir l’icône nuage et choisir « Se connecter à Infomaniak ».
3. Vérifier la page d’autorisation avec le scope `drive` ; confirmer le retour dans l’application.
4. Contrôler que l’API reconnaît bien le dossier 215 comme « Saison 2026-2027 ».
5. Tester « Synchroniser les deux fichiers kDrive ».
6. Si HTTP 403/404 : le partage externe peut ne pas être accessible par l’API ; relever uniquement le code HTTP et le chemin, **jamais le jeton**.

## Limites
- **Compilation et accès réels non testés** ici : Flutter SDK et compte kDrive authentifié indisponibles.
- La documentation Infomaniak indique que certains partages externes ne sont accessibles que via l’interface Web. Le succès de l’API n’est pas garanti.
- L’URL de redirection et la configuration Android AppAuth nécessitent validation en compilation et sur téléphone.
- Les 379 licenciés sont une cible de contrôle, non une valeur constatée par cette version.
- Ne pas ajouter de fichier Excel réel, de secret ou de token au dépôt GitHub.
