# Phone notifications (Firebase Cloud Messaging)

With this set up, alerts appear in the phone's notification bar even when the Mangao WRS app is closed
(Android app). Examples: the owner gets "New order"; the customer gets "Order accepted",
"Your water is arriving", "Your rider has arrived". Without it, the same alerts still show inside the app.

Firebase is free for this. It needs a Google account. Do it once.

Never paste the files from steps 2 and 4 into a chat or commit them to GitHub.

## 1. Create the Firebase project
1. Open https://console.firebase.google.com and sign in with the station's (or your) Google account.
2. Click **Create a project** (or **Add project**). Name: `Mangao WRS`. Continue.
3. Google Analytics: turn it **off**. Click **Create project**, wait, then **Continue**.

## 2. Add the Android app
1. On the project page click the **Android** icon (Add app).
2. Android package name: `com.mangao.mangao_wrs` (exactly this). App nickname: `Mangao WRS`.
3. Click **Register app**, then **Download google-services.json**.
4. Click **Next**, **Next**, **Continue to console** (skip the other steps; the build does them).

## 3. Give the Android settings to GitHub
1. Open https://github.com/SkiptyRed8/mangao-wrs > **Settings** > **Secrets and variables** > **Actions**.
2. Click **New repository secret**.
3. Name: `FIREBASE_ANDROID_JSON`
4. Secret: open `google-services.json` in Notepad, select all (Ctrl+A), copy, paste here.
5. Click **Add secret**.

## 4. Give the server its sending key (Render)
1. In Firebase: gear icon > **Project settings** > **Service accounts** tab.
2. Click **Generate new private key** > **Generate key**. A `.json` file downloads. Keep it private.
3. Open https://dashboard.render.com > the **mangao-wrs** service > **Environment**.
4. **Add Environment Variable**: Key `FIREBASE_SERVICE_ACCOUNT`, Value: open the downloaded key file in
   Notepad, select all, copy, paste.
5. Click **Save changes** (the server restarts by itself, about 2 to 5 minutes).

## 5. Build the app again
After step 3, the next app build includes phone notifications. Tell Claude "Firebase done", or on GitHub:
**Actions** > **App build** > **Run workflow**. The build report says `push: on`.

## 6. On each phone
1. Install the new APK over the old one (same link as always).
2. Open the app and log in. When Android asks **Allow Mangao WRS to send you notifications?** tap **Allow**.
3. Test: close the app, place an order from another phone. The owner's phone shows "New order" in the
   notification bar. Tapping it opens the order.

## Notes
- The web version (also iPhone Safari) shows alerts inside the app only; phone-bar notifications are for
  the Android app.
- If a phone does not get them: Settings > Apps > Mangao WRS > Notifications must be on, and battery
  saver should not restrict the app.
