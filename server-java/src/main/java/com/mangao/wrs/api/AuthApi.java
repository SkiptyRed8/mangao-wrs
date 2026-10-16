package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.Env;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.Jwt;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.Accounts;
import com.mangao.wrs.service.Mail;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Log in, sign up and forgot password (FR-01, Login 1-4). */
@RestController
@RequestMapping("/api/auth")
public class AuthApi {
  private static final int CODE_MINUTES = 10; // the code works for 10 minutes
  private static final int RESEND_SECONDS = 60; // a new code can be asked for after 60 seconds
  private static final int MAX_TRIES = 5; // wrong tries before the code stops working
  private static final int RESET_MINUTES = 15; // time to type the new password after the code is correct

  private final Db db;
  private final Auth auth;
  private final Mail mail;

  public AuthApi(Db db, Auth auth, Mail mail) {
    this.db = db;
    this.auth = auth;
    this.mail = mail;
  }

  // ---------------------------------------------------------------- Log in
  /** POST /api/auth/login { phone, password } -> { token, user } */
  @PostMapping("/login")
  public Map<String, Object> login(@RequestBody(required = false) Map<String, Object> raw) {
    Body b = new Body(raw);
    String phone = Body.normalizePhone(b.get("phone"));
    String password = b.str("password");
    if (phone.isEmpty() || password.isEmpty()) throw HttpError.bad("DETAILS_MISSING", "Details missing", "Type your phone number and password");
    Map<String, Object> user = db.one("SELECT * FROM users WHERE phone_number = ?", phone);
    boolean ok = user != null && Accounts.matches(password, user.get("password_hash"));
    if (!ok) throw HttpError.unauthorized("DETAILS_WRONG", "Details wrong", "Check your phone number and password");
    if (!V.truthy(user.get("is_active"))) throw HttpError.unauthorized("ACCOUNT_INACTIVE", "Cannot log in until activated again", "Contact the station");
    return M.of("token", Auth.signToken(user), "user", Auth.shapeUser(user));
  }

  /** GET /api/auth/me -> { user } (the app checks the saved session when it opens) */
  @GetMapping("/me")
  public Map<String, Object> me(HttpServletRequest req) {
    return M.of("user", Auth.shapeUser(auth.require(req)));
  }

  // ---------------------------------------------------------------- Sign up (customers only)
  /**
   * POST /api/auth/signup { name, phone, email, password, confirm, consent } -> 201 { token, user }
   * A guest who signs up (X-Guest-Token header) keeps the orders made on this phone (Customer 10).
   */
  @PostMapping("/signup")
  public ResponseEntity<Map<String, Object>> signup(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    Body b = new Body(raw);
    Accounts.Profile p = Accounts.readProfile(b, "Type your full name.");
    String password = b.str("password");
    Object c = b.get("confirm") != null ? b.get("confirm") : b.get("password");
    String confirm = c == null ? "" : V.str(c);
    Accounts.checkNewPassword(password, confirm);
    if (!b.isTrue("consent")) {
      throw HttpError.bad("CONSENT_REQUIRED", "Agree to continue", "Tick the box to agree to the Terms and Data Privacy Notice", "field", "consent");
    }
    if (db.one("SELECT user_id FROM users WHERE phone_number = ?", p.phone()) != null) throw Accounts.phoneUsed("Log in instead");
    if (db.one("SELECT user_id FROM users WHERE email = ?", p.email()) != null) throw Accounts.emailUsed();

    String hash = Accounts.hash(password);
    String guest = req.getHeader("X-Guest-Token");
    String guestToken = guest == null ? "" : guest.strip();
    long userId;
    try {
      userId = db.tx(() -> {
        long id = db.insert("INSERT INTO users (full_name, phone_number, email, password_hash, role, privacy_consent_at) VALUES (?, ?, ?, ?, 'Customer', NOW())",
            p.name(), p.phone(), p.email(), hash);
        if (guestToken.matches("^[A-Za-z0-9_-]{16,64}$")) {
          db.update("UPDATE orders SET customer_id = ?, guest_token = NULL WHERE guest_token = ? AND customer_id IS NULL", id, guestToken);
          db.update("UPDATE notifications SET user_id = ?, guest_token = NULL WHERE guest_token = ? AND user_id IS NULL", id, guestToken);
        }
        return id;
      });
    } catch (DuplicateKeyException e) {
      // Two sign ups at the same moment: the unique keys still stop a second account.
      throw Accounts.duplicateError(e, "Log in instead");
    }
    Map<String, Object> user = db.one("SELECT * FROM users WHERE user_id = ?", userId);
    return ResponseEntity.status(201).body(M.of("token", Auth.signToken(user), "user", Auth.shapeUser(user)));
  }

  // ---------------------------------------------------------------- Forgot password (all roles)
  private Map<String, Object> findByEmail(Object raw) {
    String email = Body.normalizeEmail(raw);
    if (email.isEmpty()) throw HttpError.bad("EMAIL_MISSING", "Email missing", "Type the email on your account.", "field", "email");
    Map<String, Object> user = db.one("SELECT * FROM users WHERE email = ?", email);
    if (user == null) throw HttpError.notFound("EMAIL_NOT_FOUND", "Email not found", "No account uses this email. Check it and try again.", "field", "email");
    return user;
  }

