package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.Addresses;
import com.mangao.wrs.service.Orders;
import com.mangao.wrs.service.Settings;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Customer orders (FR-15; Customer 2-5): place an order (refill or package, cash on delivery),
 * see the active order and its status steps, cancel before it is accepted.
 * Works for customer accounts and for guests (X-Guest-Token, Guest Mode in step 33).
 */
@RestController
@RequestMapping("/api/orders")
public class OrdersApi {
  private static final int MAX_GALLONS = 50;
  private final Db db;
  private final Auth auth;
  private final Orders orders;
  private final Settings settings;

  public OrdersApi(Db db, Auth auth, Orders orders, Settings settings) {
    this.db = db;
    this.auth = auth;
    this.orders = orders;
    this.settings = settings;
  }

  /** Who is ordering: a customer account or a guest phone. Staff, riders and the owner use Log Delivery Order. */
  private record W(String sql, Object param, Auth.Who who) {}

  private W who(HttpServletRequest req) {
    Auth.Who w = auth.optional(req);
    if (w.user() != null) {
      if (!"Customer".equals(Auth.role(w.user()))) {
        throw HttpError.forbidden("CUSTOMERS_ONLY", "Customers only", "Use Log Delivery Order for call, text and Messenger orders.");
      }
      return new W("o.customer_id = ?", Auth.id(w.user()), w);
    }
    if (w.guestToken() != null) return new W("o.customer_id IS NULL AND o.guest_token = ?", w.guestToken(), w);
    throw HttpError.unauthorized("LOGIN_REQUIRED", "Please log in", "Log in or continue as guest to order.");
  }

  /** Unpaid balance: delivered orders recorded as Unpaid (shown on the Order Form, never blocks ordering). */
  private double unpaid(W w) {
    Map<String, Object> r = db.one("SELECT COALESCE(SUM(o.total_amount), 0) AS owed FROM orders o WHERE " + w.sql() + " AND o.payment_status = 'Unpaid'", w.param());
    return V.num(r.get("owed"));
  }

  private List<Map<String, Object>> shape(List<Map<String, Object>> rows, Orders.Station station) {
    List<Map<String, Object>> out = new ArrayList<>();
    for (Map<String, Object> o : rows) out.add(Orders.shapeOrder(o, station));
    return out;
  }

  /** GET /api/orders/home -> { active: [orders], prices, unpaid, stationPhone }  (Customer Home) */
  @GetMapping("/home")
  public Map<String, Object> home(HttpServletRequest req) {
    W w = who(req);
    Orders.Station station = orders.stationPoint();
    List<Map<String, Object>> rows = db.query(Orders.ORDER_SELECT + " WHERE " + w.sql() + " AND o.status IN (?) ORDER BY o.created_at DESC, o.order_id DESC",
        w.param(), Orders.ACTIVE);
    return M.of("active", shape(rows, station), "prices", settings.currentPrices(), "unpaid", unpaid(w), "stationPhone", station.phone());
  }

  /** GET /api/orders -> { orders } (newest first; My Orders in step 32) */
  @GetMapping
  public Map<String, Object> list(HttpServletRequest req) {
    W w = who(req);
    Orders.Station station = orders.stationPoint();
    List<Map<String, Object>> rows = db.query(Orders.ORDER_SELECT + " WHERE " + w.sql() + " ORDER BY o.created_at DESC, o.order_id DESC LIMIT 100", w.param());
    return M.of("orders", shape(rows, station), "unpaid", unpaid(w));
  }

  private Map<String, Object> myOrder(HttpServletRequest req, String id, W w) {
    Map<String, Object> o = db.one(Orders.ORDER_SELECT + " WHERE o.order_id = ? AND " + w.sql(), StaffApi.idOf(id), w.param());
    if (o == null) throw HttpError.notFound("ORDER_NOT_FOUND", "Order not found", "It may belong to another account.");
    return o;
  }

