# Mangao WRS - Order, Inventory, Sales & Delivery Management System

Mangao Water Refilling Station. Flutter app (tested in Chrome on the laptop, released as an Android APK),
Node.js + Express server, MySQL database.

## Run it (Windows laptop with XAMPP, Node.js and Flutter)
Double-click **START.bat**. It starts MySQL, creates the database the first time, starts the server and
opens the app in Chrome. Keep the windows it opens.

| Role | Phone | Password |
|---|---|---|
| Owner | 09170000001 | owner123 |
| Staff | 09170000002 | staff123 |
| Rider | 09170000003 | rider123 |
| Customer | 09172001111 | ana123 |

- **RESET-DEMO-DATA.bat** - start over with clean demo data (removes the mangao_wrs database through MySQL).
- Never delete folders in `C:\xampp\mysql\data` by hand. Stop MySQL before shutting down the laptop.
- Troubleshooting: `logs\server.log` and `logs\app.log`; the server check is http://localhost:3100/health

## Folders
| Folder | What it is |
|---|---|
| `app/` | Flutter app (Dart). Screens in `app/lib/screens/` by role: `auth`, `owner`, `staff`, `rider`, `customer`, `common` |
| `server/` | Node.js + Express API (JavaScript). Routes in `server/src/routes/`, tests in `server/test/` (`npm test`) |
| `database/schema.sql` | MySQL tables |
| `tools/` | Helper scripts used by START.bat |

## Ports
Server http://localhost:3100 - App in Chrome http://localhost:5100 - MySQL 3306 (XAMPP, user root, no password)
