# Club MN NFC V5.2

Version d'interface figée pour Montchanin Natation.

## Parcours NFC Android
Licencié → Scanner et associer le badge → écran EN ATTENTE DU BADGE NFC → présentation NTAG213 → lecture UID → confirmation → association locale.

Android utilise Reader Mode avec `skipNdefCheck` et `noPlatformSounds`. L'application n'écrit et ne formate jamais le NTAG213.

## Interface
Accueil, Scanner, Licenciés, Groupes, Séances, Présences, Statistiques.

## Synchronisation
La V5.2 conserve le fonctionnement hors ligne et prépare le journal de présences. La connexion réelle kDrive nécessite la configuration OAuth Infomaniak (identifiant d'application / redirect URI) et ne doit jamais embarquer le mot de passe kDrive dans l'APK.
