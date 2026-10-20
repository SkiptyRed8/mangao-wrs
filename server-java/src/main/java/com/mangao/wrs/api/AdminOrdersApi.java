package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.Orders;
import com.mangao.wrs.service.Process;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Owner's Order Board (FR-04, FR-11; Admin Orders 1-4): New, Processing, Out for Delivery and
 * Delivered tabs, a filter for Not delivered / Declined / Cancelled, Order Details with the timeline,
 * Accept (one, several or all, one rider, automatic delivery time), Decline with a reason, Change rider.
 */
@RestController
@RequestMapping("/api/admin/orders")
public class AdminOrdersApi {
  static final List<String> DECLINE_REASONS = List.of("Run out of water", "Out of new gallons", "Outside delivery area", "Closed", "Too many orders", "Other");
  static final List<String> CANCEL_REASONS = List.of("Customer asked to cancel", "Cannot reach customer", "Out of stock", "Other");

  /** Which orders each tab and filter shows. Delivered, declined, cancelled and "all" are today's. */
  private static final Map<String, String> VIEWS = Map.of(
      "new", "o.status = 'New'",
      "processing", "o.status = 'Processing'",
      "out", "o.status = 'Out for Delivery'",
      "delivered", "o.status = 'Delivered' AND o.delivered_at >= ?",
      "not-delivered", "o.status = 'Not Delivered'",
      "declined", "o.status = 'Declined' AND o.updated_at >= ?",
      "cancelled", "o.status = 'Cancelled' AND o.updated_at >= ?",
      "all", "o.status <> 'Recorded' AND o.created_at >= ?");
  private static final Map<String, String> ORDER_BY = Map.of(
      "new", "o.created_at, o.order_id",
      "processing", "o.est_delivery_to, o.order_id",
      "out", "o.out_at, o.order_id",
      "delivered", "o.delivered_at DESC");

  private final Db db;
  private final Auth auth;
  private final Orders orders;
  private final Process process;

  public AdminOrdersApi(Db db, Auth auth, Orders orders, Process process) {
    this.db = db;
    this.auth = auth;
    this.orders = orders;
    this.process = process;
  }

  private Map<String, Object> counts() {
    Map<String, Object> r = db.one(
        "SELECT SUM(status = 'New') AS c_new, SUM(status = 'Processing') AS c_processing, SUM(status = 'Out for Delivery') AS c_out,"
            + " SUM(status = 'Delivered' AND delivered_at >= ?) AS c_delivered, SUM(status = 'Not Delivered') AS c_not_delivered FROM orders",
        Clock.todayStart());
    return M.of("new", V.lng(r.get("c_new")), "processing", V.lng(r.get("c_processing")), "out", V.lng(r.get("c_out")),
        "delivered", V.lng(r.get("c_delivered")), "notDelivered", V.lng(r.get("c_not_delivered")));
  }

  /** GET /api/admin/orders?view=new|processing|out|delivered|not-delivered|declined|cancelled|all -> { orders, counts } */
  @GetMapping
  public Map<String, Object> board(HttpServletRequest req, @RequestParam(required = false) String view) {
    auth.require(req, "Owner");
    String v = view != null && VIEWS.containsKey(view) ? view : "new";
    String where = VIEWS.get(v);
    Orders.Station station = orders.stationPoint();
    Object[] params = where.contains("?") ? new Object[] {Clock.todayStart()} : new Object[0];
    List<Map<String, Object>> rows = db.query(Orders.ORDER_SELECT + " WHERE o.order_source <> 'Walk-in' AND " + where
        + " ORDER BY " + ORDER_BY.getOrDefault(v, "o.updated_at DESC"), params);
    List<Map<String, Object>> out = new ArrayList<>();
    for (Map<String, Object> o : rows) out.add(Orders.shapeOrder(o, station));
    return M.of("view", v, "orders", out, "counts", counts());
  }

