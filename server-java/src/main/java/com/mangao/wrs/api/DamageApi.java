package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.Env;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.Orders;
import com.mangao.wrs.service.Process;
import com.mangao.wrs.service.Realtime;
import jakarta.servlet.http.HttpServletRequest;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Report Damaged Gallon (FR-18; UC-10; Rider 4, Staff 2/5, Admin Orders 5). The owner, staff or the
 * order's rider sends a photo and a note. The server saves the photo, takes one new gallon from stock
 * as the replacement ("Damaged customer gallon replaced"), adds it to the order's timeline and alerts
 * the owner. The order continues.
 *  POST /api/damage { orderId, photo (base64 JPEG/PNG, data: prefix allowed), note } -> { report, message }
 *  GET  /api/damage?orderId= -> { reports }
 */
@RestController
@RequestMapping("/api/damage")
public class DamageApi {
  private static final int MAX_BYTES = 3 * 1024 * 1024;
  private static final Pattern DATA_URL = Pattern.compile("^data:image/(jpeg|jpg|png|webp);base64,");
  private static final SecureRandom RANDOM = new SecureRandom();
  private final Db db;
  private final Auth auth;
  private final Orders orders;
  private final Process process;
  private final Realtime realtime;

  public DamageApi(Db db, Auth auth, Orders orders, Process process, Realtime realtime) {
    this.db = db;
    this.auth = auth;
    this.orders = orders;
    this.process = process;
    this.realtime = realtime;
  }

  private record Photo(byte[] bytes, String ext) {}

  private static Photo readPhoto(Object raw) {
    if (!V.truthy(raw)) throw HttpError.bad("PHOTO_MISSING", "Photo missing", "Take a photo of the damaged gallon.", "field", "photo");
    String s = V.str(raw);
    Matcher m = DATA_URL.matcher(s);
    String b64 = m.find() ? s.substring(m.end()) : s;
    byte[] buf;
    try {
      buf = Base64.getMimeDecoder().decode(b64);
    } catch (IllegalArgumentException e) {
      buf = new byte[0];
    }
    String ext = null;
    if (buf.length > 2 && (buf[0] & 0xff) == 0xff && (buf[1] & 0xff) == 0xd8) ext = "jpg";
    else if (buf.length > 4 && HexFormat.of().formatHex(buf, 0, 4).equals("89504e47")) ext = "png";
    else if (buf.length > 12 && new String(buf, 0, 4).equals("RIFF") && new String(buf, 8, 4).equals("WEBP")) ext = "webp";
    if (ext == null) throw HttpError.bad("PHOTO_INVALID", "Photo not valid", "Use a JPG or PNG photo.", "field", "photo");
    if (buf.length > MAX_BYTES) throw HttpError.bad("PHOTO_TOO_BIG", "Photo too big", "Use a photo under 3 MB.", "field", "photo");
    return new Photo(buf, ext);
  }

  private static Map<String, Object> shape(Map<String, Object> r) {
    return M.of(
        "id", V.lng(r.get("report_id")),
        "orderId", V.longOrNull(r.get("order_id")),
        "name", V.s(r.get("customer_name")),
        "note", V.s(r.get("note")),
        "photo", V.truthy(r.get("photo_path")) ? "/uploads/" + r.get("photo_path") : null,
        "by", "Owner".equals(r.get("role")) ? "Owner" : V.s(r.get("full_name")),
        "at", r.get("created_at"));
  }

  @GetMapping
  public Map<String, Object> list(HttpServletRequest req, @RequestParam(required = false) String orderId) {
    Map<String, Object> me = auth.require(req, "Owner", "Staff", "Rider");
    List<Object> params = new ArrayList<>();
    String where = "";
    if (orderId != null && !orderId.isEmpty()) {
      where = " WHERE d.order_id = ?";
      params.add(StaffApi.idOf(orderId));
    } else if (!"Owner".equals(Auth.role(me))) {
      throw HttpError.forbidden("NOT_ALLOWED", "Not allowed", "Open the order to see its reports.");
    }
    List<Map<String, Object>> out = new ArrayList<>();
    for (Map<String, Object> r : db.query("SELECT d.*, u.full_name, u.role FROM damage_reports d LEFT JOIN users u ON u.user_id = d.reported_by"
        + where + " ORDER BY d.created_at DESC LIMIT 200", params.toArray())) {
      out.add(shape(r));
    }
    return M.of("reports", out);
  }

