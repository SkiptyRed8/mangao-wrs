# Put Mangao WRS online and on Android phones

How it works once this is set up:

| Part | Where it runs | Cost |
|---|---|---|
| Java server (backend) | Render, https://mangao-wrs.onrender.com (Singapore) | Free |
| MySQL database | Aiven (online MySQL) | Free |
| Emails (password reset codes) | Brevo email API, sent from your Gmail address | Free (300 emails a day) |
| Android app (APK) | Built by GitHub every time the app code changes: GitHub > Releases > "Mangao WRS app (latest)" | Free |
| Web app (optional) | https://skiptyred8.github.io/mangao-wrs/ | Free |

The phones only need internet (mobile data or any Wi-Fi). The laptop does not have to be on.

You do parts A to C once (about 30 minutes). Only you can do them, because each one needs your own account.

---

## A. Database: Aiven (free MySQL)

1. Open https://aiven.io and choose **Sign up**. Signing up with Google is easiest.
2. When it asks, create a project, for example `mangao`.
3. **Create service** > **MySQL** > plan **Free**. Pick any region it offers, name it `mangao-db`, and choose **Create service**.
4. Wait until the status says **Running** (a few minutes).
5. On the service **Overview**, under **Connection information**, keep these four values for part C:
   - **Host** (looks like `mangao-db-xxxx.aivencloud.com`)
   - **Port** (a number like `12345`)
   - **User** (`avnadmin`)
   - **Password** (click the eye icon to show it)

You do not need to create tables. The server creates the `mangao_wrs` database with the demo accounts the first time it starts.

## B. Email: Brevo (free)

Render's free plan blocks normal Gmail sending, so the online server sends email through Brevo, from your Gmail address.

1. Open https://www.brevo.com and choose **Sign up free**, using the Gmail address the station will send from. Confirm the email Brevo sends you.
2. Top right menu > **Senders, Domains & Dedicated IPs** > **Senders** > **Add a sender**:
   - From name `Mangao Water Refilling Station`
   - From email: your Gmail address.

   Open the verification email in Gmail and confirm it.
3. Top right menu > **SMTP & API** > **API Keys** > **Generate a new API key**, named `mangao-wrs`. Copy the key (it starts with `xkeysib-`) and keep it for part C. Brevo shows it only once.

## C. Server: Render (free)

1. Open https://render.com and choose **Get Started** > **GitHub**. Sign in as **SkiptyRed8** and allow Render to see the `mangao-wrs` repository.
2. In Render: **New +** > **Blueprint** > choose **mangao-wrs** > **Connect**. Render reads the `render.yaml` file in the repo.
3. It asks for these values (type them exactly, with no spaces before or after):

   | Setting | What to type |
   |---|---|
   | `DB_HOST` | Host from Aiven (A5) |
   | `DB_PORT` | Port from Aiven |
   | `DB_USER` | `avnadmin` |
   | `DB_PASSWORD` | Password from Aiven |
   | `OWNER_EMAIL` | The owner's email (for password reset) |
   | `OWNER_PASSWORD` | A new password for the owner account. **Do not use owner123 online.** |
   | `BREVO_API_KEY` | The key from Brevo (B3) |
   | `BREVO_SENDER` | Your Gmail address verified in Brevo (B2) |

4. Choose **Apply**. The first build takes about 10 minutes. Watch **Logs** until you see
   `Mangao WRS API (Java) running` and `[database] mangao_wrs is empty: creating it with the demo accounts`.
5. Open the address Render shows, adding `/health`. For example https://mangao-wrs.onrender.com/health should show
   `"server":"java"` and `"database":"ok"`.
6. **If Render gave a different address** (the name was taken), tell Claude the address. The app must be rebuilt with it (`deploy/server-url.txt`).

The free server falls asleep after 15 minutes without visitors, and the next visitor then waits about a minute. The "Keep server awake" job on GitHub visits it every 10 minutes so this does not happen during use.

## D. Install the app on an Android phone

1. On the phone, open https://github.com/SkiptyRed8/mangao-wrs/releases/tag/app-latest
2. Under **Assets**, tap **mangao-wrs.apk**. Chrome may warn that the file can be harmful: choose **Download anyway**.
3. Open the downloaded file. Android asks to allow installing apps from Chrome: **Settings** > turn on **Allow from this source** > back > **Install**.
   If Play Protect warns "unknown developer", choose **More details** > **Install anyway**. It warns because the app is not from the Play Store.
4. Open **Mangao WRS** and log in:

   | Role | Phone | Password |
   |---|---|---|
   | Owner | 09170000001 | (the OWNER_PASSWORD you chose in C3) |
   | Staff | 09170000002 | staff123 |
   | Rider | 09170000003 | rider123 |
   | Customer | 09172001111 | ana123 |

   For a real customer, use **Sign up** instead.

## E. When something needs to change

1. Tell Claude what to change (a screenshot helps).
2. Claude changes the code and pushes it to GitHub. Then:
   - **Server changes** go live by themselves in about 10 minutes (Render rebuilds). Nothing to install.
   - **App changes**: GitHub builds a new APK in about 10 minutes. Open the same link (D1), download the new `mangao-wrs.apk` and install it. It installs over the old app, and you stay logged in.
3. The version number is in the release title ("version 1.0.N"). The newest is always at the same link.

## Laptop (development and backup)

START.bat still runs everything on the laptop (local database `mangao_wrs`, Chrome at http://localhost:5100). The online server has its own separate database, so laptop test data does not appear on the phones.
