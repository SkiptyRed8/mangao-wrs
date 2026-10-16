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
import com.mangao.wrs.service.Realtime;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Rider (and the owner in the Delivery view): Out for Delivery list, Delivered (Paid / Unpaid, or
 * already paid at the station), Not delivered with an optional note, Done Today (FR-05, FR-08).
 */
@RestController
@RequestMapping("/api/rider")
public class RiderApi {
  private final Db db;
  private final Auth auth;
  private final Orders orders;
  private final Process process;
  private final Realtime realtime;

  public RiderApi(Db db, Auth auth, Orders orders, Process process, Realtime realtime) {
    this.db = db;
    this.auth = auth;
    this.orders = orders;
    this.process = process;
    this.realtime = realtime;
  }

  private Map<String, Object> me(HttpServletRequest req) {
    return auth.require(req, "Rider", "Owner");
  }

  /** GET /api/rider/deliveries -> { orders, sentAt, sharing } */
  @GetMapping("/deliveries")
  public Map<String, Object> deliveries(HttpServletRequest req) {
    Map<String, Object> me = me(req);
    Orders.Station station = orders.stationPoint();
    List<Map<String, Object>> rows = db.query(Orders.ORDER_SELECT + " WHERE o.status = 'Out for Delivery' AND o.rider_id = ? ORDER BY o.out_at, o.order_id", Auth.id(me));
    Instant first = null;
    List<Map<String, Object>> out = new ArrayList<>();
    for (Map<String, Object> o : rows) {
      Instant t = V.instant(o.get("out_at"));
      if (t != null && (first == null || t.isBefore(first))) first = t;
      out.add(Orders.shapeOrder(o, station));
    }
    return M.of("orders", out, "sentAt", first, "sentClock", first != null ? Clock.clock(first) : "", "sharing", !rows.isEmpty());
  }

  private Map<String, Object> myOut(Map<String, Object> me, String id) {
    Map<String, Object> o = db.one("SELECT * FROM orders WHERE order_id = ?", StaffApi.idOf(id));
    if (o == null) throw HttpError.notFound("ORDER_NOT_FOUND", "Order not found", "It may have been removed.");
    boolean mine = V.lng(o.get("rider_id")) == Auth.id(me) && o.get("rider_id") != null || "Owner".equals(Auth.role(me));
    if (!mine) throw HttpError.notFound("ORDER_NOT_FOUND", "Order not found", "This order is in another rider's batch.");
    if (!"Out for Delivery".equals(o.get("status"))) {
      throw HttpError.conflict("NOT_OUT", "Already recorded", "This order is " + String.valueOf(o.get("status")).toLowerCase() + ".");
    }
    return o;
  }

  /** POST /api/rider/orders/:id/delivered { paid: true|false } -> { message } */
  @PostMapping("/orders/{id}/delivered")
  public Map<String, Object> delivered(HttpServletRequest req, @PathVariable String id, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = me(req);
    Map<String, Object> o = myOut(me, id);
    boolean paid = !new Body(raw).isFalse("paid");
    Process.Result r = db.tx(() -> process.recordDelivered(o, Auth.id(me), paid));
    return M.of("message", r.message(), "batchDone", r.batchDone());
  }

  /** POST /api/rider/orders/:id/not-delivered { note } -> { message } */
  @PostMapping("/orders/{id}/not-delivered")
  public Map<String, Object> notDelivered(HttpServletRequest req, @PathVariable String id, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = me(req);
    Map<String, Object> o = myOut(me, id);
    String note = new Body(raw).text("note", 200);
    Process.Result r = db.tx(() -> process.recordNotDelivered(o, Auth.id(me), note));
    return M.of("message", r.message(), "batchDone", r.batchDone());
  }

  /**
   * POST /api/rider/location { lat, lng } -> { sharing }
   * The rider's phone sends its location every few seconds while orders are out (Rider 5). Sharing
   * turns on by itself at Out for Delivery and off after the last order of the batch.
   */
  @PostMapping("/location")
  public Map<String, Object> location(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = me(req);
    Body b = new Body(raw);
    double lat = b.get("lat") == null ? Double.NaN : V.num(b.get("lat"));
    double lng = b.get("lng") == null ? Double.NaN : V.num(b.get("lng"));
    if (Double.isNaN(lat) || Double.isNaN(lng) || Double.isInfinite(lat) || Double.isInfinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      throw HttpError.bad("LOCATION_INVALID", "Location not valid", "Turn on location and try again.");
    }
    long uid = Auth.id(me);
    Map<String, Object> out = db.one("SELECT batch_id FROM orders WHERE rider_id = ? AND status = 'Out for Delivery' ORDER BY out_at DESC LIMIT 1", uid);
    if (out == null) {
      db.update("UPDATE rider_locations SET is_sharing = 0 WHERE rider_id = ?", uid);
      return M.of("sharing", false);
    }
    Instant t = Clock.now();
    db.update("INSERT INTO rider_locations (rider_id, batch_id, latitude, longitude, is_sharing, updated_at) VALUES (?, ?, ?, ?, 1, ?)"
            + " ON DUPLICATE KEY UPDATE batch_id = VALUES(batch_id), latitude = VALUES(latitude), longitude = VALUES(longitude), is_sharing = 1, updated_at = VALUES(updated_at)",
        uid, out.get("batch_id"), String.format(java.util.Locale.ROOT, "%.7f", lat), String.format(java.util.Locale.ROOT, "%.7f", lng), t);
    realtime.location(uid, M.of("lat", lat, "lng", lng, "at", t, "sharing", true));
    return M.of("sharing", true);
  }

  /** GET /api/rider/done-today -> { delivered, paidAmount, unpaidCount, orders } */
  @GetMapping("/done-today")
  public Map<String, Object> doneToday(HttpServletRequest req) {
    Map<String, Object> me = me(req);
    Orders.Station station = orders.stationPoint();
    List<Map<String, Object>> rows = db.query(Orders.ORDER_SELECT + " WHERE o.status = 'Delivered' AND o.rider_id = ? AND o.delivered_at >= ? ORDER BY o.delivered_at DESC",
        Auth.id(me), Clock.todayStart());
    List<Map<String, Object>> list = new ArrayList<>();
    double paid = 0;
    int unpaid = 0;
    for (Map<String, Object> o : rows) {
      list.add(Orders.shapeOrder(o, station));
      if ("Paid".equals(o.get("payment_status")) && !"Paid at station".equals(o.get("payment_method"))) paid += V.num(o.get("total_amount"));
      if ("Unpaid".equals(o.get("payment_status"))) unpaid++;
    }
    return M.of("delivered", list.size(), "paidAmount", paid, "unpaidCount", unpaid, "orders", list);
  }

  /** GET /api/rider/orders/:id -> { order } (view only) */
  @GetMapping("/orders/{id}")
  public Map<String, Object> order(HttpServletRequest req, @PathVariable String id) {
    Map<String, Object> me = me(req);
    Map<String, Object> o = db.one(Orders.ORDER_SELECT + " WHERE o.order_id = ? AND (o.rider_id = ? OR ? = 'Owner')", StaffApi.idOf(id), Auth.id(me), Auth.role(me));
    if (o == null) throw HttpError.notFound("ORDER_NOT_FOUND", "Order not found", "It may belong to another rider.");
    return M.of("order", Orders.shapeOrder(o, orders.stationPoint()));
  }
}
