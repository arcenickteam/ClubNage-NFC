# ClubNage NFC V7.9 — synchronisation expérimentale

- Base: V7.8, version 0.7.9+17.
- Lecture NFC/QR et correspondances des groupes inchangées.
- Les pointages restent enregistrés localement avant tout envoi.
- Bouton « SYNCHRONISER LES PRÉSENCES » dans la carte kDrive.
- Ajout automatique de la feuille « Pointages NFC » au premier envoi.
- Identifiant déterministe par pointage, dédoublonnage sur les identifiants déjà présents dans Excel.
- Contrôle d'ETag et vérification du résultat par re-téléchargement.

## Important

**NON TESTÉ sur un serveur kDrive réel ni compilé dans cet environnement.**
Le serveur doit respecter If-Match pour garantir l'absence d'écrasement en cas de modification simultanée. Ne pas utiliser sur le classeur de production sans sauvegarde et test sur une copie. La route de téléversement Infomaniak peut demander des paramètres supplémentaires; un refus HTTP laissera les présences en local.

Le format de la feuille est :
ID_Pointage, Date, Heure, Licencie_ID, Nom, Prénom, Activité, Groupe, Séance, Type_badge, Appareil_ID, Date_synchronisation.

Les autres feuilles sont recopiées sans réécriture logique. Le nouveau feuillet est produit en XML OOXML et empaqueté dans le XLSX.

## Validation

1. Créer une sauvegarde du fichier Excel sur kDrive avant le premier essai.
2. Installer la V7.9 et importer les licenciés via le jeton API avec autorisation d'écriture.
3. Pointer un nageur et contrôler l'historique local.
4. Lancer la synchronisation et lire le résultat (succès / HTTP / ETag).
5. Ouvrir le classeur et vérifier l'onglet Pointages NFC, puis recommencer pour contrôler l'absence de doublons.
6. Ne pas utiliser simultanément le classeur dans un éditeur pendant les premiers essais.
