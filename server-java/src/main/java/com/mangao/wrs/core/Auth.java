package com.mangao.wrs.core;

import jakarta.servlet.http.HttpServletRequest;
import java.util.Arrays;
import java.util.Map;
import org.springframework.stereotype.Component;

/** Log-in tokens (JWT) and role checks. */
@Component
public class Auth {
  public static final int TOKEN_DAYS = 30;
  private final Db db;

  public Auth(Db db) {
    this.db = db;
  }

  public static String signToken(Map<String, Object> user) {
    return Jwt.sign(M.of("sub", V.lng(user.get("user_id")), "role", user.get("role")), TOKEN_DAYS * 24L * 3600);
  }

  /** The user of the Bearer token, or null when there is no token. */
  public Map<String, Object> userFromHeader(HttpServletRequest req) {
    Object cached = req.getAttribute("wrs.user");
    if (cached instanceof Map<?, ?>) {
      @SuppressWarnings("unchecked")
      Map<String, Object> u = (Map<String, Object>) cached;
      return u;
    }
    String header = req.getHeader("Authorization");
    if (header == null || !header.startsWith("Bearer ")) return null;
    Map<String, Object> payload = Jwt.verify(header.substring(7));
    if (payload == null) throw HttpError.unauthorized("SESSION_ENDED", "Session ended", "Please log in again.");
    Map<String, Object> user = db.one("SELECT * FROM users WHERE user_id = ?", V.lng(payload.get("sub")));
    if (user == null) throw HttpError.unauthorized("SESSION_ENDED", "Session ended", "Please log in again.");
    if (!V.truthy(user.get("is_active"))) {
      throw HttpError.unauthorized("ACCOUNT_INACTIVE", "Account deactivated", "Ask the owner to activate your account.");
    }
    req.setAttribute("wrs.user", user);
    return user;
  }

  /** Needs a logged-in user; with roles, only those roles (e.g. require(req, "Owner", "Staff")). */
  public Map<String, Object> require(HttpServletRequest req, String... roles) {
    Map<String, Object> user = userFromHeader(req);
    if (user == null) throw HttpError.unauthorized("LOGIN_REQUIRED", "Please log in", "Log in to continue.");
    if (roles.length > 0 && !Arrays.asList(roles).contains(String.valueOf(user.get("role")))) {
      throw HttpError.forbidden("NOT_ALLOWED", "Not allowed", "Your account cannot do this.");
    }
    return user;
  }

  /** Logged-in user (or null) and the guest phone code from the X-Guest-Token header. */
  public record Who(Map<String, Object> user, String guestToken) {
    public boolean isGuest() {
      return user == null && guestToken != null;
    }
  }

  public Who optional(HttpServletRequest req) {
    Map<String, Object> user = userFromHeader(req);
    String g = req.getHeader("X-Guest-Token");
    g = g == null ? "" : g.strip();
    return new Who(user, g.matches("^[A-Za-z0-9_-]{16,64}$") ? g : null);
  }

  public static long id(Map<String, Object> user) {
    return V.lng(user.get("user_id"));
  }

  public static String role(Map<String, Object> user) {
    return String.valueOf(user.get("role"));
  }

  public static Map<String, Object> shapeUser(Map<String, Object> u) {
    return M.of(
        "id", V.lng(u.get("user_id")),
        "name", u.get("full_name"),
        "phone", u.get("phone_number"),
        "email", u.get("email"),
        "role", u.get("role"),
        "active", V.truthy(u.get("is_active")));
  }
}
