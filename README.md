# Mangao WRS - Order, Inventory, Sales & Delivery Management System

Mangao Water Refilling Station. Flutter app (tested in Chrome on the laptop, released as an Android APK),
Java + Spring Boot server (backend), MySQL database.

## Run it (Windows laptop with XAMPP, Java JDK 17 or newer, and Flutter)
First time only: double-click **SETUP-JAVA.bat** (downloads Maven and the server libraries; needs internet).

Phones and online server: see **docs/GO-ONLINE.md** (Android APK from GitHub Releases).

Double-click **START.bat**. It starts MySQL, builds the Java server when its code changed, creates the
database the first time, starts the server and
opens the app in Chrome. Keep the windows it opens.

| Role | Phone | Password |
|---|---|---|
| Owner | 09170000001 | owner123 |
| Staff | 09170000002 | staff123 |
| Rider | 09170000003 | rider123 |
| Customer | 09172001111 | ana123 |

- **ALLOW-PHONE.bat** - run once if a phone on the same Wi-Fi cannot reach the laptop server (Windows Firewall, port 3100).
- **TEST-EMAIL.bat** - checks the Gmail settings in `server-java\.env` and sends one test email.
- **RESET-DEMO-DATA.bat** - start over with clean demo data (removes the mangao_wrs database through MySQL).
- Never delete folders in `C:\xampp\mysql\data` by hand. Stop MySQL before shutting down the laptop.
- Troubleshooting: `logs\server.log`, `logs\build.log` and `logs\app.log`; the server check is http://localhost:3100/health

## Folders
| Folder | What it is |
|---|---|
| `app/` | Flutter app (Dart). Screens in `app/lib/screens/` by role: `auth`, `owner`, `staff`, `rider`, `customer`, `common` |
| `server-java/` | **The backend**: Java + Spring Boot API. Endpoints in `src/main/java/com/mangao/wrs/api/`, business rules in `service/`, settings in `server-java\.env` |
| `server/` | The first Node.js server, kept for reference, and the API tests in `server/test/` (81 tests; they also run against the Java server with `API_URL=http://localhost:3100`) |
| `database/schema.sql` | MySQL tables |
| `tools/` | Helper scripts used by START.bat |

## Ports
Server http://localhost:3100 - App in Chrome http://localhost:5100 - MySQL 3306 (XAMPP, user root, no password)
