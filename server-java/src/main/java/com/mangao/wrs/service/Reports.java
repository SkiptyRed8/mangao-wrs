package com.mangao.wrs.service;

import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * Day figures used by the owner's Home (Today's Summary) and the Daily Sales Report (FR-10), and the
 * Weekly Sales Report (step 37).
 *  - Money earned: payments received that day (paid at the station, paid on delivery, walk-ins paid,
 *    and old unpaid orders marked paid that day).
 *  - Unpaid: orders completed that day that are still unpaid.
 *  - Gallons processed: gallons counted that day (sent out or walk-in saved); delivery vs walk-in.
 *  - Rider paid: cash the riders (or the owner) collected on delivery that day.
 */
@Component
public class Reports {
  public static final List<String> SUM_KEYS = List.of("moneyEarned", "unpaid", "gallons", "packages", "deliveryGallons", "walkInGallons", "riderPaid", "walkIns", "delivered");
  private static final String[] DAY_NAMES = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
  private final Db db;

  public Reports(Db db) {
    this.db = db;
  }

  /** [start, end) of a Philippine-time day 'YYYY-MM-DD'. */
  public static Instant[] dayRange(String day) {
    Instant start = Clock.at(Clock.noonOf(day), 0, 0);
    return new Instant[] {start, start.plusSeconds(24 * 3600)};
  }

  /** [start, end) of the Philippine-time day of t. */
  public static Instant[] dayRange(Instant t) {
    Instant start = Clock.at(t, 0, 0);
    return new Instant[] {start, start.plusSeconds(24 * 3600)};
  }

  public Map<String, Object> daySummary(Instant start, Instant end) {
    Map<String, Object> money = db.one("SELECT SUM(total_amount) AS v FROM orders WHERE payment_status = 'Paid' AND paid_at >= ? AND paid_at < ?", start, end);
    Map<String, Object> unpaid = db.one(
        "SELECT SUM(total_amount) AS v FROM orders WHERE payment_status = 'Unpaid' AND status IN ('Delivered','Recorded') AND delivered_at >= ? AND delivered_at < ?",
        start, end);
    Map<String, Object> g = db.one(
        "SELECT SUM(quantity) AS total, SUM(IF(order_type = 'Package', quantity, 0)) AS packages,"
            + " SUM(IF(order_source = 'Walk-in', quantity, 0)) AS walkin, SUM(IF(order_source <> 'Walk-in', quantity, 0)) AS delivery"
            + " FROM orders WHERE tank_counted_at >= ? AND tank_counted_at < ?",
        start, end);
    Map<String, Object> rider = db.one(
        "SELECT SUM(total_amount) AS v FROM orders WHERE payment_status = 'Paid' AND payment_method IN ('COD','Pay on delivery')"
            + " AND paid_at = delivered_at AND delivered_at >= ? AND delivered_at < ?",
        start, end);
    Map<String, Object> walkins = db.one("SELECT COUNT(*) AS c FROM orders WHERE order_source = 'Walk-in' AND created_at >= ? AND created_at < ?", start, end);
    Map<String, Object> delivered = db.one("SELECT COUNT(*) AS c FROM orders WHERE status = 'Delivered' AND delivered_at >= ? AND delivered_at < ?", start, end);
    return M.of(
        "moneyEarned", V.num(money.get("v")),
        "unpaid", V.num(unpaid.get("v")),
        "gallons", V.num(g.get("total")),
        "packages", V.num(g.get("packages")),
        "deliveryGallons", V.num(g.get("delivery")),
        "walkInGallons", V.num(g.get("walkin")),
        "riderPaid", V.num(rider.get("v")),
        "walkIns", V.num(walkins.get("c")),
        "delivered", V.num(delivered.get("c")));
  }

  /** Orders completed that day (delivered or walk-in saved), newest first. */
  public List<Map<String, Object>> dayOrders(Instant start, Instant end) {
    List<Map<String, Object>> rows = db.query(
        "SELECT order_id, order_source, customer_name, quantity, order_type, total_amount, payment_method, payment_status, delivered_at"
            + " FROM orders WHERE status IN ('Delivered','Recorded') AND delivered_at >= ? AND delivered_at < ? ORDER BY delivered_at DESC",
        start, end);
    List<Map<String, Object>> out = new ArrayList<>();
    for (Map<String, Object> r : rows) {
      String name = "Walk-in".equals(r.get("order_source"))
          ? (V.truthy(r.get("customer_name")) ? "Walk-in: " + r.get("customer_name") : "Walk-in")
          : (V.truthy(r.get("customer_name")) ? V.str(r.get("customer_name")) : "Guest");
      out.add(M.of(
          "id", V.lng(r.get("order_id")),
          "name", name,
          "quantity", V.intOrNull(r.get("quantity")),
          "type", r.get("order_type"),
          "total", V.num(r.get("total_amount")),
          "tag", "Paid at station".equals(r.get("payment_method")) ? "Paid at station" : r.get("payment_status"),
          "at", r.get("delivered_at")));
    }
    return out;
  }

  /** 'YYYY-MM-DD' plus n days. */
  public static String addDays(String ymd, int n) {
    return LocalDate.parse(ymd).plusDays(n).toString();
  }

  /** The Monday of the week of 'YYYY-MM-DD'. */
  public static String mondayOf(String ymd) {
    LocalDate d = LocalDate.parse(ymd);
    return d.minusDays(d.getDayOfWeek().getValue() - 1).toString();
  }

  /** Totals of the 7 days from Monday 'start'; days after 'today' are 0 and marked future. */
  public Map<String, Object> weekSummary(String start, String today) {
    List<Map<String, Object>> days = new ArrayList<>();
    Map<String, Object> totals = new LinkedHashMap<>();
    for (String k : SUM_KEYS) totals.put(k, 0.0);
    for (int i = 0; i < 7; i++) {
      String date = addDays(start, i);
      boolean future = date.compareTo(today) > 0;
      Map<String, Object> s;
      if (future) {
        s = new LinkedHashMap<>();
        for (String k : SUM_KEYS) s.put(k, 0.0);
      } else {
        Instant[] r = dayRange(date);
        s = daySummary(r[0], r[1]);
      }
      for (String k : SUM_KEYS) totals.put(k, V.num(totals.get(k)) + V.num(s.get(k)));
      Map<String, Object> day = M.of("date", date, "day", DAY_NAMES[i], "future", future);
      day.putAll(s);
      day.put("orders", V.num(s.get("delivered")) + V.num(s.get("walkIns")));
      days.add(day);
    }
    totals.put("orders", V.num(totals.get("delivered")) + V.num(totals.get("walkIns")));
    return M.of("days", days, "totals", totals);
  }

  /** Percent change from last week to this week (null when last week was 0). */
  public static Double change(double now, double before) {
    return before == 0 ? null : Math.round(((now - before) / before) * 1000) / 10.0;
  }
}
