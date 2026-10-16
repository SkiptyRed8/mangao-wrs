package com.mangao.wrs.service;

import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import java.time.Instant;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * Rules shared by the work screens (Chapter 4, Oct 13 ordering process):
 *  - Tank counter and seals (3 per gallon) count when a delivery order goes Out for Delivery (first
 *    time only) or when a walk-in is saved. A package also uses 1 new gallon per gallon ordered.
 *    Not delivered stays counted; a re-delivery is not counted again.
 *  - At the tank limit (60) the owner gets "Tank at 60"; stock at or below its low-stock level
 *    gives "Low stock". Orders are never blocked.
 */
@Component
public class Process {
  private final Db db;
  private final Orders orders;
  private final Realtime realtime;

  public Process(Db db, Orders orders, Realtime realtime) {
    this.db = db;
    this.orders = orders;
    this.realtime = realtime;
  }

  public Map<String, Object> openCycle() {
    Map<String, Object> c = db.one("SELECT * FROM tank_cycles WHERE ended_at IS NULL ORDER BY cycle_id DESC LIMIT 1 FOR UPDATE");
    if (c != null) return c;
    Map<String, Object> s = db.one("SELECT tank_limit FROM station_settings WHERE setting_id = 1");
    long id = db.insert("INSERT INTO tank_cycles (gallons_count, tank_limit) VALUES (0, ?)", s.get("tank_limit"));
    return db.one("SELECT * FROM tank_cycles WHERE cycle_id = ?", id);
  }