  /** GET /api/orders/:id -> { order, timeline, stationPhone, rider, station } */
  @GetMapping("/{id}")
  public Map<String, Object> get(HttpServletRequest req, @PathVariable String id) {
    W w = who(req);
    Map<String, Object> o = myOrder(req, id, w);
    Orders.Station station = orders.stationPoint();
    // Out for Delivery: the rider's last location for the live map (Customer 5, Customer 11).
    Map<String, Object> rider = null;
    long otherStops = 0;
    if ("Out for Delivery".equals(o.get("status")) && o.get("rider_id") != null) {
      // Other orders the same rider still has on the road (the sidecar may go to them first).
      otherStops = V.lng(db.one("SELECT COUNT(*) AS n FROM orders WHERE rider_id = ? AND status = 'Out for Delivery' AND order_id <> ?",
          o.get("rider_id"), o.get("order_id")).get("n"));
      Map<String, Object> l = db.one("SELECT latitude, longitude, updated_at, is_sharing FROM rider_locations WHERE rider_id = ?", o.get("rider_id"));
      if (l != null && V.truthy(l.get("is_sharing"))) {
        rider = M.of("id", V.lng(o.get("rider_id")), "lat", V.num(l.get("latitude")), "lng", V.num(l.get("longitude")), "updatedAt", l.get("updated_at"));
      }
    }
    return M.of("order", Orders.shapeOrder(o, station), "timeline", orders.timeline(V.lng(o.get("order_id"))), "stationPhone", station.phone(),
        "rider", rider, "otherStops", otherStops, "station", M.of("lat", station.lat(), "lng", station.lng()));
  }

  /** Customers can choose a delivery day up to this many days ahead. */
  public static final int MAX_DAYS_AHEAD = 7;

  /** "2026-10-22" -> that day; empty or today -> null (as soon as possible). */
  static String deliveryDate(Object raw) {
    if (!V.truthy(raw)) return null;
    String d = String.valueOf(raw).trim();
    String today = Clock.ymd(Clock.now());
    String last = Clock.ymd(Clock.now().plusSeconds(MAX_DAYS_AHEAD * 86400L));
    HttpError bad = HttpError.bad("DATE_INVALID", "Delivery date not valid", "Choose today or a day up to " + MAX_DAYS_AHEAD + " days ahead.", "field", "deliveryDate");
    if (!d.matches("^\\d{4}-\\d{2}-\\d{2}$")) throw bad;
    try {
      java.time.LocalDate.parse(d);
    } catch (Exception e) {
      throw bad;
    }
    if (d.compareTo(today) < 0 || d.compareTo(last) > 0) throw bad;
    return d.equals(today) ? null : d;
  }