  /** GET /api/admin/orders/riders -> { riders: [{ id, name, owner }] } (active riders, then Me (Owner)) */
  @GetMapping("/riders")
  public Map<String, Object> riders(HttpServletRequest req) {
    Map<String, Object> me = auth.require(req, "Owner");
    List<Map<String, Object>> list = new ArrayList<>();
    for (Map<String, Object> r : db.query("SELECT user_id, full_name FROM users WHERE role = 'Rider' AND is_active = 1 ORDER BY full_name")) {
      list.add(M.of("id", V.lng(r.get("user_id")), "name", r.get("full_name"), "owner", false));
    }
    list.add(M.of("id", Auth.id(me), "name", "Me (Owner)", "owner", true));
    return M.of("riders", list, "reasons", DECLINE_REASONS, "cancelReasons", CANCEL_REASONS);
  }

  private Map<String, Object> getOrder(Object id) {
    Map<String, Object> o = orders.orderRow(id instanceof Number n ? n.longValue() : StaffApi.idOf(String.valueOf(id)));
    if (o == null) throw HttpError.notFound("ORDER_NOT_FOUND", "Order not found", "It may have been removed.");
    return o;
  }

  private Map<String, Object> shaped(long id) {
    return Orders.shapeOrder(getOrder(id), orders.stationPoint());
  }

  /** GET /api/admin/orders/:id -> { order, timeline } */
  @GetMapping("/{id}")
  public Map<String, Object> get(HttpServletRequest req, @PathVariable String id) {
    auth.require(req, "Owner");
    Map<String, Object> o = getOrder(id);
    return M.of("order", Orders.shapeOrder(o, orders.stationPoint()), "timeline", orders.timeline(V.lng(o.get("order_id"))));
  }

  /** The rider for an order: an active rider, or the owner. */
  private Map<String, Object> readRider(Body b) {
    double id = V.num(b.get("riderId"));
    Map<String, Object> r = b.get("riderId") != null && !Double.isNaN(id) && id != 0
        ? db.one("SELECT user_id, full_name, role FROM users WHERE user_id = ? AND is_active = 1 AND role IN ('Rider','Owner')", (long) id)
        : null;
    if (r == null) throw HttpError.bad("RIDER_MISSING", "Choose one rider", "Pick a rider or Me (Owner).", "field", "rider");
    return r;
  }

  static String riderLabel(Map<String, Object> r) {
    return "Owner".equals(r.get("role")) ? "Owner" : Orders.firstName(r.get("full_name"));
  }

  /** Ids from { ids: [...] }: whole numbers above 0, no repeats. */
  static List<Long> ids(Body b) {
    Set<Long> out = new LinkedHashSet<>();
    for (Object o : b.list("ids")) {
      double d = V.num(o);
      if (o != null && !Double.isNaN(d) && d == Math.rint(d) && d > 0) out.add((long) d);
    }
    return new ArrayList<>(out);
  }

  /** POST /api/admin/orders/accept { ids: [..], riderId } -> { accepted, message } */
  @PostMapping("/accept")
  public Map<String, Object> accept(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = auth.require(req, "Owner");
    Body b = new Body(raw);
    List<Long> ids = ids(b);
    if (ids.isEmpty()) throw HttpError.bad("NONE_SELECTED", "No orders selected", "Tick at least one new order.");
    Map<String, Object> rider = readRider(b);
    Instant t = Clock.now();
    Clock.Est est = Clock.estimatedDelivery(t);
    String when = Clock.deliveryText(est.from(), est.to());
    db.txRun(() -> {
      List<Map<String, Object>> rows = db.query("SELECT * FROM orders WHERE order_id IN (?) AND status = 'New' FOR UPDATE", ids);
      if (rows.size() != ids.size()) {
        throw HttpError.conflict("ALREADY_HANDLED", "Some orders changed", "An order was cancelled or already handled. The list is refreshed.");
      }
      for (Map<String, Object> o : rows) {
        long oid = V.lng(o.get("order_id"));
        // A delivery day chosen by the customer gives that day's delivery hours.
        Clock.Est e = Clock.estimatedDelivery(t, deliveryDay(o));
        String w = Clock.deliveryText(e.from(), e.to());
        db.update("UPDATE orders SET status = 'Processing', rider_id = ?, accepted_by = ?, accepted_at = ?, est_delivery_from = ?, est_delivery_to = ? WHERE order_id = ?",
            rider.get("user_id"), Auth.id(me), t, e.from(), e.to(), oid);
        orders.addHistory(oid, "Order accepted", Auth.id(me), "Rider: " + riderLabel(rider), t);
        orders.addHistory(oid, "Processing", Auth.id(me), "Delivery " + w, t);
        orders.notifyCustomer(o, "Order Accepted", "Order accepted",
            "Your " + ("Package".equals(o.get("order_type")) ? "package" : "refill") + " order is processing. Estimated delivery: " + w + ".");
      }
    });
    return M.of("accepted", ids.size(), "estText", when, "message", ids.size() == 1 ? "Accepted. Customer notified." : ids.size() + " orders accepted");
  }