  /** Changes one stock item and writes the movement; sends the low-stock alert when it drops to the level. */
  public long moveStock(String itemName, long change, String type, String note, Long orderId, Long userId, Instant at) {
    Map<String, Object> item = db.one("SELECT * FROM inventory_items WHERE item_name = ? FOR UPDATE", itemName);
    long before = V.lng(item.get("quantity_on_hand"));
    long after = before + change;
    long level = V.lng(item.get("low_stock_level"));
    db.update("UPDATE inventory_items SET quantity_on_hand = ? WHERE item_id = ?", after, item.get("item_id"));
    db.update("INSERT INTO stock_movements (item_id, order_id, recorded_by, movement_type, quantity_change, note, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        item.get("item_id"), orderId, userId, type, change, note, at == null ? Clock.now() : at);
    if (change < 0 && before > level && after <= level) {
      String label = "Seal".equals(itemName) ? "Seals" : "Gallons";
      orders.notifyOwner("Low Stock", "Low stock", label + ": " + after + " left", null);
    }
    return after;
  }

  /**
   * Counts an order once: tank counter + gallons, seals - 3 per gallon, new gallons - 1 per package gallon.
   * Returns the new tank count (or null when the order was already counted).
   */
  public Long countOrder(Map<String, Object> order, Long userId, String why, Instant at) {
    long orderId = V.lng(order.get("order_id"));
    Map<String, Object> fresh = db.one("SELECT tank_counted_at FROM orders WHERE order_id = ? FOR UPDATE", orderId);
    if (fresh.get("tank_counted_at") != null) return null;
    Map<String, Object> cycle = openCycle();
    long qty = V.lng(order.get("quantity"));
    long count = V.lng(cycle.get("gallons_count")) + qty;
    db.update("UPDATE tank_cycles SET gallons_count = ? WHERE cycle_id = ?", count, cycle.get("cycle_id"));
    long limit = V.lng(cycle.get("tank_limit"));
    if (cycle.get("alerted_at") == null && count >= limit) {
      db.update("UPDATE tank_cycles SET alerted_at = ? WHERE cycle_id = ?", at, cycle.get("cycle_id"));
      orders.notifyOwner("Tank", "Tank at " + limit, "Refill the water tank", null);
    }
    db.update("UPDATE orders SET tank_counted_at = ?, tank_cycle_id = ? WHERE order_id = ?", at, cycle.get("cycle_id"), orderId);

    Map<String, Object> s = db.one("SELECT seals_per_gallon FROM station_settings WHERE setting_id = 1");
    long seals = V.lng(s.get("seals_per_gallon")) * qty;
    moveStock("Seal", -seals, "Used", why, orderId, null, at);
    if ("Package".equals(order.get("order_type"))) {
      moveStock("New Gallon", -qty, "Used", "Package sold", orderId, null, at);
    }
    return count;
  }

  /** The owner account that rides for logged orders (the first active Owner). */
  public long ownerId() {
    return V.lng(db.one("SELECT user_id FROM users WHERE role = 'Owner' AND is_active = 1 ORDER BY user_id LIMIT 1").get("user_id"));
  }

  /** Closes a delivery batch when none of its orders is still out (location sharing stops). */
  public boolean finishBatchIfDone(Object batchIdObj, Instant at) {
    if (batchIdObj == null) return false;
    long batchId = V.lng(batchIdObj);
    Map<String, Object> r = db.one("SELECT COUNT(*) AS n FROM orders WHERE batch_id = ? AND status = 'Out for Delivery'", batchId);
    if (V.lng(r.get("n")) > 0) return false;
    db.update("UPDATE delivery_batches SET finished_at = ? WHERE batch_id = ? AND finished_at IS NULL", at, batchId);
    // Location sharing stops when the rider has no more orders on the road (Rider 5).
    Map<String, Object> b = db.one("SELECT rider_id FROM delivery_batches WHERE batch_id = ?", batchId);
    long rider = V.lng(b.get("rider_id"));
    Map<String, Object> left = db.one("SELECT COUNT(*) AS n FROM orders WHERE rider_id = ? AND status = 'Out for Delivery'", rider);
    if (V.lng(left.get("n")) == 0) {
      db.update("UPDATE rider_locations SET is_sharing = 0 WHERE rider_id = ?", rider);
      realtime.locationLater(rider, M.of("sharing", false));
    }
    return true;
  }

  public static String peso(Object n) {
    return "P" + String.format(java.util.Locale.ROOT, "%.2f", V.num(n));
  }

  public record Result(String message, boolean batchDone) {}

  /** Rider (or owner) records Delivered. paid: ignored when it was already paid at the station. */
  public Result recordDelivered(Map<String, Object> order, long userId, boolean paid) {
    Instant t = Clock.now();
    long id = V.lng(order.get("order_id"));
    boolean already = "Paid".equals(order.get("payment_status"));
    String status = already ? "Paid" : paid ? "Paid" : "Unpaid";
    db.update("UPDATE orders SET status = 'Delivered', delivered_at = ?, payment_status = ?, paid_at = IF(? = 'Paid', COALESCE(paid_at, ?), NULL) WHERE order_id = ?",
        t, status, status, t, id);
    String label = already
        ? ("Paid at station".equals(order.get("payment_method")) ? "Delivered (Paid at station)" : "Delivered (Paid)")
        : "Delivered (" + status + ")";
    orders.addHistory(id, label, userId, null, t);
    orders.notifyCustomer(order, "Delivered", "Delivered",
        "Unpaid".equals(status) ? "Thank you! Amount owed: " + peso(order.get("total_amount")) + "." : "Thank you! Enjoy your fresh water.");
    boolean batchDone = finishBatchIfDone(order.get("batch_id"), t);
    String message = already ? "Delivered." : "Paid".equals(status) ? "Delivered. Paid." : "Delivered; customer owes " + peso(order.get("total_amount"));
    if (batchDone) message += " Location sharing off.";
    return new Result(message, batchDone);
  }

  /** Rider (or owner) records Not delivered with an optional note. */
  public Result recordNotDelivered(Map<String, Object> order, long userId, String note) {
    Instant t = Clock.now();
    long id = V.lng(order.get("order_id"));
    db.update("UPDATE orders SET status = 'Not Delivered' WHERE order_id = ?", id);
    boolean hasNote = note != null && !note.isEmpty();
    orders.addHistory(id, "Not delivered", userId, hasNote ? note : null, t);
    String who = V.truthy(order.get("customer_name")) ? V.str(order.get("customer_name")) : "Guest";
    orders.notifyOwner("Not Delivered", "Not delivered", who + (hasNote ? ": " + note : "") + ". Re-deliver or cancel.", id);
    orders.notifyCustomer(order, "Not Delivered", "Not delivered", (hasNote ? note + ". " : "") + "The station will contact you.");
    boolean batchDone = finishBatchIfDone(order.get("batch_id"), t);
    return new Result(batchDone ? "Owner and customer notified. Location sharing off." : "Owner and customer notified", batchDone);
  }
}
