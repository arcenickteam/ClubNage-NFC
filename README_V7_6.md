# ClubNage NFC V7.6 — Étape 1 : référentiel licenciés

- Import Excel depuis kDrive ou sélection manuelle : validation et sauvegarde locale de tous les licenciés.
- L’accueil et l’affectation NFC/QR utilisent ensuite ce référentiel, sans la liste de démonstration.
- Les associations existantes ne sont **pas supprimées** ; elles sont isolées par identifiant de licencié.
- Les historiques de présences ne sont **pas effacés**.
- En cas d’échec réseau, le dernier référentiel valide reste enregistré.
- La liste des groupes est construite à partir des libellés Excel. Le planning automatique de démonstration reste provisoire : ne pas ouvrir de séance automatique sur cette base avant adaptation du planning V4.

## Non inclus dans cette étape

- Écriture de l’onglet « Pointages NFC » sur kDrive : **non activée**. La stratégie de mise à jour du classeur partagé et de résolution des conflits doit être validée avant d’écrire dans le fichier réel.
- RAZ des présences et des badges : aucune suppression automatique ; une commande explicite et confirmée devra être ajoutée si nécessaire.

## Installation

Appliquer les fichiers de l’archive sur la branche `v7`, puis lancer `flutter analyze` et le build Android. La branche V6 n’est pas modifiée.