  /** The delivery day the customer chose ('YYYY-MM-DD'), or null. */
  static String deliveryDay(Map<String, Object> o) {
    Object d = o.get("delivery_date");
    return d == null ? null : String.valueOf(d).substring(0, 10);
  }

  private static String reason(Body b, List<String> allowed, String pickMessage, String chooseTitle) {
    Object r = b.get("reason");
    if (!(r instanceof String) || !allowed.contains(r)) throw HttpError.bad("REASON_MISSING", chooseTitle, pickMessage);
    String reason = "Other".equals(r) ? b.text("other", 150) : (String) r;
    if (reason.isEmpty()) throw HttpError.bad("REASON_MISSING", "Type the reason", "The customer sees this reason.", "field", "other");
    return reason;
  }

  /** POST /api/admin/orders/:id/decline { reason, other } -> { order } */
  @PostMapping("/{id}/decline")
  public Map<String, Object> decline(HttpServletRequest req, @PathVariable String id, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = auth.require(req, "Owner");
    Map<String, Object> o = getOrder(id);
    String reason = reason(new Body(raw), DECLINE_REASONS, "Pick why the order is declined.", "Choose reason");
    long oid = V.lng(o.get("order_id"));
    db.txRun(() -> {
      int n = db.update("UPDATE orders SET status = 'Declined' WHERE order_id = ? AND status = 'New'", oid);
      if (n != 1) throw HttpError.conflict("ALREADY_HANDLED", "Order changed", "It was cancelled or already handled.");
      orders.addHistory(oid, "Declined", Auth.id(me), reason);
      orders.notifyCustomer(o, "Order Declined", "Order declined", reason);
    });
    return M.of("order", shaped(oid), "message", "Declined. Customer sees the reason.");
  }

  /** POST /api/admin/orders/:id/rider { riderId } -> { order } (Processing only; locked once out for delivery) */
  @PostMapping("/{id}/rider")
  public Map<String, Object> changeRider(HttpServletRequest req, @PathVariable String id, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = auth.require(req, "Owner");
    Map<String, Object> o = getOrder(id);
    Map<String, Object> rider = readRider(new Body(raw));
    long oid = V.lng(o.get("order_id"));
    db.txRun(() -> {
      int n = db.update("UPDATE orders SET rider_id = ? WHERE order_id = ? AND status = 'Processing'", rider.get("user_id"), oid);
      if (n != 1) throw HttpError.conflict("RIDER_LOCKED", "Rider cannot be changed", "Only while the order is in Processing.");
      orders.addHistory(oid, "Rider changed", Auth.id(me), "Rider: " + riderLabel(rider));
    });
    return M.of("order", shaped(oid), "message", "Rider notified.");
  }

  /**
   * POST /api/admin/orders/:id/cancel { reason, other } -> { order }
   * Cancel an accepted order (Processing) or a Not delivered one. Gallons already counted stay counted.
   */
  @PostMapping("/{id}/cancel")
  public Map<String, Object> cancel(HttpServletRequest req, @PathVariable String id, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = auth.require(req, "Owner");
    Map<String, Object> o = getOrder(id);
    String reason = reason(new Body(raw), CANCEL_REASONS, "Pick why the order is cancelled.", "Choose a reason");
    long oid = V.lng(o.get("order_id"));
    db.txRun(() -> {
      int n = db.update("UPDATE orders SET status = 'Cancelled' WHERE order_id = ? AND status IN ('New','Processing','Not Delivered')", oid);
      if (n != 1) throw HttpError.conflict("CANNOT_CANCEL", "Cannot cancel", "Only new, Processing or Not delivered orders can be cancelled.");
      orders.addHistory(oid, "Cancelled", Auth.id(me), reason);
      orders.notifyCustomer(o, "Order Cancelled", "Order cancelled", reason);
    });
    return M.of("order", shaped(oid), "message", "Order cancelled. Customer notified.");
  }