  @PostMapping
  public ResponseEntity<Map<String, Object>> report(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) throws Exception {
    Map<String, Object> me = auth.require(req, "Owner", "Staff", "Rider");
    Body b = new Body(raw);
    Map<String, Object> order = db.one("SELECT * FROM orders WHERE order_id = ?", StaffApi.idOf(V.s(b.get("orderId"))));
    if (order == null) throw HttpError.notFound("ORDER_NOT_FOUND", "Order not found", "It may have been removed.");
    if ("Rider".equals(Auth.role(me)) && (order.get("rider_id") == null || V.lng(order.get("rider_id")) != Auth.id(me))) {
      throw HttpError.forbidden("NOT_YOUR_ORDER", "Not your delivery", "Only the rider of this order can report it.");
    }
    if (List.of("Declined", "Cancelled").contains(String.valueOf(order.get("status")))) {
      throw HttpError.bad("ORDER_CLOSED", "Order is closed", "This order was declined or cancelled.");
    }
    Photo photo = readPhoto(b.get("photo"));
    String note = b.text("note", 255);
    if (note.isEmpty()) throw HttpError.bad("NOTE_MISSING", "Note missing", "Write what is damaged, e.g. cracked at the handle.", "field", "note");

    byte[] rnd = new byte[16];
    RANDOM.nextBytes(rnd);
    String file = HexFormat.of().formatHex(rnd) + "." + photo.ext();
    if (Env.photosInDatabase()) {
      // Online server: the disk is wiped on every restart, so the photo goes into the database.
      db.update("INSERT INTO stored_files (file_path, content_type, data, created_at) VALUES (?, ?, ?, ?)",
          "damage/" + file, "jpg".equals(photo.ext()) ? "image/jpeg" : "image/" + photo.ext(), photo.bytes(), Clock.now());
    } else {
      Path dir = Env.uploadsDir().resolve("damage");
      Files.createDirectories(dir);
      Files.write(dir.resolve(file), photo.bytes());
    }

    long oid = V.lng(order.get("order_id"));
    String name = V.truthy(order.get("customer_name")) ? V.str(order.get("customer_name")) : ("Walk-in".equals(order.get("order_source")) ? "Walk-in" : "Guest");
    String reporter = "Owner".equals(Auth.role(me)) ? "Owner" : V.str(me.get("full_name"));
    Instant t = Clock.now();
    long uid = Auth.id(me);
    boolean[] replaced = {true};
    long id = db.tx(() -> {
      long rid = db.insert("INSERT INTO damage_reports (order_id, customer_name, reported_by, photo_path, note, created_at) VALUES (?, ?, ?, ?, ?, ?)",
          oid, name, uid, "damage/" + file, note, t);
      Map<String, Object> stock = db.one("SELECT quantity_on_hand AS n FROM inventory_items WHERE item_name = 'New Gallon' FOR UPDATE");
      if (V.lng(stock.get("n")) >= 1) {
        process.moveStock("New Gallon", -1, "Damaged", "Damaged customer gallon replaced", oid, uid, t);
      } else {
        replaced[0] = false;
      }
      orders.addHistory(oid, "Damaged gallon", uid, replaced[0] ? note + ". Replaced with a new gallon." : note + ". No new gallon in stock.", t);
      if (!"Owner".equals(Auth.role(me))) {
        orders.notifyOwner("Damaged Gallon", "Damaged gallon", name + " (order #" + oid + "): " + note + ". Reported by " + reporter + ".", oid);
      }
      return rid;
    });
    realtime.orderChanged(oid);
    realtime.ownerRefresh("stock");
    Map<String, Object> row = db.one("SELECT d.*, u.full_name, u.role FROM damage_reports d LEFT JOIN users u ON u.user_id = d.reported_by WHERE d.report_id = ?", id);
    String message = replaced[0]
        ? ("Owner".equals(Auth.role(me)) ? "Saved. A new gallon replaces it." : "Sent to the owner. A new gallon replaces it.")
        : "Saved. No new gallon in stock: add stock to replace it.";
    return ResponseEntity.status(201).body(M.of("report", shape(row), "replaced", replaced[0], "message", message));
  }
}
