# ClubNage NFC — V4 interface + association badge

Cette version ajoute à la V3 :
- interface mobile plus structurée : Accueil / Scanner / Présences / Nageurs / Stats ;
- sélection de la séance/groupe ;
- recherche de nageur ;
- bouton **Scanner et associer le badge** dans la fiche nageur ;
- lecture du véritable UID NFC du NTAG213 puis mémorisation locale de l'association ;
- contrôle empêchant d'associer le même UID à deux nageurs ;
- conservation du QR comme solution de secours ;
- conservation du fonctionnement hors connexion et de la préparation à la synchronisation future.

## Association d'un badge

1. Ouvrir **Nageurs**.
2. Choisir le nageur.
3. Appuyer sur **SCANNER ET ASSOCIER LE BADGE**.
4. Approcher le NTAG213 du téléphone.
5. L'UID est enregistré localement pour ce nageur.

Le NTAG213 n'a pas besoin d'être écrit : son UID suffit pour identifier le porte-clé. L'écriture NDEF pourra être ajoutée ultérieurement si nécessaire.
