package com.mangao.wrs.core;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;

/**
 * Philippine time (UTC+8, no daylight saving) and the estimated delivery rule (Chapter 4):
 * 30 minutes after the order is accepted or logged; orders accepted or logged from 11:30 to 12:00
 * get 1:00 to 1:30 PM (lunch break).
 */
public final class Clock {
  public static final ZoneOffset PH = ZoneOffset.ofHours(8);

  private static volatile Instant fixedNow = null;
  /** Tests (NODE_ENV=test) can also set the time per request with the X-Test-Now header. */
  private static final ThreadLocal<Instant> requestNow = new ThreadLocal<>();

  private Clock() {}

  /** The current time (tests can set a fixed time). */
  public static Instant now() {
    Instant r = requestNow.get();
    if (r != null) return r;
    Instant f = fixedNow;
    return f != null ? f : Instant.ofEpochMilli(System.currentTimeMillis());
  }

  /** For tests only: setNow("2026-10-14T11:40:00+08:00"), setNow(null) to go back to the real clock. */
  public static void setNow(String iso) {
    fixedNow = iso == null || iso.isBlank() ? null : parseIso(iso);
  }

  public static void setRequestNow(String iso) {
    if (iso == null || iso.isBlank()) requestNow.remove();
    else requestNow.set(parseIso(iso));
  }

  public static void clearRequestNow() {
    requestNow.remove();
  }

  public static Instant parseIso(String iso) {
    return java.time.OffsetDateTime.parse(iso).toInstant();
  }

  /** Year, month (0-11 like JavaScript), day, hour, minute in Philippine time. */
  public record Parts(int y, int mo, int d, int h, int mi) {}

  public static Parts parts(Instant t) {
    ZonedDateTime z = t.atZone(PH);
    return new Parts(z.getYear(), z.getMonthValue() - 1, z.getDayOfMonth(), z.getHour(), z.getMinute());
  }

  /** A Philippine-time clock time on the same day as t. */
  public static Instant at(Instant t, int h, int mi) {
    ZonedDateTime z = t.atZone(PH);
    return z.toLocalDate().atTime(h, mi).toInstant(PH);
  }

  /** 'YYYY-MM-DD' of t in Philippine time. */
  public static String ymd(Instant t) {
    return t.atZone(PH).toLocalDate().toString();
  }

  /** Noon of a 'YYYY-MM-DD' day (Philippine time), like new Date(`${day}T12:00:00+08:00`). */
  public static Instant noonOf(String ymd) {
    return java.time.LocalDate.parse(ymd).atTime(12, 0).toInstant(PH);
  }

  public static LocalDateTime toLocal(Instant t) {
    return LocalDateTime.ofInstant(t, PH);
  }

  public static Instant fromLocal(LocalDateTime t) {
    return t.toInstant(PH);
  }

  /** Estimated delivery: from is null except for the lunch rule. */
  public record Est(Instant from, Instant to, boolean lunch) {}

  public static Est estimatedDelivery(Instant t) {
    Parts p = parts(t);
    int minutes = p.h() * 60 + p.mi();
    if (minutes >= 11 * 60 + 30 && minutes < 12 * 60) return new Est(at(t, 13, 0), at(t, 13, 30), true);
    return new Est(null, t.plusSeconds(30 * 60), false);
  }

  /** 9:50 AM */
  public static String clock(Instant d) {
    if (d == null) return "";
    Parts p = parts(d);
    int h12 = p.h() % 12 == 0 ? 12 : p.h() % 12;
    return h12 + ":" + String.format("%02d", p.mi()) + " " + (p.h() < 12 ? "AM" : "PM");
  }

  /** "by 9:50 AM" or "1:00 to 1:30 PM" */
  public static String deliveryText(Instant from, Instant to) {
    if (to == null) return "";
    if (from != null) return clock(from).replaceAll(" (AM|PM)$", "") + " to " + clock(to);
    return "by " + clock(to);
  }

  /** Start of today in Philippine time. */
  public static Instant todayStart() {
    return at(now(), 0, 0);
  }

  /** ISO text like JavaScript's toISOString(): 2026-10-14T01:40:00.000Z */
  public static String iso(Instant t) {
    return java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC).format(t);
  }
}
