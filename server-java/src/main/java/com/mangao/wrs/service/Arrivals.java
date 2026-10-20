package com.mangao.wrs.service;

import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.V;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * Tells the customer when the rider is near and when the rider is at the door, each only once per
 * order: within 300 m "Your water is arriving" (with the amount to prepare), within 50 m "Your rider
 * has arrived". Checked every time the rider's place changes (phone GPS or the demo ride).
 */
@Component
public class Arrivals {
  public static final double ARRIVING_M = 300;
  public static final double ARRIVED_M = 50;
  public static final String ARRIVING = "Rider Arriving";
  public static final String ARRIVED = "Rider Arrived";

  private final Db db;
  private final Orders orders;

  public Arrivals(Db db, Orders orders) {
    this.db = db;
    this.orders = orders;
  }

  /** "Please prepare ₱150.00." or "It is already paid." */
  public static String payText(Map<String, Object> o) {
    if ("Paid".equals(o.get("payment_status"))) return "It is already paid.";
    return "Please prepare ₱" + String.format(Locale.ROOT, "%,.2f", V.num(o.get("total_amount"))) + ".";
  }

  private boolean sent(long orderId, String type) {
    return db.one("SELECT notification_id FROM notifications WHERE order_id = ? AND notification_type = ? LIMIT 1", orderId, type) != null;
  }

  public void check(long riderId, double lat, double lng) {
    List<Map<String, Object>> out = db.query(
        "SELECT * FROM orders WHERE rider_id = ? AND status = 'Out for Delivery' AND delivery_latitude IS NOT NULL", riderId);
    for (Map<String, Object> o : out) {
      long oid = V.lng(o.get("order_id"));
      double m = Routes.meters(lat, lng, V.num(o.get("delivery_latitude")), V.num(o.get("delivery_longitude")));
      if (m <= ARRIVED_M) {
        if (!sent(oid, ARRIVED)) orders.notifyCustomer(o, ARRIVED, "Your rider has arrived", "Your water is here. " + payText(o));
      } else if (m <= ARRIVING_M) {
        if (!sent(oid, ARRIVING) && !sent(oid, ARRIVED)) {
          orders.notifyCustomer(o, ARRIVING, "Your water is arriving", "Your rider is almost there. " + payText(o));
        }
      }
    }
  }
}
