package com.mangao.wrs.core;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Collection;
import java.util.Map;

/** Value helpers that behave like the JavaScript the server was first written in. */
public final class V {
  private V() {}

  public static boolean isNull(Object o) {
    return o == null;
  }

  /** JavaScript truthiness: null, false, 0, NaN and "" are false. */
  public static boolean truthy(Object o) {
    if (o == null) return false;
    if (o instanceof Boolean b) return b;
    if (o instanceof Number n) {
      double d = n.doubleValue();
      return d != 0 && !Double.isNaN(d);
    }
    if (o instanceof String s) return !s.isEmpty();
    return true;
  }

  /** String(v) of JavaScript: numbers without a trailing ".0". */
  public static String str(Object o) {
    if (o == null) return "null";
    if (o instanceof Double d) return jsNumber(d);
    if (o instanceof Float f) return jsNumber(f.doubleValue());
    if (o instanceof BigDecimal b) return jsNumber(b.doubleValue());
    return o.toString();
  }

  /** v || '' */
  public static String s(Object o) {
    return truthy(o) ? str(o) : "";
  }

  /** Text or null (keeps empty strings). */
  public static String sn(Object o) {
    return o == null ? null : str(o);
  }

  public static String jsNumber(double d) {
    if (d == Math.rint(d) && !Double.isInfinite(d) && Math.abs(d) < 1e15) return String.valueOf((long) d);
    return String.valueOf(d);
  }

  /** Number(v): null -> 0, "" -> 0, bad text -> NaN. */
  public static double num(Object o) {
    if (o == null) return 0;
    if (o instanceof Number n) return n.doubleValue();
    if (o instanceof Boolean b) return b ? 1 : 0;
    String t = o.toString().trim();
    if (t.isEmpty()) return 0;
    try {
      return Double.parseDouble(t);
    } catch (NumberFormatException e) {
      return Double.NaN;
    }
  }

  /** A number for JSON (or null when the value is null). */
  public static Double numOrNull(Object o) {
    return o == null ? null : num(o);
  }

  public static long lng(Object o) {
    double d = num(o);
    return Double.isNaN(d) ? 0 : (long) d;
  }

  public static int i(Object o) {
    return (int) lng(o);
  }

  public static Integer intOrNull(Object o) {
    return o == null ? null : i(o);
  }

  public static Long longOrNull(Object o) {
    return o == null ? null : lng(o);
  }

  public static Instant instant(Object o) {
    return o instanceof Instant t ? t : null;
  }

  @SuppressWarnings("unchecked")
  public static Map<String, Object> map(Object o) {
    return o instanceof Map ? (Map<String, Object>) o : null;
  }

  public static boolean isCollection(Object o) {
    return o instanceof Collection;
  }

  public static double round1(double d) {
    return Math.round(d * 10) / 10.0;
  }
}
