# Club MN NFC — V5

Version 0.5.0+5 — Montchanin Natation

## Nouveautés

- Nom affiché de l'application : **Club MN NFC**.
- Logo de l'association utilisé comme icône Android et dans l'interface.
- Scanner NFC Android en **Reader Mode** avec lecture NFC-A et `skipNdefCheck` : un NTAG213 vierge ne doit plus ouvrir l'écran système « Nouveau tag analysé / Tag vide » lorsque Club MN NFC attend un badge.
- Écran d'attente explicite : **EN ATTENTE DU BADGE NFC / NFC actif**.
- Lecture de l'UID matériel du badge, sans écrire de données personnelles dans le NTAG213.
- Lors de l'association à un licencié : écran **Badge détecté** avec UID + confirmation avant enregistrement.
- Onglet **Licenciés** au lieu de « Nageurs ».
- Préparation de l'interface pour la future synchronisation avec le fichier « véritable base d'échange ClubNage » sur kDrive.

## Test A33

1. Installer l'APK.
2. Ouvrir **Club MN NFC**.
3. Aller dans **Licenciés**.
4. Ouvrir un licencié.
5. Appuyer sur **SCANNER ET ASSOCIER LE BADGE**.
6. Vérifier que **EN ATTENTE DU BADGE NFC / NFC actif** apparaît.
7. Présenter le NTAG213.
8. Vérifier que Club MN NFC affiche **Badge détecté** avec l'UID.
9. Appuyer sur **ASSOCIER**.
10. Vérifier que le licencié indique **Badge associé**.

Le NTAG213 reste vierge : l'UID matériel est utilisé comme identifiant technique.
