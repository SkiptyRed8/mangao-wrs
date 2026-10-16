package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.Addresses;
import com.mangao.wrs.service.Customers;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Customers (FR-11; Admin More 1): the owner's customer list (accounts, plus logged and walk-in
 * customers with a name or phone) and each customer's record: contact, addresses, order history,
 * unpaid orders and borrowed gallons. A customer is one key (see service/Customers).
 */
@RestController
@RequestMapping("/api/customers")
public class CustomersApi {
  private final Db db;
  private final Auth auth;
  private final Customers customers;

  public CustomersApi(Db db, Auth auth, Customers customers) {
    this.db = db;
    this.auth = auth;
    this.customers = customers;
  }

  /** Key of a loan row, the same way orders are keyed. */
  private static String loanKey(Map<String, Object> l, Map<String, Long> accountByPhone) {
    if (l.get("customer_id") != null) return "u" + V.lng(l.get("customer_id"));
    String phone = V.s(l.get("contact_phone"));
    if (!phone.isEmpty() && accountByPhone.containsKey(phone)) return "u" + accountByPhone.get(phone);
    if (!phone.isEmpty()) return "p" + phone;
    return "n" + l.get("customer_name");
  }

  private Map<String, Long> accountsByPhone() {
    Map<String, Long> m = new HashMap<>();
    for (Map<String, Object> r : db.query("SELECT user_id, phone_number FROM users WHERE role = 'Customer'")) m.put(String.valueOf(r.get("phone_number")), V.lng(r.get("user_id")));
    return m;
  }

  /** GET /api/customers?q= -> { customers: [{ key, name, phone, account, orders, lastOrder, owed, borrowed }] } */
  @GetMapping
  public Map<String, Object> list(HttpServletRequest req, @RequestParam(required = false) String q) {
    auth.require(req, "Owner");
    String query = Body.text(q, 60).toLowerCase();
    List<Map<String, Object>> rows = db.query(
        "SELECT k.ckey AS ckey, MAX(k.cuid) AS uid,"
            + " SUBSTRING_INDEX(GROUP_CONCAT(k.customer_name ORDER BY k.created_at DESC SEPARATOR '\\n'), '\\n', 1) AS name,"
            + " MAX(k.contact_phone) AS phone, COUNT(*) AS orders, MAX(k.created_at) AS last_order,"
            + " SUM(IF(" + Customers.UNPAID + ", k.total_amount, 0)) AS owed"
            + " FROM " + Customers.KEYED_ORDERS + " k WHERE k.ckey <> 'n' GROUP BY k.ckey");
    List<Map<String, Object>> accounts = db.query("SELECT user_id, full_name, phone_number, created_at FROM users WHERE role = 'Customer'");
    Map<String, Map<String, Object>> acc = new HashMap<>();
    for (Map<String, Object> a : accounts) acc.put("u" + V.lng(a.get("user_id")), a);
    Map<String, Map<String, Object>> map = new LinkedHashMap<>();
    for (Map<String, Object> r : rows) {
      String key = String.valueOf(r.get("ckey"));
      Map<String, Object> a = acc.get(key);
      map.put(key, M.of(
          "key", key,
          "name", a != null ? a.get("full_name") : (V.truthy(r.get("name")) ? r.get("name") : "Walk-in"),
          "phone", a != null ? a.get("phone_number") : V.s(r.get("phone")),
          "account", a != null,
          "orders", V.lng(r.get("orders")),
          "lastOrder", r.get("last_order"),
          "owed", V.num(r.get("owed")),
          "borrowed", 0L));
    }
    for (Map<String, Object> a : accounts) {
      String key = "u" + V.lng(a.get("user_id"));
      map.putIfAbsent(key, M.of("key", key, "name", a.get("full_name"), "phone", a.get("phone_number"), "account", true, "orders", 0L,
          "lastOrder", null, "owed", 0.0, "borrowed", 0L));
    }
    Map<String, Long> byPhone = new HashMap<>();
    for (Map<String, Object> a : accounts) byPhone.put(String.valueOf(a.get("phone_number")), V.lng(a.get("user_id")));
    for (Map<String, Object> l : db.query("SELECT customer_id, customer_name, contact_phone, quantity FROM gallon_loans WHERE returned_at IS NULL")) {
      String key = loanKey(l, byPhone);
      map.putIfAbsent(key, M.of("key", key, "name", l.get("customer_name"), "phone", V.s(l.get("contact_phone")), "account", false, "orders", 0L,
          "lastOrder", null, "owed", 0.0, "borrowed", 0L));
      Map<String, Object> c = map.get(key);
      c.put("borrowed", V.lng(c.get("borrowed")) + V.lng(l.get("quantity")));
    }
    List<Map<String, Object>> list = new ArrayList<>(map.values());
    if (!query.isEmpty()) {
      String digits = query.replaceAll("\\D", "");
      list.removeIf(c -> !(String.valueOf(c.get("name")).toLowerCase().contains(query) || (!digits.isEmpty() && String.valueOf(c.get("phone")).contains(digits))));
    }
    list.sort((x, y) -> {
      Instant a = V.instant(x.get("lastOrder")), b = V.instant(y.get("lastOrder"));
      long ta = a == null ? 0 : a.toEpochMilli(), tb = b == null ? 0 : b.toEpochMilli();
      if (ta != tb) return Long.compare(tb, ta);
      return String.valueOf(x.get("name")).compareTo(String.valueOf(y.get("name")));
    });
    return M.of("count", map.size(), "customers", list);
  }

