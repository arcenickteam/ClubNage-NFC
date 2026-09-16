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

text = text.replace('android:label="clubnage_nfc"', 'android:label="Club MN NFC"')

manifest.write_text(text, encoding='utf-8')

# Conserver le nom affiché et le logo de l'association sur le lanceur Android.
# Les PNG sont fournis dans tool/android_icons et sont copiés après flutter create.


import shutil
icons_root = Path('tool/android_icons')
res_root = Path('android/app/src/main/res')
if icons_root.exists():
    for source in icons_root.glob('mipmap-*/ic_launcher.png'):
        destination = res_root / source.parent.name / 'ic_launcher.png'
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        print(f'Launcher icon: {destination}')
