package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.service.Accounts;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * My Account (FR-20; More 5, Staff 7, Rider 7, Customer 8): every role changes its password;
 * the owner and customers also edit their profile (staff and riders are edited by the owner).
 */
@RestController
@RequestMapping("/api/account")
public class AccountApi {
  private static final String PHONE_MSG = "Another account uses this number";
  private final Db db;
  private final Auth auth;
  private final Accounts accounts;

  public AccountApi(Db db, Auth auth, Accounts accounts) {
    this.db = db;
    this.auth = auth;
    this.accounts = accounts;
  }

  /** PUT /api/account/profile { name, phone, email } -> { user } */
  @PutMapping("/profile")
  public Map<String, Object> profile(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = auth.require(req);
    if (!List.of("Owner", "Customer").contains(Auth.role(me))) {
      throw HttpError.forbidden("VIEW_ONLY", "View only", "Ask the owner to change your name, phone number or email.");
    }
    Accounts.Profile p = Accounts.readProfile(new Body(raw));
    accounts.checkFree(p.phone(), p.email(), Auth.id(me), PHONE_MSG);
    try {
      db.update("UPDATE users SET full_name = ?, phone_number = ?, email = ? WHERE user_id = ?", p.name(), p.phone(), p.email(), Auth.id(me));
    } catch (RuntimeException e) {
      throw Accounts.duplicateError(e, PHONE_MSG);
    }
    return M.of("user", Auth.shapeUser(db.one("SELECT * FROM users WHERE user_id = ?", Auth.id(me))), "message", "Profile updated");
  }

  /** POST /api/account/password { oldPassword, newPassword } -> { ok } */
  @PostMapping("/password")
  public Map<String, Object> password(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = auth.require(req);
    Body b = new Body(raw);
    String oldPassword = b.str("oldPassword");
    String newPassword = b.str("newPassword");
    if (oldPassword.isEmpty()) throw HttpError.bad("OLD_MISSING", "Old password missing", "Type your current password.", "field", "old");
    if (!Accounts.matches(oldPassword, me.get("password_hash"))) {
      throw HttpError.bad("OLD_WRONG", "Old password wrong", "Check it and try again. Forgot it? Log out and tap Forgot password.", "field", "old");
    }
    Accounts.checkNewPassword(newPassword, null);
    db.update("UPDATE users SET password_hash = ? WHERE user_id = ?", Accounts.hash(newPassword), Auth.id(me));
    return M.of("ok", true, "message", "Password changed");
  }
}
