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
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Borrowed Gallons (FR-13; Admin Orders 8, Admin Inventory 5, Staff 8). The owner and staff lend the
 * station's new gallons to a customer (stock goes down, "Lent") and mark them returned, all or part
 * (stock goes up, "Returned"). A part return splits the entry: the returned part becomes its own
 * returned entry and the rest stays out.
 */
@RestController
@RequestMapping("/api/loans")
public class LoansApi {
  private static final String SELECT = "SELECT l.*, lb.full_name AS lent_name, lb.role AS lent_role, rb.full_name AS ret_name, rb.role AS ret_role"
      + " FROM gallon_loans l LEFT JOIN users lb ON lb.user_id = l.lent_by LEFT JOIN users rb ON rb.user_id = l.returned_by";
  private final Db db;
  private final Auth auth;
  private final Orders orders;
  private final Process process;
  private final Realtime realtime;

  public LoansApi(Db db, Auth auth, Orders orders, Process process, Realtime realtime) {
    this.db = db;
    this.auth = auth;
    this.orders = orders;
    this.process = process;
    this.realtime = realtime;
  }

  private static String who(Object name, Object role) {
    return "Owner".equals(role) ? "Owner" : V.s(name);
  }

  static Map<String, Object> shape(Map<String, Object> l) {
    boolean out = l.get("returned_at") == null;
    return M.of(
        "id", V.lng(l.get("loan_id")),
        "name", l.get("customer_name"),
        "phone", V.s(l.get("contact_phone")),
        "customerId", V.longOrNull(l.get("customer_id")),
        "orderId", V.longOrNull(l.get("order_id")),
        "quantity", V.lng(l.get("quantity")),
        "lentAt", l.get("lent_at"),
        "lentBy", who(l.get("lent_name"), l.get("lent_role")),
        "returnedAt", l.get("returned_at"),
        "returnedBy", out ? "" : who(l.get("ret_name"), l.get("ret_role")),
        "note", V.s(l.get("note")),
        "out", out);
  }

  /** GET /api/loans?status=out|returned|all&q=&orderId= -> { gallonsOut, loans } */
  @GetMapping
  public Map<String, Object> list(HttpServletRequest req, @RequestParam(required = false) String status, @RequestParam(required = false) String q,
      @RequestParam(required = false) String orderId) {
    auth.require(req, "Owner", "Staff");
    List<String> where = new ArrayList<>();
    List<Object> params = new ArrayList<>();
    String st = status == null || status.isEmpty() ? "out" : status;
    if ("out".equals(st)) where.add("l.returned_at IS NULL");
    if ("returned".equals(st)) where.add("l.returned_at IS NOT NULL");
    if (orderId != null && !orderId.isEmpty()) {
      where.add("l.order_id = ?");
      params.add(StaffApi.idOf(orderId));
    }
    String text = Body.text(q, 60);
    if (!text.isEmpty()) {
      where.add("(l.customer_name LIKE ? OR l.contact_phone LIKE ?)");
      String digits = text.replaceAll("\\D", "");
      params.add("%" + text + "%");
      params.add("%" + (digits.isEmpty() ? text : digits) + "%");
    }
    List<Map<String, Object>> rows = db.query(SELECT + (where.isEmpty() ? "" : " WHERE " + String.join(" AND ", where))
        + " ORDER BY l.returned_at IS NULL DESC, COALESCE(l.returned_at, l.lent_at) DESC, l.loan_id DESC LIMIT 300", params.toArray());
    Map<String, Object> out = db.one("SELECT COALESCE(SUM(quantity), 0) AS n, COUNT(DISTINCT customer_name, COALESCE(contact_phone, '')) AS c FROM gallon_loans WHERE returned_at IS NULL");
    List<Map<String, Object>> loans = new ArrayList<>();
    for (Map<String, Object> r : rows) loans.add(shape(r));
    return M.of("gallonsOut", V.lng(out.get("n")), "customersOut", V.lng(out.get("c")), "loans", loans);
  }

  private static Instant lendDate(Object v) {
    if (!V.truthy(v)) return Clock.now();
    String s = V.str(v);
    if (!s.matches("^\\d{4}-\\d{2}-\\d{2}$")) throw HttpError.bad("DATE_INVALID", "Date not valid", "Pick the date again.");
    Instant d = Clock.noonOf(s);
    if (!d.isBefore(Clock.at(Clock.now(), 0, 0))) {
      if (d.toEpochMilli() > Clock.now().toEpochMilli() + 86400000L) throw HttpError.bad("DATE_FUTURE", "Date is in the future", "Pick today or an earlier day.");
      return Clock.now();
    }
    return d;
  }

