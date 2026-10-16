package com.mangao.wrs.core;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;

/**
 * Settings from server-java/.env (same names as the old server/.env: PORT, JWT_SECRET, DB_*, OWNER_*,
 * SMTP_*, MAIL_FROM, FIREBASE_SERVICE_ACCOUNT). Real environment variables win over the file.
 */
public final class Env {
  private static final Map<String, String> FILE = new HashMap<>();
  private static Path baseDir = Path.of("").toAbsolutePath();

  private Env() {}

  /** Reads .env from the folder the server runs in (the server-java folder). */
  public static void load(Path dir) {
    baseDir = dir.toAbsolutePath();
    Path f = baseDir.resolve(".env");
    if (!Files.exists(f)) return;
    try {
      for (String line : Files.readAllLines(f, StandardCharsets.UTF_8)) {
        String l = line.strip();
        if (l.isEmpty() || l.startsWith("#") || !l.contains("=")) continue;
        int i = l.indexOf('=');
        String k = l.substring(0, i).strip();
        String v = l.substring(i + 1).strip();
        if (v.length() >= 2 && ((v.startsWith("\"") && v.endsWith("\"")) || (v.startsWith("'") && v.endsWith("'")))) {
          v = v.substring(1, v.length() - 1);
        }
        FILE.put(k, v);
      }
    } catch (IOException e) {
      System.err.println("[settings] cannot read " + f + ": " + e.getMessage());
    }
  }

  public static Path baseDir() {
    return baseDir;
  }

  public static String get(String key, String def) {
    String v = System.getenv(key);
    if (v == null) v = System.getProperty(key);
    if (v == null) v = FILE.get(key);
    return v == null || v.isEmpty() ? def : v;
  }

  public static int getInt(String key, int def) {
    try {
      return Integer.parseInt(get(key, String.valueOf(def)).trim());
    } catch (NumberFormatException e) {
      return def;
    }
  }

  // ---- the settings the server uses
  public static int port() { return getInt("PORT", 3100); }
  public static String nodeEnv() { return get("NODE_ENV", get("APP_ENV", "development")); }
  public static boolean testMode() { return "test".equals(nodeEnv()); }
  public static String jwtSecret() { return get("JWT_SECRET", "dev-only-secret"); }
  public static String dbHost() { return get("DB_HOST", "localhost"); }
  public static int dbPort() { return getInt("DB_PORT", 3306); }
  public static String dbUser() { return get("DB_USER", "root"); }
  public static String dbPassword() { return get("DB_PASSWORD", ""); }
  public static String dbName() { return get("DB_NAME", "mangao_wrs"); }
  public static String ownerName() { return get("OWNER_NAME", "Ervin P. Mangao"); }
  public static String ownerPhone() { return get("OWNER_PHONE", "09170000001"); }
  public static String ownerEmail() { return get("OWNER_EMAIL", "owner@example.com"); }
  public static String ownerPassword() { return get("OWNER_PASSWORD", "owner123"); }
  public static String smtpHost() { return get("SMTP_HOST", "smtp.gmail.com"); }
  public static int smtpPort() { return getInt("SMTP_PORT", 465); }
  public static String smtpUser() { return get("SMTP_USER", "").trim(); }
  /** Google shows the App Password in 4 groups with spaces. */
  public static String smtpPass() { return get("SMTP_PASS", "").replaceAll("\\s+", "").replaceAll("^['\"]|['\"]$", ""); }
  public static String mailFrom() { return get("MAIL_FROM", "Mangao Water Refilling Station <no-reply@example.com>"); }
  public static String firebaseServiceAccount() { return get("FIREBASE_SERVICE_ACCOUNT", ""); }
  /** Damaged-gallon photos. */
  public static Path uploadsDir() {
    return baseDir.resolve(get("UPLOADS_DIR", "uploads")).normalize();
  }
}
