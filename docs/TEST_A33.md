# Test Samsung A33 5G — Club MN NFC V5

1. Installer l’APK `app-release.apk`.
2. Vérifier que le NFC est activé.
3. Ouvrir **Club MN NFC**.
4. Aller dans **Licenciés** et ouvrir un licencié.
5. Appuyer sur **SCANNER ET ASSOCIER LE BADGE**.
6. L’écran doit afficher **EN ATTENTE DU BADGE NFC / NFC actif**.
7. Approcher le NTAG213 du dos du A33.
8. **La page Samsung « Nouveau tag analysé / Tag vide » ne doit plus apparaître** : Club MN NFC doit afficher **Badge détecté** avec son UID.
9. Confirmer **ASSOCIER**.
10. Vérifier ensuite que le licencié affiche **Badge associé**.

Le NTAG213 doit rester vierge : l’application utilise son UID matériel comme identifiant technique.