  /**
   * POST /api/admin/orders/:id/redeliver -> { order }  Not delivered -> back to Processing for the next
   * batch (same rider, can be changed); new delivery time; not counted again in the tank counter.
   */
  @PostMapping("/{id}/redeliver")
  public Map<String, Object> redeliver(HttpServletRequest req, @PathVariable String id) {
    Map<String, Object> me = auth.require(req, "Owner");
    Map<String, Object> o = getOrder(id);
    Instant t = Clock.now();
    Clock.Est est = Clock.estimatedDelivery(t, deliveryDay(o));
    long oid = V.lng(o.get("order_id"));
    String when = Clock.deliveryText(est.from(), est.to());
    db.txRun(() -> {
      int n = db.update("UPDATE orders SET status = 'Processing', batch_id = NULL, out_at = NULL, est_delivery_from = ?, est_delivery_to = ? WHERE order_id = ? AND status = 'Not Delivered'",
          est.from(), est.to(), oid);
      if (n != 1) throw HttpError.conflict("NOT_NOT_DELIVERED", "Cannot re-deliver", "Only Not delivered orders can be re-delivered.");
      orders.addHistory(oid, "Re-deliver", Auth.id(me), "Delivery " + when, t);
      orders.notifyCustomer(o, "Re-deliver", "We will deliver again", "Your order is processing again. Estimated delivery: " + when + ".");
    });
    return M.of("order", shaped(oid), "message", "Back to Processing.");
  }

  private Map<String, Object> outOrder(String id) {
    Map<String, Object> o = db.one("SELECT * FROM orders WHERE order_id = ?", StaffApi.idOf(id));
    if (o == null) throw HttpError.notFound("ORDER_NOT_FOUND", "Order not found", "It may have been removed.");
    if (!"Out for Delivery".equals(o.get("status"))) throw HttpError.conflict("NOT_OUT", "Not out for delivery", "Mark it Out for Delivery first.");
    return o;
  }

  /** POST /api/admin/orders/:id/delivered { paid } (owner delivering, Admin Orders 6) */
  @PostMapping("/{id}/delivered")
  public Map<String, Object> delivered(HttpServletRequest req, @PathVariable String id, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = auth.require(req, "Owner");
    Map<String, Object> o = outOrder(id);
    boolean paid = !new Body(raw).isFalse("paid");
    Process.Result r = db.tx(() -> process.recordDelivered(o, Auth.id(me), paid));
    return M.of("message", r.message(), "batchDone", r.batchDone());
  }

  /** POST /api/admin/orders/:id/not-delivered { note } */
  @PostMapping("/{id}/not-delivered")
  public Map<String, Object> notDelivered(HttpServletRequest req, @PathVariable String id, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = auth.require(req, "Owner");
    Map<String, Object> o = outOrder(id);
    String note = new Body(raw).text("note", 200);
    Process.Result r = db.tx(() -> process.recordNotDelivered(o, Auth.id(me), note));
    return M.of("message", r.message(), "batchDone", r.batchDone());
  }

  /** POST /api/admin/orders/:id/paid -> { order }  Only the owner changes Unpaid to Paid (FR-08). */
  @PostMapping("/{id}/paid")
  public Map<String, Object> paid(HttpServletRequest req, @PathVariable String id) {
    Map<String, Object> me = auth.require(req, "Owner");
    Map<String, Object> o = getOrder(id);
    Instant t = Clock.now();
    long oid = V.lng(o.get("order_id"));
    db.txRun(() -> {
      int n = db.update("UPDATE orders SET payment_status = 'Paid', paid_at = ? WHERE order_id = ? AND payment_status = 'Unpaid'", t, oid);
      if (n != 1) throw HttpError.conflict("NOT_UNPAID", "Already paid", "This order is not unpaid.");
      orders.addHistory(oid, "Marked paid", Auth.id(me), Process.peso(o.get("total_amount")) + " received", t);
    });
    return M.of("order", shaped(oid), "message", "Marked paid.");
  }
}
