"""Prepares the Android project that `flutter create` makes on the build server (GitHub Actions):
- app name "Mangao WRS"
- permissions: internet, GPS (rider location, address pin)
- plain http allowed (testing against the laptop server on the same Wi-Fi)
- links the app can open: phone calls, web pages, maps
- signs the app with the project key (app/ci/mangao-release.jks) so a new version installs over the old one
Run from the app folder: python3 ci/patch_android.py
"""
import pathlib
import re
import sys

app = pathlib.Path('.')
manifest = app / 'android/app/src/main/AndroidManifest.xml'
m = manifest.read_text()

perms = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
]
for p in perms:
    if p not in m:
        m = m.replace('<application', f'<uses-permission android:name="{p}"/>\n    <application', 1)

m = re.sub(r'android:label="[^"]*"', 'android:label="Mangao WRS"', m, count=1)
if 'usesCleartextTraffic' not in m:
    m = m.replace('<application', '<application\n        android:usesCleartextTraffic="true"', 1)

queries = """
        <intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="tel"/></intent>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="http"/></intent>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="geo"/></intent>
        <intent><action android:name="android.media.action.IMAGE_CAPTURE"/></intent>
"""
if '<queries>' in m:
    m = m.replace('<queries>', '<queries>' + queries, 1)
else:
    m = m.replace('</manifest>', '    <queries>' + queries + '    </queries>\n</manifest>', 1)
manifest.write_text(m)

# Signing with the project key.
kts = app / 'android/app/build.gradle.kts'
groovy = app / 'android/app/build.gradle'
key = (app / 'ci/mangao-release.jks').resolve().as_posix()
if kts.exists():
    g = kts.read_text()
    block = f'''
    signingConfigs {{
        create("mangao") {{
            storeFile = file("{key}")
            storePassword = "mangaowrs2026"
            keyAlias = "mangao"
            keyPassword = "mangaowrs2026"
        }}
    }}
'''
    if 'create("mangao")' not in g:
        g = re.sub(r'(android\s*\{)', r'\1' + block.replace('\\', '\\\\'), g, count=1)
    # No code shrinking (R8): it removed parts of the plugins (saving on the phone failed with
    # NoSuchMethodError in shared_preferences), so the app could not keep the log-in.
    g = g.replace('signingConfig = signingConfigs.getByName("debug")',
                  'signingConfig = signingConfigs.getByName("mangao")\n            isMinifyEnabled = false\n            isShrinkResources = false')
    if 'getByName("mangao")' not in g:
        sys.exit('could not set the release signing in build.gradle.kts')
    kts.write_text(g)
elif groovy.exists():
    g = groovy.read_text()
    block = f'''
    signingConfigs {{
        mangao {{
            storeFile file("{key}")
            storePassword "mangaowrs2026"
            keyAlias "mangao"
            keyPassword "mangaowrs2026"
        }}
    }}
'''
    if 'mangao {' not in g:
        g = re.sub(r'(android\s*\{)', r'\1' + block.replace('\\', '\\\\'), g, count=1)
    g = g.replace('signingConfig signingConfigs.debug',
                  'signingConfig signingConfigs.mangao\n            minifyEnabled false\n            shrinkResources false')
    if 'signingConfigs.mangao' not in g:
        sys.exit('could not set the release signing in build.gradle')
    groovy.write_text(g)
else:
    sys.exit('no android/app/build.gradle(.kts)')

# Backup if shrinking is still on: keep every plugin's Android code.
(app / 'android/app/proguard-rules.pro').write_text('''# Keep the plugins' code (shrinking removed parts of shared_preferences before).
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class dev.flutter.pigeon.** { *; }
-keep class com.baseflow.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class io.flutter.plugins.firebase.** { *; }
-keep class com.google.firebase.** { *; }
-keepclassmembers class * { @androidx.annotation.Keep *; }
-dontwarn io.flutter.embedding.**
''')

print(manifest.read_text())
print('Android project ready')