  /**
   * POST /api/auth/forgot { email } -> { email (masked), expiresIn, resendIn, emailSent, devCode? }
   * Also used by "Resend code": the old code stops working.
   */
  @PostMapping("/forgot")
  public Map<String, Object> forgot(@RequestBody(required = false) Map<String, Object> raw) {
    Body b = new Body(raw);
    Map<String, Object> user = findByEmail(b.get("email"));
    long uid = Auth.id(user);
    Map<String, Object> last = db.one(
        "SELECT TIMESTAMPDIFF(SECOND, created_at, NOW()) AS age FROM password_resets WHERE user_id = ? ORDER BY reset_id DESC LIMIT 1", uid);
    if (last != null && V.lng(last.get("age")) < RESEND_SECONDS) {
      long wait = RESEND_SECONDS - V.lng(last.get("age"));
      throw new HttpError(429, "WAIT", "Wait a moment", "You can ask for a new code in " + wait + " seconds.", M.of("resendIn", wait));
    }
    String code = Accounts.newCode();
    String codeHash = Accounts.hash(code, 8);
    db.txRun(() -> {
      db.update("UPDATE password_resets SET used_at = NOW() WHERE user_id = ? AND used_at IS NULL", uid);
      db.update("INSERT INTO password_resets (user_id, code_hash, expires_at) VALUES (?, ?, NOW() + INTERVAL ? MINUTE)", uid, codeHash, CODE_MINUTES);
    });
    boolean sent;
    try {
      sent = mail.sendResetCode(String.valueOf(user.get("email")), String.valueOf(user.get("full_name")), code);
    } catch (Exception err) {
      System.err.println("[email] could not send the reset code: " + err.getMessage());
      System.err.println("[email] " + Mail.hint(err));
      db.update("UPDATE password_resets SET used_at = NOW() WHERE user_id = ? AND used_at IS NULL", uid);
      throw new HttpError(503, "EMAIL_NOT_SENT", "Email not sent", "Try again in a moment.");
    }
    Map<String, Object> out = M.of("email", Mail.maskEmail(String.valueOf(user.get("email"))), "expiresIn", CODE_MINUTES * 60, "resendIn", RESEND_SECONDS, "emailSent", sent);
    if (!sent && !"production".equals(Env.nodeEnv()) && !Mail.ready()) out.put("devCode", code); // demo only
    return out;
  }

  /** POST /api/auth/forgot/verify { email, code } -> { resetToken } */
  @PostMapping("/forgot/verify")
  public Map<String, Object> verify(@RequestBody(required = false) Map<String, Object> raw) {
    Body b = new Body(raw);
    Map<String, Object> user = findByEmail(b.get("email"));
    String code = b.str("code").replaceAll("\\D", "");
    HttpError wrong = HttpError.bad("CODE_WRONG", "Code wrong or expired", "Tap Resend code to get a new one.", "field", "code");
    Map<String, Object> row = db.one(
        "SELECT *, expires_at < NOW() AS expired FROM password_resets WHERE user_id = ? AND used_at IS NULL ORDER BY reset_id DESC LIMIT 1", Auth.id(user));
    if (row == null || V.truthy(row.get("expired")) || V.lng(row.get("attempts")) >= MAX_TRIES || code.length() != 6) {
      if (row != null && code.length() == 6) db.update("UPDATE password_resets SET attempts = attempts + 1 WHERE reset_id = ?", row.get("reset_id"));
      throw wrong;
    }
    if (!Accounts.matches(code, row.get("code_hash"))) {
      db.update("UPDATE password_resets SET attempts = attempts + 1 WHERE reset_id = ?", row.get("reset_id"));
      throw wrong;
    }
    String resetToken = Jwt.sign(M.of("sub", Auth.id(user), "rid", V.lng(row.get("reset_id")), "purpose", "reset"), RESET_MINUTES * 60L);
    return M.of("resetToken", resetToken);
  }

  /** POST /api/auth/forgot/reset { resetToken, password, confirm } -> { ok } */
  @PostMapping("/forgot/reset")
  public Map<String, Object> reset(@RequestBody(required = false) Map<String, Object> raw) {
    Body b = new Body(raw);
    String password = b.str("password");
    String confirm = b.get("confirm") == null ? "" : V.str(b.get("confirm"));
    HttpError ended = HttpError.bad("RESET_ENDED", "Code wrong or expired", "Start again and ask for a new code.");
    Map<String, Object> payload = Jwt.verify(b.str("resetToken"));
    if (payload == null || !"reset".equals(payload.get("purpose"))) throw ended;
    Accounts.checkNewPassword(password, confirm);
    String hash = Accounts.hash(password);
    boolean done = db.tx(() -> {
      int n = db.update("UPDATE password_resets SET used_at = NOW() WHERE reset_id = ? AND user_id = ? AND used_at IS NULL",
          V.lng(payload.get("rid")), V.lng(payload.get("sub")));
      if (n != 1) return false;
      db.update("UPDATE users SET password_hash = ? WHERE user_id = ?", hash, V.lng(payload.get("sub")));
      return true;
    });
    if (!done) throw ended;
    return M.of("ok", true, "message", "Password changed. Log in with your new password.");
  }
}
