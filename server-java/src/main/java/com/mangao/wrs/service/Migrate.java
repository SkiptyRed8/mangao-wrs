package com.mangao.wrs.service;

import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.V;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * Small changes to an existing database, run when the server starts, so a laptop that already has
 * data does not need RESET-DEMO-DATA.bat. Each change checks first, so running it again does nothing.
 */
@Component
public class Migrate {
  public static final String STATION_ADDRESS = "98 Riverside Street, Barangay Commonwealth, Quezon City";
  public static final double STATION_LAT = 14.6928230, STATION_LNG = 121.0871699;
  /** Placeholder pin used before Oct 14 (center of Commonwealth), replaced by the station's street. */
  private static final double OLD_LAT = 14.6976, OLD_LNG = 121.0886;
  private final Db db;

  public Migrate(Db db) {
    this.db = db;
  }

  private boolean columnExists(String table, String column) {
    Map<String, Object> r = db.one(
        "SELECT COUNT(*) AS c FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?", table, column);
    return V.lng(r.get("c")) > 0;
  }

  public List<String> migrate() {
    List<String> done = new ArrayList<>();
    if (!columnExists("station_settings", "station_address")) {
      db.update("ALTER TABLE station_settings ADD COLUMN station_address VARCHAR(255) NULL COMMENT 'Shown on reports and the live map' AFTER station_phone");
      db.update("UPDATE station_settings SET station_address = ? WHERE setting_id = 1 AND station_address IS NULL", STATION_ADDRESS);
      done.add("station address");
      Map<String, Object> s = db.one("SELECT station_latitude AS lat, station_longitude AS lng FROM station_settings WHERE setting_id = 1");
      boolean old = s != null && (s.get("lat") == null
          || (Math.abs(V.num(s.get("lat")) - OLD_LAT) < 1e-6 && Math.abs(V.num(s.get("lng")) - OLD_LNG) < 1e-6));
      if (old) {
        db.update("UPDATE station_settings SET station_latitude = ?, station_longitude = ? WHERE setting_id = 1", STATION_LAT, STATION_LNG);
        done.add("station pin on Riverside Street");
      }
    }
    return done;
  }
}
