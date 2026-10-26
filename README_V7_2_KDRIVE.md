# ClubNage NFC V7.2 — essai kDrive sécurisé

- Base : V7.1, version Android `0.7.2+10`.
- Dans l’écran « V7 · kDrive », bouton **Configurer le jeton API kDrive**.
- Saisir un **jeton API dédié** au club, avec droits kDrive minimum, durée limitée.
- L’application teste le dossier `/3/drive/3455819/files/215` et son nom avant de sauvegarder le jeton dans `flutter_secure_storage` (Android Keystore).
- Le bouton « Synchroniser » lit les deux classeurs V4 en consultation ; **aucune écriture kDrive**, aucun changement des badges ou du journal de présences.
- Le bouton « Oublier le jeton » supprime le secret de l’appareil. Le jeton peut aussi être révoqué dans le Manager Infomaniak.
- L’import XLSX manuel reste disponible.
- Infomaniak Authenticator sert à la double authentification du compte ; il ne remplace pas les autorisations API.

## Sécurité et limites

- Ne jamais partager le jeton dans le chat, les captures d’écran, les logs, GitHub ou le code.
- Créer un jeton **distinct par téléphone**, à durée de validité limitée, et révoquer tout jeton perdu.
- Cette version **ne synchronise pas encore les présences entre téléphones** et ne charge pas automatiquement les licenciés dans l’écran principal : le module V7 affiche seulement un aperçu des deux classeurs.
- Une sauvegarde Android ou migration d’appareil peut ne pas restaurer le secret : dans ce cas, le saisir de nouveau.
- Le correctif n’a pas été compilé dans cet environnement : le build GitHub Actions et le test sur Samsung restent nécessaires.
