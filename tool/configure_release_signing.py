#!/usr/bin/env python3
"""Configure la signature release dans le Gradle Kotlin généré par flutter create.

Arrête la compilation si le gabarit Flutter change, au lieu de publier
accidentellement un APK signé avec une clé de debug.
"""
from pathlib import Path

p = Path("android/app/build.gradle.kts")
if not p.is_file():
    raise SystemExit(f"Gradle Android introuvable : {p}")
s = p.read_text(encoding="utf-8")
marker = '    buildTypes {\n'
if s.count(marker) != 1:
    raise SystemExit("Structure buildTypes Gradle inattendue : signature non modifiée")
debug = 'signingConfig = signingConfigs.getByName("debug")'
if s.count(debug) != 1:
    raise SystemExit("Signature debug release introuvable/ambiguë : arrêter la compilation")
release = '''    signingConfigs {
        create("release") {
            val keyPath = System.getenv("CLUBNAGE_KEYSTORE_PATH")
                ?: error("CLUBNAGE_KEYSTORE_PATH manquant")
            storeFile = file(keyPath)
            storePassword = System.getenv("CLUBNAGE_STORE_PASSWORD")
                ?: error("CLUBNAGE_STORE_PASSWORD manquant")
            keyAlias = System.getenv("CLUBNAGE_KEY_ALIAS")
                ?: error("CLUBNAGE_KEY_ALIAS manquant")
            keyPassword = System.getenv("CLUBNAGE_KEY_PASSWORD")
                ?: error("CLUBNAGE_KEY_PASSWORD manquant")
        }
    }

'''
s=s.replace(marker,release+marker,1)
s=s.replace(debug,'signingConfig = signingConfigs.getByName("release")',1)
p.write_text(s,encoding="utf-8")
print("Signature release configurée dans Gradle Kotlin")
