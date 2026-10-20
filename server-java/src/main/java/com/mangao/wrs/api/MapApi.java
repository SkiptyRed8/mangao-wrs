package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.Orders;
import com.mangao.wrs.service.Settings;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Live Map (step 34; Admin Orders 7, Staff 9): the rider marker and the order pins of the orders on
 * the road. Staff can see and call; no order changes here.
 */
@RestController
@RequestMapping("/api/map")
public class MapApi {
  private final Db db;
  private final Auth auth;
  private final Orders orders;
  private final Settings settings;

  public MapApi(Db db, Auth auth, Orders orders, Settings settings) {
    this.db = db;
    this.auth = auth;
    this.orders = orders;
    this.settings = settings;
  }

  /** GET /api/map -> { station, riders: [...], orders: [...] } */
  @GetMapping
  public Map<String, Object> map(HttpServletRequest req) {
    auth.require(req, "Owner", "Staff");
    Orders.Station station = orders.stationPoint();
    List<Map<String, Object>> rows = db.query(
        "SELECT o.order_id, o.customer_name, o.quantity, o.order_type, o.status, o.rider_id, o.delivery_address_text,"
            + " o.delivery_latitude AS lat, o.delivery_longitude AS lng, o.contact_phone"
            + " FROM orders o WHERE o.status = 'Out for Delivery' ORDER BY o.out_at, o.order_id");
    Set<Long> riderIds = new LinkedHashSet<>();
    for (Map<String, Object> o : rows) if (o.get("rider_id") != null) riderIds.add(V.lng(o.get("rider_id")));
    List<Map<String, Object>> riders = riderIds.isEmpty() ? List.of() : db.query(
        "SELECT u.user_id, u.full_name, u.role, u.phone_number, l.latitude, l.longitude, l.updated_at, l.is_sharing"
            + " FROM users u LEFT JOIN rider_locations l ON l.rider_id = u.user_id WHERE u.user_id IN (?)",
        new ArrayList<>(riderIds));
    long t = Clock.now().toEpochMilli();
    List<Map<String, Object>> riderOut = new ArrayList<>();
    for (Map<String, Object> r : riders) {
      long uid = V.lng(r.get("user_id"));
      List<Long> mine = new ArrayList<>();
      for (Map<String, Object> o : rows) if (o.get("rider_id") != null && V.lng(o.get("rider_id")) == uid) mine.add(V.lng(o.get("order_id")));
      Instant up = V.instant(r.get("updated_at"));
      riderOut.add(M.of(
          "id", uid,
          "name", "Owner".equals(r.get("role")) ? "Owner" : r.get("full_name"),
          "phone", r.get("phone_number"),
          "lat", V.numOrNull(r.get("latitude")),
          "lng", V.numOrNull(r.get("longitude")),
          "updatedAt", up,
          "minutesAgo", up != null ? Math.max(0, Math.round((t - up.toEpochMilli()) / 60000.0)) : null,
          "orders", mine));
    }
    // One sidecar on the map (the station has one delivery rider for now): the rider whose place was
    // updated last. Orders of another rider still show as pins.
    if (riderOut.size() > 1) {
      Map<String, Object> best = null;
      for (Map<String, Object> r : riderOut) {
        if (r.get("lat") == null) continue;
        Instant u = (Instant) r.get("updatedAt");
        if (best == null || (u != null && (best.get("updatedAt") == null || u.isAfter((Instant) best.get("updatedAt"))))) best = r;
      }
      riderOut = best == null ? new ArrayList<>(riderOut.subList(0, 1)) : new ArrayList<>(List.of(best));
    }
    List<Map<String, Object>> orderOut = new ArrayList<>();
    int i = 0;
    for (Map<String, Object> o : rows) {
      orderOut.add(M.of(
          "n", ++i,
          "id", V.lng(o.get("order_id")),
          "name", V.truthy(o.get("customer_name")) ? o.get("customer_name") : "Guest",
          "phone", V.s(o.get("contact_phone")),
          "quantity", V.intOrNull(o.get("quantity")),
          "type", o.get("order_type"),
          "status", o.get("status"),
          "riderId", V.longOrNull(o.get("rider_id")),
          "address", V.s(o.get("delivery_address_text")),
          "lat", V.numOrNull(o.get("lat")),
          "lng", V.numOrNull(o.get("lng"))));
    }
    return M.of("station", M.of("lat", station.lat(), "lng", station.lng(), "address", settings.stationAddress()), "riders", riderOut, "orders", orderOut);
  }
}
