package com.mangao.wrs.service;

import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Env;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

/**
 * Builds the database from database/schema.sql and sets the owner account from .env.
 *   java -jar mangao-wrs-server.jar --setup-db          fresh database with the owner only
 *   java -jar mangao-wrs-server.jar --setup-db --demo   fresh database plus demo staff, rider, customers and stock
 * The old database is removed through MySQL (DROP DATABASE). Never delete the folders in
 * C:\xampp\mysql\data by hand - that breaks MySQL.
 */
public final class SetupDb {
  private SetupDb() {}

  private record DemoUser(String name, String phone, String email, String password, String role) {}

  private static final DemoUser[] DEMO_USERS = {
    new DemoUser("Joy Ramos", "09170000002", "joy.staff@example.com", "staff123", "Staff"),
    new DemoUser("Juan Dela Cruz", "09170000003", "juan.rider@example.com", "rider123", "Rider"),
    new DemoUser("Ana Lim", "09172001111", "ana@example.com", "ana123", "Customer"),
    new DemoUser("Maria Santos", "09171234567", "maria@example.com", "maria123", "Customer"),
    new DemoUser("Pedro Reyes", "09172221010", "pedro@example.com", "pedro123", "Customer"),
  };

  private record DemoOrder(String phone, int qty, String address, double lat, double lng, String notes, int mins) {}

  // Two new app orders waiting on the Order Board (owner: Accept or Decline).
  private static final DemoOrder[] DEMO_ORDERS = {
    new DemoOrder("09171234567", 3, "8 Ilang-Ilang St., Holy Spirit", 14.6826, 121.0785, "Leave at the gate", 12),
    new DemoOrder("09172221010", 1, "5 Mabuhay St., Commonwealth", 14.7031, 121.0912, null, 5),
  };

  public static String schemaSql() throws Exception {
    Path file = Env.baseDir().resolve("../database/schema.sql").normalize();
    if (Files.exists(file)) return Files.readString(file, StandardCharsets.UTF_8);
    try (InputStream in = SetupDb.class.getResourceAsStream("/db/schema.sql")) {
      return new String(in.readAllBytes(), StandardCharsets.UTF_8);
    }
  }

  /**
   * Online server (AUTO_SETUP_DB=true): builds the database the first time only, when it has no
   * users table yet. An existing database is never touched. Demo accounts when SETUP_DEMO=true.
   */
  public static void ensure() {
    String database = Env.dbName();
    String url = "jdbc:mysql://" + Env.dbHost() + ":" + Env.dbPort() + "/?useUnicode=true&characterEncoding=utf8&" + Env.jdbcSsl();
    try (Connection conn = DriverManager.getConnection(url, Env.dbUser(), Env.dbPassword());
        PreparedStatement ps = conn.prepareStatement("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = ? AND table_name = 'users'")) {
      ps.setString(1, database);
      try (java.sql.ResultSet rs = ps.executeQuery()) {
        rs.next();
        if (rs.getInt(1) > 0) return;
      }
    } catch (Exception e) {
      System.err.println("[database] cannot check the database: " + e.getMessage());
      return;
    }
    try {
      System.out.println("[database] " + database + " is empty: creating it" + (Env.setupDemo() ? " with the demo accounts" : ""));
      run(Env.setupDemo(), database, false);
    } catch (Exception e) {
      System.err.println("[database] setup failed: " + e.getMessage());
    }
  }

