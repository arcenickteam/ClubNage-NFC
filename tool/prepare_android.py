from pathlib import Path

manifest = Path('android/app/src/main/AndroidManifest.xml')
text = manifest.read_text(encoding='utf-8')

permission = '<uses-permission android:name="android.permission.NFC" />'
feature = '<uses-feature android:name="android.hardware.nfc" android:required="false" />'

if permission not in text:
    text = text.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
                        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    ' + permission)
if feature not in text:
    text = text.replace(permission, permission + '\n    ' + feature)

text = text.replace('android:label="clubnage_nfc"', 'android:label="ClubNage NFC"')

manifest.write_text(text, encoding='utf-8')
