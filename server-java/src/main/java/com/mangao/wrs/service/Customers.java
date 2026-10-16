package com.mangao.wrs.service;

import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * One "customer" across the ways orders come in (Unpaid Accounts, Customers list).
 *  - An account (u<id>): its app orders, plus logged or walk-in orders with the same phone number.
 *  - Otherwise by phone number (p<phone>), or by name when there is no phone (n<name>).
 */
@Component
public class Customers {
  /** Every order with the customer key (ckey) and the account id (cuid) when there is one. */
  public static final String KEYED_ORDERS = "("
      + " SELECT o.*, COALESCE(o.customer_id, u2.user_id) AS cuid,"
      + " CASE WHEN COALESCE(o.customer_id, u2.user_id) IS NOT NULL THEN CONCAT('u', COALESCE(o.customer_id, u2.user_id))"
      + " WHEN COALESCE(o.contact_phone, '') <> '' THEN CONCAT('p', o.contact_phone)"
      + " ELSE CONCAT('n', COALESCE(o.customer_name, '')) END AS ckey"
      + " FROM orders o"
      + " LEFT JOIN users u2 ON o.customer_id IS NULL AND u2.role = 'Customer' AND u2.phone_number = o.contact_phone"
      + ")";

  public static final String UNPAID = "k.payment_status = 'Unpaid' AND k.status IN ('Delivered','Recorded')";

  private final Db db;

  public Customers(Db db) {
    this.db = db;
  }

  /** Name and phone shown for a key (the account's, else the newest order's). */
  public Map<String, Object> who(String key) {
    if (key.startsWith("p")) {
      Map<String, Object> acc = db.one("SELECT user_id FROM users WHERE role = 'Customer' AND phone_number = ?", key.substring(1));
      if (acc != null) key = "u" + V.lng(acc.get("user_id"));
    }
    if (key.startsWith("u")) {
      long id = 0;
      try {
        id = Long.parseLong(key.substring(1));
      } catch (NumberFormatException e) {
        id = 0;
      }
      Map<String, Object> u = db.one("SELECT user_id, full_name, phone_number, email, created_at FROM users WHERE user_id = ? AND role = 'Customer'", id);
      if (u != null) {
        return M.of("key", key, "accountId", V.lng(u.get("user_id")), "name", u.get("full_name"), "phone", u.get("phone_number"),
            "email", V.s(u.get("email")), "since", u.get("created_at"), "account", true);
      }
    }
    Map<String, Object> o = db.one("SELECT customer_name, contact_phone FROM " + KEYED_ORDERS + " k WHERE k.ckey = ? ORDER BY k.created_at DESC LIMIT 1", key);
    if (o == null) return null;
    return M.of("key", key, "accountId", null, "name", V.truthy(o.get("customer_name")) ? o.get("customer_name") : "Walk-in",
        "phone", V.s(o.get("contact_phone")), "email", "", "since", null, "account", false);
  }

  /** Unpaid orders of one customer, oldest first. */
  public List<Map<String, Object>> unpaidOrders(String key) {
    List<Map<String, Object>> rows = db.query(
        "SELECT k.order_id, k.order_source, k.order_type, k.quantity, k.total_amount, k.delivered_at, k.created_at"
            + " FROM " + KEYED_ORDERS + " k WHERE k.ckey = ? AND " + UNPAID + " ORDER BY COALESCE(k.delivered_at, k.created_at)",
        key);
    List<Map<String, Object>> out = new ArrayList<>();
    for (Map<String, Object> r : rows) {
      out.add(M.of("id", V.lng(r.get("order_id")), "source", r.get("order_source"), "type", r.get("order_type"),
          "quantity", V.intOrNull(r.get("quantity")), "total", V.num(r.get("total_amount")),
          "at", r.get("delivered_at") != null ? r.get("delivered_at") : r.get("created_at")));
    }
    return out;
  }

  /** Unpaid Accounts list: customers who owe, most owed first. q searches name or phone. */
  public List<Map<String, Object>> unpaidAccounts(String q) {
    List<Object> params = new ArrayList<>();
    String search = "";
    if (q != null && !q.isEmpty()) {
      search = " HAVING name LIKE ? OR phone LIKE ?";
      String digits = q.replaceAll("\\D", "");
      params.add("%" + q + "%");
      params.add("%" + (digits.isEmpty() ? q : digits) + "%");
    }
    List<Map<String, Object>> rows = db.query(
        "SELECT k.ckey AS ckey, COALESCE(MAX(u.full_name), SUBSTRING_INDEX(GROUP_CONCAT(k.customer_name ORDER BY k.created_at DESC SEPARATOR '\\n'), '\\n', 1)) AS name,"
            + " COALESCE(MAX(u.phone_number), MAX(k.contact_phone)) AS phone, COUNT(*) AS orders, SUM(k.total_amount) AS owed,"
            + " MIN(COALESCE(k.delivered_at, k.created_at)) AS oldest"
            + " FROM " + KEYED_ORDERS + " k LEFT JOIN users u ON u.user_id = k.cuid"
            + " WHERE " + UNPAID + " GROUP BY k.ckey" + search + " ORDER BY owed DESC, oldest",
        params.toArray());
    List<Map<String, Object>> out = new ArrayList<>();
    for (Map<String, Object> r : rows) {
      out.add(M.of("key", r.get("ckey"), "name", V.truthy(r.get("name")) ? V.str(r.get("name")) : "Walk-in", "phone", V.s(r.get("phone")),
          "orders", V.lng(r.get("orders")), "owed", V.num(r.get("owed")), "oldest", r.get("oldest")));
    }
    return out;
  }
}
