package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.Push;
import jakarta.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * In-app alerts (FR-12; Admin More 4): new orders, orders logged by staff, cancelled and not
 * delivered orders, tank at 60 and low stock for the owner; order updates for customers.
 */
@RestController
@RequestMapping("/api/notifications")
public class NotificationsApi {
  /** Alerts the owner can turn on or off (Admin More 4: Preferences). */
  public static final String[][] ALERT_TYPES = {
    {"New Order", "New orders"},
    {"Logged Order", "Orders logged by staff"},
    {"Cancelled", "Cancelled orders"},
    {"Not Delivered", "Not delivered"},
    {"Tank", "Tank at 60"},
    {"Low Stock", "Low stock"},
    {"Damaged Gallon", "Damaged gallon"},
  };

  private final Db db;
  private final Auth auth;
  private final Push push;

  public NotificationsApi(Db db, Auth auth, Push push) {
    this.db = db;
    this.auth = auth;
    this.push = push;
  }

  private record W(String sql, Object param, Auth.Who who) {}

  private W who(HttpServletRequest req) {
    Auth.Who w = auth.optional(req);
    if (w.user() != null) return new W("n.user_id = ?", Auth.id(w.user()), w);
    if (w.guestToken() != null) return new W("n.guest_token = ?", w.guestToken(), w);
    throw HttpError.unauthorized("LOGIN_REQUIRED", "Please log in", "Log in to see notifications.");
  }

  /** GET /api/notifications -> { items, unread } */
  @GetMapping
  public Map<String, Object> list(HttpServletRequest req) {
    W w = who(req);
    List<Map<String, Object>> rows = db.query("SELECT n.* FROM notifications n WHERE " + w.sql() + " ORDER BY n.created_at DESC, n.notification_id DESC LIMIT 100", w.param());
    Map<String, Object> u = db.one("SELECT COUNT(*) AS c FROM notifications n WHERE " + w.sql() + " AND n.is_read = 0", w.param());
    List<Map<String, Object>> items = new ArrayList<>();
    for (Map<String, Object> r : rows) {
      items.add(M.of("id", V.lng(r.get("notification_id")), "type", r.get("notification_type"), "title", r.get("title"), "message", r.get("message"),
          "orderId", V.longOrNull(r.get("order_id")), "read", V.truthy(r.get("is_read")), "at", r.get("created_at")));
    }
    return M.of("unread", V.lng(u.get("c")), "items", items);
  }

  /** GET /api/notifications/unread -> { unread } (bell badge) */
  @GetMapping("/unread")
  public Map<String, Object> unread(HttpServletRequest req) {
    W w = who(req);
    Map<String, Object> u = db.one("SELECT COUNT(*) AS c FROM notifications n WHERE " + w.sql() + " AND n.is_read = 0", w.param());
    return M.of("unread", V.lng(u.get("c")));
  }

  /** POST /api/notifications/read { id } or { all: true } */
  @PostMapping("/read")
  public Map<String, Object> read(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    W w = who(req);
    Body b = new Body(raw);
    if (V.truthy(b.get("all"))) db.update("UPDATE notifications n SET n.is_read = 1 WHERE " + w.sql(), w.param());
    else db.update("UPDATE notifications n SET n.is_read = 1 WHERE " + w.sql() + " AND n.notification_id = ?", w.param(), StaffApi.idOf(V.s(b.get("id"))));
    return M.of("ok", true);
  }

  // ---------------------------------------------------------------- Preferences (owner) and phones (push)
  private Map<String, Object> owner(HttpServletRequest req) {
    Map<String, Object> u = auth.userFromHeader(req);
    if (u == null || !"Owner".equals(Auth.role(u))) throw HttpError.forbidden("OWNER_ONLY", "Owner only", "Only the owner chooses alerts.");
    return u;
  }

  /** GET /api/notifications/preferences -> { items: [{ type, label, enabled }], push } */
  @GetMapping("/preferences")
  public Map<String, Object> preferences(HttpServletRequest req) {
    Map<String, Object> me = owner(req);
    Set<String> off = new HashSet<>();
    for (Map<String, Object> r : db.query("SELECT notification_type, is_enabled FROM notification_preferences WHERE user_id = ?", Auth.id(me))) {
      if (!V.truthy(r.get("is_enabled"))) off.add(String.valueOf(r.get("notification_type")));
    }
    List<Map<String, Object>> items = new ArrayList<>();
    for (String[] t : ALERT_TYPES) items.add(M.of("type", t[0], "label", t[1], "enabled", !off.contains(t[0])));
    return M.of("items", items, "push", push.enabled());
  }

  /** PUT /api/notifications/preferences { type, enabled } -> { message } */
  @PutMapping("/preferences")
  public Map<String, Object> setPreference(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = owner(req);
    Body b = new Body(raw);
    boolean known = false;
    for (String[] t : ALERT_TYPES) if (t[0].equals(b.get("type"))) known = true;
    if (!known) throw HttpError.bad("TYPE_UNKNOWN", "Unknown alert", "Pick one from the list.");
    db.update("INSERT INTO notification_preferences (user_id, notification_type, is_enabled) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE is_enabled = VALUES(is_enabled)",
        Auth.id(me), b.get("type"), b.isFalse("enabled") ? 0 : 1);
    return M.of("message", "Saved. Takes effect right away.");
  }

  /** POST /api/notifications/device { token, platform } -> { ok }  (the phone's Firebase token, for push) */
  @PostMapping("/device")
  public Map<String, Object> device(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    W w = who(req);
    Body b = new Body(raw);
    String token = b.str("token").strip();
    if (token.length() < 20 || token.length() > 255) throw HttpError.bad("TOKEN_INVALID", "Push not set up", "The phone did not give a push token.");
    Object pl = b.get("platform");
    String platform = "android".equals(pl) || "web".equals(pl) ? (String) pl : "android";
    boolean user = w.who().user() != null;
    db.update("INSERT INTO device_tokens (user_id, guest_token, push_token, platform) VALUES (?, ?, ?, ?)"
            + " ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), guest_token = VALUES(guest_token), platform = VALUES(platform)",
        user ? w.param() : null, user ? null : w.param(), token, platform);
    return M.of("ok", true);
  }

  /** DELETE /api/notifications/device { token } (log out: no more push to this phone) */
  @DeleteMapping("/device")
  public Map<String, Object> removeDevice(@RequestBody(required = false) Map<String, Object> raw) {
    db.update("DELETE FROM device_tokens WHERE push_token = ?", new Body(raw).str("token"));
    return M.of("ok", true);
  }
}
