package com.mangao.wrs.service;

import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/** Current prices (newest row of each item) and station settings. */
@Component
public class Settings {
  public static final Map<String, String> ITEMS = Map.of("Refill Walk-in", "walkIn", "Refill Delivery", "delivery", "Package", "package");
  private final Db db;

  public Settings(Db db) {
    this.db = db;
  }

  public Map<String, Object> currentPrices() {
    List<Map<String, Object>> rows = db.query(
        "SELECT p.item_type, p.amount FROM prices p"
            + " JOIN (SELECT item_type, MAX(price_id) AS id FROM prices GROUP BY item_type) n ON n.id = p.price_id");
    Map<String, Object> out = M.of("walkIn", 0.0, "delivery", 0.0, "package", 0.0);
    for (Map<String, Object> r : rows) out.put(ITEMS.get(String.valueOf(r.get("item_type"))), V.num(r.get("amount")));
    return out;
  }

  public double price(String key) {
    return V.num(currentPrices().get(key));
  }

  public Map<String, Object> stationSettings() {
    Map<String, Object> s = db.one("SELECT * FROM station_settings WHERE setting_id = 1");
    List<Map<String, Object>> items = db.query("SELECT item_name, low_stock_level FROM inventory_items");
    long gallons = 0, seals = 0;
    for (Map<String, Object> i : items) {
      if ("New Gallon".equals(i.get("item_name"))) gallons = V.lng(i.get("low_stock_level"));
      if ("Seal".equals(i.get("item_name"))) seals = V.lng(i.get("low_stock_level"));
    }
    return M.of(
        "tankLimit", V.lng(s.get("tank_limit")),
        "sealsPerGallon", V.lng(s.get("seals_per_gallon")),
        "lowStock", M.of("gallons", gallons, "seals", seals),
        "station", M.of(
            "lat", V.numOrNull(s.get("station_latitude")),
            "lng", V.numOrNull(s.get("station_longitude")),
            "phone", V.s(s.get("station_phone")),
            "address", V.s(s.get("station_address"))));
  }

  @SuppressWarnings("unchecked")
  public String stationAddress() {
    return String.valueOf(((Map<String, Object>) stationSettings().get("station")).get("address"));
  }
}
