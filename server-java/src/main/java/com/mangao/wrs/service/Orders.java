package com.mangao.wrs.service;

import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * Shared order helpers: how an order is sent to the app, the status timeline,
 * distance from the station, and history / notification rows.
 */
@Component
public class Orders {
  public static final List<String> ACTIVE = List.of("New", "Processing", "Out for Delivery");

  private final Db db;
  private final Realtime realtime;
  private final Push push;

  public Orders(Db db, Realtime realtime, Push push) {
    this.db = db;
    this.realtime = realtime;
    this.push = push;
  }

  /** Kilometres between two points (straight line). */
  public static Double distanceKm(Object lat1, Object lng1, Object lat2, Object lng2) {
    if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) return null;
    double R = 6371;
    double la1 = Math.toRadians(V.num(lat1)), la2 = Math.toRadians(V.num(lat2));
    double dLat = Math.toRadians(V.num(lat2) - V.num(lat1));
    double dLng = Math.toRadians(V.num(lng2) - V.num(lng1));
    double a = Math.pow(Math.sin(dLat / 2), 2) + Math.cos(la1) * Math.cos(la2) * Math.pow(Math.sin(dLng / 2), 2);
    return Math.round(2 * R * Math.asin(Math.sqrt(a)) * 10) / 10.0;
  }

  /** "12 Sampaguita St., Blk 2 Lot 5, Commonwealth" (typed) or "Pinned: near ..." (pin only). */
  public static String addressText(Map<String, Object> a) {
    List<String> f = new ArrayList<>();
    for (String k : List.of("house", "street")) if (V.truthy(a.get(k))) f.add(V.str(a.get(k)));
    String first = String.join(" ", f);
    List<String> parts = new ArrayList<>();
    for (Object x : new Object[] {first, a.get("blockLot"), a.get("barangay")}) {
      if (x != null && !V.str(x).strip().isEmpty() && V.truthy(x)) parts.add(V.str(x));
    }
    if (V.truthy(a.get("pinned")) && !V.truthy(a.get("house"))) {
      return "Pinned: near " + (parts.isEmpty() ? "the map pin" : String.join(", ", parts));
    }
    return String.join(", ", parts);
  }

  public static String firstName(Object n) {
    String s = n == null ? "" : V.str(n);
    return s.split(" ", -1)[0];
  }

  /** Who did a step, as the timeline shows it: "Owner", "Ana (Staff)", "Juan", "Maria". */
  private static String actor(Map<String, Object> row) {
    Object role = row.get("actor_role");
    if (role == null) return V.truthy(row.get("order_customer")) ? firstName(row.get("order_customer")) : "Guest";
    if ("Owner".equals(role)) return "Owner";
    if ("Staff".equals(role)) return firstName(row.get("actor_name")) + " (Staff)";
    return firstName(row.get("actor_name"));
  }

  public List<Map<String, Object>> timeline(long orderId) {
    List<Map<String, Object>> rows = db.query(
        "SELECT h.status, h.note, h.changed_at, u.full_name AS actor_name, u.role AS actor_role, o.customer_name AS order_customer"
            + " FROM order_status_history h JOIN orders o ON o.order_id = h.order_id"
            + " LEFT JOIN users u ON u.user_id = h.changed_by"
            + " WHERE h.order_id = ? ORDER BY h.changed_at, h.history_id",
        orderId);
    List<Map<String, Object>> out = new ArrayList<>();
    for (Map<String, Object> r : rows) out.add(M.of("status", r.get("status"), "note", V.s(r.get("note")), "at", r.get("changed_at"), "by", actor(r)));
    return out;
  }

  /** Adds a timeline step. */
  public void addHistory(long orderId, String status, Long userId, String note, Instant at) {
    db.update("INSERT INTO order_status_history (order_id, status, changed_by, note, changed_at) VALUES (?, ?, ?, ?, ?)",
        orderId, status, userId != null && userId > 0 ? userId : null, note, at == null ? Clock.now() : at);
    realtime.orderChanged(orderId);
  }

  public void addHistory(long orderId, String status, Long userId, String note) {
    addHistory(orderId, status, userId, note, Clock.now());
  }

  /** In-app notification for one account (or a guest phone). Shown by the bell and pushed in step 36. */
  public void notify(Long userId, String guestToken, Long orderId, String type, String title, String message) {
    if (userId == null && guestToken == null) return;
    db.update("INSERT INTO notifications (user_id, guest_token, order_id, notification_type, title, message) VALUES (?, ?, ?, ?, ?, ?)",
        userId, guestToken, orderId, type, title, message);
    realtime.notification(userId, guestToken, title, message, type, orderId);
    push.send(userId, guestToken, title, message, type, orderId);
  }

  /** Notifies the owner (all Owner accounts), unless the owner turned that alert off in Preferences. */
  public void notifyOwner(String type, String title, String message, Long orderId) {
    List<Map<String, Object>> owners = db.query(
        "SELECT u.user_id FROM users u LEFT JOIN notification_preferences p ON p.user_id = u.user_id AND p.notification_type = ?"
            + " WHERE u.role = 'Owner' AND u.is_active = 1 AND COALESCE(p.is_enabled, 1) = 1",
        type);
    for (Map<String, Object> o : owners) notify(V.lng(o.get("user_id")), null, orderId, type, title, message);
  }

  /** Notifies the customer of an order (account or guest phone). */
  public void notifyCustomer(Map<String, Object> order, String type, String title, String message) {
    Long customer = V.longOrNull(order.get("customer_id"));
    notify(customer, customer != null ? null : V.sn(order.get("guest_token")), V.lng(order.get("order_id")), type, title, message);
  }

  public static String sourceText(Map<String, Object> o) {
    return "Logged".equals(o.get("order_source")) ? (V.truthy(o.get("logged_channel")) ? V.str(o.get("logged_channel")) : "Logged") : V.sn(o.get("order_source"));
  }

  private static final Map<String, String> PAYMENT_TEXT = Map.of(
      "COD", "Cash on delivery", "Pay on delivery", "Pay on delivery", "Paid at station", "Paid at station", "Walk-in", "Walk-in");

  public record Station(Double lat, Double lng, String phone) {}

  /** The order as the app sees it. station gives the distance. */
  public static Map<String, Object> shapeOrder(Map<String, Object> o, Station station) {
    Double km = station != null ? distanceKm(station.lat(), station.lng(), o.get("delivery_latitude"), o.get("delivery_longitude")) : null;
    Instant estFrom = V.instant(o.get("est_delivery_from"));
    Instant estTo = V.instant(o.get("est_delivery_to"));
    Instant delivered = V.instant(o.get("delivered_at"));
    String pay = V.sn(o.get("payment_method"));
    return M.of(
        "id", V.lng(o.get("order_id")),
        "source", o.get("order_source"),
        "channel", o.get("logged_channel"),
        "sourceText", sourceText(o),
        "type", o.get("order_type"),
        "quantity", V.intOrNull(o.get("quantity")),
        "unitPrice", V.num(o.get("unit_price")),
        "total", V.num(o.get("total_amount")),
        "customerId", V.longOrNull(o.get("customer_id")),
        "name", V.s(o.get("customer_name")),
        "phone", V.s(o.get("contact_phone")),
        "address", V.s(o.get("delivery_address_text")),
        "landmark", V.s(o.get("delivery_landmark")),
        "lat", V.numOrNull(o.get("delivery_latitude")),
        "lng", V.numOrNull(o.get("delivery_longitude")),
        "km", km,
        "notes", V.s(o.get("notes")),
        "status", o.get("status"),
        "payment", pay,
        "paymentText", pay == null ? null : PAYMENT_TEXT.getOrDefault(pay, pay),
        "paymentStatus", o.get("payment_status"),
        "riderId", V.longOrNull(o.get("rider_id")),
        "riderName", V.truthy(o.get("rider_name")) ? o.get("rider_name") : null,
        "riderRole", V.truthy(o.get("rider_role")) ? o.get("rider_role") : null,
        "batchId", V.longOrNull(o.get("batch_id")),
        "batchSize", V.truthy(o.get("batch_size")) ? V.lng(o.get("batch_size")) : null,
        "acceptedAt", o.get("accepted_at"),
        "estFrom", estFrom,
        "estTo", estTo,
        "estText", Clock.deliveryText(estFrom, estTo),
        "outAt", o.get("out_at"),
        "deliveredAt", delivered,
        "deliveredClock", delivered != null ? Clock.clock(delivered) : "",
        "createdAt", o.get("created_at"),
        "createdText", V.instant(o.get("created_at")) != null ? Clock.dateClock(V.instant(o.get("created_at"))) : "",
        "deliveryDate", o.get("delivery_date") == null ? null : String.valueOf(o.get("delivery_date")).substring(0, 10),
        "reason", V.s(o.get("reason")));
  }

  /** SELECT used by every order list: the order, its rider, batch size and last decline / not-delivered note. */
  public static final String ORDER_SELECT =
      " SELECT o.*, r.full_name AS rider_name, r.role AS rider_role,"
          + " (SELECT COUNT(*) FROM orders b WHERE o.batch_id IS NOT NULL AND b.batch_id = o.batch_id) AS batch_size,"
          + " (SELECT h.note FROM order_status_history h WHERE h.order_id = o.order_id"
          + " AND h.status IN ('Declined','Not delivered','Cancelled') ORDER BY h.history_id DESC LIMIT 1) AS reason"
          + " FROM orders o LEFT JOIN users r ON r.user_id = o.rider_id";

  public Station stationPoint() {
    Map<String, Object> s = db.one("SELECT station_latitude AS lat, station_longitude AS lng, station_phone AS phone FROM station_settings WHERE setting_id = 1");
    return new Station(V.numOrNull(s.get("lat")), V.numOrNull(s.get("lng")), V.s(s.get("phone")));
  }

  /** One order with ORDER_SELECT, or null. */
  public Map<String, Object> orderRow(long id) {
    return db.one(ORDER_SELECT + " WHERE o.order_id = ?", id);
  }
}
