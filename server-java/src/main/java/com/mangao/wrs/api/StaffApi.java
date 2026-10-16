package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.Accounts;
import jakarta.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Staff & Riders (FR-02, Admin More 2): the owner adds, edits, deactivates and resets the
 * passwords of staff and riders. The Owner account is listed but cannot be changed here.
 */
@RestController
@RequestMapping("/api/staff")
public class StaffApi {
  private static final String PHONE_MSG = "Another account uses this number";
  private final Db db;
  private final Auth auth;
  private final Accounts accounts;

  public StaffApi(Db db, Auth auth, Accounts accounts) {
    this.db = db;
    this.auth = auth;
    this.accounts = accounts;
  }

  static long idOf(String raw) {
    double d = V.num(raw);
    return Double.isNaN(d) ? 0 : (long) d;
  }

  private Map<String, Object> staffMember(String id) {
    Map<String, Object> u = db.one("SELECT * FROM users WHERE user_id = ? AND role IN ('Owner','Staff','Rider')", idOf(id));
    if (u == null) throw HttpError.notFound("ACCOUNT_NOT_FOUND", "Account not found", "It may have been removed.");
    if ("Owner".equals(u.get("role"))) throw HttpError.forbidden("OWNER_LOCKED", "Owner account", "The owner account cannot be changed here. Use My Account.");
    return u;
  }

  private Map<String, Object> account(long id) {
    return Auth.shapeUser(db.one("SELECT * FROM users WHERE user_id = ?", id));
  }

  /** GET /api/staff -> { accounts: [owner, then staff and riders] } */
  @GetMapping
  public Map<String, Object> list(HttpServletRequest req) {
    auth.require(req, "Owner");
    List<Map<String, Object>> out = new ArrayList<>();
    for (Map<String, Object> r : db.query("SELECT * FROM users WHERE role IN ('Owner','Staff','Rider') ORDER BY role = 'Owner' DESC, is_active DESC, full_name")) {
      out.add(Auth.shapeUser(r));
    }
    return M.of("accounts", out);
  }

  /** POST /api/staff { name, phone, email, role: Staff|Rider, password } -> 201 { account } */
  @PostMapping
  public ResponseEntity<Map<String, Object>> add(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    auth.require(req, "Owner");
    Body b = new Body(raw);
    Accounts.Profile p = Accounts.readProfile(b);
    Object role = b.get("role");
    if (!"Staff".equals(role) && !"Rider".equals(role)) throw HttpError.bad("ROLE_MISSING", "Choose Staff or Rider", "Pick one of the two.", "field", "role");
    String password = b.str("password");
    Accounts.checkNewPassword(password, null);
    accounts.checkFree(p.phone(), p.email(), 0, PHONE_MSG);
    long id;
    try {
      id = db.insert("INSERT INTO users (full_name, phone_number, email, password_hash, role) VALUES (?, ?, ?, ?, ?)",
          p.name(), p.phone(), p.email(), Accounts.hash(password), role);
    } catch (RuntimeException e) {
      throw Accounts.duplicateError(e, PHONE_MSG);
    }
    return ResponseEntity.status(201).body(M.of("account", account(id), "message", "Account created. Can log in."));
  }

  /** GET /api/staff/:id -> { account } */
  @GetMapping("/{id}")
  public Map<String, Object> get(HttpServletRequest req, @PathVariable String id) {
    auth.require(req, "Owner");
    return M.of("account", Auth.shapeUser(staffMember(id)));
  }

  /** PUT /api/staff/:id { name, phone, email } -> { account } */
  @PutMapping("/{id}")
  public Map<String, Object> edit(HttpServletRequest req, @PathVariable String id, @RequestBody(required = false) Map<String, Object> raw) {
    auth.require(req, "Owner");
    Map<String, Object> u = staffMember(id);
    Accounts.Profile p = Accounts.readProfile(new Body(raw));
    accounts.checkFree(p.phone(), p.email(), Auth.id(u), PHONE_MSG);
    try {
      db.update("UPDATE users SET full_name = ?, phone_number = ?, email = ? WHERE user_id = ?", p.name(), p.phone(), p.email(), Auth.id(u));
    } catch (RuntimeException e) {
      throw Accounts.duplicateError(e, PHONE_MSG);
    }
    return M.of("account", account(Auth.id(u)), "message", "Account updated");
  }

  /** POST /api/staff/:id/deactivate -> { account } */
  @PostMapping("/{id}/deactivate")
  public Map<String, Object> deactivate(HttpServletRequest req, @PathVariable String id) {
    return setActive(req, id, 0, "Cannot log in until activated again");
  }

  /** POST /api/staff/:id/activate -> { account } */
  @PostMapping("/{id}/activate")
  public Map<String, Object> activate(HttpServletRequest req, @PathVariable String id) {
    return setActive(req, id, 1, "Account active. Can log in.");
  }

  private Map<String, Object> setActive(HttpServletRequest req, String id, int active, String message) {
    auth.require(req, "Owner");
    Map<String, Object> u = staffMember(id);
    db.update("UPDATE users SET is_active = ? WHERE user_id = ?", active, Auth.id(u));
    return M.of("account", account(Auth.id(u)), "message", message);
  }

  /** POST /api/staff/:id/reset-password -> { tempPassword } (backup when they cannot get the email code) */
  @PostMapping("/{id}/reset-password")
  public Map<String, Object> resetPassword(HttpServletRequest req, @PathVariable String id) {
    auth.require(req, "Owner");
    Map<String, Object> u = staffMember(id);
    String temp = Accounts.tempPassword();
    db.update("UPDATE users SET password_hash = ? WHERE user_id = ?", Accounts.hash(temp), Auth.id(u));
    return M.of("tempPassword", temp, "message", "Give this to " + u.get("full_name") + ". They can change it after logging in.");
  }
}