  public static void run(boolean demo, String database, boolean quiet) throws Exception {
    if (!database.matches("^[A-Za-z0-9_]+$")) throw new IllegalArgumentException("DB_NAME may only use letters, numbers and _");
    String sql = schemaSql()
        .replace("CREATE DATABASE IF NOT EXISTS mangao_wrs", "CREATE DATABASE IF NOT EXISTS `" + database + "`")
        .replace("USE mangao_wrs;", "USE `" + database + "`;");
    String url = "jdbc:mysql://" + Env.dbHost() + ":" + Env.dbPort()
        + "/?allowMultiQueries=true&useUnicode=true&characterEncoding=utf8&" + Env.jdbcSsl()
        + "&connectionTimeZone=%2B08:00&forceConnectionTimeZoneToSession=true";
    try (Connection conn = DriverManager.getConnection(url, Env.dbUser(), Env.dbPassword()); Statement st = conn.createStatement()) {
      st.execute("DROP DATABASE IF EXISTS `" + database + "`");
      st.execute(sql);
      if (!quiet) System.out.println("Database \"" + database + "\" created.");
      st.execute("USE `" + database + "`");

      String ownerPhone = Body.normalizePhone(Env.ownerPhone());
      try (PreparedStatement ps = conn.prepareStatement("UPDATE users SET full_name = ?, phone_number = ?, email = ?, password_hash = ? WHERE user_id = 1")) {
        ps.setString(1, Env.ownerName());
        ps.setString(2, ownerPhone);
        ps.setString(3, Body.normalizeEmail(Env.ownerEmail()));
        ps.setString(4, Accounts.hash(Env.ownerPassword()));
        ps.executeUpdate();
      }
      if (!quiet) System.out.println("Owner account: " + Env.ownerName() + " / " + ownerPhone + " (password from .env)");

      if (demo) {
        LocalDateTime nowPh = LocalDateTime.now(ZoneOffset.ofHours(8));
        for (DemoUser u : DEMO_USERS) {
          try (PreparedStatement ps = conn.prepareStatement(
              "INSERT INTO users (full_name, phone_number, email, password_hash, role, privacy_consent_at) VALUES (?, ?, ?, ?, ?, ?)")) {
            ps.setString(1, u.name());
            ps.setString(2, u.phone());
            ps.setString(3, u.email());
            ps.setString(4, Accounts.hash(u.password()));
            ps.setString(5, u.role());
            ps.setObject(6, "Customer".equals(u.role()) ? nowPh : null);
            ps.executeUpdate();
          }
        }
        long ana = idOf(conn, "09172001111");
        try (PreparedStatement ps = conn.prepareStatement(
            "INSERT INTO customer_addresses (customer_id, address_name, house_unit_no, street, barangay, landmark, latitude, longitude)"
                + " VALUES (?, 'Home', '12', 'Malaya St.', 'Commonwealth', 'Near the plaza', 14.6976, 121.0886)")) {
          ps.setLong(1, ana);
          ps.executeUpdate();
        }
        // Starting stock: 24 new gallons (low-stock level 30, so the alert shows) and 420 seals.
        st.execute("UPDATE inventory_items SET quantity_on_hand = 24 WHERE item_name = 'New Gallon'");
        st.execute("UPDATE inventory_items SET quantity_on_hand = 420 WHERE item_name = 'Seal'");
        st.execute("INSERT INTO stock_movements (item_id, recorded_by, movement_type, quantity_change, note)"
            + " SELECT item_id, 1, 'Added', quantity_on_hand, 'Starting stock' FROM inventory_items");
        // Station phone (address and pin come from schema.sql; the owner can move the pin in Prices & Settings).
        try (PreparedStatement ps = conn.prepareStatement("UPDATE station_settings SET station_phone = ? WHERE setting_id = 1")) {
          ps.setString(1, ownerPhone);
          ps.executeUpdate();
        }
        for (DemoOrder d : DEMO_ORDERS) {
          long cid = idOf(conn, d.phone());
          String cname = nameOf(conn, cid);
          LocalDateTime at = nowPh.minusMinutes(d.mins());
          long oid;
          try (PreparedStatement ps = conn.prepareStatement(
              "INSERT INTO orders (order_source, order_type, customer_id, customer_name, contact_phone, delivery_address_text,"
                  + " delivery_latitude, delivery_longitude, quantity, unit_price, total_amount, notes, status, payment_method, created_at)"
                  + " VALUES ('App', 'Refill', ?, ?, ?, ?, ?, ?, ?, 35, ?, ?, 'New', 'COD', ?)", Statement.RETURN_GENERATED_KEYS)) {
            ps.setLong(1, cid);
            ps.setString(2, cname);
            ps.setString(3, d.phone());
            ps.setString(4, d.address());
            ps.setDouble(5, d.lat());
            ps.setDouble(6, d.lng());
            ps.setInt(7, d.qty());
            ps.setDouble(8, 35.0 * d.qty());
            ps.setString(9, d.notes());
            ps.setObject(10, at);
            ps.executeUpdate();
            try (ResultSet k = ps.getGeneratedKeys()) {
              k.next();
              oid = k.getLong(1);
            }
          }
          try (PreparedStatement ps = conn.prepareStatement(
              "INSERT INTO order_status_history (order_id, status, changed_by, changed_at) VALUES (?, 'Waiting for order to be accepted', ?, ?)")) {
            ps.setLong(1, oid);
            ps.setLong(2, cid);
            ps.setObject(3, at);
            ps.executeUpdate();
          }
        }
        if (!quiet) {
          System.out.println("Demo accounts (phone / password):");
          System.out.printf("  %-8s %s / %s%n", "Owner", ownerPhone, "production".equals(Env.nodeEnv()) ? "(OWNER_PASSWORD setting)" : Env.ownerPassword());
          for (DemoUser u : DEMO_USERS) System.out.printf("  %-8s %s / %s%n", u.role(), u.phone(), u.password());
        }
      }
    }
  }

  private static long idOf(Connection conn, String phone) throws Exception {
    try (PreparedStatement ps = conn.prepareStatement("SELECT user_id FROM users WHERE phone_number = ?")) {
      ps.setString(1, phone);
      try (ResultSet r = ps.executeQuery()) {
        r.next();
        return r.getLong(1);
      }
    }
  }

  private static String nameOf(Connection conn, long id) throws Exception {
    try (PreparedStatement ps = conn.prepareStatement("SELECT full_name FROM users WHERE user_id = ?")) {
      ps.setLong(1, id);
      try (ResultSet r = ps.executeQuery()) {
        r.next();
        return r.getString(1);
      }
    }
  }
}