  /** POST /api/orders { type: Refill|Package, quantity, address: {...} | addressId | fromOrderId, phone, notes, name (guests), deliveryDate } */
  @PostMapping
  public ResponseEntity<Map<String, Object>> place(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    W w = who(req);
    Map<String, Object> user = w.who().user();
    Body b = new Body(raw);
    String type = "Package".equals(b.get("type")) ? "Package" : "Refill".equals(b.get("type")) ? "Refill" : null;
    if (type == null) throw HttpError.bad("TYPE_MISSING", "Choose the order type", "Refill my gallons or Buy a package.");
    Integer qty = b.integer("quantity", 1, MAX_GALLONS);
    if (qty == null) throw HttpError.bad("GALLONS_INVALID", "Number of gallons not valid", "Order 1 to " + MAX_GALLONS + " gallons.", "field", "quantity");

    HttpError noAddress = HttpError.bad("ADDRESS_MISSING", "Delivery address missing", "Pin on map or type the address.", "field", "address");
    Map<String, Object> a;
    if (V.truthy(b.get("addressId")) && user != null) {
      Map<String, Object> r = db.one("SELECT * FROM customer_addresses WHERE address_id = ? AND customer_id = ?", StaffApi.idOf(V.str(b.get("addressId"))), Auth.id(user));
      if (r == null) throw noAddress;
      a = M.with(Addresses.shapeAddress(r), "addressId", r.get("address_id"));
    } else if (V.truthy(b.get("fromOrderId"))) {
      // Order again: same address as an earlier order of this customer.
      Map<String, Object> prev = db.one("SELECT * FROM orders o WHERE o.order_id = ? AND " + w.sql(), StaffApi.idOf(V.str(b.get("fromOrderId"))), w.param());
      if (prev == null) throw noAddress;
      a = M.of("text", prev.get("delivery_address_text"), "landmark", prev.get("delivery_landmark"),
          "lat", V.numOrNull(prev.get("delivery_latitude")), "lng", V.numOrNull(prev.get("delivery_longitude")), "addressId", prev.get("address_id"));
    } else if (b.get("address") instanceof Map) {
      a = Addresses.readAddress(b.obj("address"));
    } else {
      throw noAddress;
    }

    Object rawPhone = V.truthy(b.get("phone")) ? b.get("phone") : (user != null ? user.get("phone_number") : null);
    String phone = Body.normalizePhone(rawPhone);
    if (!Body.isPhone(phone)) throw HttpError.bad("PHONE_INVALID", "Phone number not valid", "Use 11 digits, like 0917 200 1111.", "field", "phone");
    String name = user != null ? String.valueOf(user.get("full_name")) : b.text("name", 100);
    if (name.isEmpty()) throw HttpError.bad("NAME_MISSING", "Name missing", "Type your name so the rider knows who to look for.", "field", "name");

    String day = deliveryDate(b.get("deliveryDate"));
    double unit = settings.price("Package".equals(type) ? "package" : "delivery");
    Instant t = Clock.now();
    String notes = b.text("notes", 255);
    Map<String, Object> addr = a;
    long id = db.tx(() -> {
      long oid = db.insert(
          "INSERT INTO orders (order_source, order_type, customer_id, guest_token, customer_name, contact_phone, address_id,"
              + " delivery_address_text, delivery_landmark, delivery_latitude, delivery_longitude, quantity, unit_price, total_amount,"
              + " notes, delivery_date, status, payment_method, payment_status, created_at)"
              + " VALUES ('App', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'New', 'COD', 'Pending', ?)",
          type,
          user != null ? Auth.id(user) : null,
          user != null ? null : w.who().guestToken(),
          name,
          phone,
          V.truthy(addr.get("addressId")) ? addr.get("addressId") : null,
          addr.get("text"),
          V.truthy(addr.get("landmark")) ? addr.get("landmark") : null,
          addr.get("lat"),
          addr.get("lng"),
          qty,
          unit,
          unit * qty,
          notes.isEmpty() ? null : notes,
          day,
          t);
      orders.addHistory(oid, "Waiting for order to be accepted", user != null ? Auth.id(user) : null, null, t);
      orders.notifyOwner("New Order", "New order", name + ": " + qty + " " + (qty == 1 ? "gallon" : "gallons") + " · " + type
          + " · ordered " + Clock.dateClock(t) + (day == null ? "" : " · deliver on " + Clock.dateText(Clock.noonOf(day))), oid);
      return oid;
    });
    Map<String, Object> o = orders.orderRow(id);
    return ResponseEntity.status(201).body(M.of(
        "order", Orders.shapeOrder(o, orders.stationPoint()),
        "title", "Thank you for your order!",
        "message", "Your order has been received. Please wait for the station to accept your order. Payment: cash on delivery, pay once delivered."));
  }

  /** POST /api/orders/:id/cancel -> { order } (only while waiting to be accepted) */
  @PostMapping("/{id}/cancel")
  public Map<String, Object> cancel(HttpServletRequest req, @PathVariable String id) {
    W w = who(req);
    Map<String, Object> o = myOrder(req, id, w);
    long oid = V.lng(o.get("order_id"));
    Map<String, Object> user = w.who().user();
    db.txRun(() -> {
      int n = db.update("UPDATE orders SET status = 'Cancelled' WHERE order_id = ? AND status = 'New'", oid);
      if (n != 1) throw HttpError.conflict("ALREADY_ACCEPTED", "Cannot cancel", "The station already accepted this order. Call the station.");
      orders.addHistory(oid, "Cancelled", user != null ? Auth.id(user) : null, "By customer");
      long qty = V.lng(o.get("quantity"));
      orders.notifyOwner("Cancelled", "Order cancelled",
          (V.truthy(o.get("customer_name")) ? V.str(o.get("customer_name")) : "Guest") + " cancelled " + qty + " " + (qty == 1 ? "gallon" : "gallons") + " · " + o.get("order_type"),
          oid);
    });
    return M.of("order", Orders.shapeOrder(orders.orderRow(oid), orders.stationPoint()), "message", "Order cancelled; owner notified");
  }
}
