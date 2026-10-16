package com.mangao.wrs.core;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** The JSON body of a request (req.body), with the same checks the old server used. */
public final class Body {
  public static final int MIN_PASSWORD = 6;
  private final Map<String, Object> m;

  public Body(Map<String, Object> m) {
    this.m = m == null ? new LinkedHashMap<>() : m;
  }

  public Object get(String k) {
    return m.get(k);
  }

  public boolean has(String k) {
    return m.containsKey(k);
  }

  /** Present and not null (b.x !== undefined && b.x !== null). */
  public boolean given(String k) {
    return m.get(k) != null;
  }

  public Map<String, Object> raw() {
    return m;
  }

  public Body obj(String k) {
    return new Body(V.map(m.get(k)));
  }

  public List<?> list(String k) {
    Object o = m.get(k);
    return o instanceof List<?> l ? l : List.of();
  }

  /** text(v, max): trimmed text cut to max length; '' when missing. */
  public String text(String k, int max) {
    return text(m.get(k), max);
  }

  public static String text(Object v, int max) {
    if (v == null) return "";
    String s = V.str(v).strip();
    return s.length() > max ? s.substring(0, max) : s;
  }

  /** String(b.x || '') */
  public String str(String k) {
    return V.s(m.get(k));
  }

  /** Whole number in [min, max], or null. Missing values are not a number. */
  public Integer integer(String k, int min, int max) {
    return integer(m.get(k), min, max);
  }

  public static Integer integer(Object v, int min, int max) {
    if (v == null && !(min <= 0 && 0 <= max)) return null;
    if (v == null) return null;
    double d = V.num(v);
    if (Double.isNaN(d) || d != Math.rint(d) || d < min || d > max) return null;
    return (int) d;
  }

  public boolean isTrue(String k) {
    return Boolean.TRUE.equals(m.get(k));
  }

  public boolean isFalse(String k) {
    return Boolean.FALSE.equals(m.get(k));
  }

  // ---------------------------------------------------------------- shared checks (utils/validate.js)
  /** 0917 200 1111, +63 917..., 917... -> 09172001111 */
  public static String normalizePhone(Object raw) {
    if (raw == null) return "";
    String d = V.str(raw).replaceAll("[^0-9]", "");
    if (d.startsWith("63") && d.length() == 12) d = "0" + d.substring(2);
    if (d.length() == 10 && d.startsWith("9")) d = "0" + d;
    return d;
  }

  public static boolean isPhone(String p) {
    return p != null && p.matches("^09\\d{9}$");
  }

  public static String normalizeEmail(Object raw) {
    return raw == null ? "" : V.str(raw).strip().toLowerCase();
  }

  public static boolean isEmail(String e) {
    return e != null && e.matches("^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$") && e.length() <= 100;
  }
}
