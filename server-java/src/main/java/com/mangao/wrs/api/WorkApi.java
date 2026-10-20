package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.DemoRide;
import com.mangao.wrs.service.Orders;
import com.mangao.wrs.service.Process;
import com.mangao.wrs.service.Settings;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
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
 * Work of the owner and staff (FR-03, FR-05, FR-06, FR-11): Log Walk-in, Log Delivery Order,
 * To Do (tank counter + Processing), Mark Out for Delivery in batches, Done Today, and the owner's
 * "Water tank refilled" reset.
 */
@RestController
@RequestMapping("/api/work")
public class WorkApi {
  private static final int MAX = 100;
  private static final List<String> CHANNELS = List.of("Call", "Text", "Messenger", "Walk-in for delivery");
  private final Db db;
  private final Auth auth;
  private final Orders orders;
  private final Process process;
  private final Settings settings;
  private final DemoRide demoRide;

  public WorkApi(Db db, Auth auth, Orders orders, Process process, Settings settings, DemoRide demoRide) {
    this.demoRide = demoRide;
    this.db = db;
    this.auth = auth;
    this.orders = orders;
    this.process = process;
    this.settings = settings;
  }

  private Map<String, Object> me(HttpServletRequest req) {
    return auth.require(req, "Owner", "Staff");
  }

  static String gal(long n) {
    return n + " " + (n == 1 ? "gallon" : "gallons");
  }

  private Map<String, Object> tankState() {
    Map<String, Object> c = process.openCycle();
    long count = V.lng(c.get("gallons_count")), limit = V.lng(c.get("tank_limit"));
    return M.of("count", count, "limit", limit, "alert", count >= limit);
  }

  /** GET /api/work/tank -> { count, limit, alert } */
  @GetMapping("/tank")
  public Map<String, Object> tank(HttpServletRequest req) {
    me(req);
    return db.tx(this::tankState);
  }

  /** POST /api/work/tank/reset (owner only) -> { count: 0 } "Water tank refilled" */
  @PostMapping("/tank/reset")
  public Map<String, Object> reset(HttpServletRequest req) {
    Map<String, Object> me = me(req);
    if (!"Owner".equals(Auth.role(me))) throw HttpError.forbidden("OWNER_ONLY", "Owner only", "Tell the owner: water tank needs refilling.");
    Map<String, Object> t = db.tx(() -> {
      Map<String, Object> c = process.openCycle();
      db.update("UPDATE tank_cycles SET ended_at = ?, reset_by = ? WHERE cycle_id = ?", Clock.now(), Auth.id(me), c.get("cycle_id"));
      Map<String, Object> s = db.one("SELECT tank_limit FROM station_settings WHERE setting_id = 1");
      db.insert("INSERT INTO tank_cycles (gallons_count, tank_limit, started_at) VALUES (0, ?, ?)", s.get("tank_limit"), Clock.now());
      return tankState();
    });
    return M.with(t, "message", "Counter = 0; alert cleared");
  }

  /**
   * POST /api/work/walk-in { quantity, type: Refill|Package, paid: true|false, name } -> 201
   * Walk-in pick-up: P30 per gallon (P150 package), a sale record only (no status steps).
   */
  @PostMapping("/walk-in")
  public ResponseEntity<Map<String, Object>> walkIn(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = me(req);
    Body b = new Body(raw);
    Integer qty = b.integer("quantity", 1, MAX);
    if (qty == null) throw HttpError.bad("QTY_MISSING", "Quantity missing", "Tap + to add gallons.", "field", "quantity");
    String type = "Package".equals(b.get("type")) ? "Package" : "Refill";
    boolean paid = !b.isFalse("paid");
    String nameText = b.text("name", 100);
    String name = nameText.isEmpty() ? null : nameText;
    double unit = settings.price("Package".equals(type) ? "package" : "walkIn");
    Instant t = Clock.now();
    long uid = Auth.id(me);
    Object[] result = db.tx(() -> {
      long id = db.insert(
          "INSERT INTO orders (order_source, order_type, created_by, customer_name, quantity, unit_price, total_amount, status,"
              + " payment_method, payment_status, paid_at, accepted_by, accepted_at, delivered_at, created_at)"
              + " VALUES ('Walk-in', ?, ?, ?, ?, ?, ?, 'Recorded', 'Walk-in', ?, ?, ?, ?, ?, ?)",
          type, uid, name, qty, unit, unit * qty, paid ? "Paid" : "Unpaid", paid ? t : null, uid, t, t, t);
      orders.addHistory(id, "Walk-in saved", uid, paid ? "Paid" : "Unpaid", t);
      Map<String, Object> o = db.one("SELECT * FROM orders WHERE order_id = ?", id);
      Long count = process.countOrder(o, uid, "Walk-in saved", t);
      return new Object[] {id, count};
    });
    return ResponseEntity.status(201).body(M.of(
        "id", result[0],
        "total", unit * qty,
        "tank", result[1],
        "message", "Walk-in saved: " + gal(qty) + ", " + (paid ? "Paid" : "Unpaid")));
  }

