package com.mangao.wrs.service;

import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.V;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;

/**
 * The order status follows the rider while Out for Delivery: within 300 m of the address the order
 * becomes "Arriving" (the customer gets "Your water is arriving" with the amount to prepare), within
 * 50 m "Arrived" (the customer gets "Your rider has arrived"); the rider then marks it Delivered.
 * Each step happens once per trip and is saved in orders.arrival and the order's timeline.
 *
 * The distance counts to the pin and to the end of the street route: a pin inside a compound or away
 * from the road is reached where the road ends (the sidecar cannot go closer). Checked every time the
 * rider's place changes (phone GPS or the demo ride).
 */
@Component
public class Arrivals {
  public static final double ARRIVING_M = 300;
  public static final double ARRIVED_M = 50;
  public static final String ARRIVING = "Rider Arriving";
  public static final String ARRIVED = "Rider Arrived";

  private final Db db;
  private final Orders orders;
  private final Routes routes;
  /** Where the street route to each order's pin ends (order id -> [lat, lng]). */
  private final Map<Long, double[]> roadEnd = new ConcurrentHashMap<>();

  public Arrivals(Db db, Orders orders, Routes routes) {
    this.db = db;
    this.orders = orders;
    this.routes = routes;
  }

  /** "Please prepare ₱150.00." or "It is already paid." */
  public static String payText(Map<String, Object> o) {
    if ("Paid".equals(o.get("payment_status"))) return "It is already paid.";
    return "Please prepare ₱" + String.format(Locale.ROOT, "%,.2f", V.num(o.get("total_amount"))) + ".";
  }

  private boolean sent(long orderId, String type) {
    return db.one("SELECT notification_id FROM notifications WHERE order_id = ? AND notification_type = ? LIMIT 1", orderId, type) != null;
  }

  /** The end of the street route from the station to the pin (the pin itself if there is no route). */
  private double[] endOfRoad(long orderId, double lat, double lng) {
    double[] hit = roadEnd.get(orderId);
    if (hit != null) return hit;
    Orders.Station st = orders.stationPoint();
    double[] end = new double[] {lat, lng};
    if (st.lat() != null && st.lng() != null) {
      List<double[]> pts = routes.route(List.of(new double[] {st.lat(), st.lng()}, new double[] {lat, lng})).points();
      if (!pts.isEmpty()) end = pts.get(pts.size() - 1);
    }
    if (roadEnd.size() > 500) roadEnd.clear();
    roadEnd.put(orderId, end);
    return end;
  }

  /** Meters from the rider to the order's address (the nearer of the pin and the end of the road). */
  private double distance(Map<String, Object> o, double lat, double lng) {
    double hl = V.num(o.get("delivery_latitude")), hg = V.num(o.get("delivery_longitude"));
    double m = Routes.meters(lat, lng, hl, hg);
    if (m > ARRIVED_M && m < 1500) {
      double[] end = endOfRoad(V.lng(o.get("order_id")), hl, hg);
      m = Math.min(m, Routes.meters(lat, lng, end[0], end[1]));
    }
    return m;
  }

  public void check(long riderId, double lat, double lng) {
    List<Map<String, Object>> out = db.query(
        "SELECT * FROM orders WHERE rider_id = ? AND status = 'Out for Delivery' AND delivery_latitude IS NOT NULL", riderId);
    for (Map<String, Object> o : out) {
      double m = distance(o, lat, lng);
      if (m <= ARRIVED_M) arrived(o, riderId);
      else if (m <= ARRIVING_M) arriving(o, riderId);
    }
  }

  /** The demo ride stopped at this order's address. */
  public void reached(long orderId, long riderId) {
    Map<String, Object> o = db.one("SELECT * FROM orders WHERE order_id = ? AND status = 'Out for Delivery'", orderId);
    if (o != null) arrived(o, riderId);
  }

  private void arriving(Map<String, Object> o, long riderId) {
    if (o.get("arrival") != null) return; // already Arriving or Arrived
    long oid = V.lng(o.get("order_id"));
    if (db.update("UPDATE orders SET arrival = 'Arriving' WHERE order_id = ? AND status = 'Out for Delivery' AND arrival IS NULL", oid) == 0) return;
    orders.addHistory(oid, "Arriving", riderId, "The rider is near the address");
    if (!sent(oid, ARRIVING) && !sent(oid, ARRIVED)) {
      orders.notifyCustomer(o, ARRIVING, "Your water is arriving", "Your rider is almost there. " + payText(o));
    }
  }

  private void arrived(Map<String, Object> o, long riderId) {
    if ("Arrived".equals(o.get("arrival"))) return;
    long oid = V.lng(o.get("order_id"));
    if (db.update("UPDATE orders SET arrival = 'Arrived' WHERE order_id = ? AND status = 'Out for Delivery' AND (arrival IS NULL OR arrival <> 'Arrived')", oid) == 0) return;
    orders.addHistory(oid, "Arrived", riderId, "The rider is at the address");
    if (!sent(oid, ARRIVED)) orders.notifyCustomer(o, ARRIVED, "Your rider has arrived", "Your water is here. " + payText(o));
  }
}
