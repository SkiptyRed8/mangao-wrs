package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.Process;
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Inventory (FR-07; Admin Inventory 1-4): New Gallons and Seals. Add stock, Damaged or Lost,
 * automatic entries (seals 3 per gallon, 1 new gallon per package), Movement History with a filter.
 */
@RestController
@RequestMapping("/api/inventory")
public class InventoryApi {
  private static final Map<String, String> ITEMS = Map.of("gallons", "New Gallon", "seals", "Seal");
  private static final String MOVE_SELECT = "SELECT m.*, i.item_name, u.full_name AS recorded_name, u.role AS recorded_role"
      + " FROM stock_movements m JOIN inventory_items i ON i.item_id = m.item_id LEFT JOIN users u ON u.user_id = m.recorded_by";
  private static final Map<String, String> LABELS = Map.of("Added", "Stock added", "Damaged", "Damaged", "Lost", "Lost", "Used", "Used",
      "Adjusted", "Adjusted", "Lent", "Lent", "Returned", "Returned");

  private final Db db;
  private final Auth auth;
  private final Process process;

  public InventoryApi(Db db, Auth auth, Process process) {
    this.db = db;
    this.auth = auth;
    this.process = process;
  }

  private static String itemOf(String key) {
    String name = ITEMS.get(key);
    if (name == null) throw HttpError.notFound("ITEM_NOT_FOUND", "Not found", "Use gallons or seals.");
    return name;
  }

  private static Map<String, Object> shapeMove(Map<String, Object> m) {
    boolean auto = m.get("order_id") != null || m.get("recorded_by") == null;
    boolean seal = "Seal".equals(m.get("item_name"));
    String label = V.truthy(m.get("note")) && auto ? V.str(m.get("note")) : LABELS.get(String.valueOf(m.get("movement_type")));
    return M.of(
        "id", V.lng(m.get("movement_id")),
        "item", seal ? "seals" : "gallons",
        "itemLabel", seal ? "Seals" : "New Gallons",
        "change", V.lng(m.get("quantity_change")),
        "type", m.get("movement_type"),
        "label", label,
        "note", auto ? "" : V.s(m.get("note")),
        "orderId", V.longOrNull(m.get("order_id")),
        "automatic", auto,
        "by", "Owner".equals(m.get("recorded_role")) ? "Owner" : V.s(m.get("recorded_name")),
        "at", m.get("created_at"));
  }

  /** GET /api/inventory -> { gallons, seals, sealsPerGallon } */
  @GetMapping
  public Map<String, Object> overview(HttpServletRequest req) {
    auth.require(req, "Owner");
    Map<String, Object> s = db.one("SELECT seals_per_gallon FROM station_settings WHERE setting_id = 1");
    Map<String, Object> out = M.of("sealsPerGallon", V.lng(s.get("seals_per_gallon")));
    for (Map<String, Object> i : db.query("SELECT * FROM inventory_items")) {
      long q = V.lng(i.get("quantity_on_hand")), level = V.lng(i.get("low_stock_level"));
      out.put("Seal".equals(i.get("item_name")) ? "seals" : "gallons", M.of("quantity", q, "level", level, "low", q <= level));
    }
    return out;
  }

  /** GET /api/inventory/movements?item=gallons|seals|all&type=Added|Damaged|Lost|Automatic&from=YYYY-MM-DD&to=YYYY-MM-DD */
  @GetMapping("/movements")
  public Map<String, Object> movements(HttpServletRequest req, @RequestParam(required = false) String item, @RequestParam(required = false) String type,
      @RequestParam(required = false) String from, @RequestParam(required = false) String to) {
    auth.require(req, "Owner");
    List<String> where = new ArrayList<>();
    List<Object> params = new ArrayList<>();
    if (item != null && ITEMS.containsKey(item)) {
      where.add("i.item_name = ?");
      params.add(ITEMS.get(item));
    }
    if ("Automatic".equals(type)) where.add("(m.order_id IS NOT NULL OR m.recorded_by IS NULL)");
    else if (List.of("Added", "Damaged", "Lost").contains(type)) {
      where.add("m.movement_type = ? AND m.order_id IS NULL");
      params.add(type);
    }
    String[][] range = {{from, ">=", "0"}, {to, "<", "1"}};
    for (String[] r : range) {
      if (r[0] != null && r[0].matches("^\\d{4}-\\d{2}-\\d{2}$")) {
        Instant d = Clock.at(Clock.noonOf(r[0]), 0, 0);
        where.add("m.created_at " + r[1] + " ?");
        params.add(d.plusSeconds(Integer.parseInt(r[2]) * 86400L));
      }
    }
    List<Map<String, Object>> rows = db.query(MOVE_SELECT + (where.isEmpty() ? "" : " WHERE " + String.join(" AND ", where))
        + " ORDER BY m.created_at DESC, m.movement_id DESC LIMIT 300", params.toArray());
    List<Map<String, Object>> out = new ArrayList<>();
    for (Map<String, Object> m : rows) out.add(shapeMove(m));
    return M.of("movements", out);
  }

  private static Instant readDate(Object v) {
    if (!V.truthy(v)) return Clock.now();
    String s = V.str(v);
    if (!s.matches("^\\d{4}-\\d{2}-\\d{2}$")) throw HttpError.bad("DATE_INVALID", "Date not valid", "Pick the date again.");
    Instant d = Clock.noonOf(s);
    if (d.toEpochMilli() > Clock.now().toEpochMilli() + 86400000L) throw HttpError.bad("DATE_FUTURE", "Date is in the future", "Pick today or an earlier day.");
    Instant today = Clock.at(Clock.now(), 0, 0);
    return !d.isBefore(today) ? Clock.now() : d;
  }

  /** POST /api/inventory/:item/add { quantity, date, note } -> stock goes up */
  @PostMapping("/{item}/add")
  public Map<String, Object> add(HttpServletRequest req, @PathVariable String item, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = auth.require(req, "Owner");
    String name = itemOf(item);
    Body b = new Body(raw);
    Integer qty = b.integer("quantity", 1, 100000);
    if (qty == null) throw HttpError.bad("QTY_MISSING", "Quantity missing", "Tap + to set how many were added.", "field", "quantity");
    Instant at = readDate(b.get("date"));
    String note = b.text("note", 255);
    long after = db.tx(() -> process.moveStock(name, qty, "Added", note.isEmpty() ? null : note, null, Auth.id(me), at));
    return M.of("quantity", after, "message", "Stock goes up. Entry saved.");
  }

  /** POST /api/inventory/:item/remove { quantity, kind: Damaged|Lost, note } -> stock goes down */
  @PostMapping("/{item}/remove")
  public Map<String, Object> remove(HttpServletRequest req, @PathVariable String item, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = auth.require(req, "Owner");
    String name = itemOf(item);
    Body b = new Body(raw);
    Integer qty = b.integer("quantity", 1, 100000);
    if (qty == null) throw HttpError.bad("QTY_MISSING", "Quantity missing", "Tap + to set how many.", "field", "quantity");
    String kind = "Lost".equals(b.get("kind")) ? "Lost" : "Damaged";
    String note = b.text("note", 255);
    long after = db.tx(() -> process.moveStock(name, -qty, kind, note.isEmpty() ? null : note, null, Auth.id(me), Clock.now()));
    return M.of("quantity", after, "message", "Stock goes down. Entry saved.");
  }
}