  /**
   * POST /api/work/delivery { name, phone, address, quantity, type, channel, payment: 'Pay on delivery'|'Paid at station' }
   * Logged delivery orders (call, text, Messenger, walk-in for delivery) go straight to Processing with the owner as rider.
   */
  @PostMapping("/delivery")
  public ResponseEntity<Map<String, Object>> delivery(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = me(req);
    Body b = new Body(raw);
    String name = b.text("name", 100);
    String phone = Body.normalizePhone(b.get("phone"));
    String address = b.text("address", 255);
    Integer qty = b.integer("quantity", 1, MAX);
    boolean noPhone = !V.truthy(b.get("phone"));
    if (name.isEmpty() || noPhone || address.isEmpty() || qty == null) {
      List<String> missing = new ArrayList<>();
      if (name.isEmpty()) missing.add("name");
      if (noPhone) missing.add("phone");
      if (address.isEmpty()) missing.add("address");
      if (qty == null) missing.add("quantity");
      throw HttpError.bad("FIELDS_MISSING", "Name, phone, address or quantity missing", "Fill in the marked fields.", "fields", missing);
    }
    if (!Body.isPhone(phone)) throw HttpError.bad("PHONE_INVALID", "Phone number not valid", "Use 11 digits, like 0918 555 2211.", "fields", List.of("phone"));
    Object ch = b.get("channel");
    String channel = ch instanceof String s && CHANNELS.contains(s) ? s : "Walk-in".equals(ch) ? "Walk-in for delivery" : null;
    if (channel == null) throw HttpError.bad("CHANNEL_MISSING", "Choose how the order was received", "Call, Text, Messenger or Walk-in.");
    boolean paidAtStation = "Paid at station".equals(b.get("payment"));
    String type = "Package".equals(b.get("type")) ? "Package" : "Refill";
    double unit = settings.price("Package".equals(type) ? "package" : "delivery");
    Instant t = Clock.now();
    Clock.Est est = Clock.estimatedDelivery(t);
    String notes = b.text("notes", 255);
    long uid = Auth.id(me);
    long id = db.tx(() -> {
      long rider = process.ownerId();
      long oid = db.insert(
          "INSERT INTO orders (order_source, logged_channel, order_type, created_by, customer_name, contact_phone, delivery_address_text,"
              + " quantity, unit_price, total_amount, notes, status, payment_method, payment_status, paid_at, rider_id, accepted_by, accepted_at,"
              + " est_delivery_from, est_delivery_to, created_at)"
              + " VALUES ('Logged', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Processing', ?, ?, ?, ?, ?, ?, ?, ?, ?)",
          channel, type, uid, name, phone, address, qty, unit, unit * qty, notes.isEmpty() ? null : notes,
          paidAtStation ? "Paid at station" : "Pay on delivery", paidAtStation ? "Paid" : "Pending", paidAtStation ? t : null,
          rider, uid, t, est.from(), est.to(), t);
      orders.addHistory(oid, "Order logged", uid, channel + " · Rider: Owner", t);
      orders.addHistory(oid, "Processing", uid, "Delivery " + Clock.deliveryText(est.from(), est.to()), t);
      if ("Staff".equals(Auth.role(me))) {
        orders.notifyOwner("Logged Order", "Order logged by staff", Orders.firstName(me.get("full_name")) + ": " + name + ", " + gal(qty) + " · " + channel, oid);
      }
      return oid;
    });
    return ResponseEntity.status(201).body(M.of("order", Orders.shapeOrder(orders.orderRow(id), orders.stationPoint()), "message", "Order saved"));
  }

  /** GET /api/work/todo -> { tank, processing: [orders], owner } */
  @GetMapping("/todo")
  public Map<String, Object> todo(HttpServletRequest req) {
    Map<String, Object> me = me(req);
    Orders.Station station = orders.stationPoint();
    List<Map<String, Object>> list = new ArrayList<>();
    for (Map<String, Object> o : db.query(Orders.ORDER_SELECT + " WHERE o.status = 'Processing' ORDER BY o.est_delivery_to, o.order_id")) {
      list.add(Orders.shapeOrder(o, station));
    }
    return M.of("tank", db.tx(this::tankState), "processing", list, "owner", "Owner".equals(Auth.role(me)));
  }

