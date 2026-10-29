# ClubNage NFC V7.12 — correctif expérimental

- Plusieurs séances actives en parallèle ; sélection de la séance à pointer via liste déroulante.
- Réconciliation automatique du planning du jour à H−30 et fermeture à H+4 **depuis le début** (et non quatre heures après la fin). Exécution à l'ouverture, au retour au premier plan et toutes les minutes tant que l'application tourne. **Aucune promesse de réveil Android lorsque l'application est arrêtée**.
- Fermeture manuelle ciblée sur la séance sélectionnée, les autres restent ouvertes.
- L'écran Administration > Synchronisation ouvre désormais une vraie page Nuage avec le bouton de synchronisation des présences et l'import des licenciés.
- Recherche par nom/prénom dans les statistiques d'assiduité, selon la période et les groupes sélectionnés.
- Protection des statistiques contre des groupes de séances historiques qui n'existent plus dans le référentiel importé.

## Vérification impérative

Cette version n'a pas pu être compilée localement (SDK Flutter absent de l'environnement de préparation). La compilation GitHub Actions et les essais sur Samsung sont obligatoires avant utilisation en séance réelle. Garder une copie du ZIP source V7.11 et synchroniser les pointages avant mise à jour.

Scénarios à valider : deux créneaux simultanés, fermeture de l'un, pointage sur l'autre ; ouverture H−30 ; fermeture H+4 ; relance après fermeture ; stats groupe adulte ; bouton Nuage ; réouverture avec données locales. Ne pas désinstaller en cas de problème, pour préserver les pointages locaux.
