package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.Customers;
import com.mangao.wrs.service.Reports;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Sales reports (FR-10; Admin Sales 1-3): daily, weekly and unpaid accounts. */
@RestController
@RequestMapping("/api/sales")
public class SalesApi {
  private final Auth auth;
  private final Reports reports;
  private final Customers customers;

  public SalesApi(Auth auth, Reports reports, Customers customers) {
    this.auth = auth;
    this.reports = reports;
    this.customers = customers;
  }

  /** GET /api/sales/daily?date=YYYY-MM-DD -> { date, summary, orders, today } */
  @GetMapping("/daily")
  public Map<String, Object> daily(HttpServletRequest req, @RequestParam(required = false) String date) {
    auth.require(req, "Owner");
    String today = Clock.ymd(Clock.now());
    String d = date == null || date.isEmpty() ? today : date;
    if (!d.matches("^\\d{4}-\\d{2}-\\d{2}$")) throw HttpError.bad("DATE_INVALID", "Date not valid", "Pick the date again.");
    if (d.compareTo(today) > 0) throw HttpError.bad("DATE_FUTURE", "No sales yet", "Pick today or an earlier day.");
    Instant[] r = Reports.dayRange(d);
    return M.of("date", d, "today", today, "summary", reports.daySummary(r[0], r[1]), "orders", reports.dayOrders(r[0], r[1]));
  }

  /**
   * GET /api/sales/weekly?start=YYYY-MM-DD (any day of the week; the Monday is used)
   *  -> { start, end, today, days[7], totals, lastWeek, change: { moneyEarned, gallons, orders } }
   */
  @GetMapping("/weekly")
  @SuppressWarnings("unchecked")
  public Map<String, Object> weekly(HttpServletRequest req, @RequestParam(required = false) String start) {
    auth.require(req, "Owner");
    String today = Clock.ymd(Clock.now());
    String pick = start == null || start.isEmpty() ? today : start;
    if (!pick.matches("^\\d{4}-\\d{2}-\\d{2}$")) throw HttpError.bad("DATE_INVALID", "Date not valid", "Pick the week again.");
    String monday = Reports.mondayOf(pick);
    if (monday.compareTo(today) > 0) throw HttpError.bad("DATE_FUTURE", "No sales yet", "Pick this week or an earlier week.");
    Map<String, Object> week = reports.weekSummary(monday, today);
    Map<String, Object> last = reports.weekSummary(Reports.addDays(monday, -7), today);
    Map<String, Object> t = (Map<String, Object>) week.get("totals");
    Map<String, Object> l = (Map<String, Object>) last.get("totals");
    List<Map<String, Object>> lastDays = new ArrayList<>();
    for (Map<String, Object> d : (List<Map<String, Object>>) last.get("days")) {
      lastDays.add(M.of("date", d.get("date"), "day", d.get("day"), "moneyEarned", d.get("moneyEarned")));
    }
    return M.of(
        "start", monday,
        "end", Reports.addDays(monday, 6),
        "today", today,
        "days", week.get("days"),
        "totals", t,
        "lastWeek", l,
        "lastWeekDays", lastDays,
        "change", M.of(
            "moneyEarned", Reports.change(V.num(t.get("moneyEarned")), V.num(l.get("moneyEarned"))),
            "gallons", Reports.change(V.num(t.get("gallons")), V.num(l.get("gallons"))),
            "orders", Reports.change(V.num(t.get("orders")), V.num(l.get("orders")))));
  }

  /** GET /api/sales/unpaid?q= -> { total, count, customers: [{ key, name, phone, orders, owed, oldest }] }  (Admin Sales 3) */
  @GetMapping("/unpaid")
  public Map<String, Object> unpaid(HttpServletRequest req, @RequestParam(required = false) String q) {
    auth.require(req, "Owner");
    String query = Body.text(q, 60);
    List<Map<String, Object>> list = customers.unpaidAccounts(query);
    List<Map<String, Object>> all = query.isEmpty() ? list : customers.unpaidAccounts("");
    double total = 0;
    for (Map<String, Object> c : all) total += V.num(c.get("owed"));
    return M.of("total", total, "count", all.size(), "customers", list);
  }

  /** GET /api/sales/unpaid/:key -> { customer, owed, orders }  Paid uses POST /api/admin/orders/:id/paid. */
  @GetMapping("/unpaid/{key}")
  public Map<String, Object> unpaidCustomer(HttpServletRequest req, @PathVariable String key) {
    auth.require(req, "Owner");
    Map<String, Object> customer = customers.who(key);
    if (customer == null) throw HttpError.notFound("CUSTOMER_NOT_FOUND", "Customer not found", "Go back to Unpaid Accounts.");
    List<Map<String, Object>> orders = customers.unpaidOrders(String.valueOf(customer.get("key")));
    double owed = 0;
    for (Map<String, Object> o : orders) owed += V.num(o.get("total"));
    return M.of("customer", customer, "owed", owed, "orders", orders);
  }
}