  /** POST /api/loans { orderId?, name, phone, quantity, date, note } -> { loan, message } */
  @PostMapping
  public ResponseEntity<Map<String, Object>> lend(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = auth.require(req, "Owner", "Staff");
    Body b = new Body(raw);
    Integer qty = b.integer("quantity", 1, 100);
    String name = b.text("name", 100);
    String phone = Body.normalizePhone(b.get("phone"));
    Long customerId = null;
    Map<String, Object> order = null;
    if (V.truthy(b.get("orderId"))) {
      order = db.one("SELECT * FROM orders WHERE order_id = ?", StaffApi.idOf(V.str(b.get("orderId"))));
      if (order == null) throw HttpError.notFound("ORDER_NOT_FOUND", "Order not found", "It may have been removed.");
      if (name.isEmpty()) name = V.truthy(order.get("customer_name")) ? V.str(order.get("customer_name")) : "Walk-in";
      if (phone.isEmpty()) phone = V.s(order.get("contact_phone"));
      customerId = V.longOrNull(order.get("customer_id"));
    }
    if (name.isEmpty()) throw HttpError.bad("NAME_MISSING", "Customer name missing", "Type who borrowed the gallons.", "field", "name");
    if (!phone.isEmpty() && !Body.isPhone(phone)) throw HttpError.bad("PHONE_INVALID", "Phone number not valid", "Use 11 digits, e.g. 0917 123 4567.", "field", "phone");
    if (qty == null) throw HttpError.bad("QTY_MISSING", "Quantity missing", "Tap + to set how many gallons.", "field", "quantity");
    if (customerId == null && !phone.isEmpty()) {
      Map<String, Object> acc = db.one("SELECT user_id FROM users WHERE role = 'Customer' AND phone_number = ?", phone);
      if (acc != null) customerId = V.lng(acc.get("user_id"));
    }
    long stock = V.lng(db.one("SELECT quantity_on_hand AS n FROM inventory_items WHERE item_name = 'New Gallon'").get("n"));
    if (stock < qty) throw HttpError.conflict("NOT_ENOUGH", "Not enough new gallons", "Only " + stock + " in stock. Add stock first.");
    Instant at = lendDate(b.get("date"));
    String noteText = b.text("note", 255);
    String note = noteText.isEmpty() ? null : noteText;
    String fName = name, fPhone = phone;
    Long fCustomer = customerId;
    Long orderId = order != null ? V.lng(order.get("order_id")) : null;
    long uid = Auth.id(me);
    long id = db.tx(() -> {
      long lid = db.insert("INSERT INTO gallon_loans (customer_id, customer_name, contact_phone, order_id, quantity, lent_by, lent_at, note) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
          fCustomer, fName, fPhone.isEmpty() ? null : fPhone, orderId, qty, uid, at, note);
      process.moveStock("New Gallon", -qty, "Lent", "Lent to " + fName, orderId, uid, at);
      if (orderId != null) orders.addHistory(orderId, "Gallon lent", uid, qty + " " + (qty == 1 ? "gallon" : "gallons") + " lent");
      return lid;
    });
    if (orderId != null) realtime.orderChanged(orderId);
    realtime.ownerRefresh("loans");
    return ResponseEntity.status(201).body(M.of("loan", shape(db.one(SELECT + " WHERE l.loan_id = ?", id)), "message", "Gallons lent. Stock goes down."));
  }

  /** POST /api/loans/:id/return { quantity } -> { loan, message }  quantity defaults to all still out. */
  @PostMapping("/{id}/return")
  public Map<String, Object> giveBack(HttpServletRequest req, @PathVariable String id, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = auth.require(req, "Owner", "Staff");
    Map<String, Object> loan = db.one("SELECT * FROM gallon_loans WHERE loan_id = ?", StaffApi.idOf(id));
    if (loan == null) throw HttpError.notFound("LOAN_NOT_FOUND", "Entry not found", "It may have been removed.");
    if (loan.get("returned_at") != null) throw HttpError.conflict("ALREADY_RETURNED", "Already returned", "This entry is already marked returned.");
    Body b = new Body(raw);
    int have = V.i(loan.get("quantity"));
    Object qv = b.get("quantity");
    Integer qty = qv == null || "".equals(qv) ? Integer.valueOf(have) : Body.integer(qv, 1, have);
    if (qty == null) throw HttpError.bad("QTY_INVALID", "Quantity not valid", "From 1 to " + have + ".", "field", "quantity");
    Instant t = Clock.now();
    long uid = Auth.id(me);
    long loanId = V.lng(loan.get("loan_id"));
    Long orderId = V.longOrNull(loan.get("order_id"));
    int q = qty;
    long rid = db.tx(() -> {
      long returnedId = loanId;
      if (q < have) {
        db.update("UPDATE gallon_loans SET quantity = quantity - ? WHERE loan_id = ?", q, loanId);
        returnedId = db.insert(
            "INSERT INTO gallon_loans (customer_id, customer_name, contact_phone, order_id, quantity, lent_by, lent_at, returned_at, returned_by, note)"
                + " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            loan.get("customer_id"), loan.get("customer_name"), loan.get("contact_phone"), orderId, q, loan.get("lent_by"), loan.get("lent_at"), t, uid, loan.get("note"));
      } else {
        db.update("UPDATE gallon_loans SET returned_at = ?, returned_by = ? WHERE loan_id = ?", t, uid, loanId);
      }
      process.moveStock("New Gallon", q, "Returned", "Returned by " + loan.get("customer_name"), orderId, uid, t);
      if (orderId != null) orders.addHistory(orderId, "Gallon returned", uid, q + " " + (q == 1 ? "gallon" : "gallons") + " returned", t);
      return returnedId;
    });
    if (orderId != null) realtime.orderChanged(orderId);
    realtime.ownerRefresh("loans");
    int left = have - q;
    return M.of("loan", shape(db.one(SELECT + " WHERE l.loan_id = ?", rid)), "left", left,
        "message", left > 0 ? q + " returned. " + left + " still borrowed." : "Returned. Stock goes up.");
  }
}
