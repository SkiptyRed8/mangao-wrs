package com.mangao.wrs.service;

import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.HttpError;
import java.security.SecureRandom;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * Checks shared by Sign up, Staff & Riders and My Account: name, phone number and email
 * (both required, Login 3A and Customer 8), and that no other account uses them. Passwords are hashed.
 */
@Component
public class Accounts {
  private static final SecureRandom RANDOM = new SecureRandom();
  private static final BCryptPasswordEncoder BCRYPT = new BCryptPasswordEncoder(10);
  private final Db db;

  public Accounts(Db db) {
    this.db = db;
  }

  public record Profile(String name, String phone, String email) {}

  /** Reads and checks { name, phone, email } from a request body. */
  public static Profile readProfile(Body b, String nameMessage) {
    String name = b.text("name", 100);
    String rawPhone = b.text("phone", 20);
    String email = Body.normalizeEmail(b.get("email"));
    String phone = Body.normalizePhone(rawPhone);
    if (name.isEmpty()) throw HttpError.bad("NAME_MISSING", "Name missing", nameMessage, "field", "name");
    if (rawPhone.isEmpty() || email.isEmpty()) {
      throw HttpError.bad("PHONE_EMAIL_MISSING", "Phone number or email missing", "Both are required", "field", rawPhone.isEmpty() ? "phone" : "email");
    }
    if (!Body.isPhone(phone)) throw HttpError.bad("PHONE_INVALID", "Phone number not valid", "Use 11 digits, like 0917 200 1111.", "field", "phone");
    if (!Body.isEmail(email)) throw HttpError.bad("EMAIL_INVALID", "Email not valid", "Check the email and try again.", "field", "email");
    return new Profile(name, phone, email);
  }

  public static Profile readProfile(Body b) {
    return readProfile(b, "Type the full name.");
  }

  public static HttpError phoneUsed(String msg) {
    return HttpError.conflict("PHONE_USED", "Phone number already used", msg == null ? "Log in instead" : msg, "field", "phone");
  }

  public static HttpError emailUsed() {
    return HttpError.conflict("EMAIL_USED", "Email already used", "Use another email", "field", "email");
  }

  /** Throws when another account (not exceptId) has this phone number or email. */
  public void checkFree(String phone, String email, long exceptId, String phoneMsg) {
    if (db.one("SELECT user_id FROM users WHERE phone_number = ? AND user_id <> ?", phone, exceptId) != null) throw phoneUsed(phoneMsg);
    if (db.one("SELECT user_id FROM users WHERE email = ? AND user_id <> ?", email, exceptId) != null) throw emailUsed();
  }

  /** Maps a duplicate-key error from MySQL (two saves at the same moment) to the same messages. */
  public static RuntimeException duplicateError(RuntimeException err, String phoneMsg) {
    if (err instanceof DuplicateKeyException) {
      return String.valueOf(err.getMessage()).toLowerCase().contains("email") ? emailUsed() : phoneUsed(phoneMsg);
    }
    return err;
  }

  public static void checkNewPassword(String password, String confirm) {
    if (password.length() < Body.MIN_PASSWORD) {
      throw HttpError.bad("PASSWORD_SHORT", "Password too short", "Use at least " + Body.MIN_PASSWORD + " characters.", "field", "password");
    }
    if (confirm != null && !password.equals(confirm)) {
      throw HttpError.bad("PASSWORDS_DIFFERENT", "Passwords do not match", "Type the same password in both fields.", "field", "confirm");
    }
  }

  /** Temporary password the owner reads out to a staff member or rider, e.g. wrs-4821. */
  public static String tempPassword() {
    return String.format("wrs-%04d", RANDOM.nextInt(10000));
  }

  /** 6-digit reset code. */
  public static String newCode() {
    return String.format("%06d", RANDOM.nextInt(1000000));
  }

  public static String hash(String password) {
    return BCRYPT.encode(password);
  }

  public static String hash(String password, int strength) {
    return new BCryptPasswordEncoder(strength).encode(password);
  }

  public static boolean matches(String password, Object hash) {
    if (hash == null) return false;
    try {
      return BCRYPT.matches(password, String.valueOf(hash));
    } catch (RuntimeException e) {
      return false;
    }
  }
}