  /** GET /api/customers/:key -> { customer, stats, addresses, orders, unpaid: { owed, orders }, loans } */
  @GetMapping("/{key}")
  public Map<String, Object> profile(HttpServletRequest req, @PathVariable String key) {
    auth.require(req, "Owner");
    Map<String, Object> c = customers.who(key);
    if (c == null) {
      // Someone who only borrowed gallons (no orders yet).
      Map<String, Object> l = db.one(key.startsWith("p")
          ? "SELECT * FROM gallon_loans WHERE contact_phone = ? ORDER BY lent_at DESC LIMIT 1"
          : "SELECT * FROM gallon_loans WHERE customer_name = ? AND contact_phone IS NULL ORDER BY lent_at DESC LIMIT 1", key.length() > 0 ? key.substring(1) : "");
      if (l == null) throw HttpError.notFound("CUSTOMER_NOT_FOUND", "Customer not found", "Go back to Customers.");
      c = M.of("key", key, "accountId", null, "name", key.startsWith("n") ? key.substring(1) : "", "phone", key.startsWith("p") ? key.substring(1) : "",
          "email", "", "since", null, "account", false);
    }
    if (!V.truthy(c.get("name"))) {
      Map<String, Object> l = db.one("SELECT customer_name FROM gallon_loans WHERE contact_phone = ? ORDER BY lent_at DESC LIMIT 1", c.get("phone"));
      c.put("name", l != null ? l.get("customer_name") : "Walk-in");
    }
    String ckey = String.valueOf(c.get("key"));
    Long accountId = V.longOrNull(c.get("accountId"));
    List<Map<String, Object>> orders = db.query(
        "SELECT k.order_id, k.order_source, k.order_type, k.quantity, k.total_amount, k.status, k.payment_status, k.payment_method,"
            + " k.delivery_address_text, k.delivery_latitude, k.delivery_longitude, k.created_at, k.delivered_at"
            + " FROM " + Customers.KEYED_ORDERS + " k WHERE k.ckey = ? ORDER BY k.created_at DESC, k.order_id DESC LIMIT 100",
        ckey);

    List<Map<String, Object>> addresses = new ArrayList<>();
    if (accountId != null) {
      for (Map<String, Object> a : db.query("SELECT * FROM customer_addresses WHERE customer_id = ? ORDER BY address_id", accountId)) {
        addresses.add(M.with(Addresses.shapeAddress(a), "saved", true));
      }
    }
    // Addresses used on their orders (newest first, no repeats).
    Set<String> seen = new HashSet<>();
    for (Map<String, Object> a : addresses) seen.add(String.valueOf(a.get("text")));
    for (Map<String, Object> o : orders) {
      String t = V.sn(o.get("delivery_address_text"));
      if (t == null || t.isEmpty() || seen.contains(t) || addresses.size() >= 8) continue;
      seen.add(t);
      addresses.add(M.of("id", null, "name", "Used on an order", "text", t, "lat", V.numOrNull(o.get("delivery_latitude")),
          "lng", V.numOrNull(o.get("delivery_longitude")), "saved", false));
    }

    Map<String, Long> byPhone = accountsByPhone();
    List<Map<String, Object>> loanRows = db.query(
        "SELECT l.*, lb.full_name AS lent_name, lb.role AS lent_role FROM gallon_loans l LEFT JOIN users lb ON lb.user_id = l.lent_by"
            + " WHERE l.customer_id = ? OR l.contact_phone = ? OR (l.contact_phone IS NULL AND l.customer_name = ?)"
            + " ORDER BY l.returned_at IS NULL DESC, l.lent_at DESC LIMIT 100",
        accountId != null ? accountId : 0, V.truthy(c.get("phone")) ? c.get("phone") : "#", c.get("name"));
    List<Map<String, Object>> loans = new ArrayList<>();
    long borrowed = 0;
    for (Map<String, Object> l : loanRows) {
      if (!loanKey(l, byPhone).equals(ckey)) continue;
      boolean out = l.get("returned_at") == null;
      if (out) borrowed += V.lng(l.get("quantity"));
      loans.add(M.of("id", V.lng(l.get("loan_id")), "name", l.get("customer_name"), "phone", V.s(l.get("contact_phone")), "orderId", V.longOrNull(l.get("order_id")),
          "quantity", V.lng(l.get("quantity")), "lentAt", l.get("lent_at"), "lentBy", "Owner".equals(l.get("lent_role")) ? "Owner" : V.s(l.get("lent_name")),
          "returnedAt", l.get("returned_at"), "returnedBy", "", "note", V.s(l.get("note")), "out", out));
    }

    List<Map<String, Object>> unpaid = customers.unpaidOrders(ckey);
    double owed = 0;
    for (Map<String, Object> o : unpaid) owed += V.num(o.get("total"));
    long completed = 0, gallons = 0;
    double spent = 0;
    List<Map<String, Object>> orderOut = new ArrayList<>();
    for (Map<String, Object> o : orders) {
      boolean done = List.of("Delivered", "Recorded").contains(String.valueOf(o.get("status")));
      if (done) {
        completed++;
        gallons += V.lng(o.get("quantity"));
        if ("Paid".equals(o.get("payment_status"))) spent += V.num(o.get("total_amount"));
      }
      orderOut.add(M.of("id", V.lng(o.get("order_id")), "source", o.get("order_source"), "type", o.get("order_type"), "quantity", V.intOrNull(o.get("quantity")),
          "total", V.num(o.get("total_amount")), "status", o.get("status"), "paymentStatus", o.get("payment_status"), "payment", o.get("payment_method"),
          "at", o.get("created_at")));
    }
    return M.of(
        "customer", c,
        "stats", M.of("orders", orders.size(), "completed", completed, "gallons", gallons, "spent", spent, "borrowed", borrowed),
        "addresses", addresses,
        "orders", orderOut,
        "unpaid", M.of("owed", owed, "orders", unpaid),
        "loans", loans);
  }
}
