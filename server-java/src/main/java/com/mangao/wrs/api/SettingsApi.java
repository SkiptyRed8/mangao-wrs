package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.DemoRide;
import com.mangao.wrs.service.Settings;
import jakarta.servlet.http.HttpServletRequest;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Prices & Settings (FR-09, Admin More 3): prices (walk-in, delivery, package), tank limit,
 * low-stock levels and the station location. New prices apply to new orders only:
 * each order keeps a copy of the price it was made with.
 */
@RestController
@RequestMapping("/api/settings")
public class SettingsApi {
  private static final Map<String, String> ITEMS = new LinkedHashMap<>();

  static {
    ITEMS.put("Refill Walk-in", "walkIn");
    ITEMS.put("Refill Delivery", "delivery");
    ITEMS.put("Package", "package");
  }

  private final Db db;
  private final Auth auth;
  private final Settings settings;
  private final DemoRide demoRide;

  public SettingsApi(Db db, Auth auth, Settings settings, DemoRide demoRide) {
    this.demoRide = demoRide;
    this.db = db;
    this.auth = auth;
    this.settings = settings;
  }

  /** GET /api/settings/prices -> { prices } (anyone: customers and guests see the price list) */
  @GetMapping("/prices")
  @SuppressWarnings("unchecked")
  public Map<String, Object> prices() {
    Map<String, Object> station = (Map<String, Object>) settings.stationSettings().get("station");
    return M.of("prices", settings.currentPrices(), "stationPhone", station.get("phone"));
  }

  /** GET /api/settings -> { prices, tankLimit, lowStock, station } */
  @GetMapping
  public Map<String, Object> all(HttpServletRequest req) {
    auth.require(req, "Owner");
    Map<String, Object> out = M.of("prices", settings.currentPrices());
    out.putAll(settings.stationSettings());
    out.put("demoRide", demoRide.isOn());
    out.put("demoSeconds", demoRide.legSeconds());
    return out;
  }

  /**
   * PUT /api/settings/demo-ride { on?, seconds? } -> { demoRide, demoSeconds, message }  (testing and presentations)
   * seconds: how long the trip to each stop takes, 15 to 300.
   */
  @PutMapping("/demo-ride")
  public Map<String, Object> demoRide(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    auth.require(req, "Owner");
    Object v = raw == null ? null : raw.get("on");
    Object s = raw == null ? null : raw.get("seconds");
    if (v == null && s == null) throw HttpError.bad("CHOICE_MISSING", "Choose on or off", "Turn the demo ride on or off.");
    if (v != null && !(v instanceof Boolean)) throw HttpError.bad("CHOICE_MISSING", "Choose on or off", "Turn the demo ride on or off.");
    String message = null;
    if (s != null) {
      double n = V.num(s);
      if (Double.isNaN(n) || n < DemoRide.MIN_LEG_SECONDS || n > DemoRide.MAX_LEG_SECONDS) {
        throw HttpError.bad("TIME_INVALID", "Trip time not valid", "Choose from 15 seconds to 5 minutes.", "field", "seconds");
      }
      demoRide.setLegSeconds((int) Math.round(n));
      int t = demoRide.legSeconds();
      message = "Demo trip to each stop: " + (t < 60 ? t + " seconds" : (t % 60 == 0 ? (t / 60) + (t == 60 ? " minute" : " minutes") : t / 60 + " min " + t % 60 + " s")) + ".";
    }
    if (v != null) {
      demoRide.set((Boolean) v);
      message = (Boolean) v
          ? "Demo ride on: the sidecar drives from the station by itself."
          : "Demo ride off: the rider's phone moves the sidecar.";
    }
    return M.of("demoRide", demoRide.isOn(), "demoSeconds", demoRide.legSeconds(), "message", message);
  }

  private static double money(Object v, String label, String key) {
    double n = Math.round(V.num(v) * 100) / 100.0;
    if (v == null || Double.isNaN(n) || Double.isInfinite(n) || n <= 0 || n > 10000) {
      throw HttpError.bad("PRICE_INVALID", "Price not valid", "Type a price above P0 for " + label + ".", "field", key);
    }
    return n;
  }

