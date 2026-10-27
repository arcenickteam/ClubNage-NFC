# ClubNage NFC V7.5 — correctif décodage Excel

Constat sur Samsung V7.4 : `Damaged Excel file: styles` à l'étape de décodage de la base licenciés.

Correction : lecture des valeurs OOXML du XLSX avec `archive` + `xml`, sans interpréter `xl/styles.xml`.
- Les fichiers kDrive sont téléchargés par le même service et le même jeton API sécurisé.
- Les onglets `Licenciés` et `Planning référentiel` sont lus directement.
- Les chaînes partagées, les cellules texte, numériques et booléennes sont prises en charge.
- Le parsing métier (ligne 4 des en-têtes, groupes dès Z, colonnes planning A-E) reste identique.
- L'import manuel bénéficie du même correctif.
- Aucun changement dans `main.dart`, dans les badges NFC/QR ni dans la sauvegarde des présences.

Version : 0.7.5+13. Branche visée : v7. Ne pas modifier V6.

Installation : décompresser à la racine du dépôt en branche v7, puis commit/push et vérifier GitHub Actions.