  /**
   * POST /api/work/out { ids } -> { batches, message }
   * One rider per batch (one sidecar): orders with different riders go out as separate batches.
   */
  @PostMapping("/out")
  public Map<String, Object> out(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = me(req);
    List<Long> ids = AdminOrdersApi.ids(new Body(raw));
    if (ids.isEmpty()) throw HttpError.bad("NONE_SELECTED", "No orders selected", "Tick at least one order in Processing.");
    Instant t = Clock.now();
    long uid = Auth.id(me);
    List<Long> riders = new ArrayList<>();
    List<Map<String, Object>> batches = db.tx(() -> {
      List<Map<String, Object>> rows = db.query(
          "SELECT o.*, u.full_name AS rider_name, u.role AS rider_role FROM orders o LEFT JOIN users u ON u.user_id = o.rider_id"
              + " WHERE o.order_id IN (?) AND o.status = 'Processing' FOR UPDATE",
          ids);
      if (rows.size() != ids.size()) throw HttpError.conflict("ALREADY_HANDLED", "Some orders changed", "An order is no longer in Processing. The list is refreshed.");
      Map<Long, List<Map<String, Object>>> groups = new LinkedHashMap<>();
      for (Map<String, Object> o : rows) {
        long rider = o.get("rider_id") != null ? V.lng(o.get("rider_id")) : process.ownerId();
        groups.computeIfAbsent(rider, k -> new ArrayList<>()).add(o);
      }
      List<Map<String, Object>> outList = new ArrayList<>();
      for (Map.Entry<Long, List<Map<String, Object>>> e : groups.entrySet()) {
        long rider = e.getKey();
        List<Map<String, Object>> list = e.getValue();
        long batch = db.insert("INSERT INTO delivery_batches (rider_id, sent_by, sent_at) VALUES (?, ?, ?)", rider, uid, t);
        riders.add(rider);
        Map<String, Object> f = list.get(0);
        String riderLabel = "Owner".equals(f.get("rider_role")) || !V.truthy(f.get("rider_name")) ? "Owner" : Orders.firstName(f.get("rider_name"));
        List<Long> ordersOut = new ArrayList<>();
        for (Map<String, Object> o : list) {
          long oid = V.lng(o.get("order_id"));
          db.update("UPDATE orders SET status = 'Out for Delivery', rider_id = ?, batch_id = ?, out_at = ? WHERE order_id = ?", rider, batch, t, oid);
          orders.addHistory(oid, "Out for delivery", uid, "Rider: " + riderLabel, t);
          process.countOrder(o, uid, "Order sent out for delivery", t);
          orders.notifyCustomer(o, "Out for Delivery", "Out for delivery", list.size() > 1 ? "Your rider is handling multiple orders." : "Your rider is on the way.");
          ordersOut.add(oid);
        }
        outList.add(M.of("batchId", batch, "rider", riderLabel, "orders", ordersOut));
      }
      return outList;
    });
    // The sidecar starts at the station (and drives by itself when the demo ride is on).
    for (long rider : riders) {
      try {
        demoRide.startAtStation(rider);
      } catch (Exception e) {
        System.err.println("[map] start at station: " + e.getMessage());
      }
    }
    int n = ids.size();
    return M.of("batches", batches, "message", n == 1 ? "Out for delivery. Customer notified." : n + " orders out for delivery");
  }

  /**
   * GET /api/work/done-today -> { gallons, items: [{ id, name, quantity, what, at }] }
   * Gallons processed today (counted today) and orders logged or sent out today, newest first.
   */
  @GetMapping("/done-today")
  public Map<String, Object> doneToday(HttpServletRequest req) {
    me(req);
    Instant start = Clock.todayStart();
    Map<String, Object> g = db.one("SELECT COALESCE(SUM(quantity), 0) AS n FROM orders WHERE tank_counted_at >= ?", start);
    List<Map<String, Object>> rows = db.query(
        "SELECT h.status, h.changed_at, o.order_id, o.order_source, o.customer_name, o.quantity, o.order_type"
            + " FROM order_status_history h JOIN orders o ON o.order_id = h.order_id"
            + " WHERE h.changed_at >= ? AND h.status IN ('Walk-in saved', 'Order logged', 'Out for delivery')"
            + " ORDER BY h.changed_at DESC, h.history_id DESC LIMIT 200",
        start);
    Map<String, String> what = Map.of("Walk-in saved", "Walk-in saved", "Order logged", "Delivery logged", "Out for delivery", "Sent out");
    List<Map<String, Object>> items = new ArrayList<>();
    for (Map<String, Object> r : rows) {
      String name = "Walk-in".equals(r.get("order_source"))
          ? "Walk-in" + (V.truthy(r.get("customer_name")) ? ": " + r.get("customer_name") : "")
          : (V.truthy(r.get("customer_name")) ? V.str(r.get("customer_name")) : "Guest");
      items.add(M.of("id", V.lng(r.get("order_id")), "name", name, "quantity", V.intOrNull(r.get("quantity")), "type", r.get("order_type"),
          "what", what.get(String.valueOf(r.get("status"))), "at", r.get("changed_at"), "clock", Clock.clock(V.instant(r.get("changed_at")))));
    }
    return M.of("gallons", V.num(g.get("n")), "items", items);
  }

  /** GET /api/work/orders/:id -> { order, timeline } (view only for staff) */
  @GetMapping("/orders/{id}")
  public Map<String, Object> order(HttpServletRequest req, @PathVariable String id) {
    me(req);
    Map<String, Object> o = orders.orderRow(StaffApi.idOf(id));
    if (o == null) throw HttpError.notFound("ORDER_NOT_FOUND", "Order not found", "It may have been removed.");
    return M.of("order", Orders.shapeOrder(o, orders.stationPoint()), "timeline", orders.timeline(V.lng(o.get("order_id"))));
  }
}