  /** PUT /api/settings/prices { walkIn, delivery, package } -> { prices } */
  @PutMapping("/prices")
  public Map<String, Object> setPrices(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = auth.require(req, "Owner");
    Body b = new Body(raw);
    Map<String, Double> next = new LinkedHashMap<>();
    next.put("walkIn", money(b.get("walkIn"), "Refill (walk-in)", "walkIn"));
    next.put("delivery", money(b.get("delivery"), "Refill (delivery)", "delivery"));
    next.put("package", money(b.get("package"), "Package", "package"));
    db.txRun(() -> {
      Map<String, Object> now = settings.currentPrices();
      for (Map.Entry<String, String> e : ITEMS.entrySet()) {
        if (V.num(now.get(e.getValue())) != next.get(e.getValue())) {
          db.update("INSERT INTO prices (item_type, amount, set_by) VALUES (?, ?, ?)", e.getKey(), next.get(e.getValue()), Auth.id(me));
        }
      }
    });
    return M.of("prices", settings.currentPrices(), "message", "Applies to new orders only.");
  }

  /** PUT /api/settings/tank-limit { tankLimit } -> settings. The running count uses the new number. */
  @PutMapping("/tank-limit")
  public Map<String, Object> tankLimit(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    auth.require(req, "Owner");
    Integer limit = new Body(raw).integer("tankLimit", 1, 1000);
    if (limit == null) throw HttpError.bad("LIMIT_INVALID", "Tank limit not valid", "Type a whole number from 1 to 1000.", "field", "tankLimit");
    db.txRun(() -> {
      db.update("UPDATE station_settings SET tank_limit = ? WHERE setting_id = 1", limit);
      db.update("UPDATE tank_cycles SET tank_limit = ? WHERE ended_at IS NULL", limit);
    });
    return M.with(settings.stationSettings(), "message", "Alert uses the new number.");
  }

  /** PUT /api/settings/low-stock { gallons, seals } -> settings */
  @PutMapping("/low-stock")
  public Map<String, Object> lowStock(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    auth.require(req, "Owner");
    Body b = new Body(raw);
    Integer gallons = b.integer("gallons", 0, 100000);
    Integer seals = b.integer("seals", 0, 100000);
    if (gallons == null) throw HttpError.bad("LEVEL_INVALID", "Gallon level not valid", "Type a whole number, 0 or more.", "field", "gallons");
    if (seals == null) throw HttpError.bad("LEVEL_INVALID", "Seal level not valid", "Type a whole number, 0 or more.", "field", "seals");
    db.update("UPDATE inventory_items SET low_stock_level = ? WHERE item_name = 'New Gallon'", gallons);
    db.update("UPDATE inventory_items SET low_stock_level = ? WHERE item_name = 'Seal'", seals);
    return M.with(settings.stationSettings(), "message", "Warnings use the new levels.");
  }

  /** PUT /api/settings/location { lat, lng, address } -> settings (Quezon City area) */
  @PutMapping("/location")
  public Map<String, Object> location(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    auth.require(req, "Owner");
    Body b = new Body(raw);
    double lat = b.get("lat") == null ? Double.NaN : V.num(b.get("lat"));
    double lng = b.get("lng") == null ? Double.NaN : V.num(b.get("lng"));
    if (Double.isNaN(lat) || Double.isNaN(lng) || Double.isInfinite(lat) || Double.isInfinite(lng) || lat < 4 || lat > 22 || lng < 116 || lng > 127) {
      throw HttpError.bad("LOCATION_INVALID", "Location not valid", "Move the pin to the station and try again.");
    }
    String address = b.text("address", 255);
    if (b.has("address") && address.isEmpty()) {
      throw HttpError.bad("ADDRESS_MISSING", "Address missing", "Type the station address.", "field", "address");
    }
    db.update("UPDATE station_settings SET station_latitude = ?, station_longitude = ? WHERE setting_id = 1",
        String.format(java.util.Locale.ROOT, "%.7f", lat), String.format(java.util.Locale.ROOT, "%.7f", lng));
    if (!address.isEmpty()) db.update("UPDATE station_settings SET station_address = ? WHERE setting_id = 1", address);
    return M.with(settings.stationSettings(), "message", "Distances use the new location.");
  }
}
