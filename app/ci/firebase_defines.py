"""Reads the Firebase Android settings (the google-services.json text in the GitHub secret
FIREBASE_ANDROID_JSON) and prints the --dart-define values the app needs for phone notifications.
Prints nothing when the secret is not set (the app then works without phone notifications)."""
import json
import os
import sys

raw = os.environ.get('FB_JSON', '').strip()
if not raw:
    sys.exit(0)
d = json.loads(raw)
pkg = 'com.mangao.mangao_wrs'
client = None
for c in d.get('client', []):
    if c.get('client_info', {}).get('android_client_info', {}).get('package_name') == pkg:
        client = c
if client is None:
    sys.exit(f'FIREBASE_ANDROID_JSON has no Android app with package name {pkg}')
values = {
    'FB_API_KEY': client['api_key'][0]['current_key'],
    'FB_APP_ID': client['client_info']['mobilesdk_app_id'],
    'FB_SENDER_ID': d['project_info']['project_number'],
    'FB_PROJECT_ID': d['project_info']['project_id'],
}
print(' '.join(f'--dart-define={k}={v}' for k, v in values.items()))
