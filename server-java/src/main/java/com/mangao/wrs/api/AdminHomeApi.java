package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.Process;
import com.mangao.wrs.service.Reports;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Owner's Home (FR-16, FR-10; Admin Home 1-4, 6, 7): tank counter, Switch View counts, Needs Your
 * Action, Today's Summary tiles and Stock Alerts.
 */
@RestController
@RequestMapping("/api/admin/home")
public class AdminHomeApi {
  private final Db db;
  private final Auth auth;
  private final Process process;
  private final Reports reports;

  public AdminHomeApi(Db db, Auth auth, Process process, Reports reports) {
    this.db = db;
    this.auth = auth;
    this.process = process;
    this.reports = reports;
  }

  public static List<Map<String, Object>> stockAlerts(Db db) {
    List<Map<String, Object>> out = new ArrayList<>();
    for (Map<String, Object> i : db.query("SELECT item_name, quantity_on_hand, low_stock_level FROM inventory_items")) {
      boolean seal = "Seal".equals(i.get("item_name"));
      long q = V.lng(i.get("quantity_on_hand")), level = V.lng(i.get("low_stock_level"));
      out.add(M.of("item", seal ? "seals" : "gallons", "label", seal ? "Seals" : "Gallons", "quantity", q, "level", level, "low", q <= level));
    }
    return out;
  }

  /** GET /api/admin/home */
  @GetMapping
  public Map<String, Object> home(HttpServletRequest req) {
    Map<String, Object> me = auth.require(req, "Owner");
    Map<String, Object> c = db.tx(process::openCycle);
    Map<String, Object> k = db.one(
        "SELECT SUM(status = 'New') AS c_new, SUM(status = 'Processing') AS c_proc, SUM(status = 'Out for Delivery') AS c_out,"
            + " SUM(status = 'Not Delivered') AS c_nd FROM orders");
    Instant[] r = Reports.dayRange(Clock.now());
    Map<String, Object> unread = db.one("SELECT COUNT(*) AS c FROM notifications WHERE user_id = ? AND is_read = 0", Auth.id(me));
    long count = V.lng(c.get("gallons_count")), limit = V.lng(c.get("tank_limit"));
    return M.of(
        "tank", M.of("count", count, "limit", limit, "alert", count >= limit),
        "counts", M.of("new", V.lng(k.get("c_new")), "processing", V.lng(k.get("c_proc")), "out", V.lng(k.get("c_out")), "notDelivered", V.lng(k.get("c_nd"))),
        "today", reports.daySummary(r[0], r[1]),
        "stock", stockAlerts(db),
        "unread", V.lng(unread.get("c")));
  }
}
